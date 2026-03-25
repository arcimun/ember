# Ember

> Voice to text for macOS. Fast. Beautiful. Free.

![Ember Demo](docs/demo.gif)

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple) ![MIT License](https://img.shields.io/badge/license-MIT-blue) ![Homebrew](https://img.shields.io/badge/brew-arcimun%2Ftap%2Fember-orange?logo=homebrew) [![Latest Release](https://img.shields.io/github/v/release/arcimun/ember)](https://github.com/arcimun/ember/releases/latest)

---

## Why Ember?

- **~1.7s end-to-end** — Groq Whisper transcription + LLM grammar correction, faster than you can reach for the keyboard
- **Works in any app** — auto-pastes corrected text into whatever window is active
- **Beautiful overlay** — WebGL2 plasma reacts to your voice in real time, 5 themes to choose from

---

## Install

```bash
brew install --cask arcimun/tap/ember
```

**DMG** — download from [Releases](https://github.com/arcimun/ember/releases/latest), open and drag to Applications.

**Build from source** — see [Building from source](#building-from-source) below.

---

## How it works

Press `` ` `` — speak — text appears.

```
Press `  →  Recording starts  →  Plasma overlay appears
Speak    →  Overlay reacts to your voice in real time
Press `  →  Groq Whisper STT (~0.7s)  →  LLM grammar fix (~1s)  →  Auto-paste
```

---

## Themes

Switch themes from the menu bar icon. Five included:

| Theme | Vibe |
|-------|------|
| **Violet Flame** | Deep purple plasma, default |
| **Aurora** | Green-teal northern lights |
| **Nebula** | Blue-pink cosmic dust |
| **Solar** | Warm amber and gold |
| **Minimal** | Subtle white pulse, distraction-free |

<!-- Screenshots: docs/themes/ -->

---

## Configuration

Config file: `~/.config/ember/config.env`

```env
GROQ_API_KEY=gsk_your_key_here
DICTATION_LANGUAGE=en
```

Whisper supports all major languages: `en`, `ru`, `es`, `fr`, `de`, `zh`, `ja`, `ko`, and many more. Set `DICTATION_LANGUAGE` to any [Whisper-supported language code](https://platform.openai.com/docs/guides/speech-to-text/supported-languages).

---

## Hotkeys

| Key | Action |
|-----|--------|
| `` ` `` (backtick) | Start / stop recording |
| `Escape` | Cancel recording, save partial text to clipboard |
| Auto-paste (Cmd+V) | Sent automatically after transcription — requires Accessibility permission |

---

## Requirements

- macOS 13+
- [Groq API key](https://console.groq.com/keys) — free tier available, no credit card required
- Microphone permission (prompted on first use)
- Accessibility permission for auto-paste (optional — manual paste still works without it)

**First launch:** Ember will ask for your Groq key if none is found. Enter it once, and you're set.

---

## Building from source

```bash
git clone https://github.com/arcimun/ember.git
cd ember
bash install.sh
```

Requires Xcode Command Line Tools. The script builds with Swift Package Manager, signs the bundle, and copies it to `/Applications/`.

After install, reset Accessibility permission so macOS recognizes the new binary:

```bash
tccutil reset Accessibility com.arcimun.ember
```

Then re-add Ember in System Settings → Privacy & Security → Accessibility.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

---

## License

MIT — see [LICENSE](LICENSE).
