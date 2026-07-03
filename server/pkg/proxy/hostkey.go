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
	"encoding/base64"
	"errors"
	"fmt"
	"log"
	"net"
	"os"

	"golang.org/x/crypto/ssh"
	"golang.org/x/crypto/ssh/knownhosts"
)

// ErrHostKeyMismatch is returned when the remote host presents a public key
// that does not match the expected (pinned or known_hosts) key.
var ErrHostKeyMismatch = errors.New("ssh: host key mismatch")

// HostKeyCallback builds an ssh.HostKeyCallback from the environment:
//
//  1. SSH_KNOWN_HOSTS_FILE — path to an OpenSSH known_hosts file.
//  2. SSH_HOST_KEY — base64-encoded raw public key to pin.
//
// At least one must be set; if both are set, SSH_KNOWN_HOSTS_FILE takes
// precedence. If neither is configured the function returns an error so that
// callers never fall back to an insecure default.
func HostKeyCallback() (ssh.HostKeyCallback, error) {
	if path := os.Getenv("SSH_KNOWN_HOSTS_FILE"); path != "" {
		return knownHostsCallback(path)
	}
	if raw := os.Getenv("SSH_HOST_KEY"); raw != "" {
		return pinnedKeyCallback(raw)
	}
	return nil, errors.New("ssh host key verification is not configured: set SSH_KNOWN_HOSTS_FILE or SSH_HOST_KEY")
}

// knownHostsCallback returns a callback that verifies the remote key against
// an OpenSSH known_hosts file.
func knownHostsCallback(path string) (ssh.HostKeyCallback, error) {
	cb, err := knownhosts.New(path)
	if err != nil {
		return nil, fmt.Errorf("loading known_hosts from %s: %w", path, err)
	}
	log.Printf("SSH host key verification: using known_hosts file %s", path)
	return cb, nil
}

// pinnedKeyCallback returns a callback that accepts only the exact public key
// whose raw wire bytes are provided as a base64 string (e.g. the output of
// `ssh-keyscan host | awk '{print $3}'`).
func pinnedKeyCallback(b64Key string) (ssh.HostKeyCallback, error) {
	raw, err := base64.StdEncoding.DecodeString(b64Key)
	if err != nil {
		return nil, fmt.Errorf("decoding SSH_HOST_KEY: %w", err)
	}
	pinned, err := ssh.ParsePublicKey(raw)
	if err != nil {
		return nil, fmt.Errorf("parsing SSH_HOST_KEY: %w", err)
	}
	log.Printf("SSH host key verification: pinned %s key", pinned.Type())
	return func(hostname string, remote net.Addr, key ssh.PublicKey) error {
		if key.Type() != pinned.Type() || !publicKeysEqual(key, pinned) {
			return fmt.Errorf("%w: expected %s key %s, got %s key %s",
				ErrHostKeyMismatch,
				pinned.Type(),
				ssh.FingerprintSHA256(pinned),
				key.Type(),
				ssh.FingerprintSHA256(key),
			)
		}
		return nil
	}, nil
}

// publicKeysEqual compares two ssh.PublicKey values by their marshalled wire
// format, which is the canonical representation.
func publicKeysEqual(a, b ssh.PublicKey) bool {
	am := a.Marshal()
	bm := b.Marshal()
	if len(am) != len(bm) {
		return false
	}
	for i := range am {
		if am[i] != bm[i] {
			return false
		}
	}
	return true
}
