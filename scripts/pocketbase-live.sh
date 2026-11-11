#!/usr/bin/env bash
# pocketbase-live.sh — run a command against a THROWAWAY PocketBase.
#
#   scripts/pocketbase-live.sh -- kagami test --all --strict
#
# PocketBase is one Go binary over a SQLite directory, so there is no container
# and no image (#18 review): the script runs the OFFICIAL release binary for this
# machine directly. In order:
#   1. fetches the release zip once into .build/pocketbase/<version>-<os>_<arch>/,
#      checking it against a pinned sha256 (a mismatch is refused, never retried);
#   2. creates a fresh run directory under .build/pocketbase-live/ (the data
#      directory and the pb_migrations PocketBase puts beside it) and a generated
#      superuser in it;
#   3. serves it on a free 127.0.0.1 port and waits for /api/health;
#   4. runs the command you gave it with the live-test environment set;
#   5. stops the server and deletes the run directory, always — on success,
#      failure, Ctrl-C or kill — and says so.
#
# Nothing goes to the system temporary directory: both directories sit in the
# package's own .build (git-ignored), where `swift package clean` reaps them.
#
# The superuser password is generated here and handed to the command through the
# ENVIRONMENT only; it is never printed or written to a file. It is on the argv of
# the one-second `pocketbase superuser upsert` call (PocketBase takes it no other
# way), so another process of the SAME local user could see it during that call.
# It is a throwaway credential for a server that dies with this script.
#
# The command receives:
#   NETKIT_POCKETBASE_URL              http://127.0.0.1:<port>
#   NETKIT_POCKETBASE_ADMIN_EMAIL
#   NETKIT_POCKETBASE_ADMIN_PASSWORD
#
# Environment:
#   POCKETBASE_VERSION   PocketBase release to run (default: the latest one pinned below)
#   POCKETBASE_SHA256    sha256 of that release's zip for this os/arch;
#                        required when POCKETBASE_VERSION is not one pinned below
#
# Needs: curl, unzip, shasum, python3 (to pick a free port), and network access
# to github.com the first time a given version is used.

set -euo pipefail

# The latest PocketBase release (v0.40.6, 2026-10-23).
DEFAULT_VERSION="0.40.6"
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

for tool in curl unzip shasum python3; do
    command -v "$tool" >/dev/null 2>&1 || { echo "pocketbase-live: $tool is not installed." >&2; exit 69; }
done

case "$(uname -s)" in
    Darwin) ZIP_OS="darwin" ;;
    Linux)  ZIP_OS="linux" ;;
    *) echo "pocketbase-live: unsupported OS '$(uname -s)'." >&2; exit 69 ;;
esac
case "$(uname -m)" in
    arm64 | aarch64) ZIP_ARCH="arm64" ;;
    amd64 | x86_64)  ZIP_ARCH="amd64" ;;
    *) echo "pocketbase-live: unsupported architecture '$(uname -m)'." >&2; exit 69 ;;
esac

# Pinned release checksums (github.com/pocketbase/pocketbase releases, checksums.txt).
pinned_sha256() {
    case "$1/$2" in
        0.40.6/darwin_arm64) echo "7f2f7544e9ee5994ab69f84b22a4ab9a3bcfed58c1dad7206d05ebeb753f968b" ;;
        0.40.6/darwin_amd64) echo "970464cfdb8faf0ad57e0b6b806fd85e81f99cb78000a1c9f78cdcb1b36d4b7a" ;;
        0.40.6/linux_arm64)  echo "d22c66ceb67ca92b7d767f36d826e848a276bcfa3c197ead20bf87c42208984f" ;;
        0.40.6/linux_amd64)  echo "0e1f609158ed945f809f8a02ae012aa0427129c66ebb63c1aee76f2c0309373f" ;;
        *) echo "" ;;
    esac
}
PLATFORM="${ZIP_OS}_${ZIP_ARCH}"
SHA256="${POCKETBASE_SHA256:-$(pinned_sha256 "$VERSION" "$PLATFORM")}"
if [ -z "$SHA256" ]; then
    echo "pocketbase-live: no pinned sha256 for PocketBase $VERSION ($PLATFORM); set POCKETBASE_SHA256." >&2
    exit 64
