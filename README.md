# Ember

Voice-to-text for macOS. Press a key, speak, get text.

Ember uses [Groq](https://groq.com) for lightning-fast speech recognition (Whisper) and grammar correction (Llama), with a plasma overlay that reacts to your voice.

## Install

### Homebrew (recommended)

```bash
brew install --cask arcimun/tap/ember
```

### Manual (DMG)

Download the latest `.dmg` from [Releases](https://github.com/arcimun/ember/releases), open it, and drag Ember to Applications.

### Build from source

```bash
git clone https://github.com/arcimun/ember.git
cd ember
bash install.sh
```

## Setup

1. Get a free API key at [console.groq.com](https://console.groq.com/keys)
2. Launch Ember — it will ask for your key on first run
3. Grant microphone access when prompted
4. (Optional) Add Ember to System Settings → Privacy → Accessibility for auto-paste

## Usage

| Key | Action |
|-----|--------|
| `` ` `` (backtick) | Start / stop recording |
| `Escape` | Cancel recording |

Ember appears in your menu bar. Press backtick anywhere to dictate — your speech is transcribed, corrected, and pasted into the active app.

## How it works

```
` pressed → recording starts → plasma overlay appears
          → voice audio → overlay reacts in real-time
` pressed → recording stops → audio sent to Groq Whisper (~0.7s)
          → raw text → Groq Llama grammar fix (~1s)
          → corrected text → clipboard + auto-paste
```

## Configuration

Config file: `~/.config/ember/config.env`

```env
GROQ_API_KEY=gsk_your_key_here
DICTATION_LANGUAGE=ru
```

Supported languages: any language supported by Whisper (en, ru, es, fr, de, zh, ja, ko, etc.)

## Requirements

- macOS 14+
- [Groq API key](https://console.groq.com/keys) (free tier available)

## License

MIT
