# Comet Boundary Engineering Rules (Policy-as-Code)

## 🎯 Core Mandate: HVD Alignment
All planning, architectural decisions, and infrastructure implementations MUST align with HashiCorp Validated Designs (HVD). 

### 1. Self-Critique & Subagent Delegation
- **Context Efficiency**: Do NOT pollute your main session context with long architectural debates or documentation parsing.
- **Mandatory Subagent Use**: Before implementing any structural change, you MUST invoke a subagent (e.g., `codebase_investigator` or a new session) to:
    1. Analyze the proposed design against `docs/hvd/boundary-solution-design-guide.md` (Design) and `docs/hvd/boundary-operating-guide.md` (Adoption).
    2. Provide a "HVD Compliance Score" and identify specific risks.
- **Verification**: Only proceed with implementation once the subagent confirms alignment or identifies a necessary deviation for the demo environment.

### 2. Architecture & Patterns
- **Thin Gateway**: For the BFF, prioritize the "Thin Protocol Gateway" pattern. Avoid embedding heavy SDK logic that couples application state to the transport layer.
- **Credential Brokering**: NEVER handle user passwords or SSH secrets in Go code. Use Boundary's Static Credential Stores and Libraries to inject credentials into authorized sessions.
- **Surgical Edits**: Favor the `replace` tool over rewriting entire files to maintain git history and context signal.

### 3. Operational Integrity
- **Determinism**: Every change MUST be verified using `./scripts/02_verify-setup.sh`.
- **Bootstrapping**: When adding new infrastructure (e.g., OpenLDAP), ensure the setup script is idempotent and handles dependency sequencing (Wait-for-Service) to avoid race conditions.
- **Cleanup**: Ensure `make replay` remains the "gold standard" for a clean, verified state.
