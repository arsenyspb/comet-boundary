// Copyright 2026 Arseny Chernov
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

//go:build integration

package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"
	"testing"

	"github.com/arsenyspb/comet-boundary/pkg/auth"
)

// loadEnv reads a .env file and sets variables in the process environment.
func loadEnv(t *testing.T, path string) {
	t.Helper()
	f, err := os.Open(path)
	if err != nil {
		t.Fatalf("Cannot open %s: %v", path, err)
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		parts := strings.SplitN(line, "=", 2)
		if len(parts) == 2 {
			os.Setenv(parts[0], parts[1])
		}
	}
}

func envOrFatal(t *testing.T, key string) string {
	t.Helper()
	v := os.Getenv(key)
	if v == "" {
		t.Fatalf("Required env var %s is not set", key)
	}
	return v
}

// TestBoundaryControllerHealth verifies the Boundary Controller API is reachable.
func TestBoundaryControllerHealth(t *testing.T) {
	loadEnv(t, "../.env")
	addr := envOrFatal(t, "BOUNDARY_ADDR")
	resp, err := http.Get(addr + "/v1/auth-methods?scope_id=global")
	if err != nil {
		t.Fatalf("Boundary Controller unreachable: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("Unexpected status from Boundary Controller: %d", resp.StatusCode)
	}
}

// TestAdminPasswordAuth verifies admin can authenticate via the password auth method.
func TestAdminPasswordAuth(t *testing.T) {
	loadEnv(t, "../.env")
	addr := envOrFatal(t, "BOUNDARY_ADDR")
	authMethodID := envOrFatal(t, "BOUNDARY_AUTH_METHOD_ID")
	adminPass := envOrFatal(t, "BOUNDARY_ADMIN_PASSWORD")

	authenticator, err := auth.NewAuthenticator(addr, authMethodID)
	if err != nil {
		t.Fatalf("NewAuthenticator: %v", err)
	}
	token, err := authenticator.Authenticate(t.Context(), "admin", adminPass, "")
	if err != nil {
		t.Fatalf("Admin auth failed: %v", err)
	}
	if token == "" {
		t.Fatal("Received empty token")
	}
}

// TestLDAPAuthAndTargetDiscovery verifies LDAP users can authenticate and
// discover only their authorized targets (RBAC isolation).
func TestLDAPAuthAndTargetDiscovery(t *testing.T) {
	loadEnv(t, "../.env")
	addr := envOrFatal(t, "BOUNDARY_ADDR")
	ldapAuthMethodID := envOrFatal(t, "BOUNDARY_LDAP_AUTH_METHOD_ID")

	authenticator, err := auth.NewAuthenticator(addr, ldapAuthMethodID)
	if err != nil {
		t.Fatalf("NewAuthenticator: %v", err)
	}

	cases := []struct {
		user          string
		password      string
		expectTarget  string
		denyTarget    string
	}{
		{user: "alice", password: "changeme", expectTarget: "A Team Host", denyTarget: "B Team Host"},
		{user: "bob", password: "changeme", expectTarget: "B Team Host", denyTarget: "A Team Host"},
	}

	for _, tc := range cases {
		t.Run(tc.user, func(t *testing.T) {
			token, err := authenticator.Authenticate(t.Context(), tc.user, tc.password, "")
			if err != nil {
				t.Fatalf("LDAP auth failed for %s: %v", tc.user, err)
			}
			if token == "" {
				t.Fatalf("Empty token for %s", tc.user)
			}

			// Discover targets via Boundary REST API
			req, _ := http.NewRequest("GET", addr+"/v1/targets?recursive=true&scope_id=global", nil)
			req.Header.Set("Authorization", "Bearer "+token)
			resp, err := http.DefaultClient.Do(req)
			if err != nil {
				t.Fatalf("Target discovery failed: %v", err)
			}
			defer resp.Body.Close()

			var result struct {
				Items []struct {
					ID   string `json:"id"`
					Name string `json:"name"`
				} `json:"items"`
			}
			if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
				t.Fatalf("Decode targets: %v", err)
			}

			found := false
			for _, item := range result.Items {
				if item.Name == tc.expectTarget {
					found = true
				}
				if item.Name == tc.denyTarget {
					t.Errorf("%s should NOT see %q but it was discovered", tc.user, tc.denyTarget)
				}
			}
			if !found {
				t.Errorf("%s should see %q but it was not discovered", tc.user, tc.expectTarget)
			}
		})
	}
}

// TestSessionAuthorization verifies that an LDAP user can authorize a session
// against their target and receive brokered credentials.
func TestSessionAuthorization(t *testing.T) {
	loadEnv(t, "../.env")
	addr := envOrFatal(t, "BOUNDARY_ADDR")
	ldapAuthMethodID := envOrFatal(t, "BOUNDARY_LDAP_AUTH_METHOD_ID")

	authenticator, err := auth.NewAuthenticator(addr, ldapAuthMethodID)
	if err != nil {
		t.Fatalf("NewAuthenticator: %v", err)
	}

	token, err := authenticator.Authenticate(t.Context(), "alice", "changeme", "")
	if err != nil {
		t.Fatalf("LDAP auth failed: %v", err)
	}

	// Discover alice's target
	req, _ := http.NewRequest("GET", addr+"/v1/targets?recursive=true&scope_id=global", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("Discovery: %v", err)
	}
	defer resp.Body.Close()

	var targets struct {
		Items []struct {
			ID   string `json:"id"`
			Name string `json:"name"`
		} `json:"items"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&targets); err != nil {
		t.Fatalf("Decode: %v", err)
	}

	var targetID string
	for _, item := range targets.Items {
		if item.Name == "A Team Host" {
			targetID = item.ID
			break
		}
	}
	if targetID == "" {
		t.Fatal("A Team Host not found")
	}

	// Authorize session
	authzReq, _ := http.NewRequest("POST", fmt.Sprintf("%s/v1/targets/%s:authorize-session", addr, targetID), nil)
	authzReq.Header.Set("Authorization", "Bearer "+token)
	authzResp, err := http.DefaultClient.Do(authzReq)
	if err != nil {
		t.Fatalf("Authorize session: %v", err)
	}
	defer authzResp.Body.Close()

	if authzResp.StatusCode != http.StatusOK {
		t.Fatalf("Authorize session returned %d", authzResp.StatusCode)
	}

	var session struct {
		AuthorizationToken string `json:"authorization_token"`
		SessionID          string `json:"session_id"`
		Credentials        []struct {
			Credential struct {
				Username string `json:"username"`
				Password string `json:"password"`
			} `json:"credential"`
		} `json:"credentials"`
	}
	if err := json.NewDecoder(authzResp.Body).Decode(&session); err != nil {
		t.Fatalf("Decode session: %v", err)
	}

	if session.AuthorizationToken == "" {
		t.Error("Missing authorization_token")
	}
	if session.SessionID == "" {
		t.Error("Missing session_id")
	}
	if len(session.Credentials) == 0 {
		t.Fatal("No brokered credentials returned")
	}
	cred := session.Credentials[0].Credential
	if cred.Username == "" || cred.Password == "" {
		t.Error("Brokered credential missing username or password")
	}
}
