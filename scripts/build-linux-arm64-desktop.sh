#!/usr/bin/env bash
set -euo pipefail

# Stirling PDF native Linux ARM64 desktop builder.
# Run this on an ARM64/AArch64 Ubuntu/Debian machine from the repository root.

ARCH="$(uname -m)"
case "$ARCH" in
  aarch64|arm64) ;;
  *)
    echo "ERROR: This script requires a native ARM64/AArch64 Linux host; got: $ARCH" >&2
    exit 1
    ;;
esac

for cmd in node npm cargo rustc java task file dpkg-deb; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: missing required command: $cmd" >&2
    exit 1
  fi
done

NODE_MAJOR="$(node -p 'Number(process.versions.node.split(".")[0])')"
if [ "$NODE_MAJOR" -lt 22 ]; then
  echo "ERROR: Node.js 22+ is required; found $(node --version)" >&2
  exit 1
fi

JAVA_MAJOR="$(java -version 2>&1 | awk -F '[\".]' '/version/ {print $2; exit}')"
if [ "${JAVA_MAJOR:-0}" -lt 25 ]; then
  echo "ERROR: Java 25+ is required; found:" >&2
  java -version >&2
  exit 1
fi

if [ -z "${JAVA_HOME:-}" ]; then
  JAVA_BIN="$(readlink -f "$(command -v java)")"
  export JAVA_HOME="$(dirname "$(dirname "$JAVA_BIN")")"
fi

export CI=true
export DISABLE_ADDITIONAL_FEATURES=true
export JPDFIUM_PLATFORMS=linux-arm64

echo "== Toolchains =="
echo "arch:       $(uname -m)"
echo "node:       $(node --version)"
echo "npm:        $(npm --version)"
echo "rustc:      $(rustc --version)"
echo "cargo:      $(cargo --version)"
echo "JAVA_HOME:  $JAVA_HOME"
java -version
echo "task:       $(task --version)"
echo

echo "== Preparing Stirling PDF desktop backend/JRE =="
task desktop:prepare

if [ "${RUN_TESTS:-1}" = "1" ]; then
  echo "== Running Tauri/Cargo tests =="
  task desktop:test
fi

JAVA_LIBJVM="$JAVA_HOME/lib/server/libjvm.so"
if [ -f "$JAVA_LIBJVM" ]; then
  if command -v sudo >/dev/null 2>&1; then
    sudo ln -sf "$JAVA_LIBJVM" /usr/lib/libjvm.so
  fi
fi

echo "== Building DEB =="
(
  cd frontend/editor
  npx tauri build \
    --bundles deb \
    --config '{"bundle":{"createUpdaterArtifacts":false}}'
)

echo "== Building AppImage =="
(
  cd frontend/editor
  npx tauri build \
    --bundles appimage \
    --config '{"bundle":{"createUpdaterArtifacts":false}}'
)

TARGET="$PWD/frontend/editor/src-tauri/target"
DIST="$PWD/dist-arm64"
mkdir -p "$DIST"

DEB="$(find "$TARGET" -type f -name '*.deb' | head -n 1)"
APPIMAGE="$(find "$TARGET" -type f -name '*.AppImage' | head -n 1)"

test -n "$DEB"
test -n "$APPIMAGE"

DEB_ARCH="$(dpkg-deb -f "$DEB" Architecture)"
if [ "$DEB_ARCH" != "arm64" ]; then
  echo "ERROR: DEB architecture is $DEB_ARCH, expected arm64" >&2
  exit 1
fi

if ! file "$APPIMAGE" | grep -Eqi 'aarch64|ARM'; then
  echo "ERROR: AppImage does not appear to be ARM64:" >&2
  file "$APPIMAGE" >&2
  exit 1
fi

cp "$DEB" "$DIST/Stirling-PDF-linux-arm64.deb"
cp "$APPIMAGE" "$DIST/Stirling-PDF-linux-arm64.AppImage"
chmod +x "$DIST/Stirling-PDF-linux-arm64.AppImage"

(
  cd "$DIST"
  sha256sum \
    Stirling-PDF-linux-arm64.deb \
    Stirling-PDF-linux-arm64.AppImage \
    > SHA256SUMS.txt
)

echo
echo "Build complete:"
ls -lh "$DIST"
echo
cat "$DIST/SHA256SUMS.txt"
