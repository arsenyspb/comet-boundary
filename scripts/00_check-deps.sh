#!/bin/bash

# 00_check-deps.sh
# Verifies system-level dependencies for Comet Boundary.

set -e

echo "=== Checking System Dependencies ==="

# 1. Check for jq (Critical for JSON parsing in setup scripts)
if ! command -v jq >/dev/null 2>&1; then
    echo "FAIL: jq is not installed. Please install it using your system's package manager (e.g., 'brew install jq' on macOS or 'apt-get install jq' on Linux)."
    exit 1
else
    echo "PASS: jq is installed."
fi

# 2. Check for Go (Required for Backend)
if ! command -v go >/dev/null 2>&1; then
    echo "FAIL: go is not installed. Please install Go 1.26+ (e.g., 'brew install go' on macOS or via your distribution's package manager)."
    exit 1
else
    echo "PASS: Go is installed."
fi

# 3. Check for Node.js (Required for Frontend)
if ! command -v node >/dev/null 2>&1; then
    echo "FAIL: node is not installed. Please install Node.js (e.g., 'brew install node' on macOS or via your distribution's package manager)."
    exit 1
else
    echo "PASS: Node is installed."
fi

# 4. Check for Docker Daemon
if ! command -v docker >/dev/null 2>&1; then
    echo "FAIL: Docker is not installed. Please install Docker."
    exit 1
fi
if ! docker info >/dev/null 2>&1; then
    echo "FAIL: Docker daemon is not running. Please start Docker Desktop, OrbStack, or the docker service."
    exit 1
fi
echo "PASS: Docker daemon is running."

echo "=== All system dependencies verified! ==="
