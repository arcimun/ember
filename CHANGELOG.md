# Changelog

All notable changes to Ember will be documented in this file.

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
