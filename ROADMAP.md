# Ember Roadmap — Синтез 5 экспертов

> Дата: 2026-03-24
> Эксперты: macOS/Metal Engineer, UX Researcher, Product Trend Researcher, Growth Hacker, Business Strategist

---

## Стратегическая рамка

**Ember — не standalone продукт, а флагманский open-source проект Arcimun.** Цель — репутация, доверие, funnel в экосистему. Монетизация не нужна. Ресурс: 4-6 часов/неделю соло-разработчика.

**"Грамотно"** = каждый PRD независимо shippable, упорядочен по зависимостям, размером под 1-2 недели работы. Не "всё сразу", а инкрементальные релизы, где каждый улучшает метрику (retention, activation, performance).

---

## Полный список рекомендаций (74 пункта, дедуплицированы)

### A. КРИТИЧЕСКИЕ — Silent Failures (3 эксперта совпали)

| # | Что | Источник | Effort | Impact |
|---|-----|---------|--------|--------|
| A1 | Уведомления при ошибках вместо тишины (нет ключа, нет сети, 429, 401) | UX+Metal+Trend | M | 5 |
| A2 | Визуальное различие ошибки и успеха (красный flash overlay) | UX+Metal | S | 5 |
| A3 | Различать HTTP-ошибки: 401→"Проверьте ключ", 429→"Подождите", 500→"Groq" | UX+Metal | S | 4 |
| A4 | Retry с exponential backoff для сетевых ошибок | Metal+UX | M | 3 |
| A5 | Обработка ошибок записи аудио (try? → do/catch) | Metal | S | 4 |

### B. ONBOARDING & FIRST-RUN (UX + Growth совпали)

| # | Что | Источник | Effort | Impact |
|---|-----|---------|--------|--------|
| B1 | Onboarding tooltip "Нажмите ` чтобы начать" | UX+Growth | M | 5 |
| B2 | Единый onboarding flow вместо двух модальных диалогов | UX | M | 4 |
| B3 | Валидация API ключа при вводе (формат gsk_... + тест-вызов) | UX | S | 4 |
| B4 | Объяснение ценности до запроса ключа ("Нажмите `, говорите, текст появится") | UX+Growth | S | 4 |
| B5 | NSSecureTextField в first-run диалоге (как в Preferences) | UX | S | 3 |
| B6 | Объяснение последствий "Skip" | UX | S | 3 |
| B7 | Fix рекурсивный вызов showApiKeyDialog → DispatchQueue.main.async | Metal+UX | S | 1 |

### C. CUSTOMIZATION & POWER USERS (UX + Trend совпали)

| # | Что | Источник | Effort | Impact |
|---|-----|---------|--------|--------|
| C1 | Настраиваемый hotkey (не только backtick) | UX+Trend | M | 5 |
| C2 | Toggle "Raw mode" — отключение LLM-коррекции | UX | S | 4 |
| C3 | Custom LLM system prompt в Preferences | UX | S | 3 |
| C4 | Per-app language (авто-определение → передача в LLM) | UX+Trend | S | 3 |
| C5 | Translation mode (диктовать RU → получить EN) | Trend | S | 4 |
| C6 | Выбор модели STT/LLM в Preferences | UX | M | 3 |
| C7 | Удаление записей из History + keyboard shortcuts | UX | S | 3 |
| C8 | Экспорт истории в CSV/TXT | UX | S | 3 |
| C9 | Max recording duration guard (мягкий лимит 5 мин) | UX | S | 2 |

### D. PERFORMANCE & NATIVE (Metal Engineer)

| # | Что | Источник | Effort | Impact |
|---|-----|---------|--------|--------|
| D1 | AVAudioConverter вместо afconvert subprocess | Metal | M | 4 |
| D2 | Остановка RAF-цикла когда overlay скрыт (экономия батареи) | Metal | S | 3 |
| D3 | vDSP_rmsqv вместо ручного цикла RMS | Metal | S | 2 |
| D4 | Кеширование DateFormatter в log() | Metal | S | 3 |
| D5 | OSLog вместо кастомного логирования | Metal | S | 3 |
| D6 | usleep → DispatchQueue.main.asyncAfter в auto-paste | Metal | S | 3 |
| D7 | Noise gate для overlay (rms < 0.01 → 0) | UX | S | 2 |
| D8 | Multi-display support (overlay на экране курсора) | Metal | S | 3 |

### E. ARCHITECTURE (Metal + Strategy)

