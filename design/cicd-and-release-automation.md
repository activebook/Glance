# CI/CD & Automated Release Architecture

This document provides a comprehensive technical guide to the Continuous Integration (CI) and Continuous Deployment (CD) pipeline implemented for **Glance**. It details the architectural rationale, security boundaries, versioning strategies, and developer workflows.

---

## 1. Architectural Philosophy: The Dual-Phase Pipeline

Modern software delivery separates validation from deployment to guarantee stability, security, and version integrity:

```
                            ┌─────────────────────────────────────────┐
                            │      Developer Opens Pull Request       │
                            └────────────────────┬────────────────────┘
                                                 │
                                                 ▼
                       Phase 1: Continuous Integration (CI: ci.yml)
                     ┌──────────────────────────────────────────────────┐
                     │ • Triggers on: Pull Requests targeting `main`    │
                     │ • Permissions: Read-Only (Secure Sandbox)        │
                     │ • Actions:                                       │
                     │   1. Restore SwiftPM Dependency Cache            │
                     │   2. Execute 43 Unit Tests in Parallel           │
                     │   3. Build Universal 2 App Bundle (arm64+x86_64) │
                     │   4. Verify Mach-O Slices with `lipo`            │
                     │   5. Upload Temporary 7-Day QA Preview Artifact  │
                     │ • Gate: PR Merge is blocked if any check fails   │
                     └───────────────────────────┬──────────────────────┘
                                                 │ (Code Review & Merge)
                                                 ▼
                       Phase 2: Continuous Deployment (CD: release.yml)
                     ┌──────────────────────────────────────────────────┐
                     │ • Triggers on: Merge commit onto `main` branch   │
                     │ • Permissions: Write (`contents: write`)         │
                     │ • Actions:                                       │
                     │   1. Inspect Conventional Commit / PR Title      │
                     │   2. Compute Next SemVer Version (patch/minor)   │
                     │   3. Create and Push Git Tag (`vX.Y.Z`)          │
                     │   4. Inject Version & Build into `Info.plist`    │
                     │   5. Build Optimized Universal `Glance.zip`      │
                     │   6. Compute SHA-256 Checksum                    │
                     │   7. Publish Official GitHub Release with Notes  │
                     └───────────────────────────┬──────────────────────┘
                                                 │
                                                 ▼
                            ┌─────────────────────────────────────────┐
                            │    Developer Syncs: `git pull --tags`   │
                            └─────────────────────────────────────────┘
```

---

## 2. Why CI and CD Are Separated

| Engineering Concern | Continuous Integration (CI) | Continuous Deployment (CD) |
| :--- | :--- | :--- |
| **Execution Trigger** | Open / Update a **Pull Request** | **Merge PR** into `main` branch |
| **Primary Goal** | **Pre-Merge Safety Gate**: Ensure code does not break tests or compilation. | **Post-Merge Distribution**: Mint version, package binary, and deliver to users. |
| **Security Principle** | **Read-Only**: Untrusted PRs cannot create releases, access secrets, or write tags. | **Write Access**: Restricted to authorized merges on the protected `main` branch. |
| **Version Impact** | **Zero**: No Git tags or version increments are created during PR iterations. | **Deterministic**: Bumps version once per approved PR merge. |
| **Artifact Lifecycle** | **Ephemeral**: 7-day temporary build for PR inspection. | **Permanent & Immutable**: Public release assets (`Glance.zip`, `.sha256`). |

---

## 3. Deep Dive: Continuous Integration (`ci.yml`)

