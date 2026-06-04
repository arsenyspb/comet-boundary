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
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"
	"github.com/gorilla/websocket"
	"github.com/hashicorp/boundary/api"
	"github.com/hashicorp/boundary/api/authmethods"
	apiproxy "github.com/hashicorp/boundary/api/proxy"
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

	// Initial message should contain the session authorization token
	_, p, err := ws.ReadMessage()
	if err != nil {
		log.Printf("Read initial message error: %v", err)
		return
	}

	var initReq struct {
		AuthzToken string `json:"token"`
	}
	if err := json.Unmarshal(p, &initReq); err != nil {
		log.Printf("Unmarshal init request error: %v", err)
		return
	}

	log.Printf("Received authz token, starting Boundary proxy...")
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// 1. Initialize Boundary SDK proxy using browser-provided authorization token.
	// This starts the "Data Plane" negotiation with the Boundary infrastructure.
	clientProxy, err := apiproxy.New(ctx, initReq.AuthzToken)
	if err != nil {
		log.Printf("Proxy creation error: %v", err)
		return
	}

	go func() {
		// 2. Establish the identity-aware tunnel to the Boundary Worker.
		// This background process handles authentication and encryption to the worker.
		if err := clientProxy.Start(); err != nil {
			log.Printf("Proxy start error: %v", err)
		}
	}()

	// Wait for proxy to be ready
	// 3. Retrieve local loopback address that bridges to the Boundary tunnel.
	// Any bytes sent to this address are intercepted by the SDK and routed to the Worker.
	addr := clientProxy.ListenerAddress(ctx)
	if addr == "" {
		for i := 0; i < 10; i++ {
			time.Sleep(100 * time.Millisecond)
			addr = clientProxy.ListenerAddress(ctx)
			if addr != "" {
				break
			}
		}
	}

	if addr == "" {
		log.Printf("Proxy failed to provide address")
		return
	}

	log.Printf("Boundary proxy ready at %s. Connecting to SSH...", addr)

	sshUser := os.Getenv("SSH_USER")
	if sshUser == "" {
		sshUser = "boundary-user"
	}
	sshPass := os.Getenv("SSH_PASSWORD")
	if sshPass == "" {
		sshPass = "password"
	}

	// SSH Configuration - Sourced from environment
	sshConfig := &ssh.ClientConfig{
		User:            sshUser,
		Auth:            []ssh.AuthMethod{ssh.Password(sshPass)},
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
		Timeout:         5 * time.Second,
	}

	// 4. Route SSH traffic through the Boundary Worker via the local proxy listener.
	// This completes the traversal: Browser (WS) -> Backend (Go) -> Boundary Worker -> SSH Target.
	sshConn, err := ssh.Dial("tcp", addr, sshConfig)
	if err != nil {
		log.Printf("SSH dial error: %v", err)
		return
	}
	defer sshConn.Close()

	log.Printf("SSH connection established.")
	sess, err := sshConn.NewSession()
	if err != nil {
		log.Printf("SSH session error: %v", err)
		return
	}
	defer sess.Close()

	stdin, _ := sess.StdinPipe()
	stdout, _ := sess.StdoutPipe()
	stderr, _ := sess.StderrPipe()

	// Request PTY
	if err := sess.RequestPty("xterm", 80, 24, ssh.TerminalModes{}); err != nil {
		log.Printf("PTY request error: %v", err)
		return
	}

	if err := sess.Shell(); err != nil {
		log.Printf("Shell error: %v", err)
		return
	}

	// Forward SSH output to WebSocket
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

	// Forward WebSocket input to SSH
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
		authMethodID = "ampw_8nDOy6GZUQ"
	}

	log.Printf("Backend initialized with Boundary Addr: %s", boundaryAddr)
	log.Printf("Backend initialized with Auth Method ID: %s", authMethodID)

	r.Get("/", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("Comet Boundary Prototype Backend is running"))
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

		client, err := api.NewClient(&api.Config{Addr: boundaryAddr})
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}

		amClient := authmethods.NewClient(client)
		params := map[string]interface{}{
			"login_name": req.LoginName,
			"password":   req.Password,
		}

		targetAuthMethodID := authMethodID
		if req.AuthMethodID != "" {
			targetAuthMethodID = req.AuthMethodID
		}

		result, err := amClient.Authenticate(r.Context(), targetAuthMethodID, "login", params)
		if err != nil {
			http.Error(w, err.Error(), http.StatusUnauthorized)
			return
		}

		token, err := result.GetAuthToken()
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}

		json.NewEncoder(w).Encode(AuthResponse{Token: token.Token})
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
