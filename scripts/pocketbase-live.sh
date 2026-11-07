#!/usr/bin/env bash
# pocketbase-live.sh — run a command against a THROWAWAY PocketBase in podman.
#
#   scripts/pocketbase-live.sh -- kagami test --scope NetKitPocketLiveTests --strict
#
# What it does, in order:
#   1. builds a tiny image from the OFFICIAL PocketBase release zip (the way the
#      PocketBase docs build one), checking the zip against a pinned sha256;
#   2. starts ONE container on a random 127.0.0.1 port with an in-memory data
#      directory and a freshly generated superuser;
#   3. waits for /api/health;
#   4. runs the command you gave it with the live-test environment set;
#   5. removes the container, always — on success, failure, Ctrl-C or kill —
#      and says so.
#
# The superuser password is generated here, handed to the container and to the
# command through the ENVIRONMENT only, and never printed, written to a file or
# put on a command line. It dies with the container.
#
# The command receives:
#   NETKIT_POCKETBASE_URL              http://127.0.0.1:<port>
#   NETKIT_POCKETBASE_ADMIN_EMAIL
#   NETKIT_POCKETBASE_ADMIN_PASSWORD
#
# Environment:
#   POCKETBASE_VERSION   PocketBase release to run (default: the fleet-pinned one)
#   POCKETBASE_SHA256    sha256 of that release's linux zip for this architecture;
#                        required when POCKETBASE_VERSION is not one pinned below
#   KEEP_IMAGE=1         keep the built image afterwards (default: remove it)
#
# Needs: podman with a running machine, and network access to github.com for the
# first build of a given version.

set -euo pipefail

DEFAULT_VERSION="0.25.9"
VERSION="${POCKETBASE_VERSION:-$DEFAULT_VERSION}"

if [ "${1:-}" != "--" ]; then
    echo "usage: $0 -- <command...>" >&2
    exit 64
fi
shift
if [ "$#" -eq 0 ]; then
    echo "usage: $0 -- <command...>" >&2
    exit 64
fi

command -v podman >/dev/null 2>&1 || { echo "pocketbase-live: podman is not installed." >&2; exit 69; }
podman info >/dev/null 2>&1 || { echo "pocketbase-live: podman is installed but not reachable (podman machine start?)." >&2; exit 69; }

ARCH="$(podman info --format '{{.Host.Arch}}')"
case "$ARCH" in
    arm64 | aarch64) ZIP_ARCH="arm64" ;;
    amd64 | x86_64)  ZIP_ARCH="amd64" ;;
    *) echo "pocketbase-live: unsupported podman architecture '$ARCH'." >&2; exit 69 ;;
esac

# Pinned release checksums (github.com/pocketbase/pocketbase releases, checksums.txt).
pinned_sha256() {
    case "$1/$2" in
        0.25.9/amd64) echo "64f5e755e71d14f3356bf9a125a8fcc60e621ed678ba70cc7d315af0b2b9c2ae" ;;
        0.25.9/arm64) echo "2a21424e6e8b92b4a02e82ba59d84385379657d354ca96cf76458cf1bfb99dde" ;;
        0.40.6/amd64) echo "0e1f609158ed945f809f8a02ae012aa0427129c66ebb63c1aee76f2c0309373f" ;;
        0.40.6/arm64) echo "d22c66ceb67ca92b7d767f36d826e848a276bcfa3c197ead20bf87c42208984f" ;;
        *) echo "" ;;
    esac
}
SHA256="${POCKETBASE_SHA256:-$(pinned_sha256 "$VERSION" "$ZIP_ARCH")}"
if [ -z "$SHA256" ]; then
    echo "pocketbase-live: no pinned sha256 for PocketBase $VERSION ($ZIP_ARCH); set POCKETBASE_SHA256." >&2
    exit 64
fi

IMAGE="localhost/netkit-pocketbase-live:$VERSION"
# `|| true`: `head` closing the pipe SIGPIPEs `tr`, which pipefail would turn into a failure.
SUFFIX="$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 8 || true)"
NAME="netkit-pb-live-$SUFFIX"
BUILD_DIR="$(mktemp -d)"
CREATED_IMAGE=0

