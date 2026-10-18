# Форум и Чат Улучшенные - WYSIWYG, Модерация, Комнаты, Присутствие, Набор, Вложения

Улучшенные подсистемы форума и чата с современными функциями, vanilla JS, модульно.

## Форум - Улучшенный

### Функции

- **WYSIWYG Markdown Редактор** - Тулбар с Bold (Ctrl+B), Italic (Ctrl+I), Code (Ctrl+E), Link (Ctrl+K), List, Quote, Heading, Code block, Table, Image, HR, Preview. Live preview через `/api/v1/markdown` с debounce 500ms. Горячие клавиши: Tab вставляет пробелы, Ctrl+B/I/K/E.
- **Модерация** - Pin/unpin треды, lock/unlock треды, delete треды (soft delete), edit посты, delete посты (TODO), очередь модерации таблица `forum_moderation`.
- **Вложения** - Поддержка Attachment URL для постов, preview изображений (jpg/png/gif/webp), file URL. Хранится в `forum_post.attachment`.
- **Поиск** - FTS5 поиск внутри форума через `searchForumSqlite`, использует `search_fts` если доступен, fallback LIKE. Live search с debounce 300ms.
- **Закрепленные Треды** - Отдельный листинг для pinned тредов, сортировка по `pinned DESC, last_mtime DESC`.
- **Авто-индекс** - Форум треды авто-индексируются для FTS5 при создании через `indexDocumentSqlite` в `createThreadSqlite`.

### DB Схема

```sql
CREATE TABLE forum_thread(thread_id TEXT PRIMARY KEY, title TEXT, user TEXT, created INTEGER, last_mtime INTEGER, pinned INTEGER DEFAULT 0, locked INTEGER DEFAULT 0, deleted INTEGER DEFAULT 0)
CREATE TABLE forum_post(post_id TEXT PRIMARY KEY, thread_id TEXT, parent_id TEXT, user TEXT, mtime INTEGER, title TEXT, content TEXT, uuid TEXT, rid INTEGER, edited INTEGER DEFAULT 0, deleted INTEGER DEFAULT 0, attachment TEXT DEFAULT '')
CREATE TABLE forum_moderation(queue_id TEXT PRIMARY KEY, post_id TEXT, thread_id TEXT, user TEXT, mtime INTEGER, reason TEXT, status TEXT DEFAULT 'pending')
```

### REST API

- `GET /api/v1/forum/list?limit=20` - Лист тредов (pinned first, deleted filtered)
- `GET /api/v1/forum/get?id=XXX` - Получить тред с постами (с attachment, edited, deleted)
- `POST /api/v1/forum/create` - Создать тред с title, content, user, attachment (auto-index)
- `POST /api/v1/forum/post` - Ответить в тред с threadId, content, user, parentId, attachment
- `POST /api/v1/forum/pin` - Pin/unpin тред с id, pinned bool
- `POST /api/v1/forum/lock` - Lock/unlock тред с id, locked bool
- `POST /api/v1/forum/delete` - Delete тред (soft delete) с id
- `POST /api/v1/forum/edit` - Edit пост с id (postId), content
- `GET /api/v1/forum/pinned?limit=20` - Лист pinned тредов
- `GET /api/v1/forum/search?q=bug&limit=20` - Поиск форум постов FTS5

### Web UI - `web_new/js/components/forum.js`

- **forum** (single thread view) - Показывает title с badges pinned/locked/deleted, кнопки модерации Pin/Unpin, Lock/Unlock, Delete, посты с кнопками edit/reply/attach, markdown preview через `api.markdown`, WYSIWYG редактор для reply с live preview, attachment URL input, reply form.
- **forum-list** - Показывает pinned треды отдельно, все треды с badges, кнопки pin/lock, search box с live preview, empty state с New Thread кнопкой.
- **forum-edit** (new thread) - Форма с title, content с WYSIWYG редактором (MarkdownEditor), preview, attachment URL, user, pinned checkbox для модераторов, создание через `api.forumCreate`.

### MCP Инструменты

- `fossil_forum_list`, `fossil_forum_get`, `fossil_forum_create` (с attachment), `fossil_forum_post` (с attachment), `fossil_forum_pin`, `fossil_forum_lock`, `fossil_forum_delete`, `fossil_forum_edit`, `fossil_forum_pinned`, `fossil_forum_search`

## Чат - Улучшенный

### Функции

