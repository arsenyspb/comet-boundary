# LLM Context Guide (AGENTS.md)

This document serves as the **System Prompt Extension** for all AI agents (Gemini, Devin, Claude, etc.) operating in the Comet Boundary repository. It prioritizes project-specific technical standards, architectural direction, and operational requirements.

---

## 🚨 Critical Guardrails

Before submitting any code or declaring a task complete, you **MUST** ensure the following:

1.  **Demo Integrity:** The environment must be reproducible via `make replay`.
2.  **Verification:** Every change must pass `./scripts/02_verify-setup.sh`.
3.  **Credential Protection:** Never hardcode credentials. Use `.env` (backend) or `client/.env.local` (frontend).
4.  **No "Just-in-Case" Code:** Avoid adding features or "cleanup" outside the explicit scope of your task.

---

## 🏗️ Architectural Mapping

### Directory Overview
- `server/`: Go-based SSH/RDP proxy. Uses Chi and the Boundary Go SDK.
- `client/`: React + Vite + TypeScript frontend. UI for terminal and RDP canvas.
- `docker/`: Infrastructure definitions for Boundary, Postgres, and target systems.
- `scripts/`: Critical bootstrap and verification logic.

### State & Truth
- **Roadmap:** The dynamic roadmap is maintained in [GitHub Issues](https://github.com/arsenyspb/comet-boundary/issues).
- **Credentials:** Infrastructure IDs (Target ID, Auth Method ID) are dynamically generated and injected into `.env` files by `scripts/01_setup-boundary.sh`.

---

## 🛠️ Common Procedures

### 1. Resetting the Environment
If the environment becomes inconsistent or unreachable:
```bash
make replay
```

### 2. Checking Logs
- **Backend:** `docker logs comet-boundary-backend-1`
- **Frontend:** `docker logs comet-boundary-frontend-1`
- **Setup:** `docker logs comet-boundary-setup-1` (Check this if `make replay` fails).

---

## 🎯 Legacy vs. Target Patterns

| Pattern | Status | Target Pattern |
| :--- | :--- | :--- |
| `InsecureIgnoreHostKey()` | **DEBT** | Use proper host key verification logic. |
| Hardcoded fallback IDs | **DEBT** | Mandatory environment variable validation. |
| `VITE_` login pre-fills | **DEBT** | Standard secure login flow (OIDC/SAML). |
| Shared SSH Credentials | **DEBT** | Dynamic injection via Boundary/Vault. |

---

## 🏛️ Architectural Alignment

### HashiCorp Validated Designs (HVD)
This project strictly follows HVD best practices for Boundary and Vault. All agents **MUST** reference the documentation in `docs/hvd/` when making architectural decisions or proposing infrastructure changes.

---

## 🤖 Model-Specific Tips

- **Devin:** See `.devin/environment.yaml` for VM initialization steps.
- **Gemini:** Check `GEMINI.md` for context-efficiency strategies and tool-calling optimization.
