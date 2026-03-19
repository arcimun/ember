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

**Prerequisites:** SoX (`brew install sox`) — `rec` binary used for audio recording and RMS monitoring.

## Architecture

Single-file Swift app (`Sources/main.swift`) + HTML overlay.

```
main.swift (everything)
├── Config              — loads .env (config.env, .openclaw, arcimun-voice)
├── PlasmaOverlayWindow — fullscreen transparent WKWebView, loads overlay.html
├── startRecording()    — SoX `rec` → WAV file + parallel RMS monitor → JS audio levels
├── stopRecording()     — kill rec → Groq Whisper STT → Groq LLM fix → clipboard + Cmd+V
├── cancelRecording()   — kill rec, save partial to clipboard
├── Carbon hotkeys      — RegisterEventHotKey (tilde=toggle, escape=cancel)
├── NSEvent fallback    — if Carbon registration fails
├── Sparkle updater     — SUUpdater via SPM, checks appcast.xml
└── AppDelegate         — menu bar (SF Symbols), first-run API key dialog, history
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

- Audio recording uses SoX `rec` — auto-detected via `/opt/homebrew/bin/rec`, `/usr/local/bin/rec`, or `which rec`
- LLM hallucination guard: if corrected text >3x raw length, falls back to raw

## History

Sessions saved as JSON in `~/.config/ember/history/` (filename: `YYYY-MM-DD_HH-mm-ss.json`).

## Logs

`~/Library/Logs/Ember.log`

## Project Metadata

- Bundle ID: `com.arcimun.ember`
- Version: 1.0.0
- Swift Package Manager, swift-tools-version 5.9, macOS 14+
- Ad-hoc signed (`codesign --sign -`)
- Sparkle 2 for auto-updates
- License: MIT
- Repo: `github.com/arcimun/ember`