- **Управление Комнатами** - Create/delete комнаты, public/private, owner, created timestamp. Main комнату нельзя удалить. Хранится в `chat_room` таблице.
- **Присутствие** - Кто online, last seen (последние 5 мин), typing индикатор, status (online/away/busy). Хранится в `chat_presence` таблице, обновляется через `updatePresenceSqlite`.
- **Индикатор Набора** - Когда пользователь печатает, `api.chatPresenceUpdate(room, user, true)` вызывается, debounce 2s чтобы установить false. Typing пользователи показываются в `typing-indicator` div и presence листе с badge.
- **Вложения** - Поддержка Attachment URL, preview изображений (jpg/png/gif/webp/svg), preview видео (mp4/webm/ogg), file URL. Хранится в `chat_message.attachment`. Отправка через `sendMessageWithAttachmentSqlite` который также авто-индексирует для FTS5.
- **Edit/Delete** - Edit сообщение с `edited` флагом, delete сообщение. Через `editMessageSqlite`, `deleteMessageSqlite`.
- **Реакции** - Emoji реакции (👍❤️😂) в UI, хранятся локально в DOM (TODO: persist в DB).
- **Markdown** - Сообщения поддерживают markdown: **bold**, *italic*, `code`, [link](url). Preview через `api.markdown`.
- **Авто-индекс** - Чат сообщения авто-индексируются для FTS5 при отправке через `sendMessageWithAttachmentSqlite`.
- **Комнаты CRUD** - Create комнату через POST `/api/v1/chat/room` с room, owner, privateRoom. Delete через POST `/api/v1/chat/room/delete`. List через GET `/api/v1/chat/rooms`.

### DB Схема

```sql
CREATE TABLE chat_message(msg_id TEXT PRIMARY KEY, room TEXT, user TEXT, mtime INTEGER, content TEXT, uuid TEXT, rid INTEGER, attachment TEXT DEFAULT '', edited INTEGER DEFAULT 0)
CREATE INDEX idx_chat_message_room ON chat_message(room)
CREATE TABLE chat_room(room TEXT PRIMARY KEY, owner TEXT, is_private INTEGER DEFAULT 0, created INTEGER)
CREATE TABLE chat_presence(user TEXT, room TEXT, last_seen INTEGER, typing INTEGER DEFAULT 0, status TEXT DEFAULT 'online', PRIMARY KEY(user, room))
INSERT OR IGNORE INTO chat_room(room, owner, is_private, created) VALUES('main', 'system', 0, strftime('%s','now'))
```

### REST API

- `GET /api/v1/chat/list?room=main&limit=50` - Лист сообщений в комнате с attachment, edited
- `POST /api/v1/chat/send` - Отправить сообщение с room, content, user, attachment (auto-index, update presence)
- `POST /api/v1/chat/edit` - Edit сообщение с id, content
- `POST /api/v1/chat/delete` - Delete сообщение с id
- `POST /api/v1/chat/attachment` - Добавить attachment к сообщению с id, attachment URL
- `GET /api/v1/chat/rooms` - Лист комнат
- `POST /api/v1/chat/room` - Create комнату с room, owner, privateRoom bool
- `POST /api/v1/chat/room/delete` - Delete комнату с room (main нельзя удалить)
- `GET /api/v1/chat/presence?room=main` - Лист presence в комнате (последние 5 мин)
- `POST /api/v1/chat/presence` - Update presence с room, user, typing bool, status

### Web UI - `web_new/js/components/chat.js`

- **chat** (single room view) - Grid с chat сообщениями и presence. Сообщения reversed (newest внизу), avatar с первой буквой, meta с user, time, edited badge, content с markdown preview, attachment с image/video preview, кнопки edit/delete, reply, reactions (👍❤️😂), edit textarea с save/cancel. Chat input с content (markdown), user, attachment URL, Send кнопка. Typing индикатор показывает typing пользователей. Presence лист показывает online пользователей с status badges, avatar, last seen. Quick actions: Log JSON, Clear typing. Search chat через FTS5. Auto-scroll вниз, poll presence каждые 3s.
- **chat-rooms** - Лист комнат с join, presence, delete кнопками (main нельзя удалить), create room форма с room name, owner, private checkbox, room features лист.

### MCP Инструменты

