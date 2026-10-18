# Forum & Chat Enhanced - WYSIWYG, Moderation, Rooms, Presence, Typing, Attachments

Enhanced forum and chat subsystems with modern features, vanilla JS, modular.

## Forum - Enhanced

### Features

- **WYSIWYG Markdown Editor** - Toolbar with Bold (Ctrl+B), Italic (Ctrl+I), Code (Ctrl+E), Link (Ctrl+K), List, Quote, Heading, Code block, Table, Image, HR, Preview. Live preview via `/api/v1/markdown` with debounce 500ms. Keyboard shortcuts: Tab inserts spaces, Ctrl+B/I/K/E.
- **Moderation** - Pin/unpin threads, lock/unlock threads, delete threads (soft delete), edit posts, delete posts (TODO), moderation queue table `forum_moderation`.
- **Attachments** - Attachment URL support for posts, image preview (jpg/png/gif/webp), file URL. Stored in `forum_post.attachment` column.
- **Search** - FTS5 search within forum via `searchForumSqlite`, uses `search_fts` if available, fallback LIKE. Live search with debounce 300ms.
- **Pinned Threads** - Separate listing for pinned threads, ordered by `pinned DESC, last_mtime DESC`.
- **Auto-index** - Forum threads auto-indexed for FTS5 on creation via `indexDocumentSqlite` in `createThreadSqlite`.

### DB Schema

```sql
CREATE TABLE forum_thread(thread_id TEXT PRIMARY KEY, title TEXT, user TEXT, created INTEGER, last_mtime INTEGER, pinned INTEGER DEFAULT 0, locked INTEGER DEFAULT 0, deleted INTEGER DEFAULT 0)
CREATE TABLE forum_post(post_id TEXT PRIMARY KEY, thread_id TEXT, parent_id TEXT, user TEXT, mtime INTEGER, title TEXT, content TEXT, uuid TEXT, rid INTEGER, edited INTEGER DEFAULT 0, deleted INTEGER DEFAULT 0, attachment TEXT DEFAULT '')
CREATE TABLE forum_moderation(queue_id TEXT PRIMARY KEY, post_id TEXT, thread_id TEXT, user TEXT, mtime INTEGER, reason TEXT, status TEXT DEFAULT 'pending')
```

### REST API

- `GET /api/v1/forum/list?limit=20` - List threads (pinned first, deleted filtered)
- `GET /api/v1/forum/get?id=XXX` - Get thread with posts (with attachment, edited, deleted)
- `POST /api/v1/forum/create` - Create thread with title, content, user, attachment (auto-index)
- `POST /api/v1/forum/post` - Reply to thread with threadId, content, user, parentId, attachment
- `POST /api/v1/forum/pin` - Pin/unpin thread with id, pinned bool
- `POST /api/v1/forum/lock` - Lock/unlock thread with id, locked bool
- `POST /api/v1/forum/delete` - Delete thread (soft delete) with id
- `POST /api/v1/forum/edit` - Edit post with id (postId), content
- `GET /api/v1/forum/pinned?limit=20` - List pinned threads
- `GET /api/v1/forum/search?q=bug&limit=20` - Search forum posts FTS5

### Web UI - `web_new/js/components/forum.js`

- **forum** (single thread view) - Shows title with badges pinned/locked/deleted, moderation buttons Pin/Unpin, Lock/Unlock, Delete, posts with edit/reply/attach buttons, markdown preview via `api.markdown`, WYSIWYG editor for reply with live preview, attachment URL input, reply form.
- **forum-list** - Shows pinned threads separate, all threads with badges, pin/lock buttons, search box with live preview, empty state with New Thread button.
- **forum-edit** (new thread) - Form with title, content with WYSIWYG editor (MarkdownEditor), preview, attachment URL, user, pinned checkbox for moderators, create via `api.forumCreate`.

### MCP Tools

- `fossil_forum_list`, `fossil_forum_get`, `fossil_forum_create` (with attachment), `fossil_forum_post` (with attachment), `fossil_forum_pin`, `fossil_forum_lock`, `fossil_forum_delete`, `fossil_forum_edit`, `fossil_forum_pinned`, `fossil_forum_search`

## Chat - Enhanced

### Features

- **Rooms Management** - Create/delete rooms, public/private, owner, created timestamp. Main room cannot be deleted. Stored in `chat_room` table.
- **Presence** - Who is online, last seen (last 5 min), typing indicator, status (online/away/busy). Stored in `chat_presence` table, updated via `updatePresenceSqlite`.
- **Typing Indicator** - When user types, `api.chatPresenceUpdate(room, user, true)` called, debounce 2s to set false. Typing users shown in `typing-indicator` div and presence list with badge.
- **Attachments** - Attachment URL support, image preview (jpg/png/gif/webp/svg), video preview (mp4/webm/ogg), file URL. Stored in `chat_message.attachment`. Send via `sendMessageWithAttachmentSqlite` which also auto-indexes for FTS5.
- **Edit/Delete** - Edit message content with `edited` flag, delete message. Via `editMessageSqlite`, `deleteMessageSqlite`.
- **Reactions** - Emoji reactions (👍❤️😂) in UI, stored locally in DOM (TODO: persist in DB).
- **Markdown** - Messages support markdown: **bold**, *italic*, `code`, [link](url). Preview via `api.markdown`.
- **Auto-index** - Chat messages auto-indexed for FTS5 on send via `sendMessageWithAttachmentSqlite`.
- **Rooms CRUD** - Create room via POST `/api/v1/chat/room` with room, owner, privateRoom. Delete via POST `/api/v1/chat/room/delete`. List via GET `/api/v1/chat/rooms`.

