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

# 4. HVD Alignment: Host Abstraction Layer
# In accordance with HashiCorp Validated Designs, we avoid direct-address targets.
# Instead, we define a structured hierarchy: Host Catalog -> Host -> Host Set -> Target.

echo "Creating Static Host Catalog..."
HOST_CATALOG_ID=$(docker exec -e BOUNDARY_TOKEN=$TOKEN comet-boundary-controller-1 boundary host-catalogs create static \
    -name "Standard Infrastructure" \
    -description "Catalog for Comet project assets" \
    -scope-id $PROJECT_ID \
    -token env://BOUNDARY_TOKEN \
    -format json | jq -r .item.id)

echo "Creating Host Resources..."
# HVD Practice: Hosts represent the physical/virtual network endpoint.
HOST_1_ID=$(docker exec -e BOUNDARY_TOKEN=$TOKEN comet-boundary-controller-1 boundary hosts create static \
    -name "ssh-host-1" \
    -description "Production SSH Target 1" \
    -address "ssh-target-1" \
    -host-catalog-id $HOST_CATALOG_ID \
    -token env://BOUNDARY_TOKEN \
    -format json | jq -r .item.id)

HOST_2_ID=$(docker exec -e BOUNDARY_TOKEN=$TOKEN comet-boundary-controller-1 boundary hosts create static \
    -name "ssh-host-2" \
    -description "Production SSH Target 2" \
    -address "ssh-target-2" \
    -host-catalog-id $HOST_CATALOG_ID \
    -token env://BOUNDARY_TOKEN \
    -format json | jq -r .item.id)

echo "Creating Host Sets..."
# HVD Practice: Host sets group equivalent hosts. Here we use separate sets for team isolation.
HOST_SET_1_ID=$(docker exec -e BOUNDARY_TOKEN=$TOKEN comet-boundary-controller-1 boundary host-sets create static \
    -name "Team A Host Set" \
    -description "Hosts authorized for Team A" \
    -host-catalog-id $HOST_CATALOG_ID \
    -token env://BOUNDARY_TOKEN \
    -format json | jq -r .item.id)

HOST_SET_2_ID=$(docker exec -e BOUNDARY_TOKEN=$TOKEN comet-boundary-controller-1 boundary host-sets create static \
    -name "Team B Host Set" \
    -description "Hosts authorized for Team B" \
    -host-catalog-id $HOST_CATALOG_ID \
    -token env://BOUNDARY_TOKEN \
    -format json | jq -r .item.id)

# Associate hosts with their respective sets
docker exec -e BOUNDARY_TOKEN=$TOKEN comet-boundary-controller-1 boundary host-sets add-hosts \
    -id $HOST_SET_1_ID \
    -host $HOST_1_ID \
    -token env://BOUNDARY_TOKEN > /dev/null

docker exec -e BOUNDARY_TOKEN=$TOKEN comet-boundary-controller-1 boundary host-sets add-hosts \
    -id $HOST_SET_2_ID \
    -host $HOST_2_ID \
    -token env://BOUNDARY_TOKEN > /dev/null

echo "Creating HVD-compliant targets..."
TARGET_A_ID=$(docker exec -e BOUNDARY_TOKEN=$TOKEN comet-boundary-controller-1 boundary targets create tcp \
    -name "A Team Host" \
    -description "Access for Team A" \
    -default-port 2222 \
    -scope-id $PROJECT_ID \
    -token env://BOUNDARY_TOKEN \
    -format json | jq -r .item.id)

TARGET_B_ID=$(docker exec -e BOUNDARY_TOKEN=$TOKEN comet-boundary-controller-1 boundary targets create tcp \
    -name "B Team Host" \
    -description "Access for Team B" \
    -default-port 2222 \
    -scope-id $PROJECT_ID \
    -token env://BOUNDARY_TOKEN \
    -format json | jq -r .item.id)

