# pico-bootstrap

`pico-bootstrap` is a Swift CLI that mirrors the install experience of the
`switchSDK` task inside the [pico-vscode](https://github.com/raspberrypi/pico-vscode)
extension. It resolves and downloads the Pico SDK, ARM bare-metal toolchain,
Ninja, CMake, picotool, and (optionally) pico-sdk-tools into the familiar
`~/.pico-sdk` layout so you can wire it into your own UI or automation.

## Requirements

- Swift 5.9 or newer
- macOS 13+ or Linux (x86_64 or arm64). Other platforms/architectures are
  rejected at runtime by `HostEnvironment.detect()`.
- Git and a working internet connection (downloads come from GitHub releases).
- (Optional) a personal GitHub token. Pass it via `--github-token` to avoid
  unauthenticated rate limits when the resolver hits the GitHub API.

## Building

```sh
swift build
```

You can also run the tool directly without installing it globally:

```sh
swift run pico-bootstrap --help
```

## Commands

`pico-bootstrap` exposes three async subcommands implemented in
`Sources/PicoSDKDownloader/PicoSDKDownloader.swift`.

### Install

Resolves versions and installs every component into the target directory
(`~/.pico-sdk` by default, override with `--root`).

```sh
swift run pico-bootstrap install \
  --sdk 2.2.0 \
  --toolchain 14_2_Rel1 \
  --cmake 3.31.5 \
  --ninja 1.12.1 \
  --picotool 2.2.0-a4
```

The install order matches the pico-vscode workflow: SDK → toolchain →
`pico-sdk-tools` (optional) → Ninja → CMake → picotool. Each component is
downloaded only if it does not already exist at the computed subdirectory under
the root. After each successful install a record is written to
`<root>/pico-bootstrap-manifest.json` so you can track what versions are present.

### Resolve

Computes the exact versions, download URLs, archive types, and relative install
paths without touching the filesystem. The resolver output is printed twice:

1. A human-friendly plan (component IDs, versions, and URLs)
2. Machine-readable JSON that matches `InstallPlan`

This is ideal if you are building a UI and only need to know what would happen.

```sh
swift run pico-bootstrap resolve ...flags...
```

### List

Lists available tags/releases for a given component so you can build selection
menus. Valid kinds are `sdkTags`, `picotoolReleases`, `picoSdkToolsReleases`, and
`armToolchainReleases`.

```sh
swift run pico-bootstrap list --kind sdkTags --limit 15
```

## Directory layout

Everything installs underneath the root in predictable folders so tooling can
point to them deterministically:

```
~/.pico-sdk/
  sdk/<sdkVersion>
  toolchain/<armToolchainVersion>
  tools/<sdkVersion>                  # pico-sdk-tools (optional)
  ninja/v<version>
  cmake/v<version>
  picotool/<version>
  pico-bootstrap-manifest.json
```

On macOS the installer also creates a `bin` symlink inside the unpacked CMake
bundle to match what pico-vscode expects.

## How resolution works

`VersionResolver` resolves component download URLs for the host OS/arch:

- **ARM toolchain**: Resolved via `supportedToolchains.ini` (same approach as
  pico-vscode). The CLI attempts to fetch the latest INI from GitHub, falling
  back to a bundled offline cache when the remote fetch fails. This avoids
  unreliable GitHub release tag lookups for ARM toolchains.
- **Other components** (CMake, Ninja, picotool): Resolved from official GitHub
  repositories (Kitware, ninja-build, raspberrypi), picking the correct asset
  for the host OS/arch and falling back across common tag/filename variations.
- **pico-sdk-tools**: Best-effort resolution from raspberrypi/pico-sdk-tools;
  silently skipped if no matching release asset is found.

If a tag, release, or platform-specific asset cannot be found the command exits
with a descriptive `PicoBootstrapError`, making it easy to surface failures to
end users.