| # | Что | Источник | Effort | Impact |
|---|-----|---------|--------|--------|
| E1 | STT provider abstraction (protocol, убрать Groq lock-in) | Strategy+Metal+Trend | M | 5 |
| E2 | Проверка целевого окна перед auto-paste | UX | S | 4 |
| E3 | Codable вместо JSONSerialization | Metal | M | 3 |
| E4 | async/await вместо callback chains | Metal | M | 3 |
| E5 | Вынести paste-логику (дубликат в App.swift и History.swift) | Metal | S | 2 |
| E6 | Dependency injection вместо глобальных переменных | Metal | M | 3 |
| E7 | Preferences → отдельный NSViewController/SwiftUI | Metal | M | 2 |

### F. ACCESSIBILITY (UX)

| # | Что | Источник | Effort | Impact |
|---|-----|---------|--------|--------|
| F1 | Проверка reduceMotion → fallback на minimal тему | UX | S | 4 |
| F2 | VoiceOver announcements для состояний | UX | M | 4 |
| F3 | High Contrast Mode support | UX | S | 2 |
| F4 | Проверка доступа к микрофону при старте | UX | S | 4 |

### G. UI FEEDBACK (UX + Metal)

| # | Что | Источник | Effort | Impact |
|---|-----|---------|--------|--------|
| G1 | Таймер записи в menu bar | UX | S | 3 |
| G2 | Показывать время обработки (0.7s STT + 0.9s LLM) | Growth | S | 3 |
| G3 | Celebratory pulse при успешной диктовке | UX | S | 4 |
| G4 | Haptic feedback (NSHapticFeedbackManager) | UX | S | 3 |
| G5 | Статистика: "Today: 12 transcriptions, 847 words" | Growth+UX | M | 2 |
| G6 | Настройка области overlay (только края / весь экран) | UX | M | 3 |

### H. GROWTH & DISTRIBUTION (Growth + Strategy)

| # | Что | Источник | Effort | Impact |
|---|-----|---------|--------|--------|
| H1 | README с GIF-демо (главный conversion asset) | Growth+Strategy | S | 5 |
| H2 | GitHub Topics (macos, voice-to-text, whisper, groq...) | Growth | S | 2 |
| H3 | Show HN launch post | Growth+Strategy | S | 5 |
| H4 | ProductHunt launch | Growth | M | 4 |
| H5 | Reddit посты (r/macapps, r/programming, r/commandline) | Growth | S | 3 |
| H6 | Landing page (ember.arcimun.ai) | Growth | M | 4 |
| H7 | Groq DevRel outreach (partnership) | Growth+Strategy | M | 4 |
| H8 | Contributing guide + "good first issues" | Growth+Strategy | S | 3 |
| H9 | Community themes repo/docs | Growth | M | 4 |
| H10 | Homebrew в основной cask repo (после 30+ stars) | Growth | M | 4 |
| H11 | Raycast extension | Growth+Strategy | M | 4 |
| H12 | Техническая статья (dev.to / Medium) | Growth | M | 3 |

### I. FUTURE VISION (Metal + Strategy + Trend)

| # | Что | Источник | Effort | Impact |
|---|-----|---------|--------|--------|
| I1 | On-device Whisper (CoreML / whisper.cpp) | Metal+Trend+Strategy | L | 5 |
| I2 | Apple Shortcuts (AppIntents) | Metal | M | 4 |
| I3 | Metal overlay вместо WebGL2/WKWebView | Metal | L | 4 |
| I4 | OpenClaw voice commands (v2.0) | Strategy | L | 4 |
| I5 | Apple Intelligence / Writing Tools integration | Metal | M | 4 |
| I6 | Streaming transcription (real-time text) | Trend | L | 4 |
| I7 | Per-app context (ScreenCaptureKit) | Metal+Trend | L | 3 |
| I8 | Proxy-сервер для trial без API key | Growth | L | 5 |

---

## Структура PRD

**5 PRD-документов**, каждый — независимый релиз. Порядок = зависимости + ROI.

### PRD 1: "Reliability" (v1.3) — 1 неделя
> Цель: Ember перестаёт молчать при ошибках

**Scope:** A1-A5, B7, D6, E2, E5, F4
**Метрика:** 0 silent failures (каждая ошибка → видимый feedback)
**Почему первый:** Без этого retention невозможен — пользователи уходят думая что "сломалось"

| Пункт | Effort | Что |
|-------|--------|-----|
| A1 | M | Система уведомлений при ошибках |
| A2 | S | Красный flash overlay при ошибке |
| A3 | S | Различение HTTP-ошибок по типу |
| A5 | S | try? → do/catch в аудио-записи |
| B7 | S | Fix рекурсия showApiKeyDialog |
| D6 | S | usleep → asyncAfter в auto-paste |
| E2 | S | Проверка целевого окна перед paste |
| E5 | S | Deduplicate paste logic |
| F4 | S | Проверка микрофона при старте |

---