echo "Linking host sets to targets..."
docker exec -e BOUNDARY_TOKEN=$TOKEN comet-boundary-controller-1 boundary targets add-host-sources \
    -id $TARGET_A_ID \
    -host-source $HOST_SET_1_ID \
    -token env://BOUNDARY_TOKEN > /dev/null

docker exec -e BOUNDARY_TOKEN=$TOKEN comet-boundary-controller-1 boundary targets add-host-sources \
    -id $TARGET_B_ID \
    -host-source $HOST_SET_2_ID \
    -token env://BOUNDARY_TOKEN > /dev/null

if [ -z "$TARGET_A_ID" ] || [ -z "$TARGET_B_ID" ]; then
    echo "Failed to create targets."
    exit 1
fi

echo "Created Target A ID: $TARGET_A_ID"
echo "Created Target B ID: $TARGET_B_ID"

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

# 6. Create LDAP Managed Groups for Teams
echo "Creating Managed Groups for Teams..."

MANAGED_GROUP_A_ID=$(curl -s -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"auth_method_id\": \"$LDAP_AUTH_METHOD_ID\",
        \"type\": \"ldap\",
        \"name\": \"Team A\",
        \"description\": \"Maps to LDAP team-a group\",
        \"attributes\": {
            \"group_names\": [\"team-a\"]
        }
    }" \
    "$BOUNDARY_ADDR/v1/managed-groups" | jq -r '.id')

MANAGED_GROUP_B_ID=$(curl -s -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"auth_method_id\": \"$LDAP_AUTH_METHOD_ID\",
        \"type\": \"ldap\",
        \"name\": \"Team B\",
        \"description\": \"Maps to LDAP team-b group\",
        \"attributes\": {
            \"group_names\": [\"team-b\"]
        }
    }" \
    "$BOUNDARY_ADDR/v1/managed-groups" | jq -r '.id')

echo "Created Managed Group A ID: $MANAGED_GROUP_A_ID"
echo "Created Managed Group B ID: $MANAGED_GROUP_B_ID"

# 7. Create Roles for Teams with scoped permissions
echo "Establishing Scoped RBAC..."

# Role for Team A
ROLE_A_ID=$(curl -s -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"scope_id\": \"$PROJECT_ID\",
        \"name\": \"Team A SSH Access\",
        \"description\": \"Grants Team A access to Target A\"
    }" \
    "$BOUNDARY_ADDR/v1/roles" | jq -r '.id')

curl -s -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"principal_ids\": [\"$MANAGED_GROUP_A_ID\"],
        \"version\": 1
    }" \
    "$BOUNDARY_ADDR/v1/roles/$ROLE_A_ID:add-principals" > /dev/null

curl -s -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"grant_strings\": [
            \"ids=$TARGET_A_ID;actions=authorize-session\",
            \"ids=$TARGET_A_ID;type=target;actions=list,no-op,read\",
            \"ids=*;type=host-catalog;actions=list,no-op,read\",
            \"ids=*;type=host-set;actions=list,no-op,read\",
            \"ids=*;type=host;actions=list,no-op,read\",
            \"ids=*;type=session;actions=list,no-op,read:self,cancel:self\"
        ],
        \"version\": 2
    }" \
    "$BOUNDARY_ADDR/v1/roles/$ROLE_A_ID:add-grants" > /dev/null

# Role for Team B
ROLE_B_ID=$(curl -s -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"scope_id\": \"$PROJECT_ID\",
        \"name\": \"Team B SSH Access\",
        \"description\": \"Grants Team B access to Target B\"
    }" \
    "$BOUNDARY_ADDR/v1/roles" | jq -r '.id')

curl -s -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"principal_ids\": [\"$MANAGED_GROUP_B_ID\"],
        \"version\": 1
    }" \
    "$BOUNDARY_ADDR/v1/roles/$ROLE_B_ID:add-principals" > /dev/null

