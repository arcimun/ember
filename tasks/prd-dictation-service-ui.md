# PRD: Dictation Service UI — Menu Bar & Visual Experience

## Introduction

Добавить визуальный интерфейс к существующему Swift-сервису стриминг диктовки. Сейчас сервис работает как CLI daemon без UI — пользователь не видит состояния работы. Нужно: иконка в menu bar, отображение текста в реальном времени, визуальный эффект "плазмы" по краям экрана при диктовке.

**Текущее состояние:** Работающий Swift-сервис (v5 streaming) — Deepgram WebSocket, CGEvent typing в активное поле, горячая клавиша `` ` ``.

## Goals

- Menu bar иконка с отображением статуса (готов/записывает/обрабатывает)
- Live transcript popover — видеть текст который диктуется в реальном времени
- Visual effect "плазма" по краям экрана — визуальный feedback при диктовке
- History — хранить последние 20 диктовок для возможности переделать
- Сохранить все существующие функции (стриминг, typing, clipboard)
- Запуск при старте системы (опционально, настраивается)

## User Stories

### Phase 1: Menu Bar Icon & Status

### US-001: Добавить NSStatusItem в menu bar
**Description:** Как пользователь, я хочу видеть иконку в menu bar чтобы знать что сервис запущен и готов к работе.

**Acceptance Criteria:**
- [ ] Приложение регистрируется как menu bar app (LSUIElement = true в Info.plist)
- [ ] Иконка отображается в menu bar (SF Symbol: waveform или кастомная)
- [ ] Клик по иконке показывает dropdown меню
- [ ] Иконка меняется в зависимости от статуса:
  - Серый/контурный — готов к работе (idle)
  - Залитый/пульсирующий — записывает (recording)
  - С галочкой — успешно завершено (success)
  - С восклицательным знаком — ошибка (error)
- [ ] Приложение не показывается в Dock

### US-002: Dropdown меню со статусами
**Description:** Как пользователь, я хочу видеть текущий статус и иметь быстрый доступ к управлению.

**Acceptance Criteria:**
- [ ] Меню показывает текущий статус текстом ("Ready", "Recording: привет...", "Done")
- [ ] Кнопка "Start/Stop Recording" — ручной запуск/останов
- [ ] Кнопка "Show Transcript" — открыть popover с текстом
- [ ] Separator
- [ ] Кнопка "History" — показать последние диктовки
- [ ] Separator
- [ ] Кнопка "Settings..." — открыть настройки
- [ ] Кнопка "Quit" — выйти из приложения

### Phase 2: Live Transcript Popover

### US-003: Отображение live text в popover
**Description:** Как пользователь, я хочу видеть текст который печатается в реальном времени чтобы контролировать распознавание.

**Acceptance Criteria:**
- [ ] Popover появляется при клике на "Show Transcript" или автоматически при старте записи
- [ ] Показывает interim text (что сейчас распознаётся) — приглушённым/серым цветом
- [ ] Показывает final text (подтверждённое) — нормальным цветом
- [ ] Popover позиционируется рядом с menu bar иконкой
- [ ] Текст можно скопировать кнопкой "Copy"
- [ ] Popover закрывается кнопкой "X" или при клике вне
- [ ] Анимация появления/исчезновения (fade, 200ms)

### US-004: History последних 20 диктовок
**Description:** Как пользователь, я хочу иметь доступ к последним диктовкам чтобы переделать если ошибся.

**Acceptance Criteria:**
- [ ] При выборе "History" открывается отдельное окно или popover
- [ ] Показывает список последних 20 диктовок
- [ ] Каждая запись показывает: дата/время, начало текста (первые 50 символов)
- [ ] При клике на запись — полный текст в detail view
- [ ] Кнопка "Copy" для копирования текста в буфер обмена
- [ ] Кнопка "Delete" для удаления записи
- [ ] Данные хранятся локально (SQLite или JSON файл)
- [ ] Автоматическая очистка записей старше 7 дней (чтобы не раздувать)

### Phase 3: Visual Effect (Плазма)

### US-005: Borderless window для visual effect
**Description:** Как пользователь, я хочу видеть визуальный эффект по краям экрана при диктовке чтобы понимать что система слушает.

**Acceptance Criteria:**
- [ ] Создаётся borderless NSWindow на весь экран, level: .screenSaver или выше
- [ ] Window имеет прозрачный фон (backgroundColor.clear)
- [ ] Window игнорирует mouse events (passthrough)
- [ ] Window появляется при старте записи, исчезает при остановке
- [ ] Анимация появления: fade in 300ms
- [ ] Анимация исчезновения: fade out 500ms

### US-006: Plasma shader effect
**Description:** Как пользователь, я хочу видеть красивый минималистичный эффект "плазмы" по краям экрана.

**Acceptance Criteria:**
- [ ] Metal shader для рендеринга эффекта
- [ ] Эффект рендерится только по краям экрана (inset 20-50px от краёв)
- [ ] Цветовая схема: космический минималистичный
  - Основной: приглушённый фиолетовый (#6B5B95)
  - Акцент: мягкий голубой (#88B4E3)
  - Фон: прозрачный
- [ ] Анимация: плавное движение/пульсация (speed: 0.5-1.0, не агрессивно)
- [ ] Плавный градиент от края к центру (fade к прозрачности)
- [ ] Не перекрывает контент экрана (только border)

### Phase 4: Settings

### US-007: Settings window
**Description:** Как пользователь, я хочу иметь доступ к настройкам чтобы менять провайдера, язык, горячую клавишу.

**Acceptance Criteria:**
- [ ] Отдельное окно Settings (NSWindow)
- [ ] Вкладка "General":
  - Provider: dropdown (Deepgram Nova-3, Groq Whisper) — только если ключи настроены
  - Language: dropdown (Russian, English, Auto)
  - Hotkey: поле для отображения текущей клавиши + кнопка "Change"
  - End delay: slider 0.3-2.0 seconds (текущее значение 0.8)
- [ ] Вкладка "Appearance":
  - [x] Show visual effect — toggle
  - [x] Play sounds — toggle (1113/1114 system sounds)
  - [x] Show in menu bar — toggle (всегда true для этого app)
  - [ ] Start at login — toggle
- [ ] Кнопки: "Save", "Cancel"
- [ ] Настройки сохраняются в UserDefaults
- [ ] Перезапуск не требуется — настройки применяются сразу

### US-008: Горячая клавиша для смены hotkey
**Description:** Как пользователь, я хочу менять горячую клавишу для старта/стопа диктовки.

**Acceptance Criteria:**
- [ ] При нажатии "Change" появляется prompt "Press new key..."
- [ ] Слушает следующее нажатие клавиши (CGEvent tap)
- [ ] Показывает keycode и key name
- [ ] Проверяет что клавиша не занята системой (или предупреждает)
- [ ] Сохраняет и применяет новую клавишу

### Phase 5: Интеграция с Core Service

### US-009: Интеграция UI с существующим streaming сервисом
**Description:** Как разработчик, мне нужно чтобы UI компоненты взаимодействовали с существующим кодом transcription.

**Acceptance Criteria:**
- [ ] UI использует те же функции из main.swift (connectDeepgram, startStreaming, stopStreaming)
- [ ] State management: isActive, isStopping, sessionText доступны UI
- [ ] Обновление UI при изменении статуса (delegate или callback pattern)
- [ ] typingText функция используется для interim display
- [ ] WebSocket messages парсятся и отправляются в UI
- [ ] App launch при старте системы (SMAppService для macOS 13+ или LaunchAgent)

### US-010: Audio feedback sounds
**Description:** Как пользователь, я хочу слышать звуки при старте/стопе диктовки.

**Acceptance Criteria:**
- [ ] System sound 1113 при старте записи (уже есть в коде)
- [ ] System sound 1114 при остановке (уже есть в коде)
- [ ] Sound toggle в настройках (включать/выключать)
- [ ] Звуки играют даже если visual effect выключен

## Functional Requirements

- FR-1: Приложение работает как menu bar app (LSUIElement)
- FR-2: NSStatusItem с динамической иконкой (меняется по статусу)
- FR-3: Dropdown меню с основными действиями
- FR-4: Live transcript popover с interim/final text
- FR-5: History — хранение последних 20 диктовок, 7 дней TTL
- FR-6: Borderless transparent window для visual effect
- FR-7: Metal shader для plasma border effect
- FR-8: Settings window с вкладками General и Appearance
- FR-9: Hotkey reconfiguration
- FR-10: UserDefaults для persistence настроек
- FR-11: Start at login support (SMAppService)
- FR-12: Сохранить обратную совместимость с CLI launchctl

## Non-Goals

- Поддержка нескольких языков интерфейса (только English для UI)
- Облачная синхронизация настроек
- Интеграция с third-party сервисами кроме STT провайдеров
- Текстовый редактор или продвинутое редактирование
- Горячие клавиши для управления (только toggle key)

## Technical Considerations

**App Structure:**
```
DictationService.app/
├── Contents/
│   ├── MacOS/dictation-service (executable)
│   ├── Info.plist (LSUIElement = true)
│   └── Resources/
│       └── Assets.xcassets (иконки)
```

**State Communication:** SwiftUI @Observable или Combine для UI ↔ Core связки

**Storage:**
- Настройки: UserDefaults (com.arcimun.dictation-service)
- History: SQLite.swift или JSON файл в Application Support

**Visual Effect:**
- Metal для GPU-accelerated rendering
- Single fullscreen window, level = .screenSaver
- Passthrough mouse events

**Code Organization:**
- UI компоненты: SwiftUI views
- Core transcription: существующий код main.swift
- App entry: @main AppDelegate с NSApplication

## Success Metrics

- Menu bar иконка отображается в течение 2 секунд после запуска
- Live text обновляется с задержкой <100ms от получения от Deepgram
- Visual effect не потребляет >5% CPU при idle
- Приложение использует <100MB RAM
- Startup time <3 секунд
- Toggle диктовки по горячей клавише срабатывает <50ms

## Open Questions

- Q1: Какой SF Symbol использовать для иконки? (waveform, mic, text.bubble)
- Q2: Как позиционировать popover — под иконкой или справа?
- Q3: History — показывать дату в каком формате? (относительное: "2 min ago" или абсолютное)
- Q4: Visual effect — какой inset от края экрана? (20px мало, 50px много — попробовать 35px)
- Q5: Приложение должно показывать notification при ошибке или достаточно иконки?

## Implementation Priority

1. **Phase 1** (US-001, US-002): Menu bar icon + status — 2-3 дня
2. **Phase 2** (US-003, US-004): Live transcript + History — 2-3 дня
3. **Phase 3** (US-005, US-006): Visual effect — 3-5 дней
4. **Phase 4** (US-007, US-008): Settings — 2 дня
5. **Phase 5** (US-009, US-010): Integration + polish — 1-2 дня

**Total estimate: ~10-15 дней качественной работы**
