# Foccil DB

[English](../en/README.md) · [Вики](wiki/Home.ru.md)

SQL-движок на **Nim (ARC)** — замена SQLite для проекта **Foccil-nim**. Не порт:
легаси вырезано, рантайм минимален, один исходник собирается в **C, JavaScript и
WebAssembly** без расхождений в поведении.

```
Строк ядра          4 492      SQLite: ~150 000
Тестов              44 (26 функциональных + 20 по безопасности)
Цели                C (gcc/clang) · JS (node) · wasm32 · cproc/QBE (в работе)
Размер wasm         328 КБ     SQLite wasm: ~1.2 МБ
```

## Состояние

| Область | Состояние |
|---|---|
| DDL, DML, SELECT (join, group by, having, order, limit, distinct, подзапросы, CTE, представления, union) | ✅ |
| Ограничения: PK, UNIQUE, NOT NULL, CHECK, DEFAULT, метаданные FK | ✅ |
| Строгая типизация (без молчаливых приведений) | ✅ |
| Транзакции с полным откатом (журнал DML + снимок каталога для DDL) | ✅ |
| Вторичные индексы + планировщик равенства | ✅ |
| Подготовленные выражения, параметры, кэш | ✅ |
| Тесты безопасности (инъекции, лимиты, фаззинг, статическая проверка) | ✅ 20/20 |
| Паритет C ↔ JS байт в байт | ✅ |
| wasm32 + мост | ✅ |
| cproc/QBE | ⚠️ блокер в апстриме — см. [portability](portability.md) |
| Хранилище на диске (pager, WAL, B+tree) | ⏳ v0.2 (сейчас движок в памяти) |
| FTS, JSON, оконные функции, триггеры | ⏳ v0.3–v0.5 |

## Быстрый старт

```nim
import foccil/db/api

let db = openMemory()
discard db.execute("CREATE TABLE user (id INTEGER PRIMARY KEY, nick TEXT UNIQUE, score INT)")
discard db.execute("INSERT INTO user (nick, score) VALUES (?, ?)",
                   toParams([textValue("ann"), intValue(90)]))

let rows = db.execute("SELECT nick, score FROM user WHERE score > ? ORDER BY score DESC",
                      toParams([intValue(50)])).rows
echo rows[0].asText(0), " ", rows[0].asInt(1)
```

```sh
sh tools/bootstrap.sh     # Nim + qbe + cproc + musl + zig в ~/.cache/tc
sh tools/test.sh          # гейт: ядро, безопасность, профили, JS-паритет, wasm, cproc
nim c -r -d:release --mm:arc tools/bench.nim
```

## Чем отличается от SQLite

1. **Проваливается закрыто.** Нет `ATTACH`, `load_extension`, `VACUUM INTO` — трёх
   исторических путей «SQL дотянулся до файловой системы». Неизвестные функции
   отвергаются на этапе подготовки.
2. **Строгая типизация.** `'abc'` в колонку `INTEGER` — ошибка, а не тихая смена типа.
3. **Только параметры.** В API нет функции, склеивающей значение в текст запроса.
4. **Лимиты в ядре.** Бюджет строк, глубина вложенности и защита парсера — часть движка.
5. **Один AST — три бэкенда.** Нет таблицы опкодов, нет расхождений между бэкендами
   (проверяется дайджестом).
6. **Нет GC.** ARC даёт детерминированное разрушение: без пауз и без сюрпризов по памяти
   на встраиваемом устройстве.

## Структура репозитория

```
src/foccil/db/        ядро: values, tokenizer, parser, ast, schema, funcs, engine, api
src/foccil/wasm/      мост для wasm + panicoverride
tests/                t_core, t_security, t_portable (паритет бэкендов)
tools/                bootstrap, гейт тестов, сборка wasm и cproc, бенчмарк
docs/en, docs/ru      архитектура, план, безопасность, портируемость, исследование
docs/wiki             страницы вики (RU + EN)
NOTES-git.md          замечания и вопросы по git-инфраструктуре проекта
```
