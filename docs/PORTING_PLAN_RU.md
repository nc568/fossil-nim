# План полного портирования Fossil на Nim

## Область

Портируется **только ядро Fossil**, а не SQLite, zlib, OpenSSL. Они остаются C-библиотеками, подключаемыми через `importc` Nim.

Оригинальная кодовая база Fossil:
- ~180 C файлов, ~200k строк без SQLite, ~800k с амальгамой SQLite
- Плюс TH1 (мини Tcl), Markdown и т.д.

Портируем по фазам.

## Фаза 1: Фундамент (Готово - каркас)

- [x] `types.nim` - Blob, Rid, Uuid, Result
- [x] `config.nim` - глобальная конфигурация, env
- [x] `storage/backend.nim` - интерфейс концепта
- [x] `storage/sqlite_backend.nim` - референсный бэкенд
- [x] `storage/libmdbx/lmdb/cdb` - альтернативные бэкенды
- [x] `delta/delta.nim` - формат дельт
- [x] `artifact/manifest.nim` - парсинг манифестов
- [x] `utils/hash.nim` - SHA3/SHA1
- [x] `cli/main.nim` - диспетчер CLI
- [x] `mcp/*` - MCP сервер
- [x] `api/rest.nim` - REST API
- [x] Документация

## Фаза 2: Ядро VCS (В процессе)

Нужно портировать:

- `checkout.nim` - сейчас заглушка, нужно реализовать:
  - Чтение checkout БД (таблица vvar)
  - Материализация файлов из цепочки дельт
  - Обработка бит исполняемости, симлинков
  - Оригинал C: `checkout.c` ~3000 строк

- `commit.nim` - частично, нужно:
  - Сканирование рабочего дерева, построение манифеста
  - Вычисление дельты относительно родителя
  - Вставка в хранилище
  - Оригинал: `commit.c` ~2500 строк

- `branch.nim` - базово готово, нужна полная обработка тегов

- `timeline.nim` - базово готово, нужен запрос к таблице event

- `diff.nim` - сделан простой LCS, нужен алгоритм Myers как в оригинальном `diff.c`

- `merge.nim` - сделана заглушка 3-way, нужен полный merge с маркерами конфликтов

- `stash.nim` - TODO

- `blame.nim` - TODO: аннотация

- `clean.nim`, `add.nim`, `rm.nim` - TODO

## Фаза 3: Протокол синхронизации

- `sync/protocol.nim` - протокол синхронизации Fossil
  - Оригинал: `xfer.c`, `http.c`, `http_transport.c` ~5000 строк
  - Нужно реализовать парсинг карт: `cookie`, `file`, `gimme`, `igot` и т.д.
  - HTTP клиент/сервер

- `sync/http.nim` - транспорт

## Фаза 4: Веб UI

- `web/server.nim` - базовый HTTP сервер готов
- `web/router.nim` - TODO: замапить все страницы Fossil
- `web/pages/timeline.nim`, `info.nim`, `wiki.nim`, `ticket.nim` и т.д.
- `web/th1.nim` - интерпретатор TH1 (мини Tcl) - 2000 строк C -> Nim
- `web/markdown.nim` - рендерер Markdown

Оригинальный Fossil имеет ~50 веб-страниц, каждая ~500 строк C, генерирующая HTML через `cgi_printf`.

В Nim-порте генерируем HTML через DSL, а не через C printf.

## Фаза 5: Подсистемы

- `wiki/wiki.nim` - базово готово, нужно полностью
- `ticket/ticket.nim` - базово готово, нужен парсинг формата тикетов TH1
- `forum/forum.nim` - TODO: форум - недавняя фича Fossil, использует markdown + треды
- `chat/chat.nim` - TODO

## Фаза 6: Укрепление бэкендов хранения

- Реализовать итерацию курсором для libmdbx/lmdb (сейчас `getAllRids` возвращает пусто)
- Реализовать правильный писатель CDB с хеш-таблицами (сейчас заглушка)
- Написать инструмент миграции `rebuild`, конвертирующий sqlite -> libmdbx и т.д.
- Набор бенчмарков

## Фаза 7: QBE / cproc

