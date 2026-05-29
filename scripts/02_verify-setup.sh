#!/bin/bash

# This script verifies that the entire Comet Boundary environment is functional.

echo "=== Verifying Comet Boundary Environment ==="

# 1. Verify dependencies
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required but not installed."; exit 1; }

# 2. Check for .env and load credentials
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
else
    echo "FAIL: .env file not found."
    exit 1
fi

# 3. Run Backend Unit Tests
echo "Running Backend Unit Tests..."
if (cd server && go test ./...); then
    echo "PASS: Backend unit tests passed."
else
    echo "FAIL: Backend unit tests failed."
    exit 1
fi

# 4. Check Boundary Controller Health
if curl -s --fail "$BOUNDARY_ADDR/v1/auth-methods?scope_id=global" > /dev/null; then
    echo "PASS: Boundary Controller API is reachable."
else
    echo "FAIL: Boundary Controller API is unreachable at $BOUNDARY_ADDR."
    exit 1
fi

# 3. Check Boundary Worker Status
echo "Checking Boundary Worker registration..."
TOKEN=$(docker exec -e BOUNDARY_PASSWORD=$BOUNDARY_ADMIN_PASSWORD comet-boundary-controller-1 boundary authenticate password \
    -auth-method-id $BOUNDARY_AUTH_METHOD_ID \
    -login-name admin \
    -password env://BOUNDARY_PASSWORD \
    -format json | jq -r .item.attributes.token)

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    echo "FAIL: Could not authenticate to Boundary to check workers."
    exit 1
fi

WORKER_STATUS=$(docker exec -e BOUNDARY_TOKEN=$TOKEN comet-boundary-controller-1 boundary workers list -format json -token env://BOUNDARY_TOKEN)
NUM_WORKERS=$(echo "$WORKER_STATUS" | jq '.items | length')

if [ "$NUM_WORKERS" -gt 0 ]; then
    echo "PASS: $NUM_WORKERS Boundary worker(s) registered."
else
    echo "FAIL: No Boundary workers registered."
    exit 1
fi

# 4. Check Backend Proxy Health via Docker
echo "Verifying Backend Proxy health state..."
MAX_RETRIES=12
COUNT=0
until [ "$(docker inspect --format='{{json .State.Health.Status}}' comet-boundary-backend-1 2>/dev/null)" = "\"healthy\"" ]; do
    printf '.'
    sleep 5
    COUNT=$((COUNT+1))
    if [ $COUNT -ge $MAX_RETRIES ]; then
        echo "\nFAIL: Backend Proxy failed healthcheck."
        docker logs comet-boundary-backend-1 | tail -n 20
        exit 1
    fi
done
echo "\nPASS: Backend Proxy is healthy (Docker verified)."

# 5. Check Frontend Availability via Docker
echo "Verifying Frontend health state..."
COUNT=0
until [ "$(docker inspect --format='{{json .State.Health.Status}}' comet-boundary-frontend-1 2>/dev/null)" = "\"healthy\"" ]; do
    printf '.'
    sleep 5
    COUNT=$((COUNT+1))
    if [ $COUNT -ge $MAX_RETRIES ]; then
        echo "\nFAIL: Frontend failed healthcheck."
        docker logs comet-boundary-frontend-1 | tail -n 20
        exit 1
    fi
done
echo "\nPASS: Frontend is healthy (Docker verified)."


# 6. Verify Credential Injection
if [ -f client/.env.local ]; then
    if grep -q "VITE_ADMIN_PASSWORD=$BOUNDARY_ADMIN_PASSWORD" client/.env.local; then
        echo "PASS: Frontend .env.local is correctly synchronized."
    else
        echo "FAIL: Frontend .env.local password mismatch."
        exit 1
    fi
else
    echo "FAIL: client/.env.local missing."
    exit 1
fi

echo "=== All checks passed! Demo is ready at http://localhost:5173 ==="
echo "Credentials: admin / $BOUNDARY_ADMIN_PASSWORD"
echo "Target ID: $BOUNDARY_TARGET_ID"