curl -s -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"grant_strings\": [
            \"ids=$TARGET_B_ID;actions=authorize-session\",
            \"ids=$TARGET_B_ID;type=target;actions=list,no-op,read\",
            \"ids=*;type=host-catalog;actions=list,no-op,read\",
            \"ids=*;type=host-set;actions=list,no-op,read\",
            \"ids=*;type=host;actions=list,no-op,read\",
            \"ids=*;type=session;actions=list,no-op,read:self,cancel:self\"
        ],
        \"version\": 2
    }" \
    "$BOUNDARY_ADDR/v1/roles/$ROLE_B_ID:add-grants" > /dev/null

echo "Scoped RBAC configured."

# Hardening: Remove permissive 'target:list' from the default Project role
# Boundary creates a 'Default Grants' role in every project that allows all users to list all targets.
echo "Hardening default project roles..."
DEFAULT_PROJECT_ROLE_ID=$(docker exec -e BOUNDARY_TOKEN=$TOKEN comet-boundary-controller-1 boundary roles list -scope-id $PROJECT_ID -format json -token env://BOUNDARY_TOKEN | jq -r '.items[] | select(.name == "Default Grants") | .id')
if [ -n "$DEFAULT_PROJECT_ROLE_ID" ] && [ "$DEFAULT_PROJECT_ROLE_ID" != "null" ]; then
    docker exec -e BOUNDARY_TOKEN=$TOKEN comet-boundary-controller-1 boundary roles set-grants \
        -id $DEFAULT_PROJECT_ROLE_ID \
        -grant "ids=*;type=session;actions=list,read:self,cancel:self" \
        -token env://BOUNDARY_TOKEN > /dev/null
    echo "Default project grants hardened."
fi

# Hardening: Remove permissive 'target:list,read' from the global Authenticated User Grants role
echo "Hardening global authenticated user roles..."
GLOBAL_AUTH_ROLE_ID=$(docker exec -e BOUNDARY_TOKEN=$TOKEN comet-boundary-controller-1 boundary roles list -scope-id global -format json -token env://BOUNDARY_TOKEN | jq -r '.items[] | select(.name == "Authenticated User Grants") | .id')
if [ -n "$GLOBAL_AUTH_ROLE_ID" ] && [ "$GLOBAL_AUTH_ROLE_ID" != "null" ]; then
    docker exec -e BOUNDARY_TOKEN=$TOKEN comet-boundary-controller-1 boundary roles set-grants \
        -id $GLOBAL_AUTH_ROLE_ID \
        -grant "ids=*;type=scope;actions=read" \
        -grant "ids=*;type=auth-token;actions=list" \
        -grant "ids={{.Account.Id}};actions=read,change-password" \
        -grant "ids=*;type=session;actions=list,read:self,cancel:self" \
        -grant "ids={{.User.Id}};type=user;actions=list-resolvable-aliases" \
        -token env://BOUNDARY_TOKEN > /dev/null
    echo "Global authenticated grants hardened."
fi

# 8. Add Discovery Roles for Org and Global visibility
echo "Establishing Discovery RBAC..."

# Global-level Role: Visibility for Org
GLOBAL_ROLE_ID=$(curl -s -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"scope_id\": \"global\",
        \"name\": \"Global Discovery\",
        \"description\": \"Enables org visibility at global level\"
    }" \
    "$BOUNDARY_ADDR/v1/roles" | jq -r '.id')

curl -s -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"principal_ids\": [\"$MANAGED_GROUP_A_ID\", \"$MANAGED_GROUP_B_ID\"],
        \"version\": 1
    }" \
    "$BOUNDARY_ADDR/v1/roles/$GLOBAL_ROLE_ID:add-principals" > /dev/null

curl -s -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"grant_strings\": [
            \"ids=*;type=scope;actions=list,read\",
            \"ids=*;type=auth-method;actions=list,read\",
            \"ids=*;type=target;actions=list,no-op\"
        ],
        \"version\": 2
    }" \
    "$BOUNDARY_ADDR/v1/roles/$GLOBAL_ROLE_ID:add-grants" > /dev/null

