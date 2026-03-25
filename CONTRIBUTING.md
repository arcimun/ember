# Contributing to Ember

Ember is a small, focused macOS app — about 1500 lines of Swift across 6 files. It's easy to understand in an afternoon. Contributions are welcome.

## Quick Start

```bash
git clone https://github.com/arcimun/ember.git
cd ember
swift build -c release
bash install.sh
```

After install, macOS revokes Accessibility permission (CDHash changes on every build):

```bash
tccutil reset Accessibility com.arcimun.ember
open /Applications/Ember.app
# Re-add in System Settings → Privacy & Security → Accessibility
```

You need a Groq API key. On first launch Ember will ask for it, or set it manually:

```bash
mkdir -p ~/.config/ember
echo "GROQ_API_KEY=gsk_..." > ~/.config/ember/config.env
```

## Architecture

Six files, no magic:

| File | What it does |
|------|-------------|
| `Sources/App.swift` | AppDelegate, menu bar icon, hotkeys, Preferences window, theme switcher |
| `Sources/Config.swift` | Config struct, `.env` loading, API key dialog, history persistence |
| `Sources/Recorder.swift` | AVAudioEngine recording, RMS level monitoring, WAV export |
| `Sources/STT.swift` | Groq Whisper transcription + LLM grammar correction |
| `Sources/Overlay.swift` | PlasmaOverlayWindow — the WebGL2 animated overlay |
| `Sources/History.swift` | History window (NSTableView, search, copy, re-paste) |

Pipeline: `` ` `` → record WAV → Groq Whisper (~0.7s) → Groq LLM (~1s) → clipboard + auto-paste.

## Easiest Way to Contribute: Themes

Themes are standalone HTML files in `Resources/themes/`. Each one is a self-contained WebGL2/Canvas animation that reacts to voice input. No Swift knowledge required — just GLSL and JS.

**How themes work:**

Swift calls three JS functions on the theme's `WKWebView`:

```javascript
window.setAudioLevel(float)   // 0.0–1.0, called at 30fps while recording
window.setActive(bool)        // true = recording started, false = stopped
window.setProcessing(bool)    // true = between STT and paste (thinking state)
window.setError(bool)         // true = something went wrong
window.setCelebration()       // called on successful transcription
```

Your theme must implement all five. The existing themes are good starting points.

**Creating a new theme:**

1. Copy an existing theme: `cp Resources/themes/aurora.html Resources/themes/your-theme.html`
2. Modify the GLSL shaders and JS logic
3. Build and install: `swift build -c release && bash install.sh`
4. Switch to your theme: menu bar icon → Themes → your-theme
5. Test all states: record audio, cancel with Escape, trigger an error

The theme file name (without `.html`) becomes the display name in the menu. Use lowercase with hyphens.

## Code Contributions

Standard fork → branch → PR flow:

```bash
git checkout -b feat/your-feature
# make changes
swift build -c release    # must compile clean
swift test                # run XCTest suite
git push origin feat/your-feature
```

A few guidelines:

- **One feature per PR.** Small, focused changes get reviewed faster.
- **No new dependencies.** Ember intentionally has no package dependencies beyond Sparkle. If your feature needs a library, open an issue first.
- **Match the surrounding style.** The codebase uses `guard`/early return, `log()` for logging (not `print()`), and standard Swift conventions.
- **Test the full pipeline** before submitting — record audio, transcribe, paste. Automated tests cover config and recorder logic but not the full flow.

## Reporting Bugs

Open a [GitHub Issue](https://github.com/arcimun/ember/issues) and include:

- macOS version (`sw_vers`)
- Ember version (menu bar → About)
- Log file: `~/Library/Logs/Ember.log`
- Steps to reproduce

For crashes, the log file usually has enough context. Attach it.

## Code Style

- Swift conventions throughout — no exceptions
- `guard` for early returns, not nested `if`
- Use `log()` for all logging, not `print()`
- Avoid force-unwrap (`!`) — use `guard let` or `if let`
- Keep functions focused; the existing files average ~250 lines each

## Running Tests

```bash
swift test
```

Current coverage: `ConfigTests` (config loading, key resolution) and `RecorderTests` (WAV format, RMS calculation). If you add new logic, add a test for it.
