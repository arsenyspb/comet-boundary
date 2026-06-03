#!/bin/bash

# This script initializes the Boundary targets and configurations required for the Comet Boundary demo.
# It is designed to be idempotent and robust for Gemini/agent use.

BOUNDARY_ADDR="http://localhost:9200"
MAX_RETRIES=30

# 1. Verify dependencies
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required but not installed."; exit 1; }

# 2. Wait for Boundary API to be healthy
echo "Waiting for Boundary API at $BOUNDARY_ADDR to be healthy..."
COUNT=0
# Using /v1/auth-methods?scope_id=global as a reliable health check
until $(curl --output /dev/null --silent --fail "$BOUNDARY_ADDR/v1/auth-methods?scope_id=global"); do
    printf '.'
    sleep 2
    COUNT=$((COUNT+1))
    if [ $COUNT -ge $MAX_RETRIES ]; then
        echo "\nTimeout waiting for Boundary API."
        docker logs comet-boundary-controller-1
        exit 1
    fi
done
echo "\nBoundary is healthy."

# 2. Extract credentials from setup container logs
echo "Discovering initial credentials..."
docker logs comet-boundary-setup-1 > .setup_logs.tmp

BOUNDARY_AUTH_METHOD_ID=$(grep "Auth Method ID:" .setup_logs.tmp | head -n 1 | awk '{print $NF}')
BOUNDARY_ADMIN_PASSWORD=$(grep "Password:" .setup_logs.tmp | head -n 1 | awk '{print $NF}')
PROJECT_ID=$(grep -A 5 "Initial project scope information" .setup_logs.tmp | grep "Scope ID:" | head -n 1 | awk '{print $NF}')

rm -f .setup_logs.tmp

if [ -z "$BOUNDARY_AUTH_METHOD_ID" ] || [ -z "$BOUNDARY_ADMIN_PASSWORD" ] || [ -z "$PROJECT_ID" ]; then
    echo "Failed to discover credentials or Project ID from setup logs."
    exit 1
fi

echo "Discovered Auth Method ID: $BOUNDARY_AUTH_METHOD_ID"
echo "Discovered Admin Password: $BOUNDARY_ADMIN_PASSWORD"
echo "Discovered Project ID: $PROJECT_ID"

# 3. Authenticating to Boundary
echo "Authenticating to Boundary..."
TOKEN=$(docker exec -e BOUNDARY_PASSWORD=$BOUNDARY_ADMIN_PASSWORD comet-boundary-controller-1 boundary authenticate password \
    -auth-method-id $BOUNDARY_AUTH_METHOD_ID \
    -login-name admin \
    -password env://BOUNDARY_PASSWORD \
    -format json | jq -r .item.attributes.token)

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    echo "Failed to authenticate."
    exit 1
fi

echo "Successfully authenticated."

# 4. Create a Clean Target
echo "Creating direct-address target for 'ssh-target'..."
TARGET_ID=$(docker exec -e BOUNDARY_TOKEN=$TOKEN comet-boundary-controller-1 boundary targets create tcp \
    -name "Comet SSH Target" \
    -description "Production SSH target for Comet Boundary demo" \
    -address "ssh-target" \
    -default-port 2222 \
    -scope-id $PROJECT_ID \
    -token env://BOUNDARY_TOKEN \
    -format json | jq -r .item.id)

if [ -z "$TARGET_ID" ] || [ "$TARGET_ID" = "null" ]; then
    echo "Failed to create target."
    exit 1
fi

echo "Created Target ID: $TARGET_ID"

# 5. Configure LDAP Auth Method
echo "Configuring LDAP Auth Method..."

# Wait for OpenLDAP to be reachable from the controller network
echo "Waiting for OpenLDAP to be ready..."
LDAP_RETRIES=0
until docker exec comet-boundary-controller-1 sh -c "nc -z openldap 389" 2>/dev/null; do
    printf '.'
    sleep 2
    LDAP_RETRIES=$((LDAP_RETRIES+1))
    if [ $LDAP_RETRIES -ge 15 ]; then
        echo "\nTimeout waiting for OpenLDAP."
        exit 1
    fi
done
echo "\nOpenLDAP is reachable."

ORG_ID=$(curl -s -H "Authorization: Bearer $TOKEN" "$BOUNDARY_ADDR/v1/scopes?scope_id=global" | jq -r '.items[] | select(.type == "org") | .id' | head -n 1)
if [ -z "$ORG_ID" ] || [ "$ORG_ID" = "null" ]; then
    echo "Failed to discover org scope."
    exit 1
fi
echo "Discovered Org ID: $ORG_ID"

