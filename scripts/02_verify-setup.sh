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
    echo "FAIL: Could not authenticate to Boundary as admin."
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

# 3b. Verify HVD Abstraction (Catalogs, Sets, Hosts)
echo "Verifying HVD Host Abstraction..."
CATALOG_ID=$(docker exec -e BOUNDARY_TOKEN=$TOKEN comet-boundary-controller-1 boundary host-catalogs list -scope-id global -recursive -format json -token env://BOUNDARY_TOKEN | jq -r '.items[] | select(.name == "Standard Infrastructure") | .id')
if [ -z "$CATALOG_ID" ]; then echo "FAIL: Host Catalog not found."; exit 1; fi

HOST_COUNT=$(docker exec -e BOUNDARY_TOKEN=$TOKEN comet-boundary-controller-1 boundary hosts list -host-catalog-id $CATALOG_ID -format json -token env://BOUNDARY_TOKEN | jq '.items | length')
if [ "$HOST_COUNT" -ge 2 ]; then
    echo "PASS: $HOST_COUNT hosts discovered in HVD catalog."
else
    echo "FAIL: Expected at least 2 hosts, found $HOST_COUNT."
    exit 1
fi

HOST_SET_ID=$(docker exec -e BOUNDARY_TOKEN=$TOKEN comet-boundary-controller-1 boundary host-sets list -host-catalog-id $CATALOG_ID -format json -token env://BOUNDARY_TOKEN | jq -r '.items[0].id')
if [ -z "$HOST_SET_ID" ]; then echo "FAIL: Host Set not found."; exit 1; fi
echo "PASS: HVD Host Abstraction verified."

# 3c. Verify Multi-User LDAP Authentication & Team Scoping
echo "Verifying Multi-User LDAP Authentication & Team Scoping..."

# Identify Target IDs for cross-testing
TARGET_A_ID=$(curl -s -H "Authorization: Bearer $TOKEN" "$BOUNDARY_ADDR/v1/targets?scope_id=$BOUNDARY_PROJECT_ID" | jq -r '.items[] | select(.name == "A Team Host") | .id')
TARGET_B_ID=$(curl -s -H "Authorization: Bearer $TOKEN" "$BOUNDARY_ADDR/v1/targets?scope_id=$BOUNDARY_PROJECT_ID" | jq -r '.items[] | select(.name == "B Team Host") | .id')

for USER in "alice" "bob"; do
    USER_TOKEN=$(docker exec -e BOUNDARY_PASSWORD=changeme comet-boundary-controller-1 boundary authenticate ldap \
        -auth-method-id $BOUNDARY_LDAP_AUTH_METHOD_ID \
        -login-name $USER \
        -password env://BOUNDARY_PASSWORD \
        -format json | jq -r .item.attributes.token)
    
    if [ -z "$USER_TOKEN" ] || [ "$USER_TOKEN" = "null" ]; then
        echo "FAIL: LDAP Authentication failed for user $USER."
        exit 1
    fi
    echo "PASS: LDAP Authentication successful for $USER."

    # Check scoped target visibility
    TARGETS=$(curl -s -H "Authorization: Bearer $USER_TOKEN" "$BOUNDARY_ADDR/v1/targets?recursive=true&scope_id=global")
    
    if [ "$USER" = "alice" ]; then
        MY_TARGET=$TARGET_A_ID
        OTHER_TARGET=$TARGET_B_ID
        TARGET_NAME="A Team Host"
        OTHER_NAME="B Team Host"
        EXPECTED_HOST_NAME="ssh-host-1"
    else
        MY_TARGET=$TARGET_B_ID
        OTHER_TARGET=$TARGET_A_ID
        TARGET_NAME="B Team Host"
        OTHER_NAME="A Team Host"
        EXPECTED_HOST_NAME="ssh-host-2"
    fi

    # Positive Discovery
    if echo "$TARGETS" | jq -e ".items[] | select(.id == \"$MY_TARGET\")" > /dev/null; then
        echo "PASS: $USER can see $TARGET_NAME."
    else
        echo "FAIL: $USER cannot see $TARGET_NAME."
        exit 1
    fi

    # Negative Discovery
    if echo "$TARGETS" | jq -e ".items[] | select(.id == \"$OTHER_TARGET\")" > /dev/null; then
        echo "FAIL: $USER can see $OTHER_NAME (should be hidden)."
        exit 1
    else
        echo "PASS: $USER cannot see $OTHER_NAME."
    fi

    # Negative Authorization (Crucial Security Test)
    AUTH_RESP=$(curl -s -H "Authorization: Bearer $USER_TOKEN" -X POST "$BOUNDARY_ADDR/v1/targets/$OTHER_TARGET:authorize-session")
    if echo "$AUTH_RESP" | jq -e '.kind == "PermissionDenied"' > /dev/null; then
        echo "PASS: $USER was correctly denied access to $OTHER_NAME."
    else
        echo "FAIL: $USER was NOT denied access to $OTHER_NAME (RBAC failure!)."
        exit 1
    fi

    # Positive Authorization & Session Pinning Verification
    echo "Verifying Session Pinning for $USER..."
    AUTH_RESP=$(curl -s -H "Authorization: Bearer $USER_TOKEN" -X POST "$BOUNDARY_ADDR/v1/targets/$MY_TARGET:authorize-session")
    SESSION_ID=$(echo "$AUTH_RESP" | jq -r '.session_id')
    
    if [ -z "$SESSION_ID" ] || [ "$SESSION_ID" = "null" ]; then
        echo "FAIL: Could not authorize session for $USER against $TARGET_NAME."
        exit 1
    fi

    # Inspect the session to see which host was assigned
    # Note: We need admin token to read the session details usually, or the user needs read:self
    ASSIGNED_HOST_ID=$(docker exec -e BOUNDARY_TOKEN=$TOKEN comet-boundary-controller-1 boundary sessions read -id $SESSION_ID -format json -token env://BOUNDARY_TOKEN | jq -r '.item.host_id')
    HOST_NAME=$(docker exec -e BOUNDARY_TOKEN=$TOKEN comet-boundary-controller-1 boundary hosts read -id $ASSIGNED_HOST_ID -format json -token env://BOUNDARY_TOKEN | jq -r '.item.name')

    if [ "$HOST_NAME" = "$EXPECTED_HOST_NAME" ]; then
        echo "PASS: $USER session pinned to $HOST_NAME as expected."
    else
        echo "FAIL: $USER session landed on $HOST_NAME (expected $EXPECTED_HOST_NAME)."
        exit 1
    fi
    
    # Clean up the test session
    docker exec -e BOUNDARY_TOKEN=$TOKEN comet-boundary-controller-1 boundary sessions cancel -id $SESSION_ID -token env://BOUNDARY_TOKEN > /dev/null
done

# 3d. Verify Container Hostnames
echo "Verifying Container Hostnames..."
for i in 1 2; do
    HN=$(docker exec comet-boundary-ssh-target-$i-1 hostname)
    if [ "$HN" = "ssh-host-$i" ]; then
        echo "PASS: Target $i hostname is $HN."
    else
        echo "FAIL: Target $i hostname mismatch (expected ssh-host-$i, got $HN)."
        exit 1
    fi
done

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

echo "================================================================"
echo "🎉 🚀 === All checks passed! Demo is ready! === 🚀 🎉"
echo "🌐 Web App URL:      http://localhost:5173"
echo "🎯 Target ID:         $BOUNDARY_TARGET_ID"
echo "----------------------------------------------------------------"
echo "🛡️  Boundary URL:      http://localhost:9200"
echo "🔑 Admin Credentials: admin / $BOUNDARY_ADMIN_PASSWORD"
echo "👥 LDAP Users:        alice / changeme (Team A)"
echo "                      bob   / changeme (Team B)"
echo "                      chris / changeme (Cross-Team)"
echo "================================================================"
