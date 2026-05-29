# RFC: Boundary Web-Based Client Prototype

## 1. Problem Statement
Users in restricted environments (e.g., "Comet" laptops) cannot install thick clients (Boundary CLI/Desktop). This prevents them from accessing remote targets managed by Boundary.

## 2. Proposed Architecture
A server-side web application that acts as a bridge between the browser and Boundary workers.

### Components
1. **Web UI (React):**
   - User authentication (via OIDC or Boundary direct).
   - Target listing and session initiation.
   - Terminal emulator (`xterm.js`) for SSH.
   - Remote Desktop viewer (e.g., `guacamole-common-js`) for RDP.
2. **Backend Proxy (Go/Node.js):**
   - **Boundary API Client:** Handles authentication and target authorization.
   - **Boundary Proxy Bridge:** Utilizes the Boundary `apiproxy` SDK to establish connections to workers.
   - **Protocol Adapters:**
     - **SSH Adapter:** Bridges WebSocket terminal traffic to the Boundary-proxied SSH port.
     - **RDP Adapter:** Bridges web-compatible RDP/VNC traffic to the Boundary-proxied RDP port (likely using Apache Guacamole or a similar proxy).

## 3. Implementation Plan (Prototype)
### Phase 1: Local Boundary Environment
- Setup a `docker-compose` environment with:
  - Boundary Controller & Worker.
  - A sample SSH target (Linux container).
  - A sample RDP target (Windows VM or VNC-enabled container).
  - The Web Client prototype container.

### Phase 2: SSH Prototype
- Implement the "Authorize Session" flow in the backend.
- Start the `apiproxy` for the authorized session.
- Use a Go-based SSH client on the backend to connect to the local proxy port and pipe it to a WebSocket for `xterm.js`.

### Phase 3: RDP Prototype
- Integrate Apache Guacamole (guacd) or a similar proxy.
- Point Guacamole to the Boundary-proxied RDP port.
- Render the session in the browser using `guacamole-common-js`.

## 4. Engineering Effort Estimate
- **Prototype (POC):** 2-3 weeks (1 Senior Engineer).
- **Production-Ready Feature:** 3-6 months (depending on UI polish, security hardening, and protocol coverage).

## 5. Security Considerations
- **Credential Handling:** Credentials must be handled securely on the server-side proxy.
- **Session Lifecycle:** The web client must ensure sessions are closed when the browser tab is closed.
- **Network Isolation:** The proxy server needs access to both the Boundary Controller/Worker and the end-user's browser.
