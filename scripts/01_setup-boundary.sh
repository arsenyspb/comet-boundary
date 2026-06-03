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

# Wait for OpenLDAP to be ready
echo "Waiting for OpenLDAP..."
LDAP_COUNT=0
until docker exec comet-boundary-openldap-1 ldapsearch -x -H ldap://localhost -b "dc=comet,dc=example" -D "cn=admin,dc=comet,dc=example" -w admin > /dev/null 2>&1; do
    printf '.'
    sleep 2
    LDAP_COUNT=$((LDAP_COUNT+1))
    if [ $LDAP_COUNT -ge 15 ]; then
        echo "\nTimeout waiting for OpenLDAP."
        exit 1
    fi
done
echo "\nOpenLDAP is ready."

# Get the org scope ID (global)
ORG_ID=$(docker exec -e BOUNDARY_TOKEN=$TOKEN comet-boundary-controller-1 boundary scopes list -format json -token env://BOUNDARY_TOKEN | jq -r '.items[] | select(.scope.id == "global") | .id' | head -n 1)

if [ -z "$ORG_ID" ] || [ "$ORG_ID" = "null" ]; then
    echo "Could not discover org scope, using 'global' parent for LDAP auth method..."
    ORG_ID="global"
fi

LDAP_AUTH_METHOD_ID=$(docker exec -e BOUNDARY_TOKEN=$TOKEN comet-boundary-controller-1 boundary auth-methods create ldap \
    -name "LDAP" \
    -description "OpenLDAP Identity Provider" \
    -scope-id "$ORG_ID" \
    -urls "ldap://openldap:389" \
    -user-dn "ou=People,dc=comet,dc=example" \
    -user-attr "uid" \
    -group-dn "ou=Groups,dc=comet,dc=example" \
    -group-attr "cn" \
    -bind-dn "cn=admin,dc=comet,dc=example" \
    -bind-password "admin" \
    -state "active-public" \
    -insecure-tls \
    -discover-dn \
    -token env://BOUNDARY_TOKEN \
    -format json | jq -r '.item.id')

if [ -z "$LDAP_AUTH_METHOD_ID" ] || [ "$LDAP_AUTH_METHOD_ID" = "null" ]; then
    echo "Failed to create LDAP auth method."
    exit 1
fi

echo "Created LDAP Auth Method ID: $LDAP_AUTH_METHOD_ID"

# 6. Create Managed Group for 'engineering' LDAP group
echo "Creating Managed Group for 'engineering'..."
MANAGED_GROUP_ID=$(docker exec -e BOUNDARY_TOKEN=$TOKEN comet-boundary-controller-1 boundary managed-groups create ldap \
    -auth-method-id "$LDAP_AUTH_METHOD_ID" \
    -name "engineering" \
    -description "Engineering LDAP Group" \
    -group-names "engineering" \
    -token env://BOUNDARY_TOKEN \
    -format json | jq -r '.item.id')

if [ -z "$MANAGED_GROUP_ID" ] || [ "$MANAGED_GROUP_ID" = "null" ]; then
    echo "Failed to create managed group."
    exit 1
fi

echo "Created Managed Group ID: $MANAGED_GROUP_ID"

# 7. Establish RBAC: Create a role granting the managed group access to the SSH target
echo "Establishing RBAC for engineering managed group..."

ROLE_ID=$(docker exec -e BOUNDARY_TOKEN=$TOKEN comet-boundary-controller-1 boundary roles create \
    -name "engineering-ssh-access" \
    -description "Grants engineering group access to SSH target" \
    -scope-id "$PROJECT_ID" \
    -token env://BOUNDARY_TOKEN \
    -format json | jq -r '.item.id')

if [ -z "$ROLE_ID" ] || [ "$ROLE_ID" = "null" ]; then
    echo "Failed to create role."
    exit 1
fi

# Add grants allowing session authorization and read on targets
docker exec -e BOUNDARY_TOKEN=$TOKEN comet-boundary-controller-1 boundary roles add-grants \
    -id "$ROLE_ID" \
    -grant "ids=$TARGET_ID;actions=authorize-session" \
    -grant "ids=*;type=target;actions=list,read" \
    -grant "ids=*;type=session;actions=list,read:self,cancel:self,no-op" \
    -token env://BOUNDARY_TOKEN \
    -format json > /dev/null

# Add the managed group as a principal on the role
docker exec -e BOUNDARY_TOKEN=$TOKEN comet-boundary-controller-1 boundary roles add-principals \
    -id "$ROLE_ID" \
    -principal "$MANAGED_GROUP_ID" \
    -token env://BOUNDARY_TOKEN \
    -format json > /dev/null

echo "RBAC configured: Role $ROLE_ID -> Managed Group $MANAGED_GROUP_ID -> Target $TARGET_ID"

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
VITE_AUTH_METHOD_ID=$BOUNDARY_AUTH_METHOD_ID
VITE_LDAP_AUTH_METHOD_ID=$LDAP_AUTH_METHOD_ID
VITE_TARGET_ID=$TARGET_ID
EOF

echo "--------------------------------------------------"
echo "Boundary initialization complete."
echo "Target ID: $TARGET_ID"
echo "LDAP Auth Method ID: $LDAP_AUTH_METHOD_ID"
echo "Managed Group ID: $MANAGED_GROUP_ID"
echo "LDAP User: alice / changeme"
echo "--------------------------------------------------"
