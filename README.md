# Ember

<p align="center">
  <img src="docs/header.png" alt="Ember — Speak. It types." width="100%">
</p>

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple) ![MIT License](https://img.shields.io/badge/license-MIT-blue) ![Homebrew](https://img.shields.io/badge/brew-arcimun%2Ftap%2Fember-orange?logo=homebrew) [![Latest Release](https://img.shields.io/github/v/release/arcimun/ember)](https://github.com/arcimun/ember/releases/latest)

---

## Why Ember?

- **Under 1 second** — Groq Whisper transcription, faster than you can reach for the keyboard
- **Works everywhere** — auto-pastes into whatever app you're using. Slack, VS Code, Notes, anything
- **Beautiful overlay** — voice-reactive animation on your screen edges. 16 themes including Digital Rain 2 with 3-layer parallax depth
- **Set your own hotkey** — backtick by default, change to any key combo in Preferences
- **Smart auto-stop** — detects when you stop speaking and transcribes automatically
- **Free forever** — open-source, MIT license, free Groq API

---

## Install

```bash
brew install --cask arcimun/tap/ember
```

**DMG** — download from [Releases](https://github.com/arcimun/ember/releases/latest), open and drag to Applications.

**Build from source** — see [below](#building-from-source).

---

## How it works

**Hold your hotkey. Speak. Release. Text appears.**

```
Hold `   →  Plasma overlay appears, reacts to your voice
Speak    →  Say anything in any language
Release  →  Groq Whisper transcribes in ~0.7s  →  Text auto-pastes
```

That's it. No window to switch to. No app to open. Just voice → text, wherever your cursor is.

---

## Features

| Feature | What it does |
|---------|-------------|
| **Instant transcription** | Groq Whisper large-v3-turbo — under 1 second |
| **Any language** | English, Russian, Spanish, Chinese, Japanese, 50+ languages |
| **Custom hotkey** | Set any key combo in Preferences (default: backtick) |
| **Voice auto-stop** | Detects silence and stops recording automatically (opt-in) |
| **16 overlay themes** | Digital Rain 2 (default), Violet Flame, Aurora, Chrome, and 12 more |
| **Error feedback** | Notifications for network issues, API errors, mic problems |
| **Multi-display** | Overlay appears on the screen where your cursor is |
| **Accessibility** | Respects Reduce Motion, VoiceOver announcements |
| **Auto-updates** | Sparkle 2 checks for updates automatically |

---

## Themes

Switch themes from the menu bar icon.

| Theme | Vibe |
|-------|------|
| **Digital Rain 2** | 3-layer parallax Matrix rain with water line, 3 color modes (emerald/ember/blue) — **default** |
| **Digital Rain** | Classic Matrix rain, edge-reactive |
| **Violet Flame** | Deep purple plasma |
| **Aurora** | Green-teal northern lights |
| **Nebula** | Blue-pink cosmic dust |
| **Solar** | Warm amber and gold |
| **Liquid Chrome** | Metallic mercury flow |
| **Bioluminescence** | Deep-sea glow |
| **Circuit** | PCB trace patterns |
| **Crystal Frost** | Ice crystal formations |
| **HUD** | Sci-fi heads-up display |
| **Ink Bleed** | Watercolor ink spread |
| **Pulse Rings** | Concentric audio rings |
| **Sound Terrain** | Audio-reactive landscape |
| **Waveform** | Classic audio waveform |
| **Minimal** | Subtle white pulse, distraction-free |

Want to create your own? See [Creating Themes](docs/creating-themes.md).

---

## Configuration

Config file: `~/.config/ember/config.env`

```env
GROQ_API_KEY=gsk_your_key_here
DICTATION_LANGUAGE=auto
THEME=digital-rain-2
LLM_CORRECTION=never
VAD_AUTO_STOP=false
```

| Option | Values | Default | What |
|--------|--------|---------|------|
| `GROQ_API_KEY` | `gsk_...` | — | Your free Groq API key |
| `DICTATION_LANGUAGE` | `auto`, `en`, `ru`, `es`, etc. | `auto` | Language for transcription |
| `THEME` | theme name | `digital-rain-2` | Overlay theme (see Themes section) |
| `LLM_CORRECTION` | `never`, `auto`, `always` | `never` | Grammar correction via LLM (adds ~1s) |
| `VAD_AUTO_STOP` | `true`, `false` | `false` | Auto-stop recording on silence |

All settings are also available in **Preferences** (menu bar → Preferences).

---

## Hotkeys

| Key | Action |
|-----|--------|
| Backtick `` ` `` (default) | Start / stop recording — customizable in Preferences |
| `Escape` | Cancel recording, save partial text to clipboard |
| Auto-paste (Cmd+V) | Sent automatically after transcription |

**Custom hotkeys:** Open Preferences → set any key or key combo for recording and cancel.

Accessibility permission is needed only for auto-paste. Without it, everything works — just paste manually with Cmd+V.

---

## Requirements

- macOS 13+ (Apple Silicon or Intel)
- [Free Groq API key](https://console.groq.com/keys) — no credit card needed
- Microphone permission (prompted on first use)
- Accessibility permission for auto-paste (optional)

---

## Building from source

```bash
git clone https://github.com/arcimun/ember.git
cd ember
swift build -c release
bash install.sh
```

After install, reset Accessibility so macOS recognizes the new binary:

```bash
tccutil reset Accessibility com.arcimun.ember
```

Then re-add Ember in System Settings → Privacy & Security → Accessibility.

---

## Contributing

Ember is ~1,800 lines of Swift across 6 files. The easiest way to contribute is [creating a theme](docs/creating-themes.md) — each theme is a standalone HTML file with WebGL2 shaders.

See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

---

## License

MIT — see [LICENSE](LICENSE).
