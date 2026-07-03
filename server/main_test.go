package main

import (
	"bytes"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"github.com/arsenyspb/comet-boundary/pkg/proxy"
	"golang.org/x/crypto/ssh"
)

func TestRootHandler(t *testing.T) {
	os.Setenv("BOUNDARY_AUTH_METHOD_ID", "test_auth_method")
	defer os.Unsetenv("BOUNDARY_AUTH_METHOD_ID")
	r := setupRouter()
	ts := httptest.NewServer(r)
	defer ts.Close()

	res, err := http.Get(ts.URL + "/")
	if err != nil {
		t.Fatal(err)
	}
	if res.StatusCode != http.StatusOK {
		t.Errorf("Expected status OK; got %v", res.Status)
	}
}

func TestLogin_MissingCredentials(t *testing.T) {
	os.Setenv("BOUNDARY_AUTH_METHOD_ID", "test_auth_method")
	defer os.Unsetenv("BOUNDARY_AUTH_METHOD_ID")
	r := setupRouter()
	ts := httptest.NewServer(r)
	defer ts.Close()

	// Missing password
	reqBody, _ := json.Marshal(map[string]string{
		"login_name": "admin",
	})
	req, _ := http.NewRequest("POST", ts.URL+"/auth/login", bytes.NewBuffer(reqBody))
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{}
	res, err := client.Do(req)
	if err != nil {
		t.Fatal(err)
	}

	if res.StatusCode != http.StatusBadRequest {
		t.Errorf("Expected status BadRequest (400) for missing credentials; got %v", res.Status)
	}
}

// generateSSHSigner creates a random Ed25519 SSH host key for testing.
func generateSSHSigner(t *testing.T) ssh.Signer {
	t.Helper()
	_, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatalf("generate ed25519 key: %v", err)
	}
	signer, err := ssh.NewSignerFromKey(priv)
	if err != nil {
		t.Fatalf("new signer: %v", err)
	}
	return signer
}

// startSSHServer starts a minimal SSH server on a random port and returns
// the listener address and the server's public key. The caller must close
// the returned listener.
func startSSHServer(t *testing.T, signer ssh.Signer) net.Listener {
	t.Helper()
	cfg := &ssh.ServerConfig{NoClientAuth: true}
	cfg.AddHostKey(signer)

	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}

	go func() {
		for {
			conn, err := ln.Accept()
			if err != nil {
				return
			}
			go func(c net.Conn) {
				defer c.Close()
				_, _, _, _ = ssh.NewServerConn(c, cfg)
			}(conn)
		}
	}()
	return ln
}

func TestHostKeyMismatch(t *testing.T) {
	// Generate two distinct keys: one for the server, one pinned in config.
	serverSigner := generateSSHSigner(t)
	wrongSigner := generateSSHSigner(t)

	ln := startSSHServer(t, serverSigner)
	defer ln.Close()

	// Pin the WRONG key so the SSH dial must fail with a mismatch.
	wrongB64 := base64.StdEncoding.EncodeToString(wrongSigner.PublicKey().Marshal())
	t.Setenv("SSH_HOST_KEY", wrongB64)
	t.Setenv("SSH_KNOWN_HOSTS_FILE", "")

	cb, err := proxy.HostKeyCallback()
	if err != nil {
		t.Fatalf("HostKeyCallback: %v", err)
	}

	sshCfg := &ssh.ClientConfig{
		User:            "test",
		Auth:            []ssh.AuthMethod{ssh.Password("test")},
		HostKeyCallback: cb,
	}

	_, err = ssh.Dial("tcp", ln.Addr().String(), sshCfg)
	if err == nil {
		t.Fatal("expected SSH dial to fail due to host key mismatch, but it succeeded")
	}
	if !errors.Is(err, proxy.ErrHostKeyMismatch) {
		t.Fatalf("expected ErrHostKeyMismatch, got: %v", err)
	}
	t.Logf("correctly rejected connection: %v", err)
}

func TestHostKeyMatch(t *testing.T) {
	// Pin the CORRECT key — SSH handshake should pass key verification
	// (auth will still fail, but that's after key check).
	serverSigner := generateSSHSigner(t)
	ln := startSSHServer(t, serverSigner)
	defer ln.Close()

	correctB64 := base64.StdEncoding.EncodeToString(serverSigner.PublicKey().Marshal())
	t.Setenv("SSH_HOST_KEY", correctB64)
	t.Setenv("SSH_KNOWN_HOSTS_FILE", "")

	cb, err := proxy.HostKeyCallback()
	if err != nil {
		t.Fatalf("HostKeyCallback: %v", err)
	}

	sshCfg := &ssh.ClientConfig{
		User:            "test",
		Auth:            []ssh.AuthMethod{ssh.Password("test")},
		HostKeyCallback: cb,
	}

	conn, err := ssh.Dial("tcp", ln.Addr().String(), sshCfg)
	// With NoClientAuth on the test server and the correct pinned key, the
	// connection should succeed — proving the host key was accepted.
	if err != nil {
		if errors.Is(err, proxy.ErrHostKeyMismatch) {
			t.Fatalf("unexpected host key mismatch with the correct pinned key: %v", err)
		}
		t.Fatalf("unexpected dial error: %v", err)
	}
	conn.Close()
	t.Log("host key accepted, connection succeeded")
}

func TestHostKeyCallback_NeitherConfigured(t *testing.T) {
	t.Setenv("SSH_KNOWN_HOSTS_FILE", "")
	t.Setenv("SSH_HOST_KEY", "")

	_, err := proxy.HostKeyCallback()
	if err == nil {
		t.Fatal("expected error when neither SSH_KNOWN_HOSTS_FILE nor SSH_HOST_KEY is set")
	}
	t.Logf("correctly returned error: %v", err)
}

func TestHostKeyCallback_KnownHostsFile(t *testing.T) {
	serverSigner := generateSSHSigner(t)
	ln := startSSHServer(t, serverSigner)
	defer ln.Close()

	host, port, _ := net.SplitHostPort(ln.Addr().String())

	// Write a known_hosts entry for the server.
	knownHostsLine := fmt.Sprintf("[%s]:%s %s %s\n",
		host, port,
		serverSigner.PublicKey().Type(),
		base64.StdEncoding.EncodeToString(serverSigner.PublicKey().Marshal()),
	)
	tmpFile, err := os.CreateTemp(t.TempDir(), "known_hosts")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := tmpFile.WriteString(knownHostsLine); err != nil {
		t.Fatal(err)
	}
	tmpFile.Close()

	t.Setenv("SSH_KNOWN_HOSTS_FILE", tmpFile.Name())
	t.Setenv("SSH_HOST_KEY", "")

	cb, err := proxy.HostKeyCallback()
	if err != nil {
		t.Fatalf("HostKeyCallback: %v", err)
	}

	sshCfg := &ssh.ClientConfig{
		User:            "test",
		Auth:            []ssh.AuthMethod{ssh.Password("test")},
		HostKeyCallback: cb,
	}

	_, err = ssh.Dial("tcp", ln.Addr().String(), sshCfg)
	if errors.Is(err, proxy.ErrHostKeyMismatch) {
		t.Fatalf("unexpected host key mismatch with known_hosts: %v", err)
	}
	t.Logf("host key accepted via known_hosts (connection failed for expected auth reason): %v", err)
}
