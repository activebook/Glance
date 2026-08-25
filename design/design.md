# Glance — Master Technical Architecture & Design Document

**Version:** 2.0 · **Date:** 2026-08-25 · **Status:** Production-Ready (Active Implementation)  
**Project Path:** `/Users/mac/Github/Glance`  
**Distribution:** macOS Menu Bar Utility (Universal Binary: Apple Silicon `arm64` & Intel `x86_64`)

---

## 1. Executive Summary

**Glance** is an ultra-fast, native macOS menu bar application designed for frictionless on-screen translation, OCR, and language comprehension. With a single universal shortcut (`⌥G`), Glance darkens the display, enables freeform marquee selection or smart window snapping, captures high-resolution Retina pixels, dispatches the image to vision-capable LLM endpoints (defaulting to Google Gemini Flash Lite), and projects an interactive glassmorphic floating result HUD adjacent to the capture rect.

Every capture–translation pair is permanently indexed in a high-performance SQLite database with full-text search, customizable translation tones (including Japanese Furigana annotation), history management, and an integrated background self-updating engine.

```
                  ┌─────────────────────────────────────────────────────────┐
                  │                Glance Universal Flow                    │
                  └────────────────────────────┬────────────────────────────┘
                                               │
                                       Press ⌥G (Hotkey)
                                               │
                                               ▼
                           ┌───────────────────────────────────────┐
                           │ Full-Screen Darkened Overlay          │
                           │ • Immediate backdrop feedback         │
                           │ • Freeform drag OR smart window snap  │
                           │   (activates upon cursor movement)    │
                           └───────────────────┬───────────────────┘
                                               │
                                               ▼
                           ┌───────────────────────────────────────┐
                           │ Vision LLM API Pipeline               │
                           │ • OpenAI-compatible Chat Completions  │
                           │ • Default: Google Gemini Flash Lite   │
                           │ • Multi-persona tone directives       │
                           │ • High-performance base64 downscaler │
                           └───────────────────┬───────────────────┘
                                               │
                                               ▼
                           ┌───────────────────────────────────────┐
                           │ Glassmorphic Floating Result HUD      │
                           │ • Positioned adjacent to capture rect │
                           │ • TTS Speech Synthesizer & 1-click cpy│
                           │ • Collapsible original source toggle  │
                           │ • Latency & token diagnostic badges   │
                           └───────────────────┬───────────────────┘
                                               │
                                               ▼
                           ┌───────────────────────────────────────┐
                           │ Local Persistence & History           │
                           │ • SQLite database with FTS5 indexing  │
                           │ • Original Retina PNG image archive   │
                           │ • Full management & date-range prune  │
                           └───────────────────────────────────────┘
```

---

## 2. Core Architectural Pillars & Design Decisions

| Pillar | Architectural Decision | Implementation Rationale |
| :--- | :--- | :--- |
| **Invocation** | Single Smart Hotkey (`⌥G` default) | Carbon Event HotKey API ensures global accessibility without accessibility permission hurdles. |
| **Capture Experience** | Screen Darkening + Deferred Snapping | Darkens the entire display immediately so the user knows `⌥G` registered; window snapping only activates when the mouse moves ($\ge 3\text{pt}$). |
| **Translation Engine** | Vision-First Cloud LLM | Directly consumes Retina pixels; handles complex typography, stylized text, handwriting, and layout without lossy local OCR pre-processing. |
| **Default Model** | Google Gemini Flash Lite | `gemini-flash-lite-latest` via Google's OpenAI-compatible endpoint delivers sub-second latency and zero-shot multimodal precision. |
| **Persona Directives** | 9 Tailored Translation Tones | Includes Natural, Technical, Casual, Concise, Japanese Furigana, Bilingual Explanatory, Polite, Literary, and Sarcastic modes. |
| **macOS Tahoe UI** | Dynamic SDK 26.0 Linking via `vtool` | Mach-O headers stamped with `sdk: 26.0` and `minos: 14.0` to enable macOS Tahoe's floating sidebar while remaining backward compatible with macOS 14+. |
| **Code Signing & TCC** | Repository-Embedded `.p12` Certificate | `GlanceCodeSign` identity shared across local and GitHub Actions CI builds ensures Screen Recording permissions persist forever. |
| **Self-Updater** | Integrated Semantic GitHub Updater | Queries GitHub Releases API, compares semver tags, verifies SHA-256 checksums, and atomically replaces `Glance.app` in-place. |

