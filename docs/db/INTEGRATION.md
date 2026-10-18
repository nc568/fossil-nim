# Foccil DB — интеграция в fossil-nim / integration

Короткая памятка: что добавлено, где лежит, как проверять.
A short memo: what was added, where it lives, how to verify.

---

## Что это / What this is

Переписанный с нуля встраиваемый SQL-движок на Nim (ARC), без легаси SQLite:
токенайзер, парсер, планировщик равенства, tree-walking исполнитель, транзакции,
индексы, строгая типизация. Один исходник компилируется в C, в plain JS и в wasm32.

A from-scratch embedded SQL engine in Nim (ARC): tokenizer, parser, equality
planner, tree-walking executor, transactions, indexes, strict typing. One source
compiles to C, to plain JS and to wasm32.

| / | |
|---|---|
| Ядро / core | 4 492 строки против ~150 000 у SQLite |
| Тесты / tests | 26 функциональных + 20 безопасности |
| Паритет C ↔ JS | байт в байт, md5 `0376a7c4c0dfd8cf602e8fcff9dddb40` |
| wasm | 328 770 байт, работает под Node |
| Точечный поиск | 185 842 q/s (56 до планировщика индексов) |

## Где лежит / Where it lives

```
src/fossil/db/        движок (api.nim — единственная точка входа)
src/fossil/wasm/      мост wasm: 6 экспортов, протокол TSV
tests/db/             t_core, t_security, t_portable
tools/db/             test.sh, bootstrap.sh, bench.nim, wasm/, cproc/
docs/db/{ru,en}/      архитектура, безопасность, портируемость, план
docs/db/wiki/         Home + Home.ru
examples/db_quickstart.nim
```

Импорт: `import fossil/db/api` — совпадает с тем, что уже использует
`src/fossil/storage/backend.nim`, поэтому бэкенд можно подменить без переписывания
вызывающего кода.

## Как прогнать / How to run

```sh
nim c -r --path:src examples/db_quickstart.nim      # демо
nim c -r --path:src tests/db/t_core.nim             # 26 тестов
nim c -r --path:src tests/db/t_security.nim         # 20 тестов безопасности
sh tools/db/bootstrap.sh                            # тулчейн в ~/.cache/tc
sh tools/db/test.sh                                 # полный гейт (6 стадий)
```

`sh tools/db/test.sh` — единственная точка входа: core → security →
minimal-float профиль → паритет native/JS → wasm smoke → гейт cproc/QBE.

## Важные отличия от SQLite / Deliberate differences

Отсутствуют **по замыслу**, а не по недоделке:

* `ATTACH` — второй файл в одном соединении это второй вектор атаки;
* `load_extension` — загрузка нативного кода из SQL;
* `VACUUM INTO` — SQL не должен уметь писать файлы (будет `backupTo()` в API);
* гибкая типизация по умолчанию — включается явно, ценой документированной потери данных.

Неизвестная функция — ошибка на этапе подготовки, а не `NULL` в результате.

## Что дальше / Next

`docs/db/{ru,en}/plan.md`, а живой трекер — проект **Foccil DB** в Linear:
v0.2 (VFS, pager, WAL, B+tree, crash-recovery, шифрование страниц) →
v0.3 (стоимостный планировщик) → v0.4 (FTS, JSON, окна, DECIMAL) →
v0.5 (wasm без wasi-libc, < 150 КБ) + закрытие блокеров cproc/QBE.
