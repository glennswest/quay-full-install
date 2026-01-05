#!/bin/bash
# Setup Quay registry for OpenShift mirroring
# Run on registry server (registry.gw.lo)
# Sets up: Redis, storage location, service key

set -e

QUAY_CONF="/opt/quay/conf"
KEY_DIR="${QUAY_CONF}"

echo "=== Setting up Quay Registry ==="

# Install and start Redis/Valkey (required for caching)
echo "Checking Redis..."
if ! systemctl is-active --quiet redis valkey 2>/dev/null; then
    echo "Installing Redis..."
    dnf install -y redis 2>/dev/null || true
    systemctl enable redis valkey 2>/dev/null || true
    systemctl start redis valkey 2>/dev/null || true
    echo "Redis started"
else
    echo "Redis already running"
fi

# Ensure 'default' storage location exists in database
echo "Checking storage location..."
EXISTING_LOC=$(PGPASSWORD=quaypass psql -U quay -h localhost quay -t -c "SELECT COUNT(*) FROM imagestoragelocation WHERE name = 'default';" 2>/dev/null | tr -d ' ')
if [ "${EXISTING_LOC:-0}" -eq "0" ]; then
    echo "Adding 'default' storage location..."
    PGPASSWORD=quaypass psql -U quay -h localhost quay -c "INSERT INTO imagestoragelocation (name) VALUES ('default');" 2>/dev/null
    echo "Storage location added"
else
    echo "Storage location exists"
fi

echo ""
echo "=== Setting up Service Key ==="

# Check if key files exist
if [ ! -f "${KEY_DIR}/quay.kid" ] || [ ! -f "${KEY_DIR}/quay.pem" ]; then
    echo "Generating new service key..."

    # Generate key pair
    openssl genrsa -out "${KEY_DIR}/quay.pem" 2048
    openssl rsa -in "${KEY_DIR}/quay.pem" -pubout -out "${KEY_DIR}/quay.pub"

    # Generate KID
    KID="quay-$(date +%s)"
    echo "$KID" > "${KEY_DIR}/quay.kid"

    echo "Generated new key with KID: $KID"
else
    KID=$(cat "${KEY_DIR}/quay.kid")
    echo "Using existing key with KID: $KID"
fi

# Read the public key
PUB_KEY=$(cat "${KEY_DIR}/quay.pub")

# Check if key exists in database
EXISTING=$(PGPASSWORD=quaypass psql -U quay -h localhost quay -t -c "SELECT COUNT(*) FROM servicekey WHERE kid = '$KID';" | tr -d ' ')

if [ "$EXISTING" -eq "0" ]; then
    echo "Registering service key in database..."

    # Escape the public key for SQL
    PUB_KEY_ESCAPED=$(echo "$PUB_KEY" | sed "s/'/''/g")

    PGPASSWORD=quaypass psql -U quay -h localhost quay << EOF
-- Create approval record
INSERT INTO servicekeyapproval (approver_id, approval_type, approved_date, notes)
SELECT id, 'superuser', NOW(), 'Auto-approved service key'
FROM "user" WHERE username = 'admin'
RETURNING id;

-- Insert service key with approval
INSERT INTO servicekey (name, kid, service, jwk, metadata, created_date, approval_id)
SELECT 'quay', '$KID', 'quay', '$PUB_KEY_ESCAPED', '{}', NOW(),
       (SELECT MAX(id) FROM servicekeyapproval);
EOF
    echo "Service key registered and approved"
else
    # Check if approved
    APPROVED=$(PGPASSWORD=quaypass psql -U quay -h localhost quay -t -c "SELECT approval_id FROM servicekey WHERE kid = '$KID';" | tr -d ' ')

    if [ "$APPROVED" = "" ] || [ "$APPROVED" = "NULL" ]; then
        echo "Approving existing service key..."

        PGPASSWORD=quaypass psql -U quay -h localhost quay << EOF
-- Create approval if not exists
INSERT INTO servicekeyapproval (approver_id, approval_type, approved_date, notes)
SELECT id, 'superuser', NOW(), 'Auto-approved service key'
FROM "user" WHERE username = 'admin'
ON CONFLICT DO NOTHING
RETURNING id;

-- Update service key with approval
UPDATE servicekey SET approval_id = (SELECT MAX(id) FROM servicekeyapproval)
WHERE kid = '$KID' AND approval_id IS NULL;
EOF
        echo "Service key approved"
    else
        echo "Service key already registered and approved (approval_id: $APPROVED)"
    fi
fi

# Restart Quay to pick up any changes
echo "Restarting Quay..."
systemctl restart quay

echo ""
echo "=== Service Key Setup Complete ==="
echo "KID: $KID"