LDAP_AUTH_METHOD_ID=$(curl -s -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"scope_id\": \"$ORG_ID\",
        \"type\": \"ldap\",
        \"name\": \"LDAP\",
        \"description\": \"OpenLDAP Identity Provider\",
        \"attributes\": {
            \"urls\": [\"ldap://openldap:389\"],
            \"user_dn\": \"ou=people,dc=comet,dc=example\",
            \"user_attr\": \"uid\",
            \"group_dn\": \"ou=groups,dc=comet,dc=example\",
            \"group_attr\": \"cn\",
            \"group_filter\": \"(member={{.UserDN}})\",
            \"enable_groups\": true,
            \"bind_dn\": \"cn=admin,dc=comet,dc=example\",
            \"bind_password\": \"admin\",
            \"state\": \"active-public\",
            \"insecure_tls\": true
        }
    }" \
    "$BOUNDARY_ADDR/v1/auth-methods" | jq -r '.id')

if [ -z "$LDAP_AUTH_METHOD_ID" ] || [ "$LDAP_AUTH_METHOD_ID" = "null" ]; then
    echo "Failed to create LDAP auth method."
    exit 1
fi
echo "Created LDAP Auth Method ID: $LDAP_AUTH_METHOD_ID"

# Set LDAP as primary auth method for org scope (enables user auto-creation on first login)
echo "Setting LDAP as primary auth method for org scope..."
ORG_VERSION=$(curl -s -H "Authorization: Bearer $TOKEN" "$BOUNDARY_ADDR/v1/scopes/$ORG_ID" | jq -r '.version')
curl -s -X PATCH \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"version\": $ORG_VERSION,
        \"primary_auth_method_id\": \"$LDAP_AUTH_METHOD_ID\"
    }" \
    "$BOUNDARY_ADDR/v1/scopes/$ORG_ID" > /dev/null
echo "LDAP set as primary auth method for org scope."

# 6. Create LDAP Managed Group for 'engineering'
echo "Creating Managed Group for 'engineering' LDAP group..."

MANAGED_GROUP_ID=$(curl -s -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"auth_method_id\": \"$LDAP_AUTH_METHOD_ID\",
        \"type\": \"ldap\",
        \"name\": \"Engineering Team\",
        \"description\": \"Maps to LDAP engineering group\",
        \"attributes\": {
            \"group_names\": [\"engineering\"]
        }
    }" \
    "$BOUNDARY_ADDR/v1/managed-groups" | jq -r '.id')

if [ -z "$MANAGED_GROUP_ID" ] || [ "$MANAGED_GROUP_ID" = "null" ]; then
    echo "Failed to create managed group."
    exit 1
fi
echo "Created Managed Group ID: $MANAGED_GROUP_ID"

# 7. Create Role for Managed Group with permissions to access the SSH Target
echo "Establishing RBAC for Managed Group..."

ROLE_ID=$(curl -s -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"scope_id\": \"$PROJECT_ID\",
        \"name\": \"Engineering SSH Access\",
        \"description\": \"Grants engineering team access to SSH targets\"
    }" \
    "$BOUNDARY_ADDR/v1/roles" | jq -r '.id')

if [ -z "$ROLE_ID" ] || [ "$ROLE_ID" = "null" ]; then
    echo "Failed to create role."
    exit 1
fi
echo "Created Role ID: $ROLE_ID"

# Add managed group as principal
curl -s -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"principal_ids\": [\"$MANAGED_GROUP_ID\"],
        \"version\": 1
    }" \
    "$BOUNDARY_ADDR/v1/roles/$ROLE_ID:add-principals" > /dev/null

# Add grants for target authorization and session management
curl -s -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"grant_strings\": [
            \"ids=$TARGET_ID;actions=authorize-session\",
            \"ids=*;type=target;actions=list,no-op,read\",
            \"ids=*;type=session;actions=list,no-op,read:self,cancel:self\"
        ],
        \"version\": 2
    }" \
    "$BOUNDARY_ADDR/v1/roles/$ROLE_ID:add-grants" > /dev/null

echo "RBAC configured: Engineering team can access SSH target."

# 8. Synchronize .env
echo "Synchronizing .env..."
cat <<EOF > .env
BOUNDARY_ADDR=$BOUNDARY_ADDR
BOUNDARY_AUTH_METHOD_ID=$BOUNDARY_AUTH_METHOD_ID
BOUNDARY_LDAP_AUTH_METHOD_ID=$LDAP_AUTH_METHOD_ID
BOUNDARY_ADMIN_USER=admin
BOUNDARY_ADMIN_PASSWORD=$BOUNDARY_ADMIN_PASSWORD
BOUNDARY_TARGET_ID=$TARGET_ID
EOF

# 9. Synchronize Frontend defaults (Inject via .env.local)
echo "Synchronizing Frontend defaults..."
cat <<EOF > client/.env.local
VITE_LDAP_AUTH_METHOD_ID=$LDAP_AUTH_METHOD_ID
VITE_TARGET_ID=$TARGET_ID
EOF

echo "--------------------------------------------------"
echo "Boundary initialization complete."
echo "Target ID: $TARGET_ID"
echo "LDAP Auth Method ID: $LDAP_AUTH_METHOD_ID"
echo "LDAP users can log in with their directory credentials."
echo "  Example: alice / changeme"
echo "--------------------------------------------------"
