# ADR 1: Dockerization of Application Services

## Status
Accepted

## Context
The initial implementation of the Go backend and React frontend utilized local background processes (`nohup`). This led to several issues:
1. **Process Reaping:** Shell session termination in transient agent environments killed the application services despite successful verification.
2. **Race Conditions:** Lack of strict dependency management meant services could start before their required configuration (credentials) was generated.
3. **Connectivity Errors:** Resolution issues between the browser, backend, and Boundary infrastructure due to inconsistent `localhost` mapping.

## Decision
We decided to fully containerize the application services and move them into the `docker-compose` orchestration.

Key implementation details:
- **Multi-stage Dockerfiles** for the Go backend and Node/Vite frontend.
- **Strict Health-based Sequencing** using `depends_on` with `service_healthy` and `service_completed_successfully` conditions.
- **Unified Entry Point** via a Vite reverse proxy, consolidating all browser traffic to port 5173.

## Consequences
- **Stability:** Services now have a persistent lifecycle managed by the Docker daemon.
- **Hermeticity:** The "One-Button Replay" is deterministic and guaranteed to be ready before verification runs.
- **Simplified Networking:** Internal service communication uses Docker DNS (e.g., `http://backend:8080`), resolving port/host collision issues.
- **Build Overhead:** Initial builds take longer, but are cached for subsequent replays.
