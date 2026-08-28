<p align="center">
  <img src="images/AppIcon.png" width="128" height="128" alt="Glance App Icon" />
</p>

<h1 align="center">Glance</h1>

<p align="center">
  <strong>Capture anything on your screen. Understand it instantly.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2014.0%2B-000000?style=flat-square&logo=apple&logoColor=white" alt="Platform: macOS 14.0+" />
  <img src="https://img.shields.io/badge/Language-Swift%205.10-FA7343?style=flat-square&logo=swift&logoColor=white" alt="Language: Swift 5.10" />
  <img src="https://img.shields.io/badge/UI-SwiftUI%20%2F%20AppKit-0071e3?style=flat-square" alt="UI: SwiftUI / AppKit" />
  <img src="https://img.shields.io/badge/Architecture-Native%20macOS-312E81?style=flat-square" alt="Native macOS" />
  <img src="https://img.shields.io/badge/License-MIT-blue?style=flat-square" alt="License: MIT" />
</p>

---

## Overview

**Glance** is a native macOS menu bar companion for frictionless on-screen translation, OCR, and language comprehension.

Whenever you encounter foreign languages, code snippets, scanned documents, video subtitles, or unselectable text, press a global shortcut and select the area. Glance delivers accurate, context-aware translations and audio pronunciations right beside your selection.

<table width="100%">
  <tr>
    <th width="50%" align="center"><strong>List View (⌘1)</strong></th>
    <th width="50%" align="center"><strong>Gallery View (⌘2)</strong></th>
  </tr>
  <tr>
    <td align="center"><img src="images/main_window_list.png" width="100%" alt="Glance Main Window — List View" /></td>
    <td align="center"><img src="images/main_window_gallery.png" width="100%" alt="Glance Main Window — Gallery View" /></td>
  </tr>
</table>

---

## Features

### Global Shortcuts & Instant Translation

<p align="center">
  <img src="images/settings_translation.png" width="540" alt="Glance Translation & Global Shortcuts Settings" />
</p>

- **`⌥G` Capture & Translate**: Drag to select any area or click to snap to a window.
- **`⇧⌥G` Re-translate Last Area**: Instantly re-capture the previous selection without overlays — perfect for video subtitles, manga, and reading.
- **Japanese Furigana (振仮名)**: Displays phonetic reading annotations directly above Kanji in both captured and translated text, with customizable font sizing and full text selection.
- **Tailored Translation Tones**: Natural & Fluent, Bilingual Explanatory, Technical, Concise, and more.
- **Natural Voice Audio**: High-quality text-to-speech pronunciation with adjustable playback speed.

---

### Multi-Provider AI Service Presets

<p align="center">
  <img src="images/settings_ai_service.png" width="540" alt="Glance AI Service Provider Presets" />
</p>

- **1-Click Presets**: Ready to use with **OpenAI**, **Google Gemini**, **DeepSeek**, **OpenRouter**, **Ollama (Local)**, or any custom AI service.
- **Secure Keychain Storage**: API keys are encrypted and stored safely in the macOS Keychain.
- **Live Connection Testing**: Test service connectivity and response speed with a single click.

---

### Appearance & History Management

<p align="center">
  <img src="images/settings_appearance.png" width="540" alt="Glance Appearance & Customization Settings" />
</p>

- **Dual Browsing Layouts**: Instant switching between **List View (`⌘1`)** and Finder-style **Gallery View (`⌘2`)** with arrow key scrubbing (`←` / `→`).
- **Glassmorphic Themes**: Translucent Dark, Frosted Glass, Deep Obsidian, and Vibrant Acrylic with opacity controls.
- **Custom Typography**: Independent font sizing and color options for source and translated text.
- **Searchable Timeline**: Full-text SQLite (FTS5) search, status badges, and dynamic **`↑ Top`** jump navigation (`⌘↑`).

---

## Getting Started

1. **Launch**: Glance resides quietly in the macOS menu bar.
2. **Configure**: Select your AI provider under **Settings (`⌘,`) $\rightarrow$ AI Service**.
3. **Translate**: Press **`⌥G`** to capture any area, or **`⇧⌥G`** to re-translate the previous selection.
4. **Interact**: View the glass result HUD, copy segments, or listen via neural text-to-speech.

---

## License

This project is licensed under the [MIT License](LICENSE).
