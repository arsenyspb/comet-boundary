# Comet Boundary ☄️

[![Tier 1 CI](https://github.com/arsenyspb/comet-boundary/actions/workflows/tier1.yml/badge.svg)](https://github.com/arsenyspb/comet-boundary/actions/workflows/tier1.yml)
[![Tier 2 Integration CI](https://github.com/arsenyspb/comet-boundary/actions/workflows/tier2.yml/badge.svg)](https://github.com/arsenyspb/comet-boundary/actions/workflows/tier2.yml)
[![Release](https://github.com/arsenyspb/comet-boundary/actions/workflows/release.yml/badge.svg)](https://github.com/arsenyspb/comet-boundary/actions/workflows/release.yml)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

A zero-install, web-based remote access client for [HashiCorp Boundary](https://www.boundaryproject.io/).

> **Note on Naming:** This project is named after the [Comet programming technique](https://en.wikipedia.org/wiki/Comet_(programming)), an umbrella term for long-held HTTP requests allowing a web server to push data to a browser. This project is a proactive community contribution, and feedback is highly welcomed!

### Why use this?
In enterprise environments with highly restricted laptops, end users often cannot install native desktop clients like the Boundary Desktop app. Comet Boundary solves this by providing secure SSH (and soon RDP) access directly from the browser. It acts as a trusted intermediary, seamlessly translating web traffic into Boundary's native protocols without requiring heavy operators or custom local installations.

---

## Deployment Flow

```text
Terraform Module ──(outputs)──> Helm Chart values.yaml ──(deploys)──> Comet Container
     │ configures                                                          │
     v                                                                     v
Boundary Cluster (existing) <──────(boundary connect subprocess)───── Comet Container
     │
     v
SSH Targets (existing)
```

---

## Quick Start

### Prerequisites
Before getting started, ensure you have the following installed:
- **Docker**: Docker Desktop, OrbStack, or a running Docker daemon.
- **jq**: For JSON processing in setup scripts.
- **Node.js**: For frontend dependencies.
- **Go 1.26+**: For backend compilation.

### For Kubernetes Adopters
Deploy the unified container into your Kubernetes cluster via Helm:
```bash
helm install comet-boundary oci://ghcr.io/arsenyspb/charts/comet-boundary --version 0.1.0
```
> See the [Terraform Module README](./terraform/comet-boundary-integration/README.md) for instructions on provisioning Boundary resources for the Comet container.

### For Local Evaluation (One-Button Demo)
To quickly spin up a fully hermetic demo environment (includes Boundary, OpenLDAP, Postgres, and the Comet App) on macOS:
```bash
make replay
```
This command installs dependencies, bootstraps infrastructure, seeds LDAP test users (`alice`, `bob`, `chris`), and spins up the web UI at `http://localhost:5173`.

> **Want to test Kubernetes locally?** Check out the [Interactive Minikube Demo](kube-demo.ipynb) (a Jupyter Notebook) to explore bridging this local setup into a local cluster.

---

## Documentation
- **Architecture & Build Modes:** Technical deep dives are available in the [Architecture Guide](./docs/architecture.md) and [AGENTS.md](./AGENTS.md).
- **HVD Alignment:** Built strictly according to [HashiCorp Validated Designs](./docs/hvd/boundary-operating-guide.md).

## Contributing
Interested in contributing, tracking known technical debt, or viewing the project roadmap? Please read our [Contributing Guide](./CONTRIBUTING.md) to get started!
