# Бэкенды хранения - Глубокий анализ

Изначально Fossil жестко кодирует SQLite как единственное хранилище. Этот порт абстрагирует хранилище за концептом `StorageBackend`.

## 1. Зачем заменять SQLite?

SQLite отличный, но не оптимален для нагрузки Fossil:

- Fossil хранит **контент-адресуемые блобы** (артефакты) по ключу SHA3. Это чистый KV workload, а не реляционный.
- SQLite использует B-Tree + WAL + rollback journal = лишние накладные расходы.
- Конкурентность SQLite: один писатель, много читателей, записи сериализуются через `sqlite3_busy_timeout`.
- Таблица `blob` может расти до 10GB+, много случайных чтений для цепочек дельт.
- `VACUUM` дорогой.

KV-хранилища вроде LMDB/libmdbx - это **memory-mapped B+Tree**, zero-copy чтения, ультра-быстро, идеально для хранилища артефактов.

## 2. Интерфейс

```nim
type FossilError* = object
  code*: int
  msg*: string

type Rid* = distinct int64
type Uuid* = distinct string
type Blob* = object
  data*: string

type StorageBackend* = concept b
  proc open(b: var Self, path: string): Result[void, FossilError]
  proc close(b: var Self)
  proc getBlob(b: Self, rid: Rid): Result[Blob, FossilError]
  proc getBlobByUuid(b: Self, uuid: Uuid): Result[Blob, FossilError]
  proc putBlob(b: var Self, uuid: Uuid, data: Blob, isDelta: bool): Result[Rid, FossilError]
  proc hasUuid(b: Self, uuid: Uuid): bool
  proc getAllRids(b: Self): seq[Rid]
  proc beginTxn(b: var Self)
  proc commitTxn(b: var Self): Result[void, FossilError]
  proc rollbackTxn(b: var Self)
```

Все бэкенды реализуют одинаковую схему на логическом уровне, но физическое расположение отличается.

## 3. SQLite бэкенд (по умолчанию, 100% совместим)

- Использует C-библиотеку `sqlite3` через importc.
- Схема идентична upstream Fossil: таблицы `blob`, `delta`, `event`, `tag`, `mlink`, `filename` и т.д.
- Плюсы: полностью совместим, может открыть любой `.fossil` файл, созданный C fossil.
- Минусы: те же, что у оригинала.

Реализация: `src/fossil/storage/sqlite_backend.nim` оборачивает `sqlite3_prepare_v2`, `sqlite3_bind_*`, `sqlite3_step`.

Для QBE: линкует `-lsqlite3` динамически или статически.

## 4. libmdbx бэкенд (РЕКОМЕНДУЕТСЯ)

**libmdbx** - форк LMDB от Ершова, с улучшениями:
- Авто-рост, авто-компакция
- Лучшее восстановление после краша
- Append режим для быстрой массовой вставки
- GC, который не деградирует

### Разметка

Окружение с 3 DBI:

- `artifacts`: ключ = uuid (64-байтная строка) или rid (int64 big-endian), значение = blob данные + флаги (сжат? дельта? размер).
  Лучше два DBI:
  - `uuid_to_rid`: `uuid (string) -> rid (int64)`
  - `rid_to_blob`: `rid (int64 BE) -> blob (bytes)` где blob = заголовок (1 байт флаги) + данные

- `meta`: ключ = строка, значение = строка/int. Хранит `next_rid`, `schema_version`, `project_code` и т.д.

- `links`: ключ = child rid, значение = parent rid список (для DAG).

### Производительность

- Чтения: zero-copy через `mdbx_get`, возвращающий указатель в mmap. Никакого `memcpy`, если не нужно декомпрессировать.
- Записи: батчами в транзакции. `MDBX_APPEND` для последовательной вставки rid.
- Конкурентность: MVCC, читатели никогда не блокируют писателей, писатели сериальны, но быстры (без WAL).

### Миграция

`fossil rebuild --backend libmdbx old.fossil new.fossil` будет итерироваться по sqlite таблице `blob`, упорядоченной по rid, и вставлять в mdbx.

### Почему не LMDB?

LMDB имеет узкое место одного писателя + фиксированный размер карты (надо предопределять). libmdbx авто-растет и имеет лучшую производительность.

