#!/bin/bash
# Run on registry server - mirrors OpenShift release locally
# Usage: ./mirror-local.sh <version>
# Retries up to 5 times to handle token timeouts

if [ -z "$1" ]; then
    echo "Usage: $0 <version>"
    exit 1
fi

VERSION="$1"
LOCAL_REGISTRY="registry.gw.lo"
LOCAL_REPO="openshift/release"
PULL_SECRET="/root/pullsecret-combined.json"

UPSTREAM_RELEASE="quay.io/openshift-release-dev/ocp-release:${VERSION}-x86_64"
LOCAL_RELEASE="${LOCAL_REGISTRY}/${LOCAL_REPO}:${VERSION}-x86_64"

echo "=== Mirroring OpenShift ${VERSION} locally ==="
echo "Source: ${UPSTREAM_RELEASE}"
echo "Destination: ${LOCAL_RELEASE}"
echo "Started: $(date)"
echo ""

MAX_RETRIES=5
RETRY=0

while [ $RETRY -lt $MAX_RETRIES ]; do
    RETRY=$((RETRY + 1))
    echo "=== Attempt $RETRY of $MAX_RETRIES ==="

    if time oc adm release mirror \
        --from="${UPSTREAM_RELEASE}" \
        --to="${LOCAL_REGISTRY}/${LOCAL_REPO}" \
        --to-release-image="${LOCAL_RELEASE}" \
        --registry-config="${PULL_SECRET}" \
        --insecure \
        --max-per-registry=4; then
        echo ""
        echo "=== Mirror Complete ==="
        echo "Finished: $(date)"
        echo "Release: ${LOCAL_RELEASE}"
        exit 0
    fi

    echo "Attempt $RETRY failed, retrying in 5 seconds..."
    sleep 5
done

echo "=== Mirror failed after $MAX_RETRIES attempts ==="
exit 1
