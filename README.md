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

---

## Boundary Audit Logs: Unredacting PII Experiment (poc-oidc)

### Problem Statement
The goal of this experiment was to configure HashiCorp Boundary to display actual user emails or usernames (e.g., `alice@comet.example`) instead of opaque internal UUIDs (e.g., `u_p2H90RO0tm`) within the `authorize-session` JSON audit logs. This aligns with visibility goals while respecting the [Boundary Operating Guides Adoption](https://developer.hashicorp.com/validated-designs/boundary-operating-guides-adoption).

### Boundary's Identity Design
Per the public HVD Operating Guides, Boundary strictly decouples identities:
- **User:** A resource that represents an individual person or entity for the purposes of access control.
- **Account:** A representation of a user's identity within a specific authentication method.
- **Authentication Method:** The mechanism by which users authenticate to Boundary. Can also be integrated with external identity providers like LDAP, Active Directory, or OIDC providers.

Boundary intentionally uses an internal UUID for the `user_id` so a single user can map to multiple authentication methods (IdPs) for flexibility without breaking the immutable audit trail. Because of this, the `user_id` field in the audit log will *always* be the internal UUID and cannot be mapped to an email.

### The Workaround
A well-documented workaround exists to map IdP claims (like email) to the session context, which then appears in the `auth` block of the audit log.
- [HCP Boundary Support: Display User Email Instead of Username with OIDC](https://support.hashicorp.com/hc/en-us/articles/33520715513235-How-to-configure-HCP-Boundary-to-Display-User-Email-Instead-of-Username-with-OIDC-Authentication)
- [Boundary Tutorials: Event Logging - `audit_filter_overrides`](https://developer.hashicorp.com/boundary/tutorials/self-managed-deployment/event-logging#audit_enabled)

To unredact these fields, you can add an `audit_filter_overrides` block to your controller's `sink` configuration:
```hcl
events {
  audit_enabled = true
  sink "stderr" {
    # ...
    audit_config {
      audit_filter_overrides {
        sensitive = "" # Disables redaction for sensitive fields
      }
    }
  }
}
```

### The Caveat: LDAP vs OIDC (`omitempty`)
While this workaround functions perfectly for **OIDC**, it is **not reproducible with LDAP** due to how Boundary handles the session context in memory.

If you apply `sensitive = ""` using an LDAP auth method, the `email` and `name` fields completely disappear from the audit JSON. 

**Source Code Reference:**
If we inspect the Boundary source code at `internal/event/event.go`, the authentication identity fields are defined as:
```go
UserEmail string `json:"email,omitempty" class:"sensitive"`
UserName  string `json:"name,omitempty" class:"sensitive"`
```

**Why this happens:**
1. **OIDC:** Boundary automatically copies OIDC identity claims directly into the active session context in memory.
2. **LDAP:** Boundary does *not* natively populate the `email` and `name` fields into the session context during an LDAP authentication. In memory, they remain empty strings `""`.
3. **Redaction ON (Default):** The redaction engine sees the `class:"sensitive"` tag and forcefully overwrites the empty strings with `"[REDACTED]"`. Since the strings now have a value, they are marshaled into the JSON output.
4. **Redaction OFF (`sensitive = ""`):** The redaction engine skips the fields, leaving them as empty strings. When the JSON marshaller processes the event, the `omitempty` struct tag triggers, entirely dropping the `email` and `name` keys from the resulting JSON payload.

Thus, to achieve cleartext email logging natively in Boundary audit events, an OIDC provider is strictly required.
