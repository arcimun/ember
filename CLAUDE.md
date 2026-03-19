# CLAUDE.md — Ember

macOS voice-to-text app with plasma overlay and auto-paste. Version 1.0.0.

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

**Prerequisites:** None — audio recording uses native AVAudioEngine (no external dependencies).

## Architecture

Modular Swift app (5 files in `Sources/`) + HTML overlay.

```
Sources/
├── App.swift       — AppDelegate, menu bar, hotkeys, Sparkle, Preferences window
├── Config.swift    — Config struct, .env loading, API key dialog, history
├── Recorder.swift  — AVAudioEngine recording, RMS monitoring, WAV export
├── STT.swift       — Groq Whisper transcription, Groq LLM grammar correction
└── Overlay.swift   — PlasmaOverlayWindow (WebGL2 GLSL, voice-reactive)
```

**Pipeline:** `` ` `` → record WAV → Groq Whisper (`whisper-large-v3-turbo`) ~0.7s → Groq LLM (`llama-3.3-70b-versatile`) ~1s → clipboard + auto-paste

## Key Files

| File | What |
|------|------|
| `Sources/main.swift` | Entire app: delegate, overlay, recording, STT, LLM, hotkeys, Sparkle |
| `Resources/overlay.html` | Violet Flame theme — WebGL2 GLSL fragment shader |
| `install.sh` | Build + sign + copy to /Applications/ |
| `scripts/build-dmg.sh` | Build + create distributable DMG |
| `Package.swift` | SPM config (macOS 14+, Sparkle dependency) |
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
- AVAudioConverter resamples from mic's native rate (usually 48kHz) to 16kHz mono for Groq Whisper
- LLM hallucination guard: if corrected text >3x raw length, falls back to raw

## History

Sessions saved as JSON in `~/.config/ember/history/` (filename: `YYYY-MM-DD_HH-mm-ss.json`).

## Logs

`~/Library/Logs/Ember.log`

## Build & Test

```bash
# Build
swift build -c release

# Install locally
bash install.sh

# Create DMG
bash scripts/build-dmg.sh 1.0.0

# Manual test checklist (no automated tests — Swift single-file app)
# 1. Launch: open /Applications/Ember.app
# 2. Hotkey: press ` — recording starts, menu bar shows waveform
# 3. Speak, press ` — processing (ellipsis.circle), then auto-paste
# 4. Escape during recording — cancel, text saved to clipboard
# 5. No API key: first-run dialog appears
```

## Release Process

gstack `/ship` workflow adapted for Ember:

```
/ship → bump VERSION → CHANGELOG entry → commit → push → tag
     → GitHub Actions builds DMG → GitHub Release created
     → manual: sign_update DMG → update appcast.xml → push
     → manual: update homebrew-tap SHA256 → push
```

Step-by-step:
1. `/ship` bumps `VERSION`, appends to `CHANGELOG.md`, commits, pushes
2. Create tag: `git tag v$(cat VERSION | tr -d '[:space:]' | sed 's/\.[0-9]*$//')` → push tag
3. CI builds DMG and publishes GitHub Release automatically
4. Sign new DMG: `.build/artifacts/sparkle/Sparkle/bin/sign_update dist/Ember-X.Y.Z.dmg`
5. Update `appcast.xml` with new version entry + EdDSA signature → push
6. Update `Casks/ember.rb` in `arcimun/homebrew-tap` with new SHA256 → push

Key files for release:
- `VERSION` — 4-digit (MAJOR.MINOR.PATCH.MICRO), bumped by `/ship`
- `CHANGELOG.md` — appended by `/ship`
- `appcast.xml` — Sparkle update feed (manual after CI)
- `.github/workflows/release.yml` — CI trigger on `v*` tags

## Project Metadata

- Bundle ID: `com.arcimun.ember`
- Version: read from `VERSION` file
- Swift Package Manager, swift-tools-version 5.9, macOS 14+
- Ad-hoc signed (`codesign --sign -`)
- Sparkle 2 for auto-updates (EdDSA, private key in GitHub Secret `SPARKLE_PRIVATE_KEY`)
- License: MIT
- Repo: `github.com/arcimun/ember`
- Homebrew: `brew install --cask arcimun/tap/ember`
