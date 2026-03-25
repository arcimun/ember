# Changelog

All notable changes to Ember will be documented in this file.

## [1.3.0] - 2026-03-25

### Added
- **Error handling system** — EmberError enum with 10 typed errors, delegate-based propagation
- User-visible notifications for all 12 error paths (no more silent failures)
- Overlay error flash (red) across all 5 themes
- Overlay celebration pulse on successful transcription across all 5 themes
- Recording timer in menu bar (elapsed time display)
- Microphone access check on launch with user guidance
- Multi-display support (overlay follows cursor screen)
- Reduce Motion accessibility (auto-switches to minimal theme)
- API key validation (gsk_ prefix check) in first-run dialog
- Value proposition text in onboarding dialog
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
