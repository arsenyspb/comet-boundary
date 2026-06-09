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

package proxy

import (
	"context"
	"fmt"
	"log"
	"time"

	apiproxy "github.com/hashicorp/boundary/api/proxy"
	"golang.org/x/crypto/ssh"
)

// SSHSession holds the resources for an active SSH session over a Boundary tunnel.
type SSHSession struct {
	Proxy   *apiproxy.ClientProxy
	SSHConn *ssh.Client
	Session *ssh.Session
	Cancel  context.CancelFunc
}

// Close tears down the SSH session, connection, and Boundary proxy.
func (s *SSHSession) Close() {
	if s.Session != nil {
		s.Session.Close()
	}
	if s.SSHConn != nil {
		s.SSHConn.Close()
	}
	if s.Cancel != nil {
		s.Cancel()
	}
}

// DialThroughBoundary creates a Boundary SDK proxy tunnel using the given
// authorization token, then dials SSH through the resulting local listener.
func DialThroughBoundary(ctx context.Context, authzToken, sshUser, sshPass string) (*SSHSession, error) {
	ctx, cancel := context.WithCancel(ctx)

	clientProxy, err := apiproxy.New(ctx, authzToken)
	if err != nil {
		cancel()
		return nil, fmt.Errorf("proxy creation: %w", err)
	}

	go func() {
		if err := clientProxy.Start(); err != nil {
			log.Printf("Proxy start error: %v", err)
		}
	}()

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
		cancel()
		return nil, fmt.Errorf("proxy failed to provide listener address")
	}

	log.Printf("Boundary proxy ready at %s", addr)

	sshConfig := &ssh.ClientConfig{
		User:            sshUser,
		Auth:            []ssh.AuthMethod{ssh.Password(sshPass)},
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
		Timeout:         5 * time.Second,
	}

	sshConn, err := ssh.Dial("tcp", addr, sshConfig)
	if err != nil {
		cancel()
		return nil, fmt.Errorf("ssh dial: %w", err)
	}

	sess, err := sshConn.NewSession()
	if err != nil {
		sshConn.Close()
		cancel()
		return nil, fmt.Errorf("ssh session: %w", err)
	}

	return &SSHSession{
		Proxy:   clientProxy,
		SSHConn: sshConn,
		Session: sess,
		Cancel:  cancel,
	}, nil
}
