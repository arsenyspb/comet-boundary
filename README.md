# Comet Boundary Prototype

A web-based client for [HashiCorp Boundary](https://www.boundaryproject.io/) designed for restricted "Comet" environments. Enables secure SSH access directly from the browser without requiring native thick clients.

> [!CAUTION]
> **SECURITY WARNING: DEMO MODE ONLY**
> This project is a **technical prototype** and is strictly intended for demonstration purposes. It contains several architectural and security trade-offs (such as disabled host key verification and shared static credentials) designed for ease of setup in a development environment. 
> 
> **DO NOT use this in production or with sensitive data.** For a detailed breakdown of current deficiencies and the security roadmap, see [CONTRIBUTING.md](./CONTRIBUTING.md).

## Architecture (Slice 1: SSH)

The system is split into a **Control Plane** (identity & authorization) and a **Data Plane** (secure traffic proxying). Since browsers cannot speak Boundary's native protocols, the Go Backend acts as a **Trusted Intermediary**.

### Component Overview
```mermaid
graph TB
    subgraph Browser ["User Browser"]
        UI["Web UI (React/xterm.js)"]
    end

    subgraph Docker ["Docker Compose Network"]
        subgraph App ["Application Services (BFF)"]
            Front["Frontend (Vite Proxy)"]
            Back["Backend Proxy (Go SDK)"]
        end

        subgraph Boundary ["Boundary Infrastructure"]
            Cont["Controller (Control Plane)"]
            Work["Worker (Data Plane)"]
            DB[(Postgres)]
        end

        subgraph Targets ["Resource Targets"]
            SSH["SSH Target (OpenSSH)"]
        end
    end

    UI -- "HTTPS/WSS" --> Front
    UI -- "HTTP (via Proxy)" --> Cont
    Front -- "Internal Proxy" --> Back
    Back -- "Tunnel (apiproxy)" --> Work
    Cont -- "State" --> DB
    Work -- "SSH" --> SSH

    %% Styling for light gray background
    style Browser fill:#f9f9f9,stroke:#d3d3d3
    style Docker fill:#f9f9f9,stroke:#d3d3d3
    style App fill:#f9f9f9,stroke:#d3d3d3
    style Boundary fill:#f9f9f9,stroke:#d3d3d3
    style Targets fill:#f9f9f9,stroke:#d3d3d3
```

### Communication Planes
1.  **Identity & Control Plane (Browser -> Backend/Controller):** 
    *   **Login:** The Browser sends LDAP or Password credentials to the Backend's `/auth/login` endpoint. The Backend uses the Boundary Go SDK to exchange these for a Boundary `token`.
    *   **Discovery:** Once logged in, the Browser uses the `token` to call the Boundary Controller directly (via Vite proxy) to fetch `GET /v1/targets`. This leverages Boundary's RBAC to show only authorized targets.
    *   **Authorization:** The Browser calls `POST /v1/targets/:id:authorize-session` directly against the Controller to receive a short-lived `authorization_token`.
2.  **Data Plane (BFF -> Worker):** The Browser establishes a WebSocket to the Backend, passing the `authorization_token`. The Backend uses `apiproxy` to create a secure tunnel to the Boundary Worker and pipes the SSH stream.

### Connection Flow
```mermaid
sequenceDiagram
    participant User as Browser (xterm.js)
    participant LDAP as OpenLDAP
    participant Back as Backend (Go Proxy)
    participant Bound as Boundary (Controller)
    participant Work as Boundary (Worker)
    participant Host as Target Host (SSH)

    Note over User,Back: Phase 1: Identity (Proxied via BFF)
    User->>Back: POST /auth/login (alice/changeme)
    Back->>Bound: SDK: Authenticate (LDAP)
    Bound->>LDAP: Bind User
    LDAP-->>Bound: Success
    Bound-->>Back: session_token
    Back-->>User: token (JWT)

    Note over User,Bound: Phase 2: Discovery & Authz
    User->>Bound: GET /v1/targets (using token)
    Bound-->>User: Scoped Target List (RBAC filtered)
    User->>Bound: POST /v1/targets/:id:authorize-session
    Bound-->>User: authorization_token + worker_endpoint

    Note over User,Host: Phase 3: Data Plane (Managed Tunnel)
    User->>Back: WebSocket /ws/ssh (authorization_token)
    Back->>Back: Start SDK Bridge (apiproxy)
    Back->>Work: Negotiate Tunnel (Mutual TLS)
    Work-->>Back: Local Loopback Ready (127.0.0.1:port)
    
    Note right of Back: [DEBT] BFF injects static credentials
    Back->>Back: Dial SSH via Loopback
    Back->>Work: (SDK Tunnels Traffic)
    Work->>Host: Connect to Target Host
    Host-->>Work: Handshake Success
    Work-->>Back: (Tunnel Stream Established)
    Back-->>User: WebSocket Stream Established
    User->>Host: Secure Shell Session (Bi-directional)
```

- **Backend:** Go (Chi) + Boundary SDK. Bridges Boundary TCP sessions to WebSockets.
- **Frontend:** React + Tailwind CSS + xterm.js.
- **Proxying:** Uses Boundary's `apiproxy` to establish identity-aware tunnels.
- **Auto-Discovery:** The setup script extracts dynamic credentials from Docker logs and injects them into the environment.

## Prerequisites
Before running the demo, ensure you have:
1. **macOS** (The setup scripts are currently optimized for macOS).
2. **Homebrew** (`brew`) installed.
3. **Docker** (Docker Desktop or OrbStack) installed and running.

## One-Button Demo Replay
The fastest way to establish a working demo environment is using the provided Makefile. The process is fully "hermetic" and will verify/install missing system dependencies (like `jq`, `go`, and `node`) via Homebrew automatically.

```bash
make replay
```

This command performs the following sequence:
1.  **Clean:** Wipes all Docker volumes and logs.
2.  **Dependencies (`deps`):** Runs `./scripts/00_check-deps.sh` to ensure `brew`, `jq`, `go`, `node`, and Docker are available.
3.  **Infrastructure & Setup:**
    *   Starts core infrastructure (Postgres, Boundary, SSH Target).
    *   Runs `./scripts/01_setup-boundary.sh` to initialize Boundary and generate credentials.
4.  **Start:** Launches the Backend and Frontend services **inside Docker** using the generated credentials.
5.  **Verify:** Executes `./scripts/02_verify-setup.sh` which validates Docker healthchecks and runs backend unit tests.

## Technical Details
- **SSH Credentials:** The demo is hardcoded to connect to the target as `boundary-user` with password `password`.
- **UI Login:** Pre-filled automatically via Vite environment variables. If fields are empty, check `client/.env.local`.
- **Boundary API:** Accessible at [http://localhost:9200](http://localhost:9200).

## Known Limitations — Hermetic VM Exposure

When running the demo on a hermetic (headless) VM and exposing ports via a tunnel service (e.g. Traefik, Cloudflare Tunnel, or Devin's `deploy expose`), be aware of the following:

### Tunnel Basic Auth breaks SPA Fetch API calls

Most tunnel services authenticate external access by embedding HTTP Basic Auth credentials in the URL (`https://user:token@tunnel-host`). This works for simple page serving but **breaks any Single-Page Application that uses the Fetch API** — the [Fetch specification](https://fetch.spec.whatwg.org/#concept-request-url) rejects requests when the page's origin URL includes credentials.

**Affected:** The Boundary Admin UI (port 9200) is an Ember.js SPA — it shows "ERROR" when accessed through a Basic Auth tunnel because its `/v1/...` API calls are rejected by the browser.

**Not affected:** The Comet Boundary frontend (port 5173) works through tunnels because it uses Vite's server-side proxy for API calls (the browser never makes cross-origin fetch requests directly).

### Recommended development approaches

| Approach | Boundary UI | Comet Frontend | Notes |
|----------|-------------|----------------|-------|
| **Mac-bound development** (preferred) | `localhost:9200` | `localhost:5173` | Full access to all services. Run `make replay` locally. |
| **VNC / Remote Desktop** | `localhost:9200` via VNC | `localhost:5173` via VNC | Access VM desktop directly. No tunnel auth conflicts. |
| **Tunnel exposure** | Not functional (Fetch API limitation) | Functional (with `allowedHosts: true`) | Only the Comet frontend works through tunnels. |

### Vite host allowlisting

Vite 6+ blocks requests from unrecognized hostnames. When exposing the frontend via a tunnel, set `server.allowedHosts: true` in `client/vite.config.ts` or the dev server will return `403 Blocked request`.

### Tunnel proxy Authorization header conflict

Tunnel proxies that use HTTP Basic Auth intercept the `Authorization` header at the proxy level. If the application sends its own tokens via `Authorization`, the proxy will reject them with `401`. Use a custom header (e.g. `X-Boundary-Token`) to avoid the conflict.

## Roadmap & Project Status
The project roadmap, including feature development (Slice 2 RDP) and architectural alignment (HVD), is managed dynamically via GitHub Issues.

- **Active Backlog:** [GitHub Issues](https://github.com/arsenyspb/comet-boundary/issues)
- **HVD Alignment Tracker:** [Issues labeled `hvd-alignment`](https://github.com/arsenyspb/comet-boundary/issues?q=is%3Aopen+is%3Aissue+label%3Ahvd-alignment)

For a detailed breakdown of technical debt and implementation standards, see [CONTRIBUTING.md](./CONTRIBUTING.md).
