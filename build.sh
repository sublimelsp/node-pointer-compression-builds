#!/bin/bash

set -e
cd "$(dirname "$0")"
ROOT_DIR=$(pwd)

NODE_TAG=$(tr -d '[:space:]' < node-version.txt)
NODE_DIR="node-src-$NODE_TAG"
RELEASE_DIR="$ROOT_DIR/release"

case "$(uname -s)" in
  Linux) PLATFORM=linux ;;
  Darwin) PLATFORM=darwin ;;
  *) echo "Unsupported platform: $(uname -s)" >&2; exit 1 ;;
esac
case "$(uname -m)" in
  x86_64) ARCH=x64 ;;
  arm64|aarch64) ARCH=arm64 ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac
# Same install layout as the CI tarballs
ARTIFACT_NAME="node-$NODE_TAG-$PLATFORM-$ARCH"

CONFIGURE_FLAGS=(
  --prefix="/usr/local/$ARTIFACT_NAME"
  --ninja
  --experimental-enable-pointer-compression
  --experimental-pointer-compression-shared-cage
  --without-siphash
)
if [ "$PLATFORM" = darwin ]; then
  # Use the macOS system Keychain for CA certificates
  CONFIGURE_FLAGS+=(--openssl-use-def-ca-store)
elif [ -z "$CC" ] && command -v gcc-12 >/dev/null && command -v g++-12 >/dev/null; then
  # CI builds Linux with GCC 12
  export CC=gcc-12 CXX=g++-12
fi

if [ ! -d "$NODE_DIR" ]; then
  git clone --depth 1 --branch "$NODE_TAG" https://github.com/nodejs/node.git "$NODE_DIR"
  (cd "$NODE_DIR" && ../script/git-import-patches ../patches)
fi
cd "$NODE_DIR"
./configure "${CONFIGURE_FLAGS[@]}"
make
./out/Release/node --version
rm -rf "$RELEASE_DIR"
make install DESTDIR="$RELEASE_DIR"
"$RELEASE_DIR/usr/local/$ARTIFACT_NAME/bin/npm" --version
