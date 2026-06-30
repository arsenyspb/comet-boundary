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

package main

import (
	"context"
	"embed"
	"encoding/json"
	"fmt"
	"io/fs"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"strings"

	"github.com/arsenyspb/comet-boundary/pkg/auth"
	"github.com/arsenyspb/comet-boundary/pkg/proxy"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"
	"github.com/gorilla/websocket"
	"golang.org/x/crypto/ssh"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

type SSHMessage struct {
	Type string `json:"type"`
	Data string `json:"data"`
	Cols int    `json:"cols"`
	Rows int    `json:"rows"`
}

func handleSSH(w http.ResponseWriter, r *http.Request) {
	log.Printf("SSH WebSocket connection attempt from %s", r.RemoteAddr)
	ws, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("Upgrade error: %v", err)
		return
	}
	defer ws.Close()

	_, p, err := ws.ReadMessage()
	if err != nil {
		log.Printf("Read initial message error: %v", err)
		return
	}

	var initReq struct {
		AuthzToken string `json:"token"`
		SSHUser    string `json:"ssh_user"`
		SSHPass    string `json:"ssh_password"`
	}
	if err := json.Unmarshal(p, &initReq); err != nil {
		log.Printf("Unmarshal init request error: %v", err)
		return
	}

	if initReq.SSHUser == "" || initReq.SSHPass == "" {
		log.Printf("Brokered credentials missing from session request")
		return
	}

	log.Printf("Received authz token, starting Boundary proxy...")
	ctx := context.Background()

	sshSess, err := proxy.DialThroughBoundary(ctx, initReq.AuthzToken, initReq.SSHUser, initReq.SSHPass)
	if err != nil {
		log.Printf("Dial through Boundary error: %v", err)
		return
	}
	defer sshSess.Close()

	sess := sshSess.Session
	stdin, _ := sess.StdinPipe()
	stdout, _ := sess.StdoutPipe()
	stderr, _ := sess.StderrPipe()

	if err := sess.RequestPty("xterm", 80, 24, ssh.TerminalModes{}); err != nil {
		log.Printf("PTY request error: %v", err)
		return
	}

	if err := sess.Shell(); err != nil {
		log.Printf("Shell error: %v", err)
		return
	}

	go func() {
		buf := make([]byte, 1024)
		for {
			n, err := stdout.Read(buf)
			if err != nil {
				return
			}
			ws.WriteJSON(SSHMessage{Type: "data", Data: string(buf[:n])})
		}
	}()

	go func() {
		buf := make([]byte, 1024)
		for {
			n, err := stderr.Read(buf)
			if err != nil {
				return
			}
			ws.WriteJSON(SSHMessage{Type: "data", Data: string(buf[:n])})
		}
	}()

	for {
		var msg SSHMessage
		if err := ws.ReadJSON(&msg); err != nil {
			break
		}
		switch msg.Type {
		case "data":
			stdin.Write([]byte(msg.Data))
		case "resize":
			sess.WindowChange(msg.Rows, msg.Cols)
		}
	}
}

type AuthRequest struct {
	LoginName    string `json:"login_name"`
	Password     string `json:"password"`
	AuthMethodID string `json:"auth_method_id,omitempty"`
}

type AuthResponse struct {
	Token string `json:"token"`
}

type SessionRequest struct {
	TargetID string `json:"target_id"`
}

type SessionResponse struct {
	SessionID          string `json:"session_id"`
	AuthorizationToken string `json:"authorization_token"`
	Endpoint           string `json:"endpoint"`
}

//go:embed all:static
var staticFiles embed.FS

func boundaryReverseProxy(targetAddr string) http.HandlerFunc {
	target, _ := url.Parse(targetAddr)
	proxy := httputil.NewSingleHostReverseProxy(target)
	return func(w http.ResponseWriter, r *http.Request) {
		r.URL.Path = strings.TrimPrefix(r.URL.Path, "/boundary")
		proxy.ServeHTTP(w, r)
	}
}

func setupRouter() *chi.Mux {
	r := chi.NewRouter()
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)
	r.Use(cors.Handler(cors.Options{
		AllowedOrigins:   []string{"*"},
		AllowedMethods:   []string{"GET", "POST", "OPTIONS"},
		AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type", "X-Boundary-Token"},
		AllowCredentials: true,
	}))

	boundaryAddr := os.Getenv("BOUNDARY_ADDR")
	if boundaryAddr == "" {
		boundaryAddr = "http://localhost:9200"
	}

	authMethodID := os.Getenv("BOUNDARY_AUTH_METHOD_ID")
	if authMethodID == "" {
		log.Fatal("BOUNDARY_AUTH_METHOD_ID environment variable is required")
	}

	log.Printf("Backend initialized with Boundary Addr: %s", boundaryAddr)
	log.Printf("Backend initialized with Auth Method ID: %s", authMethodID)

	authenticator, err := auth.NewAuthenticator(boundaryAddr, authMethodID)
	if err != nil {
		log.Fatalf("Failed to create authenticator: %v", err)
	}

	r.HandleFunc("/boundary/*", boundaryReverseProxy(boundaryAddr))

	staticSubFS, _ := fs.Sub(staticFiles, "static")
	fileServer := http.FileServer(http.FS(staticSubFS))

	r.Get("/*", func(w http.ResponseWriter, req *http.Request) {
		path := strings.TrimPrefix(req.URL.Path, "/")
		if _, err := fs.Stat(staticSubFS, path); os.IsNotExist(err) && path != "" {
			req.URL.Path = "/"
		}
		fileServer.ServeHTTP(w, req)
	})

	r.Post("/auth/login", func(w http.ResponseWriter, r *http.Request) {
		var req AuthRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		if req.LoginName == "" || req.Password == "" {
			http.Error(w, "login_name and password are required", http.StatusBadRequest)
			return
		}

		token, err := authenticator.Authenticate(r.Context(), req.LoginName, req.Password, req.AuthMethodID)
		if err != nil {
			http.Error(w, err.Error(), http.StatusUnauthorized)
			return
		}

		json.NewEncoder(w).Encode(AuthResponse{Token: token})
	})

	r.HandleFunc("/ws/ssh", handleSSH)
	return r
}

func main() {
	r := setupRouter()

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	fmt.Printf("Server starting on port %s...\n", port)
	log.Fatal(http.ListenAndServe(":"+port, r))
}
