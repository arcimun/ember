# PRD: Dictation Service v11 — SOTA Quality

## Introduction

Диктовка работает (тильда → запись → текст в поле + clipboard). Но качество текста ~6/10: слипшиеся слова, плохая пунктуация, английские слова не распознаются. Нужно довести до 10/10.

## Goals

- Исправить слипшиеся слова (пробелы между финальными фразами)
- Поддержка английских слов в русской речи (code-switching)
- LLM post-processing для грамматики, пунктуации, орфографии
- Результат: текст как если бы его написал грамотный человек

## User Stories

### US-001: Multilingual mode (RU+EN code-switching)
**Type:** fix
**Status:** pending
**Files:** `Sources/main.swift` — connectDeepgram()

**Acceptance Criteria:**
- [ ] Deepgram параметр `language=multi` вместо `language=ru`
- [ ] Английские слова распознаются правильно (Claude Code, iPhone, Deepgram)
- [ ] Русские слова по-прежнему хорошего качества

### US-002: LLM post-processing при остановке записи
**Type:** feat
**Status:** pending
**Files:** `Sources/main.swift` — stopRecording(), новая функция postProcessText()

**Acceptance Criteria:**
- [ ] При нажатии ` (stop): текст уже в поле (raw)
- [ ] Отправить currentText в Groq API (llama или mixtral — бесплатно) с промптом: "Исправь грамматику, пунктуацию, орфографию. Не меняй смысл. Верни только исправленный текст."
- [ ] Получить исправленный текст
- [ ] Select All в поле (Cmd+A) → вставить исправленный текст (Cmd+V)
- [ ] Обновить clipboard с исправленным текстом
- [ ] Если LLM недоступен — оставить raw текст (graceful fallback)

### US-003: Пробелы — финальный фикс
**Type:** fix
**Status:** pending
**Files:** `Sources/main.swift` — handleDeepgramMessage()

**Acceptance Criteria:**
- [ ] Пробел добавляется ВСЕГДА между финальными фразами
- [ ] Не добавляется двойной пробел
- [ ] Пробел не добавляется перед пунктуацией (.,!?)

## Functional Requirements

- FR-1: Deepgram WebSocket URL использует `language=multi`
- FR-2: После stopRecording, перед clipboard save: отправить текст в Groq (llama-3.3-70b) для коррекции
- FR-3: Groq промпт: системный — "You are a text corrector", user — raw text
- FR-4: Если Groq ответил — заменить текст в поле через Select All + Paste
- FR-5: Timeout для Groq: 10 секунд, если не ответил — оставить raw

## Non-Goals

- Не менять STT провайдер (остаётся Deepgram)
- Не делать real-time коррекцию (только при остановке)
- Не делать UI для настройки LLM

## Technical Considerations

- Groq API key уже есть в ~/.openclaw/.env (GROQ_API_KEY)
- Groq модель: `llama-3.3-70b-versatile` (бесплатный tier, быстрая)
- Для Select All + Paste: нужен Accessibility (CGEvent Cmd+A, Cmd+V)
- Fallback: если нет Accessibility — просто обновить clipboard

## Success Metrics

- "Claude Code" распознаётся правильно (не "CLOD код")
- Пробелы между всеми словами
- Пунктуация корректная
- Текст читается как написанный, а не надиктованный