# Org-level Role: Visibility for Team A
ORG_ROLE_A_ID=$(curl -s -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"scope_id\": \"$ORG_ID\",
        \"name\": \"Team A Discovery\",
        \"description\": \"Enables resource visibility for Team A\"
    }" \
    "$BOUNDARY_ADDR/v1/roles" | jq -r '.id')

curl -s -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"principal_ids\": [\"$MANAGED_GROUP_A_ID\"],
        \"version\": 1
    }" \
    "$BOUNDARY_ADDR/v1/roles/$ORG_ROLE_A_ID:add-principals" > /dev/null

curl -s -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"grant_strings\": [
            \"ids=*;type=scope;actions=list,read\",
            \"ids=*;type=host-catalog;actions=list,read\",
            \"ids=*;type=host-set;actions=list,read\",
            \"ids=*;type=host;actions=list,read\",
            \"ids=$TARGET_A_ID;type=target;actions=list,read\"
        ],
        \"version\": 2
    }" \
    "$BOUNDARY_ADDR/v1/roles/$ORG_ROLE_A_ID:add-grants" > /dev/null

# Org-level Role: Visibility for Team B
ORG_ROLE_B_ID=$(curl -s -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"scope_id\": \"$ORG_ID\",
        \"name\": \"Team B Discovery\",
        \"description\": \"Enables resource visibility for Team B\"
    }" \
    "$BOUNDARY_ADDR/v1/roles" | jq -r '.id')

curl -s -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"principal_ids\": [\"$MANAGED_GROUP_B_ID\"],
        \"version\": 1
    }" \
    "$BOUNDARY_ADDR/v1/roles/$ORG_ROLE_B_ID:add-principals" > /dev/null

curl -s -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"grant_strings\": [
            \"ids=*;type=scope;actions=list,read\",
            \"ids=*;type=host-catalog;actions=list,read\",
            \"ids=*;type=host-set;actions=list,read\",
            \"ids=*;type=host;actions=list,read\",
            \"ids=$TARGET_B_ID;type=target;actions=list,read\"
        ],
        \"version\": 2
    }" \
    "$BOUNDARY_ADDR/v1/roles/$ORG_ROLE_B_ID:add-grants" > /dev/null

echo "Discovery RBAC configured: Teams can only discover their own targets."

# 9. Synchronize .env
echo "Synchronizing .env..."
cat <<EOF > .env
BOUNDARY_ADDR=$BOUNDARY_ADDR
BOUNDARY_AUTH_METHOD_ID=$BOUNDARY_AUTH_METHOD_ID
BOUNDARY_LDAP_AUTH_METHOD_ID=$LDAP_AUTH_METHOD_ID
BOUNDARY_PROJECT_ID=$PROJECT_ID
BOUNDARY_ADMIN_USER=admin
BOUNDARY_ADMIN_PASSWORD=$BOUNDARY_ADMIN_PASSWORD
BOUNDARY_TARGET_ID=$TARGET_A_ID
EOF

# 9. Synchronize Frontend defaults (Inject via .env.local)
echo "Synchronizing Frontend defaults..."
cat <<EOF > client/.env.local
VITE_LDAP_AUTH_METHOD_ID=$LDAP_AUTH_METHOD_ID
VITE_TARGET_ID=$TARGET_A_ID
VITE_ADMIN_PASSWORD=$BOUNDARY_ADMIN_PASSWORD
EOF

echo "--------------------------------------------------"
echo "Boundary initialization complete."
echo "Target A ID: $TARGET_A_ID (Team A)"
echo "Target B ID: $TARGET_B_ID (Team B)"
echo "LDAP Auth Method ID: $LDAP_AUTH_METHOD_ID"
echo "LDAP users can log in with their directory credentials."
echo "  Example: alice / changeme"
echo "           bob   / changeme"
echo "--------------------------------------------------"
