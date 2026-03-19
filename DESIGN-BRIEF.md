# Design Brief: Dictation Service — Plasma Listening Interface

## Vision

Когда пользователь нажимает тильду — экран **оживает**. Как если бы невидимая сущность проснулась и начала слушать. Тонкие языки плазменного пламени охватывают края экрана, реагируя на голос — пульсируя, колеблясь, усиливаясь при громкой речи и затихая при паузах. Это не индикатор записи — это **живой интерфейс**, который дышит вместе с говорящим.

Вдохновение: **Saint Germain's Violet Flame** — фиолетовое пламя трансмутации, превращающее одну форму энергии в другую. Голос → Текст = трансмутация.

## Design Principles

### 1. Живое, не механическое
- Никаких progress bars, spinner dots, loading circles
- Органическое движение: как пламя, как дыхание, как плазма
- Каждый момент визуально уникален (procedural animation)

### 2. Присутствие, не отвлечение
- Overlay НЕ блокирует работу (click-through)
- Видно периферийным зрением — не нужно фокусироваться
- Достаточно заметно на 24" мониторе (текущие 4px — слишком мало)

### 3. Реактивность к голосу
- Amplitude → интенсивность свечения + размах "языков пламени"
- Тишина → пламя тлеет (тонкое, спокойное свечение)
- Голос → пламя разгорается (шире, ярче, динамичнее)
- Громкий голос → вспышки, расширение, более интенсивные цвета

### 4. Трансмутация (Violet Flame)
- Начало записи: пламя вспыхивает из ничего (fade from transparent)
- Во время записи: пламя живёт, дышит, реагирует
- Конец записи: пламя собирается → сжимается → исчезает (как трансмутация завершена)

## Color Palette

### Primary Theme: "Violet Flame" (default)
Инспирирован Saint Germain's Violet Flame — огонь трансмутации.

| Role | Color | Hex | Description |
|------|-------|-----|-------------|
| **Core Violet** | Deep Amethyst | `#7B2FBE` | Основной цвет пламени — глубокий фиолетовый |
| **Hot Violet** | Electric Purple | `#9B59F0` | Яркие вспышки при громком голосе |
| **Inner Gold** | Sacred Gold | `#F0A830` | Сердце пламени — золотой огонь |
| **Flame Orange** | Agni Orange | `#E87D2F` | Кончики пламени — тёплый оранжевый |
| **Deep Night** | Arabian Night | `#1A0A2E` | Фон свечения — глубокая ночь |
| **Glow Cyan** | Ethereal Blue | `#4ECDC4` | Холодные акценты — контраст |

### Gradient Flow (анимированный)
```
Gold Core (#F0A830) → Agni Orange (#E87D2F) → Deep Violet (#7B2FBE) → Hot Violet (#9B59F0) → Transparent
```

Градиент движется от края экрана внутрь. Золотое ядро у самого края, переходит в оранжевый, затем в фиолетовый, и растворяется в прозрачность.

### Alternative Themes (future)
- **Ice** — бело-голубой, ледяной, как Frozen
- **Ember** — красно-оранжевый, как тлеющие угли
- **Forest** — зелёно-золотой, как северное сияние
- **Void** — чёрно-белый, минималистичный

## Overlay Architecture

### Edge Flames (основной эффект)
- **Ширина зоны**: 40-80px от края экрана (не 4px как сейчас)
- **4 стороны**: top, bottom, left, right — но с разной интенсивностью
- **Нижний край** — самый яркий (основной фокус внимания)
- **Боковые** — средние
- **Верхний** — самый тонкий (не отвлекает от menu bar)

### Flame Animation
- **Базовый ритм**: синусоидальное "дыхание" opacity (0.3 → 0.7 → 0.3) каждые 3-4 секунды
- **Voice-reactive**: amplitude audio → множитель opacity + расширение gradient
- **Procedural noise**: Perlin/Simplex шум для "языков пламени" — каждый кадр уникален
- **FPS**: 30-60fps (CADisplayLink вместо Timer)

### Mesh/Grid Effect (advanced, optional)
- Тонкая сетка (mesh) поверх gradient — как "плазменный шар"
- Сетка деформируется от audio amplitude
- Создаёт эффект "силового поля" вокруг экрана

### Implementation Options

| Approach | Complexity | Quality | Performance |
|----------|-----------|---------|-------------|
| **CAGradientLayer + CABasicAnimation** | Low | Medium | Excellent |
| **Core Image (CIFilter) + Metal** | Medium | High | Good |
| **Metal Shader (custom fragment)** | High | Excellent | Excellent |
| **SceneKit + particle system** | Medium | High | Good |

