# Contributing to Comet Boundary

Welcome to the Comet Boundary project. This document outlines the current state of the prototype, known limitations, and the roadmap for future development slices.

## Project Vision
Comet Boundary aims to provide a zero-install, web-based remote access client for HashiCorp Boundary. It is specifically designed for restricted "Comet" environments where native Boundary desktop clients cannot be installed.

---

## Development Roadmap & Technical Debt
To prevent stale documentation, the project roadmap and technical debt are tracked exclusively via **GitHub Issues**. 

- **Backlog & Tasks:** [GitHub Issues](https://github.com/arsenyspb/comet-boundary/issues)
- **Architectural Alignment:** All changes must align with [HashiCorp Validated Designs (HVD)](./docs/hvd/boundary-operating-guide.md).
- **Standards:** See [AGENTS.md](./AGENTS.md) for automated agent guardrails and coding patterns.

## Engineering Workflow
To contribute:

1.  **Context:** Read [AGENTS.md](./AGENTS.md) and the [HVD Operating Guide](./docs/hvd/boundary-operating-guide.md).
2.  **Environment:** Run `make replay` to establish a fresh, verified baseline.
3.  **Issues:** Pick an issue from the backlog or create a new one to propose a change.
4.  **Validate:** Ensure `./scripts/02_verify-setup.sh` passes before and after your changes.

