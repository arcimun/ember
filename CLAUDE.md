# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

macOS voice-to-text app: global hotkey → record → Groq Whisper STT → Groq LLM grammar fix → auto-paste. Menu bar only (LSUIElement), no dock icon. Plasma/orb overlay reacts to voice in real-time.

## Build & Run

```bash
# Build only (dev cycle)
swift build -c release

# Build + install to /Applications/ + sign ad-hoc
bash install.sh

# After each rebuild (CDHash changes → macOS revokes permission):
tccutil reset Accessibility com.arcimun.dictation-service
open /Applications/DictationService.app
# Then re-add in System Settings → Accessibility
```

Without Accessibility: everything works except auto-paste (Cmd+V). Use manual paste.

**Prerequisites:** SoX (`brew install sox`) — `rec` binary used for audio recording and RMS monitoring.

## Architecture

Single-file Swift app (`Sources/main.swift`, ~690 lines) + HTML overlay files.

```
main.swift (everything)
├── Config          — loads .env from 3 paths (config.env, .openclaw, arcimun-voice)
├── PlasmaOverlayWindow — fullscreen transparent WKWebView, loads HTML themes
├── startRecording()    — SoX `rec` → WAV file + parallel RMS monitor → JS audio levels
├── stopRecording()     — kill rec → Groq Whisper STT → Groq LLM fix → clipboard + Cmd+V
├── cancelRecording()   — kill rec, save partial to clipboard
├── Carbon hotkeys      — RegisterEventHotKey (tilde=toggle, escape=cancel)
├── NSEvent fallback    — if Carbon registration fails
└── AppDelegate         — menu bar, theme switching, history
```

**Pipeline:** `` ` `` → record WAV → Groq Whisper (`whisper-large-v3-turbo`) ~0.7s → Groq LLM (`llama-3.3-70b-versatile`) ~1s → clipboard + auto-paste

## Key Files

| File | What |
|------|------|
| `Sources/main.swift` | Entire app: delegate, overlay, recording, STT, LLM, hotkeys |
| `Resources/overlay.html` | Violet Flame theme — WebGL2 GLSL fragment shader |
| `Resources/overlay-orb.html` | Arcimun Orb — Three.js CymaticSphere (10K particles, plasma) |
| `install.sh` | Build + sign + copy to /Applications/ |
| `Package.swift` | SPM config (macOS 13+, only `overlay.html` in resources) |

**Note:** `overlay-orb.html` is NOT in Package.swift resources — it's loaded from `~/Dev/dictation-service/Resources/` at runtime via fallback path. Same for `overlay.html` when running from Xcode/SPM (Bundle.main fallback).

## Config

File: `~/.config/dictation-service/config.env`

```env
DICTATION_LANGUAGE=ru
GROQ_API_KEY=gsk_...
DEEPGRAM_API_KEY=...   # legacy key name, still loaded but STT uses Groq now
```

API keys loaded in order from: `config.env` → `~/.openclaw/.env` → `~/Dev/arcimun-voice/.env`. First non-empty value wins.

## Overlay API (Swift → JS)

```javascript
window.setAudioLevel(float)  // 0-1, called 30fps from Timer
window.setActive(bool)       // start/stop listening animation
window.setProcessing(bool)   // thinking state (called between STT and paste)
window.setState(string)      // "idle"/"listening"/"thinking"/"speaking" (orb only)
window.toggleGui()           // show/hide lil-gui settings panel (orb only)
```

## Hotkeys

| Key | Action | Needs Accessibility |
|-----|--------|-------------------|
| `` ` `` (tilde, keycode 50) | Toggle recording | No (Carbon) |
| `Escape` (keycode 53) | Cancel recording, save partial to clipboard | No (Carbon) |
| Auto-paste (CGEvent Cmd+V) | After transcription completes | Yes |

## Themes

Switch via menu bar → Theme. Two actually implemented:

| Theme | File | Behavior |
|-------|------|----------|
| Violet Flame | `overlay.html` | GLSL shader on screen edges, appears/disappears with recording |
| Arcimun Orb | `overlay-orb.html` | 3D sphere always visible, state-driven (idle/listening/thinking) |

"Neon Circuit" and "Minimal" are in the menu but not implemented — they load `overlay.html` as fallback.

## Known Quirks

- `saveHistory()` writes `"provider": "deepgram-nova-3"` but actual provider is Groq Whisper — hardcoded string not updated
- Audio recording uses `/opt/homebrew/bin/rec` (hardcoded Homebrew ARM path)
- LLM hallucination guard: if corrected text >3x raw length, falls back to raw
- Menu bar shows "Neon Circuit" and "Minimal" themes that don't have dedicated HTML files

## History

Sessions saved as JSON in `~/.config/dictation-service/history/` (filename: `YYYY-MM-DD_HH-mm-ss.json`).

## Logs

`~/Library/Logs/DictationService.log`

## Project Metadata

- Bundle ID: `com.arcimun.dictation-service`
- Swift Package Manager, swift-tools-version 5.9, macOS 13+
- Ad-hoc signed (`codesign --sign -`)
- CymaticSphere orb converted from `/Users/ihyart/Dev/arcimun-voice-web/app/CymaticSphere.tsx`
