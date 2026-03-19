# PRD: Dictation Service v8 — Smooth Streaming + Cancel/Recovery

## Introduction

Dictation Service v7 работает: streaming Deepgram, plasma overlay, menu bar. Но interim текст дёргается (стирается/перепечатывается при каждом обновлении), нет отмены по Escape, clipboard не обновляется инкрементально. v8 решает эти проблемы.

## Goals

- Убрать дёрганье: печатать только финальный текст (is_final=true), показывать "..." спиннер между фразами
- Escape отменяет запись, стирает напечатанное, но сохраняет в clipboard
- Clipboard обновляется после каждой финальной фразы (crash-safe)
- Текст появляется плавно, как будто стелится посимвольно

## User Stories

### US-001: Только финальный текст в текстовом поле
**Type:** fix
**Status:** pending
**Description:** Убрать interim-based backspace/retype. Печатать в текстовое поле ТОЛЬКО когда Deepgram отправляет is_final=true.
**Files:** `Sources/main.swift` — handleDeepgramMessage(), typeText(), backspace()

**Acceptance Criteria:**
- [ ] handleDeepgramMessage() игнорирует interim (is_final=false) для печати
- [ ] При is_final=true текст печатается посимвольно с 1-2ms задержкой (плавно)
- [ ] Никакого backspace — текст только добавляется
- [ ] interimLength удалён (не нужен)

### US-002: Спиннер "..." между фразами
**Type:** feat
**Status:** pending
**Description:** Пока Deepgram обрабатывает речь (получаем interim, но ещё нет final), показывать "⟨ ··· ⟩" после последнего напечатанного текста, затем стирать перед печатью финальной фразы.
**Files:** `Sources/main.swift` — handleDeepgramMessage()

**Acceptance Criteria:**
- [ ] При первом interim после final — напечатать " ···" (3 точки)
- [ ] При получении final — стереть " ···" (backspace 4), затем напечатать финальный текст
- [ ] Если interim приходит повторно — ничего не делать (спиннер уже показан)
- [ ] При stopRecording — стереть спиннер если он есть

### US-003: Escape — отмена с сохранением в clipboard
**Type:** feat
**Status:** pending
**Description:** Нажатие Escape во время записи: останавливает запись, стирает весь напечатанный текст из поля, но сохраняет его в clipboard.
**Files:** `Sources/main.swift` — setupEventTap(), новая функция cancelRecording()

**Acceptance Criteria:**
- [ ] Escape (keycode 53) перехватывается в event tap во время записи
- [ ] cancelRecording() останавливает rec + WebSocket
- [ ] Стирает currentText.count символов из текстового поля (backspace)
- [ ] Стирает спиннер если он есть
- [ ] Копирует currentText в clipboard перед стиранием
- [ ] Overlay скрывается, menu bar возвращается к 🎤
- [ ] History НЕ сохраняется при отмене

### US-004: Incremental clipboard после каждой фразы
**Type:** feat
**Status:** pending
**Description:** Clipboard обновляется после каждого is_final — если приложение крашнется, текст уже в clipboard.
**Files:** `Sources/main.swift` — handleDeepgramMessage()

**Acceptance Criteria:**
- [ ] После каждого is_final=true: `NSPasteboard.general.setString(currentText, forType: .string)`
- [ ] currentText накапливает ВСЕ финальные фразы сессии
- [ ] При Escape — clipboard уже содержит последний распознанный текст

### US-005: Плавная посимвольная печать
**Type:** feat
**Status:** pending
**Description:** Текст появляется посимвольно с микро-задержкой (1-2ms), создавая эффект "стелящегося" текста.
**Files:** `Sources/main.swift` — typeText()

**Acceptance Criteria:**
- [ ] typeText() печатает по 1 символу с usleep(1500) между ними
- [ ] Русские символы корректно отображаются через CGEvent + keyboardSetUnicodeString

## Functional Requirements

- FR-1: При is_final=false — НЕ печатать в текстовое поле, только установить флаг "interim pending"
- FR-2: При is_final=true — стереть спиннер (если есть), напечатать финальный текст посимвольно, обновить clipboard
- FR-3: Спиннер " ···" показывается один раз после первого interim и стирается перед final
- FR-4: Escape (keycode 53) во время записи → cancelRecording() → стереть текст + сохранить clipboard
- FR-5: Тильда во время записи → stopRecording() → НЕ стирать текст, сохранить clipboard + history
- FR-6: Clipboard содержит currentText после каждого is_final

## Non-Goals

- Посимвольная анимация появления (fade-in per char) — это требует overlay, слишком сложно
- Визуальное отличие interim/final (серый/белый) — не печатаем interim
- Звуковая обратная связь при каждом слове

## Technical Considerations

- backspace() всё ещё нужен для спиннера (4 символа) и для Escape (стирание currentText)
- interimLength заменяется на `spinnerShown: Bool`
- currentText уже accumulates final text — менять не нужно
- CGEvent typing уже работает с Unicode — менять не нужно

## Success Metrics

- Текст НЕ дёргается при печати
- Escape стирает + сохраняет — проверяется через Cmd+V после Escape
- Спиннер виден между фразами

## Open Questions

- Нет
