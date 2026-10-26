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

# Records the commit the patches were last applied (or exported) at, so local
# commits that were never exported can be told apart from stale patches.
APPLIED_REF=refs/patches/build-sh-applied

# Prints the patch series in a directory: the .patches list, then each patch.
patch_series() {
  cat "$1/.patches"
  while read -r patch; do
    cat "$1/$patch"
  done < "$1/.patches"
}

# Whether the commits on top of the Node.js tag match patches/.
patches_in_sync() {
  local exported in_sync=0
  exported=$(mktemp -d)
  ../script/git-export-patches -o "$exported" "$NODE_TAG.." 2>/dev/null
  cmp -s <(patch_series "$exported") <(patch_series ../patches) || in_sync=1
  rm -rf "$exported"
  return $in_sync
}

if [ ! -d "$NODE_DIR" ]; then
  git clone --depth 1 --branch "$NODE_TAG" https://github.com/nodejs/node.git "$NODE_DIR"
fi
cd "$NODE_DIR"
if patches_in_sync; then
  git update-ref "$APPLIED_REF" HEAD
else
  HEAD_COMMIT=$(git rev-parse HEAD)
  if [ -e "$(git rev-parse --git-path rebase-apply)" ]; then
    echo "Applying patches to $NODE_DIR did not finish." >&2
    echo "Fix the failing patch in patches/, then run: cd $NODE_DIR && git am --abort" >&2
    exit 1
  fi
  if [ -n "$(git status --porcelain)" ] || {
       [ "$HEAD_COMMIT" != "$(git rev-parse "$NODE_TAG^{commit}")" ] &&
       [ "$HEAD_COMMIT" != "$(git rev-parse -q --verify "$APPLIED_REF")" ]
     }; then
    echo "$NODE_DIR has local changes that are not in patches/." >&2
    echo "Export them with: cd $NODE_DIR && ../script/git-export-patches -o ../patches" >&2
    echo "Or discard them with: cd $NODE_DIR && git reset --hard $NODE_TAG" >&2
    exit 1
  fi
  echo "Applying patches to $NODE_DIR"
  git reset -q --hard "$NODE_TAG"
  ../script/git-import-patches ../patches
  git update-ref "$APPLIED_REF" HEAD
fi
./configure "${CONFIGURE_FLAGS[@]}"
make
./out/Release/node --version
rm -rf "$RELEASE_DIR"
make install DESTDIR="$RELEASE_DIR"
"$RELEASE_DIR/usr/local/$ARTIFACT_NAME/bin/npm" --version
