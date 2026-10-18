# 📈 Отчет: Линейный таймлайн, Статусы и Автоперемещение к дате старта задачи

## 1. Резюме выполненных работ

По запросу пользователя были решены следующие задачи:
1. **Устранение бага сжатых пилюль (по скрину пользователя):**
   - **Причина:** При просмотре месяца без задач (например, `Июль 2027`) задачи из `Ноября 2026` рисовались с зажатыми отрицательными смещениями, превращаясь в 34-пиксельные кружочки `◄ ⦿` на 1-м числе месяца.
   - **Решение:** Внедрена строгая фильтрация по пересечению временного диапазона (`overlaps = createdTs <= windowEnd && deadlineTs >= windowStart`). Вне-диапазонные задачи больше не отображаются на чужих месяцах.
   - **Empty State:** При отсутствии задач в выбранном месяце выводится понятное сообщение «В этом периоде нет задач» с кнопкой быстрого перехода к ближайшему месяцу с задачами: `[ 📅 Перейти к ... ]` и кнопкой `[ 🌐 Показать всю дорожную карту ]`.

2. **Ото отображение статусов задач (Open / In_Process / Closed / Fixed / Deferred):**
   - На карточках в левой колонке таймлайна теперь отображаются **как приоритет, так и статус** (`.badge-status-open`, `.badge-status-closed`, и т.д.).
   - Внутри самой полосы Gantt добавлен компактный бейдж статуса: `.timeline-bar-status-tag` (`OPEN`, `CLOSED`, `IN_PROCESS`).
   - На карточках в боковой панели и во всплывающей подсказке (Tooltip) статус виден с цветовой дифференциацией.

3. **Автоматическое перемещение в календаре на дату старта задачи при клике:**
   - В боковой панели добавлен переключатель вкладок: `[ 📋 Бэклог ]` и `[ 📅 С дедлайном ]`.
   - При клике по любому тикету из списка с дедлайнами:
     - Вычисляется дата его старта (`createdTs` / `mtime`).
     - Если задача начинается в другом месяце, календарь автоматически переключается на этот месяц (`state.calendarYear = startYear; state.calendarMonth = startMonth`).
     - Таймлайн плавно скроллится по горизонтали прямо к началу полосы задачи.
     - Полоса и карточка задачи подсвечиваются яркой пульсирующей анимацией `.timeline-highlight-pulse`.
     - Показывается всплывающее подтверждение с датой начала.
   - На карточках в левом столбце Gantt добавлен отдельный значок `✏️` для открытия окна редактирования, а клик по карточке перемещает фокус на дату начала задачи.

4. **Полная поддержка во всех 3 базах данных (IndexedDB, SQLite WASM, Pure-Nim CDB):**
   - В SQLite WASM добавлена колонка `created REAL` в таблицу `ticket`, добавлены запросы миграции `ALTER TABLE` и сохранение временных меток в `ticket_create`, `ticket_list` и `ticket_get`.
   - Проведено сквозное обезьянье тестирование во всех трёх БД (41 проверка из 41 успешно пройдена).

---

## 2. Результаты обезьяньего тестирования (`test_monkey_timeline_all_dbs.js`)