### PRD 2: "First Impressions" (v1.4) — 1-2 недели
> Цель: от установки до "wow" за 60 секунд

**Scope:** B1-B6, C1, D1, D2, D4, D8, F1, G1, G3
**Метрика:** Activation rate (% пользователей, сделавших 3+ транскрипции в первый день)
**Почему второй:** После reliability — следующий блокер это "не понял как пользоваться"

| Пункт | Effort | Что |
|-------|--------|-----|
| B1 | M | Onboarding tooltip |
| B2 | M | Единый onboarding flow |
| B3 | S | Валидация API ключа |
| B4 | S | Ценностное предложение до запроса ключа |
| B5 | S | SecureTextField |
| B6 | S | Объяснение Skip |
| C1 | M | Настраиваемый hotkey |
| D1 | M | AVAudioConverter (нативный) |
| D2 | S | RAF-цикл stop когда overlay скрыт |
| D4 | S | Кеширование DateFormatter |
| D8 | S | Multi-display overlay |
| F1 | S | reduceMotion → minimal тема |
| G1 | S | Таймер записи |
| G3 | S | Celebratory pulse при успехе |

---

### PRD 3: "Launch" (маркетинг) — 2-3 недели
> Цель: 500 GitHub stars, 1000 Homebrew installs

**Scope:** H1-H12
**Метрика:** Stars, installs, HN front page
**Почему третий:** Запускать нужно ПОСЛЕ reliability + onboarding. Иначе первое впечатление убьёт рост.

| Пункт | Effort | Что |
|-------|--------|-----|
| H1 | S | README + GIF-демо |
| H2 | S | GitHub Topics |
| H3 | S | Show HN |
| H4 | M | ProductHunt |
| H5 | S | Reddit посты |
| H6 | M | Landing page |
| H7 | M | Groq DevRel |
| H8 | S | Contributing guide |
| H9 | M | Community themes |
| H10 | M | Homebrew cask PR |
| H11 | M | Raycast extension |
| H12 | M | Техническая статья |

---

### PRD 4: "Power Users" (v1.5) — 2 недели
> Цель: daily users получают контроль и удовольствие

**Scope:** C2-C9, E1, E3, E4, G2, G4, G5, G6, F2, F3, D3, D5, D7, A4
**Метрика:** Retention D7/D30, среднее кол-во транскрипций/день
**Почему четвёртый:** Power user фичи нужны когда есть пользователи (после Launch)

| Пункт | Effort | Что |
|-------|--------|-----|
| E1 | M | STT provider abstraction (Groq lock-in) |
| C2 | S | Raw mode toggle |
| C3 | S | Custom LLM prompt |
| C4 | S | Per-app language |
| C5 | S | Translation mode |
| C6 | M | Выбор модели |
| C7 | S | History CRUD + shortcuts |
| C8 | S | Экспорт истории |
| E3 | M | Codable |
| E4 | M | async/await |
| G2 | S | Показ времени обработки |
| G4 | S | Haptic feedback |
| D3 | S | vDSP_rmsqv |
| D5 | S | OSLog |
| A4 | M | Retry logic |
| F2 | M | VoiceOver |

---

### PRD 5: "Vision" (v2.0) — квартал
> Цель: Ember = voice layer для macOS

**Scope:** I1-I8, E6, E7
**Метрика:** Offline capability, ecosystem integration
**Почему последний:** Требует больших вложений, оправдан только при proven adoption

| Пункт | Effort | Что |
|-------|--------|-----|
| I1 | L | On-device Whisper (CoreML) |
| I2 | M | Apple Shortcuts (AppIntents) |
| I3 | L | Metal overlay |
| I4 | L | OpenClaw voice commands |
| I5 | M | Apple Intelligence integration |
| I6 | L | Streaming transcription |
| I8 | L | Proxy для trial без API key |
| E6 | M | Dependency injection |
| E7 | M | SwiftUI Preferences |

---

## Timeline

```
Апрель 2026     PRD 1: Reliability (v1.3)
                PRD 3: Launch prep (README, GIF, topics)
Май 2026        PRD 2: First Impressions (v1.4)
                PRD 3: HN + ProductHunt + Reddit
Июнь 2026       PRD 4: Power Users (v1.5)
                PRD 3: Raycast, Homebrew cask, Groq partnership
Q3 2026         PRD 5: Vision (v2.0) — начало
Q4 2026         PRD 5: Vision (v2.0) — on-device Whisper, OpenClaw integration
```

---

## North Star

**"Голос как интерфейс — бесплатный, красивый, для всех."**

Ember сегодня: 1,351 строка Swift + 5 GLSL-тем + бесплатный Groq API.
Ember через год: стандартный voice layer для macOS power users, gateway в Arcimun экосистему.