---

## 3. System Architecture & Module Map

The codebase is organized cleanly under the Swift Package Manager directory structure:

```
Sources/Glance/
├── App/
│   ├── AppDelegate.swift              # App lifecycle, menu bar icon, status item coordinator
│   ├── MenuBarController.swift        # Menu bar dropdown, active endpoint switcher, quick actions
│   └── main.swift                     # NSApplication bootstrap
├── Capture/
│   ├── CaptureCoordinator.swift       # State machine orchestrating capture → translate → store → display
│   ├── SelectionOverlay.swift         # Multi-screen borderless selection panel & window hover highlights
│   ├── ScreenCaptureService.swift     # CoreGraphics / ScreenCaptureKit pixel capture & display mapping
│   ├── WindowDetector.swift           # Window server query & z-order geometric hit testing
│   └── CaptureGeometry.swift          # Display-relative scaling and coordinate transform utilities
├── Translate/
│   ├── LLMClient.swift                # OpenAI-compatible HTTP vision client, prompt injection, recovery parsers
│   ├── ImageDownscaler.swift          # Long-side pixel budget downscaler (≤ 2000 px) for token economy
│   └── NotificationService.swift      # User notification dispatch for background errors/events
├── Models/
│   ├── AppLanguage.swift              # Supported source & target languages with prompt names
│   ├── TranslationTone.swift          # Tone personas, system prompt directives, use-case descriptions
│   ├── EndpointConfig.swift           # LLM endpoint metadata, base URL, and model identifiers
│   ├── SnapshotRecord.swift           # SQLite record model for history persistence
│   ├── TranslationItem.swift          # Structured `{ source, translation }` item pairs
│   ├── HotkeyCombo.swift              # Carbon keycode & modifier flag representations
│   └── UpdateManager.swift            # GitHub release polling, semver comparison, atomic updater
├── Storage/
│   ├── HistoryStore.swift             # SQLite3 C API wrapper, WAL journaling, FTS5 queries, date deletions
│   ├── SettingsStore.swift            # UserDefaults persistence for active endpoint, tone, languages, hotkeys
│   └── KeychainHelper.swift           # Security framework wrapper for per-endpoint API key encryption
└── UI/
    ├── ResultPanel/
    │   ├── FloatingResultPanel.swift  # Floating glassmorphic HUD, draggable titlebar, TTS, copy actions
    │   └── VisualEffectBackground.swift # NSVisualEffectView glassmorphic material wrapper
    ├── History/
    │   ├── HistoryWindow.swift        # Tahoe NavigationSplitView, search bar, segmented status filter
    │   ├── HistoryModel.swift         # Observable history state, async queries, pagination
    │   └── DetailView.swift           # Side-by-side zoomable image inspection & translation blocks
    ├── Settings/
    │   ├── SettingsWindowController.swift # Multi-tab Preferences window
    │   ├── GeneralTab.swift           # Target language, tone selector with use-case guide, timeout
    │   ├── EndpointsTab.swift         # LLM endpoints CRUD, connectivity tester, key management
    │   ├── HotkeyTab.swift            # Interactive hotkey recorder & collision detection
    │   └── AppearanceTab.swift        # Color themes and HUD aesthetic options
    └── Update/
        ├── VersionPillView.swift      # Menu bar update indicator badge
        └── UpdateModalView.swift      # Release notes presentation, download progress, restart trigger
```

---

## 4. Detailed Feature Specifications

### 4.1 Smart Screen Capture (`⌥G`)