```
=================================================================
🐒 MONKEY TEST: LINEAR TIMELINE, STATUSES, CLICK-TO-JUMP & MULTI-DB
=================================================================

--- PHASE 1: Loading In-Browser Fossil UI & Navigating to Timeline Calendar ---
  ✅ [PASS] Timeline Calendar tab is active

--- PHASE 2: Verifying Status Badges Display ---
  ✅ [PASS] Timeline bars display status tags (6 tags found: OPEN, CLOSED, OPEN)
  ✅ [PASS] Left task items display status badges (6 badges found)
  ✅ [PASS] Side panel has '📅 С дедлайном' tab button
  ✅ [PASS] Side panel switched to scheduled tickets view
  ✅ [PASS] Side panel scheduled tickets display status badges (6 found: Closed, Open, Open)

--- PHASE 3: Testing Date Overlap Filtering & Empty State (Fixing User Screenshot Issue) ---
  [INFO] Navigated to month: Июль 2027
  ✅ [PASS] Out-of-range 2026 tasks are NOT drawn in Июль 2027 (got 0 squished bars, was bugged previously)
  ✅ [PASS] Empty state correctly displayed in Июль 2027: 'В этом периоде нет задач'
  ✅ [PASS] Smart jump button is present in empty state
  [INFO] Smart Jump Button text: "📅 Перейти к Октябрь 2026 (6 задач)"
  ✅ [PASS] Smart jump returned to active month (Октябрь 2026) with 6 tasks rendered

--- PHASE 4: Testing Click-to-Jump to Task Start Date ---
  ✅ [PASS] Ticket found in side panel scheduled list
  [INFO] Clicking on ticket #tkt-103 in scheduled list to test auto-jump...
  ✅ [PASS] Clicking scheduled ticket auto-navigated calendar to task start month (6 tasks visible)
  ✅ [PASS] Target task bar #tkt-103 received vibrant .timeline-highlight-pulse animation
  ✅ [PASS] Left column task item exists
  ✅ [PASS] Toast confirmed jump to start date: "Переход к дате начала задачи #tkt-103: 6.10.2026"
  ✅ [PASS] Left column item has direct ✏️ edit button
  ✅ [PASS] Clicking ✏️ edit button opened ticket edit modal directly

--- PHASE 5: Monkey Testing Across All 3 Databases ---
  >>> Testing Database Backend: [INDEXEDDB] <<<
  ✅ [PASS] Successfully switched active storage to indexeddb
  ✅ [PASS] indexeddb: linear timeline rendered 6 task bars
  ✅ [PASS] indexeddb: status tags rendered: OPEN, CLOSED
  ✅ [PASS] indexeddb: ticket_create succeeded (ID: tkt-869700)
  ✅ [PASS] indexeddb: newly created ticket #tkt-869700 appears on the timeline
  ✅ [PASS] indexeddb: ticket status updated to Closed (got: Closed)
  ✅ [PASS] indexeddb: bar visually styled as .status-closed (emerald green)
  ✅ [PASS] indexeddb: navigateToTicketStart triggered .timeline-highlight-pulse on #tkt-869700

  >>> Testing Database Backend: [SQLITE_WASM] <<<
  ✅ [PASS] Successfully switched active storage to sqlite_wasm
  ✅ [PASS] sqlite_wasm: linear timeline rendered 6 task bars
  ✅ [PASS] sqlite_wasm: status tags rendered: OPEN, CLOSED
  ✅ [PASS] sqlite_wasm: ticket_create succeeded (ID: tkt-3ebca5)
  ✅ [PASS] sqlite_wasm: newly created ticket #tkt-3ebca5 appears on the timeline
  ✅ [PASS] sqlite_wasm: ticket status updated to Closed (got: Closed)
  ✅ [PASS] sqlite_wasm: bar visually styled as .status-closed (emerald green)
  ✅ [PASS] sqlite_wasm: navigateToTicketStart triggered .timeline-highlight-pulse on #tkt-3ebca5

  >>> Testing Database Backend: [CDB] <<<
  ✅ [PASS] Successfully switched active storage to cdb
  ✅ [PASS] cdb: linear timeline rendered 6 task bars
  ✅ [PASS] cdb: status tags rendered: OPEN, CLOSED
  ✅ [PASS] cdb: ticket_create succeeded (ID: tkt-c2e218)
  ✅ [PASS] cdb: newly created ticket #tkt-c2e218 appears on the timeline
  ✅ [PASS] cdb: ticket status updated to Closed (got: Closed)
  ✅ [PASS] cdb: bar visually styled as .status-closed (emerald green)
  ✅ [PASS] cdb: navigateToTicketStart triggered .timeline-highlight-pulse on #tkt-c2e218

=================================================================
📊 FINAL RESULT: 41 PASSED, 0 FAILED
=================================================================
```

---

## 3. Скриншоты и визуальные подтверждения

````carousel
![IndexedDB Timeline](/home/nc568/.gemini/antigravity/brain/61058840-d586-4e96-a395-fdd951e4f976/monkey_timeline_indexeddb.png)
<!-- slide -->
![SQLite WASM Timeline](/home/nc568/.gemini/antigravity/brain/61058840-d586-4e96-a395-fdd951e4f976/monkey_timeline_sqlite_wasm.png)
<!-- slide -->
![Pure-Nim CDB Timeline](/home/nc568/.gemini/antigravity/brain/61058840-d586-4e96-a395-fdd951e4f976/monkey_timeline_cdb.png)
<!-- slide -->
![Tooltip Details](/home/nc568/.gemini/antigravity/brain/61058840-d586-4e96-a395-fdd951e4f976/linear_timeline_hover_tooltip.png)
````

---

## 4. Измененные файлы

1. [`web_new/browser.html`](file:///home/nc568/antigravity/hopeful-volta/fossil-nim/web_new/browser.html):
   - Добавлены вкладки боковой панели `[ 📋 Бэклог ]` и `[ 📅 С дедлайном ]`.
2. [`web_new/css/app.css`](file:///home/nc568/antigravity/hopeful-volta/fossil-nim/web_new/css/app.css):
   - Стили бейджей статусов (`.badge-status-open`, `.badge-status-in_process`, `.badge-status-closed`, `.badge-status-deferred`).
   - Стили тегов статуса полосы (`.timeline-bar-status-tag`).
   - Анимация плавного фокуса при автопереходе (`@keyframes timelinePulseHighlight`).
   - Стили кнопки редактирования `.btn-ghost`.
3. [`web_new/js/fossil_browser_ui.js`](file:///home/nc568/antigravity/hopeful-volta/fossil-nim/web_new/js/fossil_browser_ui.js):
   - Метод `navigateToTicketStart(ticketId)`: переключение месяца, горизонтальный автоскролл и пульс-подсветка.
   - Фильтрация по пересечению временных интервалов (`overlaps`).
   - Отображение статусов в Gantt, левом списке задач и боковом списке.
   - Empty state с кнопкой быстрого прыжка к месяцу с задачами.
4. [`web_new/js/fossil_browser_storage.js`](file:///home/nc568/antigravity/hopeful-volta/fossil-nim/web_new/js/fossil_browser_storage.js):
   - Добавлена колонка `created REAL` в таблицу `ticket` SQLite WASM, миграция и заполнение seed-данных.
5. [`web_new/js/fossil_mcp_agent.js`](file:///home/nc568/antigravity/hopeful-volta/fossil-nim/web_new/js/fossil_mcp_agent.js):
   - Сохранение и выдача `created` в `ticket_create`, `ticket_list` и `ticket_get`.
6. [`fossil-browser.html`](file:///home/nc568/antigravity/hopeful-volta/fossil-nim/fossil-browser.html):
   - Автономный монолитный бандл (559 КБ) пересобран со всеми улучшениями.
