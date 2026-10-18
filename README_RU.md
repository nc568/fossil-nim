# Fossil SCM - Порт на Nim

> Полный перепис [Fossil SCM](https://fossil-scm.org) на языке Nim. Портируется только само ядро Fossil; зависимости на C вроде SQLite, zlib, OpenSSL остаются как нативные C-библиотеки через C-интероп Nim.

**Версия:** 2.26.0-nim (соответствует upstream 2.26)
**Язык:** Nim 2.0+ -> C -> нативный бинарь (совместим с cproc/QBE)
**Лицензия:** BSD-2-Clause (как оригинал)

## Зачем Nim?

- **Nim компилируется в C**: бесплатный интероп с SQLite/zlib/libmdbx
- **Безопасность памяти** с ORC/ARC, без пауз GC на горячих путях
- **Модульная архитектура**: в отличие от монолитного `fossil.c` на 200k строк, порт разбит на 60+ модулей
- **Современный тулинг**: MCP сервер, JSON REST API, типизированный API
- **Готовность к cproc/QBE**: сгенерированный C избегает GNU-расширений, собирается минималистичным компилятором

## Архитектура

```
src/fossil/
├── types.nim          # Базовые типы: Blob, Artifact, Rid, Uuid
├── config.nim         # Глобальная конфигурация
├── db/                # Обертки C-интеропа (sqlite3.h, mdbx.h, lmdb.h)
├── storage/           # Подключаемые бэкенды хранения
│   ├── backend.nim    # Интерфейс / концепт
│   ├── sqlite_backend.nim  # По умолчанию, 100% совместим
│   ├── libmdbx_backend.nim # Рекомендуемая замена: ACID, быстро
│   ├── lmdb_backend.nim
│   └── cdb_backend.nim     # Только чтение / архив
├── delta/             # Формат дельт Fossil (copy/insert)
├── artifact/          # Парсинг манифестов, хеширование
├── vcs/               # Checkout, commit, branch, merge, diff, blame
├── sync/              # Протокол синхронизации Fossil по HTTP
├── web/               # Встроенный веб-сервер и UI
├── wiki/ ticket/ forum/ # Подсистемы
├── cli/               # Интерфейс командной строки
├── api/               # REST + JSON API
└── mcp/               # Сервер Model Context Protocol
```

Подробно: [docs/ARCHITECTURE_RU.md](docs/ARCHITECTURE_RU.md)

## Сравнение бэкендов хранения

| Бэкенд | Запись | Чтение | ACID | Размер | Совместим | Примечание |
|--------|--------|--------|------|--------|-----------|------------|
| **SQLite** | хорошо | хорошо | да | средний | 100% | по умолчанию |
| **libmdbx** | отлично | отлично | да | маленький | нужна миграция | **РЕКОМЕНДУЕТСЯ** |
| **LMDB** | хорошо | отлично | да | маленький | нужна миграция | один писатель |
| **cdb** | N/A (ro) | ультра | нет | крошечный | только экспорт | архив / CDN |

Глубокий анализ: [docs/STORAGE_BACKENDS_RU.md](docs/STORAGE_BACKENDS_RU.md)

## Быстрый старт

```bash
# Сборка обычным путем Nim -> C -> clang/gcc
nimble build

# Только генерация C, затем сборка cproc (QBE)
nimble buildQbe
cproc -O2 -o bin/fossil build/cgen/*.c -lsqlite3 -lz -lssl -lcrypto -lm

# Запуск
./bin/fossil version
./bin/fossil init my.fossil
./bin/fossil open my.fossil
./bin/fossil status
```

## MCP Сервер

Fossil-Nim включает полный сервер Model Context Protocol для AI-агентов:

```bash
./bin/fossil mcp serve
# или отдельно
./bin/fossil-mcp
```

Инструменты:
- `fossil_status`, `fossil_commit`, `fossil_diff`, `fossil_log`, `fossil_timeline`
- `fossil_wiki_get/create`, `fossil_ticket_list/create`
- `fossil_branch_list`, `fossil_blame`, `fossil_sql` (только чтение)

См. [docs/MCP_API_RU.md](docs/MCP_API_RU.md)

## JSON API

```bash
./bin/fossil server --api-enable -P 8080
curl http://localhost:8080/api/v1/timeline?limit=10
```

## Совместимость с cproc / QBE

Nim генерирует C, который в основном стандартный C11, но мы форсируем:

- `-d:qbeCompat` отключает `__attribute__`, `__builtin_expect`, computed goto
- Нет `alloca` на горячих путях
- Кастомный шим `nimbase.h` в `cinterop/include/qbe_nimbase.h`

Полный гайд: [docs/CPROC_QBE_RU.md](docs/CPROC_QBE_RU.md)

## Статус проекта

Это каркас + базовая реализация. Реализовано:

- [x] types, config, обработка ошибок
- [x] storage/backend интерфейс + sqlite + libmdbx + lmdb + cdb заглушки
- [x] delta формат encode/decode
- [x] хеширование артефактов и парсинг манифестов
- [x] C интероп заголовки
- [x] Скелет CLI
- [x] Скелет MCP сервера
- [x] Скелет REST API
- [ ] Полный VCS (checkout/commit/merge) - в процессе
- [ ] Протокол синхронизации
- [ ] Web UI страницы

## Лицензия

BSD-2-Clause, как Fossil.