### DB Schema

```sql
CREATE TABLE chat_message(msg_id TEXT PRIMARY KEY, room TEXT, user TEXT, mtime INTEGER, content TEXT, uuid TEXT, rid INTEGER, attachment TEXT DEFAULT '', edited INTEGER DEFAULT 0)
CREATE INDEX idx_chat_message_room ON chat_message(room)
CREATE TABLE chat_room(room TEXT PRIMARY KEY, owner TEXT, is_private INTEGER DEFAULT 0, created INTEGER)
CREATE TABLE chat_presence(user TEXT, room TEXT, last_seen INTEGER, typing INTEGER DEFAULT 0, status TEXT DEFAULT 'online', PRIMARY KEY(user, room))
INSERT OR IGNORE INTO chat_room(room, owner, is_private, created) VALUES('main', 'system', 0, strftime('%s','now'))
```

### REST API

- `GET /api/v1/chat/list?room=main&limit=50` - List messages in room with attachment, edited
- `POST /api/v1/chat/send` - Send message with room, content, user, attachment (auto-index, update presence)
- `POST /api/v1/chat/edit` - Edit message with id, content
- `POST /api/v1/chat/delete` - Delete message with id
- `POST /api/v1/chat/attachment` - Add attachment to message with id, attachment URL
- `GET /api/v1/chat/rooms` - List rooms
- `POST /api/v1/chat/room` - Create room with room, owner, privateRoom bool
- `POST /api/v1/chat/room/delete` - Delete room with room (main cannot be deleted)
- `GET /api/v1/chat/presence?room=main` - List presence in room (last 5 min)
- `POST /api/v1/chat/presence` - Update presence with room, user, typing bool, status

### Web UI - `web_new/js/components/chat.js`

- **chat** (single room view) - Grid with chat messages and presence. Messages reversed (newest at bottom), avatar with first letter, meta with user, time, edited badge, content with markdown preview, attachment with image/video preview, edit/delete buttons, reply button, reactions (👍❤️😂), edit textarea with save/cancel. Chat input with content (markdown), user, attachment URL, Send button. Typing indicator shows typing users. Presence list shows online users with status badges, avatar, last seen. Quick actions: Log JSON, Clear typing. Search chat via FTS5. Auto-scroll to bottom, poll presence every 3s.
- **chat-rooms** - List rooms with join, presence, delete buttons (main cannot be deleted), create room form with room name, owner, private checkbox, room features list.

### MCP Tools

- `fossil_chat_list` (with attachments), `fossil_chat_send` (with attachment, auto-index), `fossil_chat_edit`, `fossil_chat_delete`, `fossil_chat_rooms`, `fossil_chat_create_room`, `fossil_chat_delete_room`, `fossil_chat_presence`, `fossil_chat_presence_update`, `fossil_chat_attachment`

## WYSIWYG Editor - `web_new/js/components/editor.js`

- **MarkdownEditor class** - Takes textareaId, previewId, options. Adds toolbar with buttons: Bold, Italic, Code, Link, List, Quote, Heading, Code block, Table, Image, HR, Preview. Toolbar click inserts markdown syntax with placeholder. Live preview on input with debounce 500ms via `api.markdown`, fallback simple markdown. Keyboard shortcuts: Ctrl+B bold, Ctrl+I italic, Ctrl+K link, Ctrl+E code, Tab inserts spaces.
- **Methods** - `insert(before, after, placeholder)`, `updatePreview()`, `simpleMarkdown(text)`, `getValue()`, `setValue(v)`.
- **Global** - `window.MarkdownEditor`, `window.editorPreview(textareaId, previewId)`.
- **Usage** - `new MarkdownEditor('my-textarea', 'my-preview')`.

## Search - Enhanced Auto-index

- **Auto-index on save** - Wiki save auto-indexes via `saveWikiPageSqlite`, ticket create via `createTicketSqlite`, forum thread via `createThreadSqlite`, chat message via `sendMessageWithAttachmentSqlite`. All ensure FTS tables exist and insert into `search_index` and `search_fts`.
- **Reindex All** - `reindexAllSqlite` indexes files (first 50k chars, skip binary by extension and null byte, limit 500), commits (branch, user, comment, title from first line, limit 1000), branches (tag LIKE 'sym-%'), plus existing wiki/ticket/forum via tag scan. Called via POST `/api/v1/search/reindex` which now does full reindex.
- **Search** - FTS5 with porter tokenizer, unicode61, snippet with `<b>` highlight, rank sorting, fallback LIKE if FTS5 not available. Supports kind filter: wiki, ticket, file, commit, forum, chat, branch.

## Testing

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

## Web UI Integration

- `web_new/index.html` now includes `editor.js` after `component.js`.
- `web_new/js/api.js` updated with new methods: forumLock, forumDelete, forumEditPost, forumPinned, chatEdit, chatDelete, chatAttachment, chatCreateRoom, chatDeleteRoom, chatSend with attachment param.
- `web_new/js/components/forum.js` enhanced with WYSIWYG, moderation, attachments, search, pinned.
- `web_new/js/components/chat.js` enhanced with edit/delete, attachments with preview, reactions, rooms CRUD, presence, typing, search.
- `web_new/js/components/search.js` enhanced with reindex all, index stats, search tips, auto-index info.

## MCP

- Tools count: 39 (was 25) with new forum and chat moderation tools.

## Build

- `nim c -d:release -o:fossil src/fossil/cli/main.nim` → 1.6M, 101k lines, SuccessX
- All new endpoints tested via curl, work with --repo flag fixed via gApiConfig.