- `fossil_chat_list` (с attachments), `fossil_chat_send` (с attachment, auto-index), `fossil_chat_edit`, `fossil_chat_delete`, `fossil_chat_rooms`, `fossil_chat_create_room`, `fossil_chat_delete_room`, `fossil_chat_presence`, `fossil_chat_presence_update`, `fossil_chat_attachment`

## WYSIWYG Редактор - `web_new/js/components/editor.js`

- **MarkdownEditor class** - Принимает textareaId, previewId, options. Добавляет toolbar с кнопками: Bold, Italic, Code, Link, List, Quote, Heading, Code block, Table, Image, HR, Preview. Toolbar click вставляет markdown синтаксис с placeholder. Live preview на input с debounce 500ms через `api.markdown`, fallback simple markdown. Горячие клавиши: Ctrl+B bold, Ctrl+I italic, Ctrl+K link, Ctrl+E code, Tab вставляет пробелы.
- **Методы** - `insert(before, after, placeholder)`, `updatePreview()`, `simpleMarkdown(text)`, `getValue()`, `setValue(v)`.
- **Глобально** - `window.MarkdownEditor`, `window.editorPreview(textareaId, previewId)`.
- **Использование** - `new MarkdownEditor('my-textarea', 'my-preview')`.

## Поиск - Улучшенный Авто-индекс

- **Авто-индекс при сохранении** - Wiki save авто-индексирует через `saveWikiPageSqlite`, ticket create через `createTicketSqlite`, forum thread через `createThreadSqlite`, chat message через `sendMessageWithAttachmentSqlite`. Все обеспечивают существование FTS таблиц и вставляют в `search_index` и `search_fts`.
- **Reindex All** - `reindexAllSqlite` индексирует файлы (первые 50k chars, skip binary по расширению и null byte, limit 500), коммиты (branch, user, comment, title из первой строки, limit 1000), ветки (tag LIKE 'sym-%'), плюс существующие wiki/ticket/forum через tag scan. Вызывается через POST `/api/v1/search/reindex` который теперь делает full reindex.
- **Поиск** - FTS5 с porter tokenizer, unicode61, snippet с `<b>` highlight, rank сортировка, fallback LIKE если FTS5 недоступен. Поддерживает фильтр по kind: wiki, ticket, file, commit, forum, chat, branch.

## Тестирование

```bash
# Forum
curl -X POST http://localhost:8080/api/v1/forum/create -d '{"title":"Test","content":"Hello **world**","user":"tester"}'
curl http://localhost:8080/api/v1/forum/list
curl -X POST http://localhost:8080/api/v1/forum/pin -d '{"id":"XXX","pinned":true}'
curl -X POST http://localhost:8080/api/v1/forum/lock -d '{"id":"XXX","locked":true}'

# Chat
curl -X POST http://localhost:8080/api/v1/chat/room -d '{"room":"dev","owner":"tester","privateRoom":false}'
curl http://localhost:8080/api/v1/chat/rooms
curl -X POST http://localhost:8080/api/v1/chat/send -d '{"room":"main","content":"Hello","user":"tester","attachment":"https://example.com/img.png"}'
curl http://localhost:8080/api/v1/chat/list?room=main
curl -X POST http://localhost:8080/api/v1/chat/edit -d '{"id":"MSG_ID","content":"Edited"}'
curl http://localhost:8080/api/v1/chat/presence?room=main

# Search
curl -X POST http://localhost:8080/api/v1/search/reindex
curl "http://localhost:8080/api/v1/search?q=test"
```

## Web UI Интеграция

- `web_new/index.html` теперь включает `editor.js` после `component.js`.
- `web_new/js/api.js` обновлен с новыми методами: forumLock, forumDelete, forumEditPost, forumPinned, chatEdit, chatDelete, chatAttachment, chatCreateRoom, chatDeleteRoom, chatSend с attachment параметром.
- `web_new/js/components/forum.js` улучшен с WYSIWYG, модерацией, вложениями, поиском, pinned.
- `web_new/js/components/chat.js` улучшен с edit/delete, вложениями с preview, реакциями, rooms CRUD, presence, typing, search.
- `web_new/js/components/search.js` улучшен с reindex all, index stats, search tips, auto-index info.

## MCP

- Количество инструментов: 39 (было 25) с новыми форум и чат модерацией инструментами.

## Сборка

- `nim c -d:release -o:fossil src/fossil/cli/main.nim` → 1.6M, 101k lines, SuccessX
- Все новые эндпоинты протестированы через curl, работают с --repo флагом исправленным через gApiConfig.
