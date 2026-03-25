# Launch Drafts — Ember

## Show HN (H3)

**Title:** Show HN: Ember – macOS voice-to-text in 1.7s (Groq Whisper + LLM, open-source)

**Text:**
Hey HN, I built Ember — a menu bar app for macOS that turns speech into text in ~1.7 seconds.

How it works: press backtick → speak → text auto-pastes into whatever app you're using. Under the hood: AVAudioEngine records audio, Groq's Whisper API transcribes it (~0.7s), then Llama 3.3 70B fixes grammar/punctuation (~1s).

A few things I'm happy with:
- Carbon hotkeys (no Accessibility permission needed for recording)
- WebGL2 plasma overlay with 5 GLSL themes that react to your voice
- Zero dependencies beyond Swift standard library + Sparkle for updates
- Works with any language Whisper supports (auto-detect or configurable)

Install: `brew install --cask arcimun/tap/ember`

Requires a free Groq API key. MIT licensed.

GitHub: https://github.com/arcimun/ember

Would love feedback — especially on the overlay themes and any edge cases with different mic setups.

---

## Reddit r/macapps (H5)

**Title:** I built a free, open-source voice-to-text app for macOS with AI grammar correction

**Text:**
Ember sits in your menu bar. Press backtick, speak, and corrected text appears in whatever app you're using. Takes about 1.7 seconds total.

Uses Groq's free Whisper API for transcription and Llama 3.3 for grammar fixing. Has a pretty cool plasma overlay that reacts to your voice with 5 different visual themes.

Free, open-source (MIT), no subscription. Just need a free Groq API key.

`brew install --cask arcimun/tap/ember`

https://github.com/arcimun/ember

---

## Reddit r/programming (H5)

**Title:** How I built sub-2s voice-to-text for macOS with Groq Whisper and zero dependencies

**Text:**
I've been building Ember, a macOS menu bar app for voice-to-text. The pipeline:

1. AVAudioEngine records at native mic rate (usually 48kHz)
2. AVAudioConverter resamples to 16kHz mono Int16 WAV in-memory
3. Groq Whisper API transcribes (~0.7s for typical utterances)
4. Llama 3.3 70B fixes grammar/punctuation (~1s)
5. CGEvent simulates Cmd+V to paste into the active app

Some interesting technical choices:
- Carbon API for global hotkeys (works without Accessibility permission)
- WebGL2 GLSL shaders for the voice-reactive overlay
- NSEvent.mouseLocation for multi-display overlay positioning

The whole app is ~1,500 lines of Swift across 6 files. No Electron, no dependencies beyond Sparkle for auto-updates.

MIT licensed: https://github.com/arcimun/ember

---

## Reddit r/commandline (H5)

**Title:** One-command voice-to-text for macOS: brew install --cask arcimun/tap/ember

Pretty simple — press backtick anywhere, speak, text appears. Uses Groq's free Whisper API. Open-source, MIT.

https://github.com/arcimun/ember

---

## ProductHunt (H4) — Tagline options

1. "Voice to text for macOS in 1.7 seconds"
2. "Press backtick, speak, text appears — in any app"
3. "Beautiful, free voice-to-text for macOS with AI grammar correction"

**First comment (maker):**
Hi! I built Ember because macOS dictation felt slow and didn't fix my grammar.

Ember sits in your menu bar. Press backtick → speak → corrected text auto-pastes wherever your cursor is. The whole thing takes about 1.7 seconds.

It uses Groq's free Whisper API for transcription and Llama 3.3 for grammar correction. There's also a WebGL2 plasma overlay with 5 visual themes that react to your voice in real-time.

Everything is open-source (MIT) and free. You just need a free Groq API key to get started.

I'd love to hear what you think — especially about the visual themes and any languages you'd like better support for.