1. **Activation**:
   - Hotkey triggers [`SelectionOverlayController.begin()`](file:///Users/mac/Github/Glance/Sources/Glance/Capture/SelectionOverlay.swift).
   - An invisible, borderless `NSPanel` (`.screenSaver` level) covers each connected display.
2. **Visual Feedback & Deferral**:
   - The overlay immediately fills the screen with `NSColor.black.withAlphaComponent(0.40)` to indicate that capture mode is active.
   - `WindowDetector` pre-queries visible windows but **defers drawing window cutouts** until the cursor moves $\ge 3\text{pt}$ from the initial invocation point.
3. **Capture Execution**:
   - **Marquee Selection**: Dragging creates a sharp accent-bordered selection with a live pixel dimension pill (`1280 × 720`). Minimum selection size is $16 \times 16\text{pt}$.
   - **Smart Window Snapping**: Moving the cursor over a window highlights its exact bounding box with an 8pt corner radius and displays a title/size badge (`Xcode • 1440 × 900`). A single click captures that window.
   - **Cancellation**: Pressing `Esc` or right-clicking dismisses the overlay instantly without capturing.

---

### 4.2 Translation Pipeline & Personas

#### OpenAI-Compatible Vision Protocol
Glance serializes captured screenshots into base64 PNG data. If the long side exceeds 2000px, [`ImageDownscaler`](file:///Users/mac/Github/Glance/Sources/Glance/Translate/ImageDownscaler.swift) proportionally rescales the image to conserve API tokens while maintaining text legibility.

```http
POST {baseURL}/chat/completions
Content-Type: application/json
Authorization: Bearer {apiKey}

{
  "model": "gemini-flash-lite-latest",
  "temperature": 0.2,
  "response_format": {"type": "json_object"},
  "messages": [
    {
      "role": "user",
      "content": [
        {"type": "text", "text": "<System Prompt with Tone Directive>"},
        {"type": "image_url", "image_url": {"url": "data:image/png;base64,..."}}
      ]
    }
  ]
}
```

#### Translation Persona Directives

| Persona | Key | Specific Prompt Directive & Formatting |
| :--- | :--- | :--- |
| **Natural** | `natural` | Balanced, idiomatic translation that sounds natural to native speakers. |
| **Technical** | `technical` | Preserves code syntax, API/function names, framework terms, and engineering jargon. |
| **Casual** | `casual` | Uses relaxed, localized colloquialisms and chat slang. |
| **Concise** | `concise` | Strips filler and boilerplate; delivers the core factual message in minimal words. |
| **Japanese Furigana** | `furigana` | Transcribes the original Japanese in the `source` field with inline hiragana readings attached to every Kanji (e.g. `漢字[かんじ]`), while keeping the `translation` field completely clean. |
| **Bilingual Explanatory** | `explanatory` | Translates fluently and provides helpful notes explaining key vocabulary and idioms. |
| **Polite & Formal** | `polite` | Uses formal honorifics and respectful etiquette suitable for business communication. |
| **Literary / Imaginative** | `imaginative` | Translates with vivid imagery, rich metaphors, and creative storytelling flair. |
| **Sarcastic** | `sarcastic` | Delivers punchy translations with sharp wit, irony, and humorous cynicism. |

---

### 4.3 Glassmorphic Result HUD

- **Positioning**: Automatically positioned adjacent to the capture rect, clamped within the screen bounds with a 20pt margin.
- **Visual Style**: Native `NSVisualEffectView` with `.hudWindow` / `.popover` material, rounded corners (16pt), and a subtle border.
- **Interactive Controls**:
  - **Copy All / Copy Segment**: 1-click clipboard copy with visual checkmark feedback.
  - **Text-To-Speech (TTS)**: Built-in speech synthesizer to pronounce translated text aloud.
  - **Source Toggle**: Collapsible disclosure triangle to reveal original source text side-by-side with translation.
  - **Diagnostic Badges**: Displays execution latency (e.g., `842 ms`), capture dimensions, and active model name.
  - **Auto-Dismissal**: Auto-dismisses after a configurable timeout (default 10s), paused whenever the mouse hovers over the HUD.

---

### 4.4 History Browser & Data Management

- **Storage Architecture**:
  - Database: `~/Library/Application Support/Glance/glance.sqlite` (SQLite 3 with Write-Ahead Logging `WAL`).
  - Snapshots: `~/Library/Application Support/Glance/snapshots/{YYYY}/{MM}/{UUID}.png`.
  - Keys: Encrypted in macOS Keychain under service `Glance`.
- **History Window (`NavigationSplitView`)**:
  - **macOS Tahoe Compatibility**: Mach-O stamped `sdk: 26.0` to render the floating translucent liquid glass sidebar.
  - **Search & Filter**: Real-time FTS5 search across all source and translated text, with segmented status filtering (`All`, `Translated`, `Failed`, `No text`, `Pending`).
  - **Detail Inspector**: Split-view with zoomable/pannable original capture on the left and full translation breakdown on the right.
  - **Bulk Deletion**: Date-range deletion sheet with live item count and storage size calculation before irreversible deletion.

---

### 4.5 Security, Code Signing & TCC Persistence

To ensure macOS **Screen Recording** (`kTCCServiceScreenCapture`) permissions are preserved across all local rebuilds and GitHub Actions releases:

1. **Permanent Signing Identity**:
   - Certificate: `certs/glance_codesign.p12` (`CN=GlanceCodeSign`).
   - Key: 2048-bit RSA key valid for 10 years (3650 days).
2. **Automated Keychain Provisioning**:
   - Handled non-interactively via [`scripts/import_cert.sh`](file:///Users/mac/Github/Glance/scripts/import_cert.sh).
   - In GitHub Actions CI runners, imports the `.p12` into a build keychain and unlocks it with `security set-key-partition-list -S apple-tool:,apple:`.
3. **Identical Designated Requirement**:
   ```
   designated => identifier "com.activebook.glance" and certificate leaf = H"8c3e9e6f50ed658e6dfc05ccf62d3797eef2691a"
   ```
   Because both local builds and CI binaries produce this exact designated requirement hash, macOS TCC recognizes all updates as the same trusted binary.

---

### 4.6 Automated CI/CD & Self-Updating Engine

- **GitHub Actions Pipeline** ([`.github/workflows/release.yml`](file:///Users/mac/Github/Glance/.github/workflows/release.yml)):
  - Triggers on every push to `main`.
  - Determines semantic version bumps (`patch`, `minor`, `major`) from conventional commits.
  - Compiles universal binary slices (`arm64` + `x86_64`).
  - Stamps target SDK `26.0` via `vtool`.
  - Codesigns with `GlanceCodeSign`.
  - Generates `Glance.zip` and `Glance.zip.sha256`.
  - Publishes GitHub Releases with release notes.
- **In-App Update Workflow** ([`UpdateManager.swift`](file:///Users/mac/Github/Glance/Sources/Glance/Models/UpdateManager.swift)):
  - Periodically queries `https://api.github.com/repos/activebook/Glance/releases/latest`.
  - Compares version numbers using strict semver component parsing.
  - Displays update pill in the menu bar popover and detailed modal sheet.
  - Downloads release `.zip` to a temporary directory, verifies SHA-256 checksum, unzips, and atomically swaps `/Applications/Glance.app` before relaunching.

---

## 5. Build, Test & Release Reference

### Local Development Commands

```bash
# Run the entire test suite (52 unit tests)
swift test --parallel

# Compile universal debug binary and launch Glance locally
bash scripts/debug.sh

# Build universal release bundle and zip package
bash scripts/release.sh

# Verify Mach-O architecture slices
lipo -info build/Glance.app/Contents/MacOS/Glance

# Verify Mach-O load command SDK header
vtool -show-build build/Glance.app/Contents/MacOS/Glance

# Inspect codesign Designated Requirement
codesign -dvvv build/Glance.app
codesign -d -r- build/Glance.app
```

---

## 6. Verification & Test Coverage Matrix

The repository contains 52 comprehensive unit tests spanning all core engines:

| Test Suite | Test Count | Key Verifications |
| :--- | :--- | :--- |
| `LLMClientTranslateTests` | 8 | Vision request construction, JSON mode toggling, Furigana directive injection, JSON parsing recovery, assistant text extraction. |
| `SettingsStoreTests` | 8 | Endpoint persistence, fallback chains, active endpoint resolution, default English target language, hotkey serialization. |
| `EndpointConfigTests` | 4 | Default Gemini configuration, base URL normalization, model validation, clone operations. |
| `UpdateManagerTests` | 4 | Semantic version comparison (patch, minor, major, multi-component). |
| `HistoryStoreTests` | 13 | SQLite persistence, FTS5 full-text indexing, status filtering, date-range batch deletion, thumbnail generation. |
| `KeychainHelperTests` | 6 | Secure password storage, overwrite, roundtrip retrieval, delete resilience. |
| `WindowDetectorTests` | 3 | Z-order window hit testing, display tag formatting, AppKit-to-CoreGraphics coordinate conversion. |
| `ImageDownscalerTests` | 2 | Budget constraints on extreme dimensions (4000px+), aspect ratio preservation. |
| `CaptureGeometryTests` | 4 | Multi-monitor display bounds intersection and DPI scaling. |

---

## 7. Future Roadmap (Post-v1.0 Enhancements)

- [ ] **Instant OCR-Only Mode**: Toggle to copy extracted text without invoking translation.
- [ ] **Pinned Region Frame**: Re-enable pinned persistent on-screen frame overlay for repeated automated captures.
- [ ] **On-Device Apple Intelligence Fallback**: Optional offline translation fallback when network connectivity is unavailable.
