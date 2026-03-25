# Creating Ember Themes

Ember themes are standalone HTML files that render voice-reactive visuals along the screen edges using WebGL2. They live in `Resources/themes/` and are selectable from the menu bar.

---

## Overview

Each theme is a single `.html` file loaded into a transparent, click-through overlay window that covers the entire screen. Your job is to draw something beautiful on the edges and stay invisible in the center — the user needs to see their work.

Ember calls five JavaScript functions on the `window` object as recording state changes. Your theme must implement all five.

---

## Quick Start

Copy `minimal.html` and rename it:

```bash
cp Resources/themes/minimal.html Resources/themes/my-theme.html
```

Open the file, change the comment at the top, edit the fragment shader colors and math, then build and install:

```bash
swift build -c release && bash install.sh
```

Ember picks up the new file automatically on next launch. Select it from menu bar → Themes.

---

## Required JS API

Ember calls these five functions. All must exist on `window` — Ember does not check for their presence, missing functions will crash the overlay silently.

### `window.setAudioLevel(level: float)`

Called at ~30fps while recording is active. `level` is the RMS amplitude from the microphone, normalized to 0–1. 0 is silence, 1 is peak input.

Use this to drive pulse intensity, glow width, flame height, or any other audio-reactive visual.

```javascript
window.setAudioLevel = (v) => { audioLevel = v; };
```

Inside the render loop, smooth it to avoid jitter:

```javascript
smoothAudio = audioLevel > smoothAudio
  ? smoothAudio * 0.3 + audioLevel * 0.7   // fast attack
  : smoothAudio * 0.93 + audioLevel * 0.07; // slow decay
```

Then pass to the shader as a uniform:

```javascript
gl.uniform1f(uAudio, Math.min(smoothAudio * 3, 0.8)); // cap at 0.8 — avoid whitewash
```

### `window.setActive(on: bool)`

Called when recording starts (`true`) or stops (`false`). Drive your fade-in / fade-out here. Also reset `smoothAudio` on deactivation so residual audio does not linger visually.

```javascript
window.setActive = (on) => {
  active = on;
  if (!on) { smoothAudio = 0; }
  else { ensureRafRunning(); }
};
```

The `ensureRafRunning()` pattern matters: stop `requestAnimationFrame` when `fadeProgress` reaches zero, and restart it here. This saves GPU cycles and battery when Ember is idle.

### `window.setProcessing(on: bool)`

Called after Whisper finishes and the LLM correction pass begins. Typically ~1 second. Conventionally shown as a warm color shift — violet-flame shifts to orange, minimal shifts to soft blue.

```javascript
window.setProcessing = (on) => { processing = on; if (on) ensureRafRunning(); };
```

In GLSL, blend between two color palettes using a `uProcessing` uniform:

```glsl
uniform float uProcessing;  // 0.0 = listening, 1.0 = processing

vec3 listeningColor = vec3(0.35, 0.12, 0.55); // violet
vec3 processingColor = vec3(0.55, 0.22, 0.06); // orange
vec3 color = mix(listeningColor, processingColor, uProcessing);
```

Smooth the transition on the JS side:

```javascript
smoothProcessing += ((processing ? 1.0 : 0.0) - smoothProcessing) * 0.05;
gl.uniform1f(uProc, smoothProcessing);
```

### `window.setError(on: bool)`

Called when transcription fails. The standard implementation adds a CSS overlay div with a red border that auto-removes after 800ms. You do not need to touch the WebGL canvas for this — a DOM overlay is simpler and more reliable.

```javascript
window.setError = (on) => {
  if (on) {
    const overlay = document.createElement('div');
    overlay.style.cssText = 'position:fixed;inset:0;pointer-events:none;' +
      'border:6px solid rgba(255,60,60,0.85);' +
      'box-shadow:inset 0 0 60px rgba(255,0,0,0.4);' +
      'transition:opacity 0.2s;z-index:9999;';
    document.body.appendChild(overlay);
    setTimeout(() => { if (overlay.parentNode) overlay.parentNode.removeChild(overlay); }, 800);
  }
};
```

### `window.setCelebration()`

Called on successful transcription + paste. A quick bright flash — in and out in ~600ms total. Like `setError`, a DOM overlay handles this cleanly. The color should match your theme's palette.

```javascript
window.setCelebration = () => {
  ensureRafRunning();
  const el = document.createElement('div');
  el.style.cssText = 'position:fixed;inset:0;pointer-events:none;z-index:9998;' +
    'border:4px solid rgba(180,120,255,0.0);' +
    'box-shadow:inset 0 0 80px rgba(160,80,255,0.0);transition:none;';
  document.body.appendChild(el);
  requestAnimationFrame(() => {
    el.style.transition = 'border-color 0.08s ease-out, box-shadow 0.08s ease-out';
    el.style.borderColor = 'rgba(220,180,255,0.9)';
    el.style.boxShadow = 'inset 0 0 100px rgba(180,100,255,0.55)';
    setTimeout(() => {
      el.style.transition = 'border-color 0.45s ease-in, box-shadow 0.45s ease-in';
      el.style.borderColor = 'rgba(180,120,255,0.0)';
      el.style.boxShadow = 'inset 0 0 80px rgba(160,80,255,0.0)';
      setTimeout(() => { if (el.parentNode) el.parentNode.removeChild(el); }, 500);
    }, 120);
  });
};
```