fi

PACKAGE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$PACKAGE_ROOT/.build/pocketbase/$VERSION-$PLATFORM"
BIN="$BIN_DIR/pocketbase"
# `|| true`: `head` closing the pipe SIGPIPEs `tr`, which pipefail would turn into a failure.
SUFFIX="$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 8 || true)"
# PocketBase puts pb_migrations BESIDE its data directory, so each run gets its
# own folder holding both, and cleanup removes that folder.
RUN_DIR="$PACKAGE_ROOT/.build/pocketbase-live/$SUFFIX"
DATA_DIR="$RUN_DIR/pb_data"
SERVER_PID=""

cleanup() {
    status=$?
    set +e
    if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill "$SERVER_PID" 2>/dev/null
        wait "$SERVER_PID" 2>/dev/null
    fi
    if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
        echo "pocketbase-live: FAILED to stop PocketBase (pid $SERVER_PID)" >&2
        status=70
    elif [ -n "$SERVER_PID" ]; then
        echo "pocketbase-live: PocketBase (pid $SERVER_PID) stopped."
    fi
    rm -rf "$RUN_DIR"
    if [ -e "$RUN_DIR" ]; then
        echo "pocketbase-live: FAILED to remove $RUN_DIR" >&2
        status=70
    else
        echo "pocketbase-live: run directory removed."
    fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# 1. Binary: the official release, checksum-verified, fetched once per version --
if [ ! -x "$BIN" ]; then
    mkdir -p "$BIN_DIR"
    ZIP="$BIN_DIR/pocketbase.zip"
    echo "pocketbase-live: fetching PocketBase $VERSION ($PLATFORM)..."
    curl -fsSL -o "$ZIP" \
        "https://github.com/pocketbase/pocketbase/releases/download/v${VERSION}/pocketbase_${VERSION}_${PLATFORM}.zip"
    if ! echo "$SHA256  $ZIP" | shasum -a 256 -c - >/dev/null 2>&1; then
        rm -f "$ZIP"
        echo "pocketbase-live: checksum mismatch for PocketBase $VERSION ($PLATFORM) — refusing it." >&2
        exit 70
    fi
    unzip -q -o "$ZIP" pocketbase -d "$BIN_DIR"
    rm -f "$ZIP"
    chmod +x "$BIN"
fi

# 2. Data directory and superuser: environment only, never printed --------------
mkdir -p "$DATA_DIR"
PB_ADMIN_EMAIL="admin-$SUFFIX@netkit-live.test"
PB_ADMIN_PASSWORD="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 28 || true)"
"$BIN" superuser upsert "$PB_ADMIN_EMAIL" "$PB_ADMIN_PASSWORD" --dir="$DATA_DIR" >/dev/null

# 3. Serve on a free localhost port ------------------------------------------------
PORT="$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
URL="http://127.0.0.1:$PORT"
"$BIN" serve --http="127.0.0.1:$PORT" --dir="$DATA_DIR" >"$RUN_DIR/server.log" 2>&1 &
SERVER_PID=$!

READY=0
for _ in $(seq 1 120); do
    if curl -fsS "$URL/api/health" >/dev/null 2>&1; then READY=1; break; fi
    kill -0 "$SERVER_PID" 2>/dev/null || break
    sleep 0.5
done
if [ "$READY" != "1" ]; then
    echo "pocketbase-live: PocketBase did not become healthy. Server log (no credentials in it):" >&2
    tail -n 20 "$RUN_DIR/server.log" >&2
    exit 70
fi
echo "pocketbase-live: $("$BIN" --version 2>&1) healthy at $URL (pid $SERVER_PID)"

# 4. Run the command -----------------------------------------------------------------
set +e
NETKIT_POCKETBASE_URL="$URL" \
NETKIT_POCKETBASE_ADMIN_EMAIL="$PB_ADMIN_EMAIL" \
NETKIT_POCKETBASE_ADMIN_PASSWORD="$PB_ADMIN_PASSWORD" \
    "$@"
COMMAND_STATUS=$?
set -e

echo "pocketbase-live: command exited $COMMAND_STATUS"
exit "$COMMAND_STATUS"