**Recommended**: Start with CAGradientLayer (current approach but wider + more layers), add CIGaussianBlur for glow effect. Upgrade to Metal shader later for procedural flame.

## Menu Bar

### Status Icon
- **Idle**: 🎤 (current) → upgrade to custom SF Symbol or icon
- **Recording**: Animated icon — pulsing dot or waveform
- **Processing**: Spinning indicator

### Menu Items
```
─────────────────────────
🎤 Start Recording (`)
─────────────────────────
Mode: Silent ▸
  ◉ Silent (clipboard only)
  ○ Live (type in field)
─────────────────────────
Theme: Violet Flame ▸
  ◉ Violet Flame
  ○ Ice
  ○ Ember
─────────────────────────
History...          ⌘H
─────────────────────────
Quit                ⌘Q
─────────────────────────
```

## Interaction Design

### Recording Flow
```
IDLE          →  ` pressed   →  LISTENING         →  ` pressed   →  PROCESSING      →  DONE
(🎤 in bar)      (instant)      (overlay flames)      (instant)      (overlay fades)     (📋 clipboard)
                                 (voice reactive)                     (LLM corrects)      (Cmd+V to paste)
```

### Cancel Flow
```
LISTENING  →  Escape  →  CANCELLED
(flames)      (instant)   (flames dissolve)
                          (text in clipboard)
                          (nothing typed)
```

### Visual States
1. **Fade In** (200ms) — пламя появляется от краёв
2. **Breathing** — пламя "дышит" (ambient)
3. **Voice Active** — пламя реагирует на голос (responsive)
4. **Fade Out** (300ms) — пламя сворачивается и исчезает
5. **Processing** (optional) — короткая вспышка перед исчезновением (трансмутация завершена)

## Technical Constraints

- **macOS 14+** (Sonoma)
- **Single binary** — Swift, no Electron, no web views
- **Apple Silicon optimized** — Metal для шейдеров
- **Low CPU** — <5% CPU во время записи
- **Click-through** — overlay не перехватывает клики
- **Multi-monitor** — overlay на всех экранах (future)

## Deliverables

1. ✅ Color palette with hex values
2. ✅ Animation specification
3. ✅ Overlay architecture
4. ✅ Menu bar design
5. ⬜ Figma/Excalidraw mockup (optional)
6. ⬜ Metal shader prototype (future)

## Saint Germain Violet Flame — Research (2026-03-15)

### Визуальные свойства из первоисточников (I AM Activity, Summit Lighthouse)

- **Основание пламени** — синее/ультрафиолетовое, "холодный центр"
- **Середина** — чистый аметист (#9B59B6)
- **Верхушки** — розово-фиолетовые, переходящие в почти белый (#DA70D6 → white)
- **Движение** — спиральное, контрротация (против часовой стрелки)
- **Текстура** — полупрозрачное, "как цветное стекло с огнём внутри"
- **Свечение** — наэлектризованное, как разряд в аргоновом газе

### Символизм (применимо к UX)

| Процесс | Символ | В нашем приложении |
|---------|--------|--------------------|
| Трансмутация | Изменение природы энергии | Голос → Текст |
| Очищение | Растворение шума | Сырая речь → Чистый текст |
| Свобода | Освобождение от паттернов | Освобождение мысли от голоса |

### Цветовая схема (уточнённая)

```
Gradient flow (от края экрана внутрь):
  Gold Core (#F0A830)
    → Agni Orange (#E87D2F)
      → Deep Violet (#5B2D8E / #6A0DAD)
        → Amethyst (#9B59B6)
          → Orchid tips (#DA70D6)
            → Transparent
```

Золото у самого края (ядро пламени), затем через оранжевый в глубокий фиолетовый, аметист, и растворяется.

### Анимация (спиральная контрротация)

- Gradient locations должны медленно вращаться/смещаться
- Создавая эффект "спирального" движения пламени
- При высокой громкости — вращение ускоряется
- При тишине — замедляется почти до остановки

## References

- Apple Siri activation glow (macOS Sequoia)
- Plasma ball physics (reactive mesh)
- Saint Germain Violet Flame (I AM Activity, 1930s)
- Elizabeth Clare Prophet — Summit Lighthouse iconography
- Amethyst crystal spectrum (#5B2D8E)
- Argon gas discharge glow
- Northern Lights (Aurora Borealis) color dynamics