- Готово: шим `qbe_nimbase.h`
- Готово: `config.nims` с флагами qbeCompat
- Готово: цель `Makefile` qbe
- TODO: реально протестировать с cproc, исправить проблемы сгенерированного C (удаление атрибутов через sed сделано, но нужно проверить)
- TODO: вендорить sqlite3.c и mdbx.c, чистые для cproc

## Фаза 8: Укрепление API и MCP

- API: реализовать OpenAPI спек, аутентификацию, пагинацию
- MCP: реализовать все обработчики инструментов с реальной логикой (сейчас многие возвращают заглушки)
- MCP: добавить ресурсы для содержимого файлов, wiki, тикетов
- MCP: добавить промпты для генерации сообщений коммитов и т.д.

## Фаза 9: Тестирование

- `tests/test_delta.nim` - roundtrip против оригинального бинаря fossil (нужен бинарь fossil)
- `tests/test_manifest.nim` - парсит все манифесты из репозитория fossil
- `tests/test_storage.nim` - одинаковая нагрузка на всех бэкендах
- `tests/test_sync.nim` - синхронизация двух репо
- `tests/test_mcp.nim` - соответствие JSON-RPC

## Фаза 10: Документация и релиз

- Завершить документацию на английском + русском
- Написать руководство по миграции с C fossil на Nim fossil
- Сравнение производительности
- Релиз бинаря

## Стиль кода для совместимости с QBE

- Никаких исключений на горячем пути, использовать `Result`
- Никаких closure итераторов, использовать `seq` или inline итераторы
- Никакого `async` в ядре VCS, только в веб/api/mcp серверах
- Использовать `{.push stackTrace: off.}` в горячих модулях когда `qbeCompat`
- Избегать `std/re` (использует PCRE), использовать `parseutils` или простые операции со строками
- Избегать `std/json` в ядре? Это нормально, но для QBE используем минимальный парсер json

## Стратегия C интеропа

Все C библиотеки обернуты в `db/c_interop.nim` или на бэкенд:

```nim
{.push header: "<sqlite3.h>".}
type sqlite3 {.importc, incompleteStruct.} = object
proc sqlite3_open(...) {.importc.}
{.pop.}
```

Для вендорных:

```nim
{.compile: "cinterop/sqlite/sqlite3.c".}
```

Это компилирует C файл вместе с C, сгенерированным Nim, так что cproc видит один большой C файл.

## Задачи Nimble

- `nimble build` - обычно
- `nimble buildQbe` - только генерация C
- `nimble mcp` - сборка отдельного MCP
- `nimble test` - запуск тестов

## Оценка LOC

- Оригинальное ядро Fossil (без SQLite): ~200k C
- Nim порт: оценка ~40k Nim (Nim более выразителен)
  - types/config: 1k
  - storage: 5k
  - delta: 1k
  - artifact: 3k
  - vcs: 10k
  - sync: 5k
  - web: 10k
  - wiki/ticket/forum: 5k
  - api/mcp/cli: 5k

Сейчас каркас ~5k Nim, нужно еще ~35k.

## Как внести вклад

1. Выберите модуль из Фазы 2-5
2. Прочитайте оригинальный C файл с https://fossil-scm.org/home/file?ci=trunk&name=src/<module>.c
3. Портируйте на Nim, сохраняя тот же алгоритм, но используя идиомы Nim + Result
4. Напишите тест в `tests/`
5. Убедитесь, что `nim c -d:qbeCompat --compileOnly` все еще работает (без GCC атрибутов)

## Ссылки

- Доки Fossil: https://fossil-scm.org/home/doc/trunk/www/fileformat.wiki
- Формат дельты Fossil: https://fossil-scm.org/home/doc/trunk/www/delta_format.wiki
- Доки LMDB: https://lmdb.readthedocs.io/
- Доки libmdbx: https://libmdbx.dqdkfa.ru/
- Спека CDB: https://cr.yp.to/cdb/cdb.txt
- QBE: https://c9x.me/compile/
- cproc: https://git.sr.ht/~mcf/cproc
- Спека MCP: https://spec.modelcontextprotocol.io/