File: [`.github/workflows/ci.yml`](file:///Users/mac/Github/Glance/.github/workflows/ci.yml)

### A. Triggers & Concurrency
```yaml
on:
  pull_request:
    branches: [main]
  workflow_dispatch:

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
```
- **`cancel-in-progress: true`**: If a developer pushes 3 commits in rapid succession to a PR, previous unfinished CI runs are immediately cancelled to conserve runner minutes.

### B. Dependency Caching
```yaml
- name: Cache SwiftPM Dependencies
  uses: actions/cache@v4
  with:
    path: .build
    key: ${{ runner.os }}-spm-${{ hashFiles('Package.resolved', 'Package.swift') }}
    restore-keys: ${{ runner.os }}-spm-
```
- Hashes `Package.swift` to cache compiled package artifacts across runs, reducing build times from minutes to seconds.

### C. Universal 2 Binary Verification
```yaml
- name: Verify Universal 2 Binary Slices
  run: |
    lipo -info build/Glance.app/Contents/MacOS/Glance | grep -q "arm64"
    lipo -info build/Glance.app/Contents/MacOS/Glance | grep -q "x86_64"
```
- Automatically asserts that the binary is a true Mach-O fat executable containing both Apple Silicon (`arm64`) and Intel (`x86_64`) instruction sets.

---

## 4. Deep Dive: Automated Release & Semantic Versioning (`release.yml`)

File: [`.github/workflows/release.yml`](file:///Users/mac/Github/Glance/.github/workflows/release.yml)

### A. Semantic Versioning Algorithm
When a PR is merged into `main`, the workflow analyzes the commit history:

1. **Find Latest Tag**: Runs `git describe --tags --abbrev=0` (defaults to `v0.1.0` if no tags exist).
2. **Parse Version Triple**: Splits into `MAJOR.MINOR.PATCH`.
3. **Determine Bump Type**:
   - `feat!: ...` or `BREAKING CHANGE:` $\rightarrow$ **Major Bump** (`v1.0.0`)
   - `feat: ...` or `feat(ui): ...` $\rightarrow$ **Minor Bump** (`v0.2.0`)
   - `fix: ...`, `chore: ...`, `docs: ...` or default $\rightarrow$ **Patch Bump** (`v0.1.1`)
4. **Push Git Tag**: Pushes `vX.Y.Z` back to GitHub using the actions bot credentials.

### B. Dynamic Plist Version Injection
In [scripts/make_app.sh](file:///Users/mac/Github/Glance/scripts/make_app.sh), the version and build count are resolved dynamically at build time:
```bash
GIT_TAG="$(git describe --tags --abbrev=0 2>/dev/null || echo "")"
RAW_VERSION="${VERSION:-${GIT_TAG:-0.1.0}}"
APP_VERSION="${RAW_VERSION#v}"
APP_BUILD="${BUILD_NUM:-$(git rev-list --count HEAD 2>/dev/null || echo "1")}"
```
This guarantees that `CFBundleShortVersionString` and `CFBundleVersion` inside `Info.plist` perfectly mirror the Git release tag.

### C. Cryptographic Verification & Asset Packaging
```bash
shasum -a 256 Glance.zip > Glance.zip.sha256
```
Users and package managers (e.g., Homebrew Cask) can verify download integrity by validating the SHA-256 hash.

---

## 5. Branch Protection Rules

The `main` branch is protected using GitHub Branch Protection:
1. **Require Pull Request**: Direct pushes to `main` via `git push origin main` are rejected by GitHub.
2. **Required Status Checks**: The check `Test & Build Universal Binary` (`ci.yml`) must report green before the PR merge button is enabled.
3. **Stale Review Dismissal**: Force pushes to PR branches automatically invalidate previous approvals.

---

## 6. Developer Workflow Cheatsheet

### Daily Development Routine

```bash
# 1. Create a feature or bugfix branch
git checkout -b feat/custom-shortcuts

# 2. Make changes and run local debug build
bash scripts/debug.sh

# 3. Run test suite locally
swift test

# 4. Commit using Conventional Commits
git commit -m "feat: add customizable HUD transparency slider"
git push origin feat/custom-shortcuts

# 5. Open Pull Request on GitHub
gh pr create --fill

# 6. Once CI passes and PR is merged on GitHub:
git checkout main
git pull --tags
```

---

## 7. Script Responsibilities Matrix

| Script | Execution Target | Output Location | Purpose |
| :--- | :--- | :--- | :--- |
| **[`scripts/debug.sh`](file:///Users/mac/Github/Glance/scripts/debug.sh)** | Local Development | `build/Glance.app` | Fast unoptimized build & launches app immediately. |
| **[`scripts/release.sh`](file:///Users/mac/Github/Glance/scripts/release.sh)** | CI / Local Release | `build/Glance.app` + `build/Glance.zip` | Optimized Universal build & zip distribution packaging. |
| **[`scripts/make_app.sh`](file:///Users/mac/Github/Glance/scripts/make_app.sh)** | Internal Engine | `build/Glance.app` | Core bundle assembler invoked by debug and release scripts. |
| **[`scripts/generate_icon.swift`](file:///Users/mac/Github/Glance/scripts/generate_icon.swift)** | Asset Generator | `AppIcon.icns` | Programmatically generates all icon resolutions ($16\text{px}$ to $1024\text{px}$). |

---

## 8. macOS SDK Linking, Compatibility Mode & `vtool` Mach-O Stamping

### A. The "Linked-On" Binary Compatibility Gate
Apple’s dynamic linker (`dyld`), AppKit, and the macOS WindowServer inspect the **`LC_BUILD_VERSION`** load command embedded inside the Mach-O binary to determine the exact SDK version used at compile time.

```
  ┌────────────────────────────────────────────────────────┐
  │ Local Developer Build (macOS Tahoe / Xcode 17+)        │
  │ • Linked SDK: >= 26.0                                  │
  │ • WindowServer Behavior: Modern Liquid Glass Floating  │
  │   Sidebar Panel with Inset Floating Margins.           │
  └────────────────────────────────────────────────────────┘

  ┌────────────────────────────────────────────────────────┐
  │ Untreated Cloud CI Build (e.g., `macos-15` Runner)     │
  │ • Linked SDK: 15.x                                     │
  │ • WindowServer Behavior: Legacy AppKit Compatibility   │
  │   Mode (forces classic edge-to-edge attached sidebar   │
  │   with vertical divider line to prevent breakage).     │
  └────────────────────────────────────────────────────────┘
```

### B. Why Cloud CI Runners Alter App UI Appearance
GitHub Actions cloud runners currently provide `macos-14` (Sonoma) and `macos-15` (Sequoia). When GitHub Actions compiles the universal application bundle on `macos-15`, the resulting Mach-O header records `sdk: 15.5`. When a user runs that binary on macOS Tahoe (macOS 26), the operating system deliberately forces AppKit into backward-compatibility mode, suppressing the floating Liquid Glass sidebar.

### C. The Solution: Mach-O Header Stamping via `vtool`
To ensure cloud-built binaries activate the modern floating UI while retaining 100% dynamic runtime linking and backward compatibility down to macOS 14.0, [scripts/make_app.sh](file:///Users/mac/Github/Glance/scripts/make_app.sh) incorporates Apple's official `vtool` utility directly before code signing:

```bash
# Stamp target SDK 26.0 into Mach-O LC_BUILD_VERSION load command
if command -v vtool >/dev/null 2>&1; then
    vtool -set-build-version macos 14.0 26.0 -replace \
          -output "$APP_DIR/Contents/MacOS/Glance" "$APP_DIR/Contents/MacOS/Glance"
fi
```

### D. Verification Workflow
Developers can verify the embedded SDK version across both architecture slices using `vtool` or `otool`:

```bash
$ vtool -show-build build/Glance.app/Contents/MacOS/Glance
build/Glance.app/Contents/MacOS/Glance (architecture x86_64):
  cmd LC_BUILD_VERSION
  platform MACOS
  minos 14.0
  sdk 26.0
build/Glance.app/Contents/MacOS/Glance (architecture arm64):
  cmd LC_BUILD_VERSION
  platform MACOS
  minos 14.0
  sdk 26.0
```

This guarantees that releases distributed from GitHub Actions render with the identical ultra-modern floating sidebar aesthetics as local Xcode builds.