## 5. LMDB бэкенд

Аналогичен libmdbx, но использует оригинальный LMDB API.

- Плюсы: широко доступен, стабилен, меньше кода.
- Минусы: ошибки `MDB_MAP_FULL`, если размер карты слишком мал, более медленный GC.

Оставляем как опцию для систем, где libmdbx недоступен.

## 6. CDB бэкенд (Constant Database)

CDB Даниэля Бернштейна: иммутабельная двухфайловая хеш-таблица, экстремально быстрые чтения, крошечный код.

- Кейс: **архив / CDN дистрибуция**. Вы строите `.cdb` файл из fossil репо, затем раздаете через dumb HTTP. Нет записей после создания.
- Разметка: ключ = uuid, значение = blob. Все. Нет транзакций.
- Для timeline/tags мы встраиваем вторичный индекс как отдельный cdb или как JSON блоб.

Плюсы:
- 4KB кода, без зависимостей
- O(1) lookup
- Идеально для `fossil export` на статический хостинг

Минусы:
- Только чтение, без ACID, пересборка всего файла при изменении.

## 7. Гибридный режим

Fossil нужны и repository DB и checkout DB.

- Repository DB: может быть любым бэкендом (sqlite/libmdbx/lmdb/cdb ro)
- Checkout DB: всегда sqlite? В этом порте checkout DB тоже подключаемая, но по умолчанию sqlite для совместимости.

Также поддерживаем **split**: репо в libmdbx, checkout в sqlite (или даже JSON для отладки).

## 8. Бенчмарки (ожидаемые)

Для 1M артефактов, 10GB репо, случайное чтение:

- SQLite: ~15k чтений/сек, 2.1ms среднее
- LMDB: ~120k чтений/сек, 0.2ms (zero-copy)
- libmdbx: ~150k чтений/сек, 0.15ms
- CDB: ~300k чтений/сек, 0.05ms (но холодный)

Запись (массовый импорт 100k артефактов):

- SQLite (WAL): ~3k записей/сек
- LMDB: ~8k записей/сек
- libmdbx (append): ~20k записей/сек

## 9. Выбор бэкенда

- **Новый проект, производительность**: libmdbx
- **Нужна 100% совместимость с C fossil**: sqlite
- **Встроенный / без зависимостей**: lmdb
- **Статический сайт / архив**: cdb
- **Эксперимент**: можно иметь репо в libmdbx, но экспортировать в cdb для дистрибуции.

## 10. Шаги реализации

1. Реализовать `backend.nim` концепт + хелперы `Result`
2. Реализовать `sqlite_backend.nim` первым (референс)
3. Написать `tests/test_storage.nim`, который гоняет одинаковый набор тестов на всех бэкендах
4. Реализовать `libmdbx_backend.nim`, пройти тесты
5. Реализовать `lmdb_backend.nim`
6. Реализовать `cdb_backend.nim`
7. Написать команду `fossil rebuild`, которая может конвертировать между бэкендами.

## 11. Детали C интеропа

Для каждого бэкенда вендорим минимальный C заголовок и линкуем:

- sqlite3: `-lsqlite3` или компиляция `sqlite3.c` амальгамы
- libmdbx: компиляция `mdbx.c` (один файл) или линковка `-lmdbx`
- lmdb: компиляция `mdb.c` + `midl.c` или линковка `-llmdb`
- cdb: компиляция `cdb.c` (public domain, ~500 LOC)

Все обернуто через `{.compile: "mdbx.c".}` или `{.passL: "-lmdbx".}` в зависимости от флага `-d:vendored`.

Для QBE: предпочитаем статическую компиляцию, потому что cproc может не иметь пути поиска динамической линковки. Так что `cinterop/mdbx/mdbx.c` компилируется вместе.

## 12. Безопасность

- Все бэкенды используют `Result`, а не исключения.
- Memory-mapped данные: копируем из транзакции до закрытия транзакции, если вызывающий не использует шаблон `withTxn`, который держит транзакцию живой.
- Для libmdbx/lmdb обрабатываем `MDBX_MAP_FULL` авто-ресайзом (libmdbx делает авто, lmdb удваиваем размер карты).
