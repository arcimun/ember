# Changelog

All notable changes to Ember will be documented in this file.

## [1.7.0] - 2026-03-25

### Added
- **10 new overlay themes** — Digital Rain (Matrix), Bioluminescence (deep ocean), Geometric HUD (Iron Man), Circuit Trace (neon PCB), Pulse Rings (sonar), Liquid Chrome (metallic), Sound Terrain (3D topography), Ink Bleed (watercolor), Crystal Frost (ice), Waveform Bar (equalizer). Total: 15 themes.
- **Digital Rain as default theme** — new installs start with Matrix-style overlay
- **Adaptive display scaling** — EDGE_MIN scales to 17% of screen height (works from 13" MacBook to 4K displays)
- **Dynamic Matrix spread** — quiet speech = edges only, loud = Matrix covers the entire screen
- **3-layer parallax depth** in Digital Rain — far (tiny/dim), mid, near (large/bright) for 3D feel
- **Dark backdrop** behind theme overlay — ensures visibility on light backgrounds

### Improved
- **Smooth exit animation** — streams freeze in place and dissolve (no more "falling down" effect)
- **Processing color shift** — green → cyan/purple during "thinking" state
- **Audio sensitivity boost** (2.5x) — normal speech clearly activates the overlay
- **CI auto-update appcast.xml** — Sparkle appcast is now automatically signed and committed on every release tag, so auto-updates never go stale

### Changed
- Default theme: `violet-flame` → `digital-rain`
- Fallback theme: `violet-flame` → `digital-rain`

## [1.6.0] - 2026-03-25

### Added
- **Voice Activity Detection (VAD)** — auto-stops recording after ~0.5s of silence once speech is detected. Opt-in via Preferences checkbox "Auto-stop on silence (experimental)" or `VAD_AUTO_STOP=true` in config.env.
- **VAD config key** — `VAD_AUTO_STOP=true|false` (default: false) in `~/.config/ember/config.env`
- **VAD Preferences checkbox** — "Auto-stop on silence (experimental)" in Preferences window

### Fixed
- **Yellow flash on overlay show** — WebView is now hidden until theme HTML finishes loading, preventing flash of default white/yellow background
- Preferences window height increased to accommodate new VAD checkbox

### Blocked (infrastructure)
- **WhisperKit on-device STT** (US-001/002/003) — blocked by swift-collections incompatibility with current Swift toolchain. WhisperKit 0.17.0 depends on swift-collections 1.4.1 which fails to compile against the `Span._unsafeElements` API change. Will retry in next release when WhisperKit updates its dependencies.

## [1.4.0] - 2026-03-25

### Added — Reliability (PRD 1)
- **Error handling system** — EmberError enum with 10 typed errors, delegate-based propagation
- User-visible notifications for all 12 error paths (no more silent failures)
- Overlay error flash (red) across all 5 themes
- Microphone access check on launch with user guidance

### Added — First Impressions (PRD 2)
- Overlay celebration pulse on successful transcription across all 5 themes
- Recording timer in menu bar (elapsed time display)
- Multi-display support (overlay follows cursor screen)
- Reduce Motion accessibility (auto-switches to minimal theme)
- API key validation (gsk_ prefix check) in first-run dialog
- Value proposition text in onboarding dialog

### Added — Launch (PRD 3)
- Theme creation guide (docs/creating-themes.md)
- CONTRIBUTING.md for community contributions
- GitHub issue templates (bug, feature, theme submission)
- Launch-ready README with header image and badges

### Changed
- `afconvert` subprocess replaced with native AVAudioConverter (faster, no shell dependency)
- `usleep` replaced with `DispatchQueue.main.asyncAfter` in auto-paste (non-blocking)
- Paste logic deduplicated into `simulatePaste()` shared function
- Frontmost application check before auto-paste (prevents pasting into wrong window)
- `NSSecureTextField` in first-run API key dialog (was plain NSTextField)
- `DateFormatter` cached in log() (was recreating on every call)
- RAF animation cycle stops when overlay is hidden (battery savings)
- Skip button explains consequences ("transcription disabled")

### Fixed
- Recursive `showApiKeyDialog()` call replaced with `DispatchQueue.main.async`
- Audio write errors now caught with do/catch (was silently swallowed with try?)

## [1.2.0] - 2026-03-21

### Added
- 5 visual themes: Violet Flame, Aurora, Nebula, Solar, Minimal — all WebGL2 GLSL, voice-reactive
- Theme switcher in menu bar with checkmarks, instant reload, disabled during recording
- History window (600x500) with search, copy to clipboard, and re-paste
- Background loading with spinner for history files
- Whisper model benchmark script (`scripts/benchmark-whisper.sh`)
- XCTest foundation: ConfigTests + RecorderTests

### Changed
- Language auto-detection by default (`DICTATION_LANGUAGE=auto`)
- Whisper API switched to `verbose_json` format for detected language metadata
- LLM prompt is now language-agnostic (works for any language, not just Russian)
- `saveHistory()` now saves raw + corrected text, detected language, and duration
- `Config.save()` uses read-modify-write pattern (preserves all fields)
- Theme system: `Resources/themes/` directory, each theme = standalone HTML file
- History JSON format: `corrected` + `raw` fields (backward-compatible with old `text` format)

### Removed
- Hardcoded Russian language in LLM prompt
- Static `overlay.html` (replaced by theme system)

## [1.1.0] - 2026-03-19

### Added
- Native Preferences window (Cmd+,) with API Key and Language settings
- Language selection: Auto-detect, Russian, English, Spanish, French, German, Chinese, Japanese, Korean

### Changed
- Replaced SoX (`rec`) with native AVAudioEngine — zero external dependencies
- Refactored single-file main.swift (694 lines) into 5 modular files: App, Config, Recorder, STT, Overlay
- Encapsulated recording state in Recorder class with delegate pattern
- DRY Info.plist: single template in Resources/, used by install.sh, build-dmg.sh, and CI
- CI now auto-updates Homebrew tap on release (via HOMEBREW_TAP_TOKEN secret)
- AVAudioConverter resamples from mic native rate to 16kHz mono for Groq Whisper
- WAV writes use background DispatchQueue to avoid blocking audio thread

### Removed
- SoX dependency (`brew install sox` no longer required)

## [1.0.0] - 2026-03-18

### Added
- Groq Whisper STT (whisper-large-v3-turbo) with ~0.7s latency
- Groq Llama 3.3 70B grammar/punctuation correction
- Violet Flame plasma overlay (WebGL2 GLSL, voice-reactive)
- Global hotkey (backtick) via Carbon — no Accessibility needed
- Auto-paste (Cmd+V) with Accessibility permission
- First-run API key dialog (NSAlert)
- SF Symbol menu bar icons (mic.fill / waveform / ellipsis.circle)
- Sparkle 2 auto-update with EdDSA signing
- GitHub Actions CI/CD (tag push → DMG → GitHub Release)
- Homebrew cask (`brew install --cask arcimun/tap/ember`)
- Session history (JSON in ~/.config/ember/history/)