---

## Design Guidelines

### Transparent background — non-negotiable

```css
html, body { background: transparent !important; }
canvas { background: transparent !important; }
```

The overlay window is transparent. If you set any background color, it will paint a solid rectangle over the user's screen.

WebGL context must be created with `alpha: true, premultipliedAlpha: false`:

```javascript
const gl = canvas.getContext('webgl2', {
  alpha: true,
  premultipliedAlpha: false,
  antialias: true
});
```

Enable alpha blending so semi-transparent pixels composite correctly:

```javascript
gl.enable(gl.BLEND);
gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
```

Always clear to fully transparent before each frame:

```javascript
gl.clearColor(0, 0, 0, 0);
gl.clear(gl.COLOR_BUFFER_BIT);
```

### Render on edges only — leave the center clear

The user is dictating while looking at their screen. Anything drawn in the center blocks their work.

The standard pattern uses the distance from the nearest edge (`dEdge`) to confine the visual:

```glsl
float dT = vUv.y;          // distance from top
float dB = 1.0 - vUv.y;   // distance from bottom
float dL = vUv.x;          // distance from left
float dR = 1.0 - vUv.x;   // distance from right
float dEdge = min(min(dT, dB), min(dL, dR));

// Only render within `depth` of any edge
float depth = 0.07 + uAudio * 0.05;  // 7-12% of screen
float glow = 1.0 - smoothstep(0.0, depth, dEdge);
```

Minimal uses `depth = 0.025` (hairline). Violet-flame uses `0.07`. Do not exceed ~15% — anything larger starts covering window title bars and content.

The final alpha must go to zero before the center. Use `smoothstep` for a natural falloff:

```glsl
alpha *= smoothstep(depth * 1.8, depth * 0.2, dEdge);
```

### Use `fadeProgress` for smooth transitions

`fadeProgress` is a 0–1 float that drives fade-in and fade-out. Hard-code the rates:

- Fade in: `+= 0.06` per frame (~0.5s at 60fps)
- Fade out: `-= 0.02` per frame (~1.5s at 60fps)

```javascript
if (active && fadeProgress < 1) fadeProgress = Math.min(1, fadeProgress + 0.06);
if (!active && fadeProgress > 0) fadeProgress = Math.max(0, fadeProgress - 0.02);
```

Pass it to the shader as `uFade` and multiply it into the final alpha:

```glsl
float alpha = glow * breath * uFade;
```

This means the overlay appears quickly when you start speaking and fades out slowly when you stop — which feels natural.

### Stop the render loop when invisible

When `fadeProgress` reaches zero and `active` is false, cancel `requestAnimationFrame`:

```javascript
} else if (!active) {
  cancelAnimationFrame(rafHandle);
  rafHandle = null;
}
```

Restart it whenever something needs to be shown:

```javascript
function ensureRafRunning() {
  if (rafHandle === null) render();
}
```

Call `ensureRafRunning()` from `setActive(true)`, `setProcessing(true)`, and `setCelebration()`. This pattern keeps GPU usage at zero when Ember is idle.

### HiDPI / Retina

Always account for device pixel ratio:

```javascript
function resize() {
  const dpr = window.devicePixelRatio || 2;
  W = window.innerWidth; H = window.innerHeight;
  canvas.width = W * dpr; canvas.height = H * dpr;
  canvas.style.width = W + 'px'; canvas.style.height = H + 'px';
  gl.viewport(0, 0, canvas.width, canvas.height);
}
resize();
window.onresize = resize;
```

Pass `canvas.width` / `canvas.height` (physical pixels) to your shader as `uRes`, not `W` / `H`.

---

## GLSL Tips

### Simplex noise

The organic, non-repeating look in violet-flame and aurora comes from 3D simplex noise. Paste the full `snoise(vec3)` implementation from any existing theme — it is self-contained and has no dependencies.

Call it with different scales and time offsets to get multiple octaves:

```glsl
float n1 = snoise(vec3(uv * 4.0, uTime * 0.6)) * 0.5 + 0.5;
float n2 = snoise(vec3(uv * 8.0, uTime * 1.0 + 5.0)) * 0.5 + 0.5;
float n3 = snoise(vec3(uv * 16.0, uTime * 1.5 + 10.0)) * 0.5 + 0.5;
float noise = n1 * 0.6 + n2 * 0.3 + n3 * 0.1;
```

Higher UV scale = finer detail. Higher time scale = faster animation. Mix octaves to control the look.

### Time-based animation

`uTime` is `performance.now() / 1000` (seconds since page load). Use it for:

- Breathing: `0.85 + 0.15 * sin(uTime * 0.4)` — slow, ~15-second cycle
- Pulse: `0.9 + 0.1 * sin(uTime * 1.5)` — faster, ~4-second cycle
- Noise scrolling: feed `uTime * speed` as the Z component of `snoise(vec3)`

