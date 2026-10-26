# node-pointer-compression-builds

Custom builds of Node.js with [V8 pointer compression](https://v8.dev/blog/pointer-compression) enabled. Pointer compression shrinks V8 heap pointers from 8 bytes to 4 bytes, reducing heap memory usage significantly for applications with many heap-allocated objects.

Prebuilt binaries for all platforms are published as GitHub Releases. Each release is triggered manually via the **"Build Node.js from Source"** Actions workflow.

The build steps live in the reusable [`build.yaml`](.github/workflows/build.yaml) workflow. The Node.js version to build is set in [`node-version.txt`](node-version.txt), which both CI and `build.sh` read. It holds the tag of one of the [official Node.js releases](https://github.com/nodejs/node/releases). Pull requests that touch the version, patches, scripts or build workflows start **"Test Node.js build"**, which runs the same build on all platforms without uploading artifacts or publishing a release. Because a full build takes hours, each run waits for a maintainer to approve it (the `test-build` environment has required reviewers). It can also be started manually from the Actions tab.

## Build flags

All builds are configured with:

| Flag | Effect |
|---|---|
| `--experimental-enable-pointer-compression` | Compress V8 heap pointers from 8 → 4 bytes |
| `--experimental-pointer-compression-shared-cage` | Share the compression cage across Isolates in the same process; this also enables the V8 sandbox (`v8_enable_sandbox`) |
| `--without-siphash` | Use a simpler alternative to SipHash for V8 hash seeds |

## Platforms

| Platform | Architecture | Runner |
|---|---|---|
| Linux | x64 | ubuntu-22.04 |
| Linux | arm64 | ubuntu-22.04-arm |
| macOS | x64 | macos-15-intel |
| macOS | arm64 | macos-15 (Apple Silicon) |
| Windows | x64 | windows-2025 |
| Windows | arm64 | windows-11-arm |

## Patches

The builds apply a small set of patches on top of the Node.js source tree, stored in [`patches/`](patches/). These are necessary to make the pointer-compression build work.

[Electron](https://github.com/electron/electron) builds its bundled Node.js with pointer compression enabled, so the core patch is taken from its [Node.js patch set](https://github.com/electron/electron/tree/main/patches/node), along with the `git-import-patches` and `git-export-patches` scripts used to manage patches. When updating Node.js, take it from an [Electron release](https://github.com/electron/electron/releases) whose `node_version` in [`DEPS`](https://github.com/electron/electron/blob/main/DEPS) matches `node-version.txt`. Most of Electron's other Node.js patches are Electron-specific, or adapt Node.js to the newer V8 that Chromium ships; these builds use the V8 bundled with Node.js, so they don't need them. Patches not marked as coming from Electron are specific to this repository:

- **`support_v8_sandboxed_pointers`** (from Electron) — refactors several allocators to allocate within the V8 memory cage, required when `V8_SANDBOXED_POINTERS` is active.
- **`fix_hdr_histogram_build_with_clang_22_on_windows_x64`** — fixes a pointer type mismatch in the bundled HdrHistogram that ClangCL 22 (Visual Studio 2026) rejects on Windows x64. Already fixed in Node.js `main` (histogram 0.12.0); drop it once the built Node.js version includes that update.

### Adding a new patch

Run `./build.sh` once to get a patched source tree in `node-src-<tag>/`, then:

```bash
cd node-src-<tag>
vim some/code/file.cc
git commit
../script/git-export-patches -o ../patches
```

> [!NOTE]
> `git-export-patches` ignores uncommitted files — create a commit first. The commit subject line becomes the patch file name; the body should explain why the patch exists.

Re-exporting patches may cause shasums in unrelated patches to change. This is harmless — include those changes in your PR anyway to keep things consistent for others.

## Building locally

`build.sh` builds on macOS and Linux; Windows builds only run in CI (through `vcbuild.bat`).

### Prerequisites

- **macOS:** Xcode with Apple clang 16 or newer, plus `ninja` (`brew install ninja`).
- **Linux:** GCC 12 (`gcc-12` and `g++-12`, which the script picks up when they are installed), `make` and `ninja-build`.
- On both: `git` and Python 3.

### Build

```bash
./build.sh
```

On macOS, if a Homebrew LLVM `clang` comes first on your `PATH`, point the build at Apple clang to match CI:

```bash
CC=/usr/bin/clang CXX=/usr/bin/clang++ ./build.sh
```

The script:

1. Clones Node.js at the tag pinned in [`node-version.txt`](node-version.txt) into `node-src-<tag>/` and applies the patches from `patches/`.
2. Configures with the same flags as CI (plus `--openssl-use-def-ca-store` on macOS).
3. Builds with Ninja on all cores. The first build takes a while.
4. Smoke tests `node` and `npm`, then installs into `./release/usr/local/node-<tag>-<platform>-<arch>/` (the same layout as the release tarballs).

### Trying the result

```bash
./release/usr/local/node-<tag>-<platform>-<arch>/bin/node --version
```

To confirm pointer compression is on, this prints `1`:

```bash
./release/usr/local/node-<tag>-<platform>-<arch>/bin/node -p "process.config.variables.v8_enable_pointer_compression"
```

Pointer compression also caps the V8 heap at about 4 GB, so this prints at most about `4096` (MB):

```bash
./release/usr/local/node-<tag>-<platform>-<arch>/bin/node -p "v8.getHeapStatistics().heap_size_limit / 2**20"
```

### Rebuilding

Later runs reuse `node-src-<tag>/` and build incrementally. If `patches/` has changed since the patches were applied there, the script resets the tree to the tag and applies them again. Uncommitted edits are built as they are. It stops without touching anything when the tree has commits that were never exported, or uncommitted edits while the patches need re-applying, and says how to export or discard them.

To start from scratch, delete `node-src-<tag>/` and `release/`.
