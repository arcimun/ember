# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Ember

macOS voice-to-text app with plasma overlay and auto-paste.

## Quick Start

```bash
# Build + install to /Applications/
bash install.sh

# After each rebuild (CDHash changes → macOS revokes permission):
tccutil reset Accessibility com.arcimun.ember
open /Applications/Ember.app
# Then re-add in System Settings → Accessibility
```

### Install Methods

```bash
# Homebrew
brew install --cask arcimun/tap/ember

# DMG
bash scripts/build-dmg.sh 1.0.0
# → dist/Ember-1.0.0.dmg

# From source
bash install.sh
```

Without Accessibility: everything works except auto-paste (Cmd+V). Use manual paste.

**Prerequisites:** Swift 6.2+ — audio recording uses native AVAudioEngine (no external dependencies).

## Architecture

Modular Swift app (6 files in `Sources/`) + WebGL2 themes.

```
Sources/
├── App.swift       — AppDelegate, menu bar, hotkeys, Sparkle, Preferences window
├── Config.swift    — Config struct, .env loading, API key dialog, history
├── Recorder.swift  — AVAudioEngine recording, RMS monitoring, WAV export
├── STT.swift       — Groq Whisper transcription (verbose_json), Groq LLM grammar correction
├── Overlay.swift   — PlasmaOverlayWindow (WebGL2 GLSL, voice-reactive)
└── History.swift   — HistoryWindowController (NSTableView, search, copy, re-paste)
```

**Pipeline:** `` ` `` → record WAV → Groq Whisper (`whisper-large-v3-turbo`, verbose_json) ~0.7s → Groq LLM (`llama-3.3-70b-versatile`) ~1s → clipboard + auto-paste

## Key Files

| File | What |
|------|------|
| `Sources/App.swift` | AppDelegate, menu bar, hotkeys, Sparkle, Preferences, theme switcher |
| `Resources/themes/*.html` | WebGL2 GLSL themes (violet-flame, aurora, nebula, solar, minimal) |
| `install.sh` | Build + sign + copy to /Applications/ |
| `scripts/build-dmg.sh` | Build + create distributable DMG |
| `Package.swift` | SPM config (macOS 13+, Sparkle dependency) |
| `.github/workflows/release.yml` | CI: build + DMG + GitHub Release on tag push |

## Config

File: `~/.config/ember/config.env`

```env
GROQ_API_KEY=gsk_...
DICTATION_LANGUAGE=ru
```

On first launch, if no API key is found, Ember shows a dialog asking for the Groq key.

API keys loaded in order from: `~/.config/ember/config.env` → `~/.openclaw/.env`. First non-empty value wins.

## Overlay API (Swift → JS)

```javascript
window.setAudioLevel(float)  // 0-1, called 30fps from Timer
window.setActive(bool)       // start/stop listening animation
window.setProcessing(bool)   // thinking state (called between STT and paste)
```

## Hotkeys

| Key | Action | Needs Accessibility |
|-----|--------|-------------------|
| `` ` `` (tilde, keycode 50) | Toggle recording | No (Carbon) |
| `Escape` (keycode 53) | Cancel recording, save partial to clipboard | No (Carbon) |
| Auto-paste (CGEvent Cmd+V) | After transcription completes | Yes |

## Auto-Update (Sparkle 2)

Ember uses [Sparkle](https://sparkle-project.org/) for automatic updates.

- Feed URL: `https://raw.githubusercontent.com/arcimun/ember/main/appcast.xml`
- Checks automatically on launch
- Menu bar → "Check for Updates..." triggers manual check
- `SUPublicEDKey` in Info.plist for EdDSA signature verification

## Distribution

### Creating a release

```bash
# Build DMG locally
bash scripts/build-dmg.sh 1.0.0

# Or push a tag → GitHub Actions builds + publishes
git tag v1.0.0
git push origin v1.0.0
```

### GitHub Actions

On tag push (`v*`), `.github/workflows/release.yml`:
1. Builds on `macos-14` runner
2. Assembles Ember.app bundle
3. Creates DMG via `create-dmg`
4. Publishes GitHub Release with DMG attached

## Known Quirks

- Audio recording uses native AVAudioEngine — no external dependencies
- Audio resampling: records at mic's native rate (48kHz), converts to 16kHz mono WAV via `afconvert` shell command (not Swift API)
- LLM hallucination guard: if corrected text >3x raw length, falls back to raw

## History

Sessions saved as JSON in `~/.config/ember/history/` (filename: `YYYY-MM-DD_HH-mm-ss.json`).

## Logs

`~/Library/Logs/Ember.log`

## Build & Test

```bash
swift build -c release    # Build
swift test                # XCTest (ConfigTests, RecorderTests)
bash install.sh           # Build + install to /Applications/
bash scripts/build-dmg.sh 1.0.0  # Create DMG
```

After each rebuild: CDHash changes → macOS revokes Accessibility permission. Run `tccutil reset Accessibility com.arcimun.ember` and re-add in System Settings.

## Release Process

`/ship` → bump VERSION → CHANGELOG → commit → push → tag → CI builds DMG + GitHub Release.

**Manual post-CI:** sign DMG (`sign_update`), update `appcast.xml` + push, update `homebrew-tap` SHA256 + push.

Key files: `VERSION` (4-digit), `CHANGELOG.md`, `appcast.xml`, `.github/workflows/release.yml`.

## Project Metadata

- Bundle ID: `com.arcimun.ember`
- Version: read from `VERSION` file
- Swift Package Manager, swift-tools-version 5.9, macOS 13+
- Ad-hoc signed (`codesign --sign -`)
- Sparkle 2 for auto-updates (EdDSA, private key in GitHub Secret `SPARKLE_PRIVATE_KEY`)
- License: MIT
- Repo: `github.com/arcimun/ember`
- Homebrew: `brew install --cask arcimun/tap/ember`
