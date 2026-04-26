#!/usr/bin/env bash
# pin-digest.sh — Updates the Umbrel docker-compose.yml with the multi-arch
# sha256 digest pulled directly from GitHub Container Registry.
#
# Why this exists: pinning the image by digest (image:tag@sha256:...) is
# required by Umbrel store conventions and is good practice generally.
# Manually copying digests is error-prone, so this scrapes GHCR for you.
#
# Usage:
#   ./pin-digest.sh 0.1.0
#
# Requires: curl, jq

set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "usage: $0 <version>     # e.g. $0 0.1.0"
  exit 1
fi

# GHCR image path
OWNER="gbechtel-beck"
IMAGE_NAME="fleetswarm"
FULL_IMAGE="ghcr.io/${OWNER}/${IMAGE_NAME}"
COMPOSE_FILE="$(dirname "$0")/docker-compose.yml"

echo "==> Fetching multi-arch digest for ${FULL_IMAGE}:${VERSION}"

# GHCR public-image auth: any token works for read-only pulls of public images.
# The simplest approach is to request an anonymous token from ghcr.io itself.
TOKEN=$(curl -fsSL \
  "https://ghcr.io/token?scope=repository:${OWNER}/${IMAGE_NAME}:pull" \
  | jq -r '.token // empty')

if [[ -z "$TOKEN" ]]; then
  echo "!! Could not get a registry token from ghcr.io"
  echo "   If your image is private, run: docker login ghcr.io -u $OWNER"
  echo "   Then export GHCR_TOKEN=<your_pat> and re-run this script."
  exit 1
fi

# Fetch the manifest list (multi-arch index). The Docker-Content-Digest header
# of this response is the multi-arch digest we want.
DIGEST=$(curl -fsSL -I \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Accept: application/vnd.oci.image.index.v1+json" \
  -H "Accept: application/vnd.docker.distribution.manifest.list.v2+json" \
  "https://ghcr.io/v2/${OWNER}/${IMAGE_NAME}/manifests/${VERSION}" \
  | grep -i '^docker-content-digest:' \
  | awk '{print $2}' | tr -d '\r\n')

if [[ -z "$DIGEST" ]]; then
  echo "!! Could not retrieve digest."
  echo "   Image may not be published yet — wait a minute and retry."
  echo "   Or: GH Actions may have failed. Check"
  echo "   https://github.com/${OWNER}/${IMAGE_NAME}/actions"
  exit 1
fi

echo "==> Digest: $DIGEST"
echo "==> Updating $COMPOSE_FILE"

# Replace the image: line. Pattern handles:
#   image: ghcr.io/owner/name:VERSION
#   image: ghcr.io/owner/name:VERSION@sha256:OLD_DIGEST
# Resulting in:
#   image: ghcr.io/owner/name:VERSION@sha256:NEW_DIGEST
sed -i.bak -E \
  "s|image: ${FULL_IMAGE}:[^@[:space:]]+(@sha256:[a-f0-9]+)?|image: ${FULL_IMAGE}:${VERSION}${DIGEST}|" \
  "$COMPOSE_FILE"

echo "==> Done. Diff:"
diff "$COMPOSE_FILE.bak" "$COMPOSE_FILE" || true
rm "$COMPOSE_FILE.bak"

echo
echo "==> Next steps:"
echo "    cd .."
echo "    git add umbrelsolostrike-fleetswarm/"
echo "    git commit -m 'fleetswarm: pin ${VERSION} digest'"
echo "    git push"
