#!/bin/bash
# Mirror OpenShift release via registry server
# Usage: ./mirror.sh <version>
# Example: ./mirror.sh 4.20.8

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 4.20.8"
    exit 1
fi

VERSION="$1"
REGISTRY="registry.gw.lo"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

echo "=== Submitting mirror job for OpenShift ${VERSION} to ${REGISTRY} ==="

# Copy scripts to registry
cat mirror-local.sh | ssh $SSH_OPTS root@${REGISTRY} "cat > /root/mirror-local.sh && chmod +x /root/mirror-local.sh"
cat setup-quay-servicekey.sh | ssh $SSH_OPTS root@${REGISTRY} "cat > /root/setup-quay.sh && chmod +x /root/setup-quay.sh"

# Run setup (ensures Redis, storage, and service key are configured)
echo "Running registry setup..."
ssh $SSH_OPTS root@${REGISTRY} "/root/setup-quay.sh" 2>&1 | grep -v "^$"

# Run mirror on registry with nohup, output to log file
ssh $SSH_OPTS root@${REGISTRY} "nohup /root/mirror-local.sh ${VERSION} > /root/mirror-${VERSION}.log 2>&1 &"

echo ""
echo "Mirror job submitted. Monitor with:"
echo "  ssh root@${REGISTRY} 'tail -f /root/mirror-${VERSION}.log'"
echo ""
echo "Check if complete:"
echo "  ssh root@${REGISTRY} 'grep -E \"(real|error:|Success)\" /root/mirror-${VERSION}.log'"
