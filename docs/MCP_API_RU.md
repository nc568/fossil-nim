# MCP Сервер - Fossil Nim

Model Context Protocol (MCP) - открытый протокол для взаимодействия AI-агентов с инструментами. Fossil-Nim реализует полный MCP сервер.

## Запуск

```bash
./bin/fossil mcp serve
# режим stdio (для Claude Desktop и т.д.)
./bin/fossil mcp serve --stdio

# отдельный бинарь
./bin/fossil-mcp
```

## Транспорт

- **stdio**: JSON-RPC 2.0 поверх stdin/stdout, построчно
- **sse**: Server-Sent Events поверх HTTP (для удаленных агентов)
- **http**: Streamable HTTP (новый спек MCP)

## Инициализация

Клиент отправляет:
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "2024-11-05",
    "capabilities": {},
    "clientInfo": {"name": "claude", "version": "1.0"}
  }
}
```

Сервер отвечает capabilities: tools, resources, prompts.

## Инструменты

Все инструменты определены в `src/fossil/mcp/tools.nim` с JSON Schema.

### VCS Инструменты

| Инструмент | Описание | Вход |
|------------|----------|------|
| `fossil_status` | Статус рабочего дерева | `{repoPath?: string}` |
| `fossil_diff` | Diff рабочего vs репо или rev vs rev | `{rev1?: string, rev2?: string, file?: string}` |
| `fossil_commit` | Коммит изменений | `{message: string, files?: string[], branch?: string}` |
| `fossil_log` | История файла | `{file: string, limit?: int}` |
| `fossil_timeline` | Таймлайн | `{limit?: int, branch?: string, since?: string}` |
| `fossil_branch_list` | Список веток | `{}` |
| `fossil_branch_create` | Создать ветку | `{name: string, base?: string}` |
| `fossil_checkout` | Checkout ревизии | `{rev: string}` |
| `fossil_blame` | Аннотация файла | `{file: string, rev?: string}` |
| `fossil_stash_list` | Список стэшей | `{}` |
| `fossil_stash_save` | Сохранить стэш | `{message?: string}` |
| `fossil_info` | Инфо об артефакте | `{uuid: string}` |

### Wiki Инструменты

| Инструмент | Описание |
|------------|----------|
| `fossil_wiki_list` | Список wiki страниц |
| `fossil_wiki_get` | Получить содержимое страницы |
| `fossil_wiki_create` | Создать/редактировать страницу |

### Ticket Инструменты

| Инструмент | Описание |
|------------|----------|
| `fossil_ticket_list` | Список тикетов с фильтром |
| `fossil_ticket_get` | Получить детали тикета |
| `fossil_ticket_create` | Создать тикет |
| `fossil_ticket_update` | Обновить статус тикета |

### Продвинутые

| Инструмент | Описание |
|------------|----------|
| `fossil_sql` | Read-only SQL запрос (безопасный) |
| `fossil_artifact_get` | Получить сырой артефакт по uuid |
| `fossil_rebuild` | Пересобрать репо с другим бэкендом |
| `fossil_sync` | Синхронизация с удаленным |

### Пример: вызов инструмента

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "fossil_status",
    "arguments": {"repoPath": "/home/user/myrepo"}
  }
}
```

Ответ:
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "content": [{"type": "text", "text": "M file.nim\n? untracked.txt\n"}],
    "isError": false
  }
}
```

## Ресурсы

MCP Resources предоставляют данные Fossil как читаемые URI:

- `fossil://timeline?limit=100` - таймлайн как JSON
- `fossil://wiki/{pagename}` - wiki страница markdown
- `fossil://ticket/{id}` - тикет JSON
- `fossil://file/{path}@{rev}` - содержимое файла в ревизии
- `fossil://branch/{name}/timeline` - таймлайн ветки
- `fossil://config` - конфиг fossil

Список:
```json
{"jsonrpc":"2.0","id":3,"method":"resources/list","params":{}}
```

Чтение:
```json
{"jsonrpc":"2.0","id":4,"method":"resources/read","params":{"uri":"fossil://wiki/Home"}}
```

## Промпты

Предопределенные промпты для общих workflow:

- `commit-message` - сгенерировать сообщение коммита из diff
- `code-review` - ревью изменений в чекине
- `bisect` - помочь с bisect бага
- `release-notes` - сгенерировать release notes из таймлайна

## Безопасность

- `fossil_sql` только для чтения, заблокированные стейтменты: INSERT, UPDATE, DELETE, DROP и т.д. Использует authorizer sqlite3 или read-only txn mdbx.
- Доступ к файлам ограничен корнем репо + корнем checkout.
- `fossil_sync` требует явного разрешения в конфиге.
- MCP сервер работает с теми же правами, что и пользователь.

## Примеры интеграции

### Claude Desktop

`claude_desktop_config.json`:
```json
{
  "mcpServers": {
    "fossil": {
      "command": "/home/user/fossil-nim/bin/fossil-mcp",
      "args": ["--repo", "/home/user/myproject"]
    }
  }
}
```

## Детали реализации

`src/fossil/mcp/server.nim`:

- Использует `std/json` для JSON-RPC
- Не нужен async для stdio режима (блокирующее чтение строки)
- Для SSE/HTTP режима использует `asynchttpserver`
- Инструменты регистрируются через `proc registerTool(name, schema, handler)`

Каждый обработчик инструментов вызывает библиотечные функции `fossil/vcs/*`, а не CLI.

Обработка ошибок: инструмент возвращает `isError: true` с текстом, содержащим `FossilError.msg`.
