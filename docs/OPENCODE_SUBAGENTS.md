# OpenCode Sub-Agents - Использование opencode-cli как саб-агентов

Дата: 2026-10-17
Автор: Fossil-Nim team

## Установка

```bash
# Установка bun (требуется для opencode)
curl -fsSL https://bun.sh/install | bash
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
bun --version # 1.4.3

# Установка opencode-cli
bun add -g opencode-ai
opencode --version # 1.19.3

# Проверка бесплатных моделей
opencode models
# opencode/big-pickle
# opencode/cat-jam-free
# opencode/deepseek-v4.1-flash-free
# opencode/glm-5.3-flash-free
# opencode/ll-alpha-free
# opencode/longcat-2.5-preview-free
# opencode/mimo-v2.6-flash-free
# opencode/muse-spark-1.3-contributor-free
# opencode/nemotron-3-ultra-free
# opencode/nemotron-3.5-lightning-free
# opencode/nemotron-3.5-super-vl-free
# opencode/space-bunny-free
```

## Конфигурация

`~/.config/opencode/opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "permission": {
    "*": "allow"
  },
  "model": "opencode/deepseek-v4.1-flash-free"
}
```

`permission: * allow` требуется чтобы саб-агенты могли писать в `/tmp/opencode/` и в проект.

## Использование как саб-агентов

### Один саб-агент

```bash
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

opencode run --auto -m opencode/deepseek-v4.1-flash-free \
  --dir /home/user/fossil-nim \
  --title "web-pages" \
  "Implement file_page.nim, info_page.nim, graph_page.nim for Fossil-Nim web UI. Look at src/fossil/api/rest.nim and src/fossil/web/pages/"
```

### Параллельные саб-агенты

Создаём task файлы:

```bash
cat > /tmp/opencode/task_web.md <<'MD'
# Task: Implement Web UI pages...
MD

cat > /tmp/opencode/task_search.md <<'MD'
# Task: Search indexing file contents...
MD

# Запуск 4 параллельно
opencode run --auto -m opencode/deepseek-v4.1-flash-free --dir /home/user/fossil-nim < task_web.md &
opencode run --auto -m opencode/glm-5.3-flash-free --dir /home/user/fossil-nim < task_search.md &
opencode run --auto -m opencode/mimo-v2.6-flash-free --dir /home/user/fossil-nim < task_forum.md &
opencode run --auto -m opencode/nemotron-3.5-lightning-free --dir /home/user/fossil-nim < task_mdbx.md &
wait
```

В проекте Fossil-Nim мы использовали 4 саб-агента:
- **web** (deepseek-v4.1-flash-free): file.c, info.c, graph.c, login.c, setup.c, CSS/JS
- **search** (glm-5.3-flash-free): index file contents, commits, branches, reindexAll
- **forum_chat** (mimo-v2.6-flash-free): moderation pinning, chat rooms, presence, typing, attachments
- **mdbx_vendor** (nemotron-3.5-lightning-free): vendor mdbx.c, migration batched 10k txn

### Логи

```bash
ls /tmp/opencode/*.log
cat /tmp/opencode/web.log
```

## Результаты 2026-10-17

Саб-агенты были запущены, но из-за ограничений песочницы (CPU, permission) часть работы была выполнена основным агентом напрямую:

- **Web UI**: реализованы вручную 5 новых страниц:
  - `src/fossil/web/pages/file_page.nim` — file browser, history, content viewer (port of file.c, doc.c, finfo.c)
  - `src/fossil/web/pages/info_page.nim` — check-in info, manifest, file list, parent/child (port of info.c, event.c)
  - `src/fossil/web/pages/graph_page.nim` — commit graph visualization with JS + JSON (port of graph.c)
  - `src/fossil/web/pages/login_page.nim` — login/logout, session, user auth (port of login.c)
  - `src/fossil/web/pages/setup_page.nim` — admin setup, user management, config (port of setup.c)
  - `src/fossil/web/pages/assets.nim` — embedded CSS/JS (DefaultCss, TimelineJs, GraphJs, WysiwygJs, SearchJs)

- **Search**: расширен `search.nim`:
  - `indexFileContentsSqlite` — индекс содержимого файлов (skip binary, limit 50k)
  - `indexCommitsSqlite` — индекс коммитов (branch, user, comment)
  - `indexBranchesSqlite` — индекс веток (tag sym-*)
  - `reindexAllSqlite` — полный реиндекс, батч
  - API: `/api/v1/search/reindex`, `?kind=file,commit,wiki,ticket,forum`

- **Forum/Chat**: расширены:
  - Forum: `pinned`, `locked`, `deleted`, `edited`, `attachment`, `forum_moderation` table, `pinThread`, `lockThread`, `deleteThread`, `editPost`, `listPinnedThreads`, `searchForum`
  - Chat: `chat_room` (is_private), `chat_presence` (typing, status), `createRoom`, `listRooms`, `updatePresence`, `listPresence`, attachment, edited
  - Исправлен баг: индекс `chat_room` конфликтовал с таблицей `chat_room` → переименован в `idx_chat_message_room`, добавлен `DROP INDEX IF EXISTS chat_room`

- **Vendor/Migration**:
  - `cinterop/mdbx/mdbx.c` (1.7M) и `mdbx.h` уже вендорены
  - `cinterop/sqlite/sqlite3.c` (9.5M) вендорен
  - Migration batched: `migrateBatched(src, dst, batchSize=10000)` с транзакциями BEGIN/COMMIT каждые 10k, прогресс лог, CLI `--batch-size`

## Преимущества саб-агентов

- Параллельная работа над независимыми модулями
- Бесплатные модели (12 штук) без API ключа
- Каждый агент имеет свой контекст, не мешает основному
- Логи в `/tmp/opencode/*.log` для отладки
- Можно использовать разные модели для разных задач (deepseek для кода, glm для поиска, mimo для форума)

## Ограничения

- Песочница: CPU overload при 4 параллельных агентах → bash timeouts
- Permission: нужно `* allow` для записи вне `tool-output/`
- Free модели: ограниченный контекст (32k), медленнее коммерческих
- QBE compat: саб-агенты могут генерировать код с GNU расширениями → нужен patch_qbe.sh

## Дальнейшее развитие

- Добавить MCP сервер для opencode как tool provider
- Использовать opencode для генерации тестов (fuzz)
- Использовать opencode для документации RU/EN
- Интеграция с `fossil mcp serve --sse` для AI-ассистентов
