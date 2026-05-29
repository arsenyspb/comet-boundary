# Project: Comet Boundary

## 🚀 First-Run Access Instructions
Once the environment is initialized (via `make replay`), use the following details to access the system:

- **Comet Web UI:** [http://localhost:5173](http://localhost:5173) (Custom SSH client)
- **Native Boundary UI:** [http://localhost:9200](http://localhost:9200) (Admin console)
- **Credentials:**
  - **Username:** `admin`
  - **Password:** (Check `.env` file for the latest generated `ADMIN_PASSWORD`)
- **Pre-filled Resource IDs:**
  - **Auth Method ID:** (Check `.env` for `AUTH_METHOD_ID`)
  - **Target ID:** (Check `.env` for `TARGET_ID`)

---

## Overview
Comet Boundary is a web-based client for HashiCorp Boundary, designed for users in restricted "Comet" environments who cannot use native thick clients.

## Tech Stack
- **Frontend:** React (TypeScript), Tailwind CSS, Vite.
- **Backend:** Go (Chi), Boundary SDK, WebSockets.
- **Infrastructure:** Docker (Postgres, Boundary Controller/Worker, SSH Target).

---

## Agent Initialization & Replay
When a Gemini agent initializes this workspace, the **mandatory first step** is to establish a verified demo environment.

### 1. Verification of the Current State
Agents should run the verification script to check if a previously started environment is still functional:
```bash
./scripts/02_verify-setup.sh
```

### 2. The "One-Button" Replay
If no environment is running, or if a clean state is required, use:
```bash
make replay
```
**Expectation:** This command MUST result in a passing verification script. If it fails, check `docker logs comet-boundary-setup-1` to ensure credentials were extracted correctly.

> **Note for Agents:** The `make replay` command is fully hermetic. It will automatically check for and install missing system dependencies (`jq`, `go`, `node`) via Homebrew. You do not need to attempt to install these manually if they are missing; the bootstrap process handles it.

### 3. Critical Environment Variables
Dynamic configuration is handled via:
- `.env`: Used by the Go backend (included in `Makefile`).
- `client/.env.local`: Used by Vite/Frontend (auto-generated, git-ignored).

---

## Agent Task Checklist
- [x] **Boundary Source:** `boundary/` directory exists (ignored).
- [x] **Config Integration:** `Makefile` includes `.env` and exports it to the backend.
- [x] **Frontend Injection:** `App.tsx` uses `import.meta.env` for pre-filled data.
- [x] **Infrastructure Health:** Run `make replay` to establish a fresh environment. All services (including Backend/Frontend) now run in Docker for maximum stability.

---

## Architectural Decision Records (ADR)
All significant architectural choices must be recorded in `docs/adr/`. These should be concise, semantic, and provide context for why a specific path was chosen over alternatives.

## Agent Memory & Planning
- **Plans:** The `/plans` directory is a **private scratchpad** managed by the CLI runtime. It is used for staging implementation details and must **NEVER** be committed to the repository.
- **ADRs:** Use `docs/adr/` for persistent, team-visible decisions.
- **Incremental Slices:** Work proceeds through vertical slices (Slice 1: SSH, Slice 2: RDP).
- **Persistence:** All services run in Docker. Use `make stop` or `make clean` for lifecycle management.
