---
name: testing-comet-boundary
description: Test the Comet Boundary SSH proxy end-to-end. Use when verifying credential brokering, RBAC isolation, or the full login-to-SSH flow.
---

# Testing Comet Boundary

## Prerequisites

- Docker and Docker Compose v2 must be available
- The Makefile uses `docker-compose` (hyphenated) but newer systems only have `docker compose` (space). If `make replay` fails with "No such file or directory", use `docker compose` commands directly.

## Environment Setup

The project uses Docker Compose with these services:
- `postgres` — Boundary database
- `openldap` — LDAP directory for alice/bob users
- `setup` — Database initialization (runs once)
- `controller` — Boundary controller (port 9200)
- `worker` — Boundary worker (port 9202)
- `ssh-target-1`, `ssh-target-2` — SSH targets
- `backend` — Go BFF (port 8080 internal)
- `frontend` — React/Vite app (port 5173)

### Startup Sequence (if `make replay` doesn't work)

```bash
cd /path/to/comet-boundary
docker compose down -v
rm -f .env client/.env.local
docker compose up -d postgres openldap setup
docker wait comet-boundary-setup-1
docker compose up -d controller worker ssh-target-1 ssh-target-2
# Wait for controller to be healthy
bash scripts/01_setup-boundary.sh
docker compose up -d --build backend frontend
```

### Verify All Services Healthy

```bash
docker compose ps  # All should show "healthy" or "Up"
```

## Test Credentials

- **Boundary Admin**: username `admin`, password from setup script output (look for "Discovered Admin Password: ...")
- **LDAP Users**: `alice / changeme` (Team A), `bob / changeme` (Team B)
- **SSH credential (brokered)**: username `boundary-user`, password `password` — stored in Boundary's Static Credential Store

## Key Test Scenarios

### 1. Credential Store Verification (Boundary Admin UI, port 9200)

1. Log in as admin at `http://localhost:9200`
2. Navigate: Generated org scope → Generated project scope → Credential Stores
3. Verify "SSH Credential Store" exists (type: Static)
4. Click into it → Credentials tab → verify "SSH Target Credential" exists (type: Username & Password)
5. Navigate to Targets → "A Team Host" → Brokered Credentials tab → verify credential is linked
6. Same for "B Team Host"

### 2. Team A End-to-End (Frontend, port 5173)

1. Open `http://localhost:5173`
2. Auth Method: LDAP (should be default)
3. Login: `alice` / `changeme`
4. Verify only "A Team Host" appears in dropdown (RBAC isolation)
5. Select target, click Connect
6. Verify SSH terminal shows `Welcome to OpenSSH Server` and `ssh-host-1:~$`
7. Verify NO red "WebSocket connection failed" error banner appears

### 3. Team B End-to-End (Frontend, port 5173)

1. Refresh page to return to login
2. Login: `bob` / `changeme`
3. Verify only "B Team Host" appears (RBAC isolation)
4. Select target, click Connect
5. Verify SSH terminal shows `Welcome to OpenSSH Server` and `ssh-host-2:~$`
6. Verify NO red error banner appears

### 4. Negative Case (No Hardcoded Fallback)

```bash
docker exec comet-boundary-backend-1 env | grep -i ssh
# Should return empty — no SSH_PASSWORD or SSH_USER env vars
```

### 5. API-Level Verification (Optional)

```bash
source .env
ALICE_TOKEN=$(docker exec -e BOUNDARY_PASSWORD=changeme comet-boundary-controller-1 \
  boundary authenticate ldap \
  -auth-method-id $BOUNDARY_LDAP_AUTH_METHOD_ID \
  -login-name alice \
  -password env://BOUNDARY_PASSWORD \
  -format json | jq -r .item.attributes.token)

curl -s -X POST \
  -H "Authorization: Bearer $ALICE_TOKEN" \
  "http://localhost:9200/v1/targets/$BOUNDARY_TARGET_ID:authorize-session" | \
  jq '.credentials[].credential'
# Should return {"username": "boundary-user", "password": "password"}
```

## Common Issues

- **`make replay` fails**: The Makefile uses `docker-compose` (hyphenated). Use `docker compose` directly or create a symlink.
- **Setup script fails at credential store creation**: Ensure controller is fully healthy before running. Wait for `docker compose ps` to show controller as healthy.
- **Frontend shows "Credential brokering failed"**: The credential source might not be linked to the target. Re-run `scripts/01_setup-boundary.sh`.
- **SSH connection timeout**: Worker might not be healthy yet. Check `docker compose ps` and wait for worker health.
- **React StrictMode double WebSocket connections**: In dev mode (`<StrictMode>`), `useEffect` runs twice. This creates two WebSocket connections to `/ws/ssh` per Connect click — the first gets `close 1001 (going away)` in backend logs. The `TerminalView.tsx` component uses a `cancelled` flag to prevent the stale first connection from showing a red error banner. If you see `Read initial message error: websocket: close 1001 (going away)` in backend logs, this is expected StrictMode behavior and is harmless.

## Devin Secrets Needed

No external secrets required — all credentials are bootstrapped locally by the setup script.