cleanup() {
    status=$?
    set +e
    if podman container exists "$NAME" 2>/dev/null; then
        podman rm -f "$NAME" >/dev/null 2>&1
    fi
    if podman container exists "$NAME" 2>/dev/null; then
        echo "pocketbase-live: FAILED to remove container $NAME" >&2
        status=70
    else
        echo "pocketbase-live: container $NAME removed."
    fi
    if [ "$CREATED_IMAGE" = "1" ] && [ "${KEEP_IMAGE:-0}" != "1" ]; then
        podman rmi -f "$IMAGE" >/dev/null 2>&1 && echo "pocketbase-live: image $IMAGE removed."
    fi
    rm -rf "$BUILD_DIR"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# 1. Image -----------------------------------------------------------------
if ! podman image exists "$IMAGE" 2>/dev/null; then
    cat >"$BUILD_DIR/Containerfile" <<'CONTAINERFILE'
FROM docker.io/library/alpine:3.20
ARG PB_VERSION
ARG PB_ARCH
ARG PB_SHA256
RUN apk add --no-cache ca-certificates curl unzip \
 && curl -fsSL -o /tmp/pocketbase.zip \
      "https://github.com/pocketbase/pocketbase/releases/download/v${PB_VERSION}/pocketbase_${PB_VERSION}_linux_${PB_ARCH}.zip" \
 && echo "${PB_SHA256}  /tmp/pocketbase.zip" | sha256sum -c - \
 && mkdir -p /pb \
 && unzip -q /tmp/pocketbase.zip pocketbase -d /pb \
 && rm /tmp/pocketbase.zip \
 && apk del curl unzip
EXPOSE 8090
CONTAINERFILE
    echo "pocketbase-live: building $IMAGE (PocketBase $VERSION, linux/$ZIP_ARCH)..."
    podman build --quiet \
        --build-arg "PB_VERSION=$VERSION" --build-arg "PB_ARCH=$ZIP_ARCH" --build-arg "PB_SHA256=$SHA256" \
        -t "$IMAGE" -f "$BUILD_DIR/Containerfile" "$BUILD_DIR" >/dev/null
    CREATED_IMAGE=1
fi

# 2. Credentials: environment only, never printed ---------------------------
PB_ADMIN_EMAIL="admin-$SUFFIX@netkit-live.test"
PB_ADMIN_PASSWORD="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 28 || true)"
export PB_ADMIN_EMAIL PB_ADMIN_PASSWORD

# 3. Container: random localhost port, data in memory ------------------------
podman run -d --name "$NAME" \
    -p 127.0.0.1::8090 \
    --tmpfs /pb/pb_data \
    -e PB_ADMIN_EMAIL -e PB_ADMIN_PASSWORD \
    "$IMAGE" \
    sh -c '/pb/pocketbase superuser upsert "$PB_ADMIN_EMAIL" "$PB_ADMIN_PASSWORD" --dir=/pb/pb_data >/dev/null \
           && exec /pb/pocketbase serve --http=0.0.0.0:8090 --dir=/pb/pb_data' >/dev/null

HOST_PORT="$(podman port "$NAME" 8090/tcp | head -n 1 | sed 's/.*://')"
URL="http://127.0.0.1:$HOST_PORT"

# 4. Health -------------------------------------------------------------------
READY=0
for _ in $(seq 1 120); do
    if curl -fsS "$URL/api/health" >/dev/null 2>&1; then READY=1; break; fi
    if [ "$(podman inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null)" != "true" ]; then break; fi
    sleep 0.5
done
if [ "$READY" != "1" ]; then
    echo "pocketbase-live: PocketBase did not become healthy. Container log (no credentials in it):" >&2
    podman logs "$NAME" 2>&1 | tail -n 20 >&2
    exit 70
fi
echo "pocketbase-live: $(podman exec "$NAME" /pb/pocketbase --version 2>&1) healthy at $URL (container $NAME)"

# 5. Run the command ------------------------------------------------------------
set +e
NETKIT_POCKETBASE_URL="$URL" \
NETKIT_POCKETBASE_ADMIN_EMAIL="$PB_ADMIN_EMAIL" \
NETKIT_POCKETBASE_ADMIN_PASSWORD="$PB_ADMIN_PASSWORD" \
    "$@"
COMMAND_STATUS=$?
set -e

echo "pocketbase-live: command exited $COMMAND_STATUS"
exit "$COMMAND_STATUS"
