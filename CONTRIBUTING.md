# Contributing to Comet Boundary

Welcome to the Comet Boundary project. This document outlines the current state of the prototype, known limitations, and the roadmap for future development slices.

## Project Vision
Comet Boundary aims to provide a zero-install, web-based remote access client for HashiCorp Boundary. It is specifically designed for restricted "Comet" environments where native Boundary desktop clients cannot be installed.

---

## Current State: Slice 1 (SSH)
We have successfully implemented **Slice 1: SSH via Web**. 
- **Backend:** A Go-based proxy that handles Boundary authentication and WebSocket-to-SSH bridging.
- **Frontend:** A React application using `xterm.js` to provide a functional terminal in the browser.
- **Bootstrap:** The `make replay` command provides a fully automated setup of the Boundary infrastructure and the web client.

## Security & Architectural Roadmap (The "Naughty List")
The current version is a **technical prototype**. To facilitate a "one-button" demo experience, several security best practices have been bypassed. These are prioritized for correction in future development slices:

### 1. Credentials & Secrets Management
- **Static SSH Credentials:** The backend currently uses shared credentials (`SSH_USER`/`SSH_PASSWORD`) for the final hop to the target. Future slices must integrate with Boundary/Vault for dynamic credential injection.
- **Credential Fallbacks:** The Go backend contains hardcoded default IDs and passwords as fallbacks in `main.go`. These will be removed in favor of mandatory environment validation.
- **Frontend Secret Exposure:** Vite environment variables (`VITE_`) are used to pre-fill login fields for the demo. This is a **temporary convenience hack** and will be replaced by a standard, secure login flow.

### 2. Infrastructure Security
- **SSH Host Key Verification:** Currently using `InsecureIgnoreHostKey()`. This is a major anti-pattern that permits MitM attacks and must be replaced with a proper identity mechanism for targets.
- **Broad CORS Policy:** The backend currently allows all origins (`*`). This will be tightened to specific allowed domains in the next iteration.

### 3. Authentication & Authorization
- **Password-only Auth:** Only password-based authentication is currently supported.
- **Strategic Goal:** Future iterations will implement production-grade authentication via **SAML, OIDC, or SSO plugins**, established directly between the browser and Boundary.
- **Session Scoping:** Improved validation is needed to ensure the backend proxy cannot be tricked into connecting to unauthorized targets using a valid session token.

---

## Future Roadmap: Slice 2 (RDP)
The next major iteration of development is **Slice 2: RDP via Web**.

### Objectives:
- **Guacamole Integration:** Introduce `guacd` (Apache Guacamole) to the Docker environment to handle the translation of raw RDP traffic into a web-consumable protocol.
- **RDP Canvas:** Implement a Guacamole-compatible canvas in the React frontend to allow interactive desktop sessions.
- **Protocol Proxying:** Extend the Go backend to authorize RDP sessions via Boundary and bridge them to the Guacamole tunnel.

---

## Development Workflow
To contribute or test the current state:

1.  **Replay the Demo:** Run `make replay` to wipe the environment and start fresh with auto-discovered credentials.
2.  **Verify SSH:** Access the UI at `http://localhost:5173`, login with the pre-filled credentials, and establish a session.
3.  **Logs:** Monitor `server.log` and `client.log` for debugging the proxy and frontend respectively.

## Future Infrastructure Goals
- [ ] Migrate target settings to a persistent backend database.
- [ ] Implement Vault KV integration for dynamic target configuration.
- [ ] Transition to production-grade authentication (SAML/OIDC/SSO).
- [ ] Add support for Boundary's session recording features.
- [ ] Refactor the backend to use the Boundary Go SDK for more robust session management.
