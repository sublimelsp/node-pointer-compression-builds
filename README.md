# node-pointer-compression-builds

Custom builds of Node.js with [V8 pointer compression](https://v8.dev/blog/pointer-compression) enabled. Pointer compression shrinks V8 heap pointers from 8 bytes to 4 bytes, reducing heap memory usage significantly for applications with many heap-allocated objects.

Prebuilt binaries for all platforms are published as GitHub Releases. Each release is triggered manually via the **"Build Node.js from Source"** Actions workflow.

The build steps live in the reusable [`build.yaml`](.github/workflows/build.yaml) workflow. The Node.js version to build is set in [`node-version.txt`](node-version.txt), which both CI and `build.sh` read. It holds a tag of one of the [official Node.js releases](https://github.com/nodejs/node/releases), such as `v24.15.0`. Pull requests that touch the version, patches, scripts or build workflows start **"Test Node.js build"**, which runs the same build on all platforms without uploading artifacts or publishing a release. Because a full build takes hours, each run waits for a maintainer to approve it (the `test-build` environment has required reviewers). It can also be started manually from the Actions tab.

## Build flags

All builds are configured with:

| Flag | Effect |
|---|---|
| `--experimental-enable-pointer-compression` | Compress V8 heap pointers from 8 → 4 bytes |
| `--experimental-pointer-compression-shared-cage` | Share the compression cage across Isolates in the same process |
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

[Electron](https://github.com/electron/electron) builds its bundled Node.js with pointer compression enabled, so the core patches are taken from its [Node.js patch set](https://github.com/electron/electron/tree/main/patches/node), along with the `git-import-patches` and `git-export-patches` scripts used to manage them. Patches not marked as coming from Electron are specific to this repository:

- **`support_v8_sandboxed_pointers`** (from Electron) — refactors several allocators to allocate within the V8 memory cage, required when `V8_SANDBOXED_POINTERS` is active.
- **`random_build_flag_changes`** — enables the V8 sandbox (`v8_enable_sandbox`) when pointer compression is on, matching V8's expectations.
- **`api_remove_deprecated_getisolate`** (from Electron) — replaces a deprecated `context->GetIsolate()` call with `Isolate::GetCurrent()`, required by newer V8.
- **`fix_hdr_histogram_build_with_clang_22_on_windows_x64`** — fixes a pointer type mismatch in the bundled HdrHistogram that ClangCL 22 (Visual Studio 2026) rejects on Windows x64. Already fixed in Node.js `main` (histogram 0.12.0); drop it once the built Node.js version includes that update.

### Adding a new patch

Run `./build.sh` once to get a patched source tree in `node-src-<tag>/`, then:

```bash
cd node-src-v24.15.0
vim some/code/file.cc
git commit
../script/git-export-patches -o ../patches
```

> [!NOTE]
> `git-export-patches` ignores uncommitted files — create a commit first. The commit subject line becomes the patch file name; the body should explain why the patch exists.

Re-exporting patches may cause shasums in unrelated patches to change. This is harmless — include those changes in your PR anyway to keep things consistent for others.

## Building locally

```bash
./build.sh
```

This clones Node.js at the tag pinned in [`node-version.txt`](node-version.txt), applies all patches, configures with the same flags as CI, and installs the result into `./release/usr/local/node-<tag>-<platform>-<arch>/` (the same layout as the release tarballs).

On later runs it reuses `node-src-<tag>/` and builds incrementally. If `patches/` has changed since the patches were applied there, it resets the tree to the tag and applies them again. Uncommitted edits are built as they are. It stops without touching anything when the tree has commits that were never exported, or uncommitted edits while the patches need re-applying, and says how to export or discard them.
