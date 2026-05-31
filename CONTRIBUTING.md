# Contributing to Comet Boundary

Welcome to the Comet Boundary project. This document outlines the current state of the prototype, known limitations, and the roadmap for future development slices.

## Project Vision
Comet Boundary aims to provide a zero-install, web-based remote access client for HashiCorp Boundary. It is specifically designed for restricted "Comet" environments where native Boundary desktop clients cannot be installed.

---

## Development Roadmap
The project roadmap is dynamically managed via **GitHub Issues**. This allows AI agents and human contributors to track state and progress in real-time.

- **Current Backlog:** [GitHub Issues](https://github.com/arsenyspb/comet-boundary/issues)
- **Technical Standards:** See [AGENTS.md](./AGENTS.md) for architectural guardrails and "Legacy vs. Target" patterns.

## Engineering Workflow
To contribute:

1.  **Context:** Read [AGENTS.md](./AGENTS.md) to understand the technical grounding.
2.  **Environment:** Run `make replay` to establish a fresh environment.
3.  **Validate:** Ensure `./scripts/02_verify-setup.sh` passes before and after your changes.
4.  **Issues:** Pick an issue from the backlog and update its status via the `gh` tool or GitHub UI.

