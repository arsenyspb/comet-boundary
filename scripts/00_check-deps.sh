#!/bin/bash

# 00_check-deps.sh
# Verifies and installs system-level dependencies for Comet Boundary.
# Targets a bare MacBook with Homebrew installed.

set -e

echo "=== Checking System Dependencies ==="

# 1. Check for Homebrew
if ! command -v brew >/dev/null 2>&1; then
    echo "FAIL: Homebrew is not installed. Please install it from https://brew.sh/"
    exit 1
fi
echo "PASS: Homebrew is installed."

# 2. Check/Install jq (Critical for JSON parsing in setup scripts)
if ! command -v jq >/dev/null 2>&1; then
    echo "Installing jq..."
    brew install jq
else
    echo "PASS: jq is installed."
fi

# 3. Check/Install Go (Required for Backend)
if ! command -v go >/dev/null 2>&1; then
    echo "Installing go..."
    brew install go
else
    echo "PASS: Go is installed."
fi

# 4. Check/Install Node.js (Required for Frontend)
if ! command -v node >/dev/null 2>&1; then
    echo "Installing node..."
    brew install node
else
    echo "PASS: Node is installed."
fi

# 5. Check for Docker Daemon
if ! docker info >/dev/null 2>&1; then
    echo "FAIL: Docker daemon is not running. Please start Docker Desktop or OrbStack."
    exit 1
fi
echo "PASS: Docker daemon is running."

echo "=== All system dependencies verified! ==="
