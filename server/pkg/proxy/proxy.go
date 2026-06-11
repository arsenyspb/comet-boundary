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
	"bufio"
	"context"
	"fmt"
	"log"
	"os/exec"
	"regexp"
	"syscall"
	"time"

	"golang.org/x/crypto/ssh"
)

// SSHSession holds the resources for an active SSH session backed by a
// `boundary connect` subprocess.
type SSHSession struct {
	Cmd     *exec.Cmd
	SSHConn *ssh.Client
	Session *ssh.Session
	Cancel  context.CancelFunc
}

// Close tears down the SSH session, connection, and Boundary subprocess.
func (s *SSHSession) Close() {
	if s.Session != nil {
		s.Session.Close()
	}
	if s.SSHConn != nil {
		s.SSHConn.Close()
	}
	if s.Cmd != nil && s.Cmd.Process != nil {
		// SIGTERM the process group for graceful shutdown.
		_ = syscall.Kill(-s.Cmd.Process.Pid, syscall.SIGTERM)
		done := make(chan struct{})
		go func() {
			s.Cmd.Wait()
			close(done)
		}()
		select {
		case <-done:
		case <-time.After(5 * time.Second):
			_ = syscall.Kill(-s.Cmd.Process.Pid, syscall.SIGKILL)
			<-done
		}
	}
	if s.Cancel != nil {
		s.Cancel()
	}
}

// DialThroughBoundary spawns a `boundary connect` subprocess using the given
// authorization token, parses the ephemeral local port from its output, then
// dials SSH through that port.
func DialThroughBoundary(ctx context.Context, authzToken, sshUser, sshPass string) (*SSHSession, error) {
	ctx, cancel := context.WithCancel(ctx)

	cmd := exec.Command("boundary", "connect",
		"-authz-token", authzToken,
	)
	// Own process group so we can signal the entire tree on teardown.
	// Pdeathsig ensures the child is killed if the BFF crashes.
	cmd.SysProcAttr = &syscall.SysProcAttr{
		Setpgid:   true,
		Pdeathsig: syscall.SIGTERM,
	}

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		cancel()
		return nil, fmt.Errorf("stdout pipe: %w", err)
	}

	if err := cmd.Start(); err != nil {
		cancel()
		return nil, fmt.Errorf("boundary connect start: %w", err)
	}

	// Parse the proxy listening port from the CLI output.
	portCh := make(chan string, 1)
	errCh := make(chan error, 1)
	go func() {
		scanner := bufio.NewScanner(stdout)
		portRe := regexp.MustCompile(`Port:\s+(\d+)`)
		found := false
		for scanner.Scan() {
			line := scanner.Text()
			if !found {
				if m := portRe.FindStringSubmatch(line); m != nil {
					portCh <- m[1]
					found = true
				}
			}
			// Keep draining stdout to prevent the subprocess from blocking.
		}
		if !found {
			errCh <- fmt.Errorf("boundary connect exited without providing a port")
		}
	}()

	var port string
	select {
	case port = <-portCh:
	case err := <-errCh:
		cmd.Process.Kill()
		cancel()
		return nil, err
	case <-time.After(30 * time.Second):
		cmd.Process.Kill()
		cancel()
		return nil, fmt.Errorf("timeout waiting for boundary connect to provide a port")
	case <-ctx.Done():
		cmd.Process.Kill()
		cancel()
		return nil, ctx.Err()
	}

	addr := fmt.Sprintf("127.0.0.1:%s", port)
	log.Printf("Boundary subprocess ready at %s (PID %d)", addr, cmd.Process.Pid)

	sshConfig := &ssh.ClientConfig{
		User:            sshUser,
		Auth:            []ssh.AuthMethod{ssh.Password(sshPass)},
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
		Timeout:         5 * time.Second,
	}

	sshConn, err := ssh.Dial("tcp", addr, sshConfig)
	if err != nil {
		_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGTERM)
		cancel()
		return nil, fmt.Errorf("ssh dial: %w", err)
	}

	sess, err := sshConn.NewSession()
	if err != nil {
		sshConn.Close()
		_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGTERM)
		cancel()
		return nil, fmt.Errorf("ssh session: %w", err)
	}

	return &SSHSession{
		Cmd:     cmd,
		SSHConn: sshConn,
		Session: sess,
		Cancel:  cancel,
	}, nil
}
