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

package auth

import (
	"context"
	"fmt"

	"github.com/hashicorp/boundary/api"
	"github.com/hashicorp/boundary/api/authmethods"
)

// Authenticator wraps the Boundary SDK authentication logic.
type Authenticator struct {
	Client       *api.Client
	AuthMethodID string
}

// NewAuthenticator creates an Authenticator backed by the given Boundary address
// and default auth method ID.
func NewAuthenticator(boundaryAddr, authMethodID string) (*Authenticator, error) {
	client, err := api.NewClient(&api.Config{Addr: boundaryAddr})
	if err != nil {
		return nil, fmt.Errorf("boundary client: %w", err)
	}
	return &Authenticator{Client: client, AuthMethodID: authMethodID}, nil
}

// Authenticate exchanges login credentials for a Boundary token. If
// overrideAuthMethodID is non-empty it is used instead of the default.
func (a *Authenticator) Authenticate(ctx context.Context, loginName, password, overrideAuthMethodID string) (string, error) {
	amClient := authmethods.NewClient(a.Client)
	params := map[string]interface{}{
		"login_name": loginName,
		"password":   password,
	}

	methodID := a.AuthMethodID
	if overrideAuthMethodID != "" {
		methodID = overrideAuthMethodID
	}

	result, err := amClient.Authenticate(ctx, methodID, "login", params)
	if err != nil {
		return "", fmt.Errorf("authenticate: %w", err)
	}

	token, err := result.GetAuthToken()
	if err != nil {
		return "", fmt.Errorf("get auth token: %w", err)
	}

	return token.Token, nil
}
