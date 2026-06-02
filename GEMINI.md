# Project: Comet Boundary (Gemini CLI Context)

## 🎯 Model-Specific Instructions
This file provides Gemini-specific strategies for operating within this repository. For general architectural grounding, refer to [AGENTS.md](./AGENTS.md).

### 1. Context Efficiency
- **State Discovery:** Use `gh issue list` to identify active tasks before proposing changes.
- **Environment State:** Run `./scripts/02_verify-setup.sh` as your first turn to establish a verified baseline.
- **Log Inspection:** When debugging, use `docker logs` for the relevant service (backend/frontend) rather than reading massive log files.

### 2. Tool-Calling Optimization
- **Parallelism:** You can run `grep_search` and `glob` in parallel to map dependencies quickly.
- **Surgical Edits:** Favor the `replace` tool over `write_file` for existing components to minimize token usage.
- **Sequential Dependencies:** If a tool depends on the side-effect of a previous one (e.g., `make setup` before `make start`), set `wait_for_previous: true`.

### 3. Architectural Standards
- **HVD Alignment:** All planning, architectural decisions, and infrastructure implementations MUST align with HashiCorp Validated Designs. Before proposing changes or writing configuration, you MUST read the relevant guides in `docs/hvd/` and validate your approach against them.

---

## 🚀 First-Run Access
If you are starting a new session, verify the environment:
```bash
./scripts/02_verify-setup.sh
```
If verification fails, establish a fresh state:
```bash
make replay
```
**Access Details:** Check `.env` for generated credentials and target IDs.