### Audio reactivity

`uAudio` arrives capped at 0.8 and pre-smoothed. Common patterns:

```glsl
// Widen the effect when speaking
float depth = 0.07 + uAudio * 0.05;

// Boost brightness
flame *= (0.8 + uAudio * 0.4);

// Scale noise amplitude
float waveBoost = 1.0 + uAudio * 2.0;
float n2 = snoise(...) * waveBoost;
```

Avoid multiplicative factors above ~3x — the visual can become overwhelming during loud speech.

### Color gradients from intensity

Map `flame` (0–1) to a color gradient using nested `mix()` calls:

```glsl
vec3 dark   = vec3(0.12, 0.04, 0.25);
vec3 mid    = vec3(0.35, 0.12, 0.55);
vec3 bright = vec3(0.70, 0.38, 0.80);
vec3 peak   = vec3(0.80, 0.55, 0.90);

vec3 color;
float t = flame;
if (t < 0.3) {
  color = mix(dark, mid, t / 0.3);
} else if (t < 0.7) {
  color = mix(mid, bright, (t - 0.3) / 0.4);
} else {
  color = mix(bright, peak, (t - 0.7) / 0.3);
}
```

For pre-multiplied alpha output (required for correct transparency):

```glsl
fragColor = vec4(color * alpha, alpha);
```

Do not write `vec4(color, alpha)` — that causes bright halos on dark backgrounds.

### Aspect-correct noise coordinates

Noise looks distorted on non-square screens without aspect correction. Fix it:

```glsl
vec2 aspect = vec2(uRes.x / uRes.y, 1.0);
vec2 noiseCoord = vUv * aspect;
float n = snoise(vec3(noiseCoord * scale, uTime));
```

---

## Minimal Theme Walkthrough

`minimal.html` is the reference implementation — no noise, no octaves, just math. Here is the structure annotated:

```html
<!DOCTYPE html>
<html><head><meta charset="utf-8">
<style>
* { margin: 0; padding: 0; }
html, body { width: 100%; height: 100%; overflow: hidden; background: transparent !important; }
canvas { position: fixed; top: 0; left: 0; background: transparent !important; }
</style>
</head><body>
<canvas id="gl"></canvas>
<script>
```

**State variables** — everything Ember can change lives here at module scope:

```javascript
let W, H, audioLevel = 0, smoothAudio = 0, active = false, fadeProgress = 0, processing = false;
```

**Vertex shader** — a full-screen quad, passes UV coordinates to the fragment shader:

```glsl
#version 300 es
in vec2 a_pos;
out vec2 vUv;
void main() { vUv = a_pos * 0.5 + 0.5; gl_Position = vec4(a_pos, 0, 1); }
```

**Fragment shader** — four uniforms drive the entire visual:
- `uTime` — animation clock
- `uAudio` — smoothed mic level
- `uFade` — opacity envelope
- `uProcessing` — 0 or 1 for color shift

The shader computes `dEdge`, applies a `smoothstep` glow, multiplies by audio intensity, and outputs pre-multiplied RGBA.

**Full-screen quad geometry** — two triangles covering clip space:

```javascript
gl.bufferData(gl.ARRAY_BUFFER,
  new Float32Array([-1,-1, 1,-1, -1,1, 1,1]),
  gl.STATIC_DRAW);
gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
```

**Render loop** — smooths audio, advances fadeProgress, stops RAF when fully faded:

```javascript
function render() {
  rafHandle = requestAnimationFrame(render);
  // ... smooth, advance fade, draw ...
  if (fadeProgress <= 0.01 && !active) {
    cancelAnimationFrame(rafHandle);
    rafHandle = null;
  }
}
```

**Error and celebration** — CSS overlay divs, not WebGL. Simpler, no shader changes needed:

```javascript
window.setError = (on) => {
  if (on) {
    const overlay = document.createElement('div');
    overlay.style.cssText = '...red border...';
    document.body.appendChild(overlay);
    setTimeout(() => overlay.remove(), 800);
  }
};
```

---

## Submitting Your Theme

**Pull request** — the preferred path:

1. Fork the repo
2. Drop your `.html` file into `Resources/themes/`
3. Test on at least one screen resolution (Retina required)
4. Open a PR with a short description of the visual concept and a screenshot or screen recording

**Theme Submission issue** — if you want feedback before writing code, open a GitHub issue with the label `theme-submission` and describe the concept. Include color palette and what the audio reactivity should feel like.

**Naming** — use lowercase kebab-case: `aurora-borealis.html`, `deep-ocean.html`. Single word is fine: `ember.html`.

**What makes a good theme:**
- Clear visual identity — one color story, not a rainbow
- Readable center at all audio levels — test by shouting
- Reasonable GPU cost — check Activity Monitor's GPU History panel while speaking
- All five API functions implemented correctly

**What gets rejected:**
- Covers more than ~15% of screen height/width at normal audio levels
- Non-transparent background
- Missing any of the five API functions
- Breaks on Retina displays (canvas width/height not scaled by `devicePixelRatio`)
