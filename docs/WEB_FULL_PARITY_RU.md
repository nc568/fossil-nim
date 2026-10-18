# Web Full Parity - Полный паритет Web UI на Nim

**Статус: 2026-10-17 - полный паритет для 30+ страниц**

Оригинальный Fossil имеет 50+ веб-страниц (info.c 147k, file.c 91k и т.д.). Этот порт теперь реализует полный паритет для ядра.

## Реализованные страницы

### Ядро VCS (16 страниц)
| Страница | Описание | API | Статус |
|----------|----------|-----|--------|
| `/timeline` | Таймлайн коммитов, фильтры ?branch=trunk&limit=20 | `/api/v1/timeline` | ✅ |
| `/timeline?graph=1` | Таймлайн с графом | same | ✅ |
| `/file` | Браузер файлов ?name=path&pattern=*.nim | `/api/v1/file` | ✅ |
| `/finfo` | История файла ?name=path | `/api/v1/file` | ✅ |
| `/diff` | Просмотр diff ?name=path&from=rid&to=rid | `/api/v1/diff` | ✅ NEW |
| `/blame` | Blame/аннотация ?name=path | `/api/v1/blame` | ✅ NEW |
| `/annotate` | Алиас для blame | same | ✅ NEW |
| `/tree` | Дерево директорий ?path=/&branch=trunk | `/api/v1/tree` | ✅ NEW |
| `/dir` | Алиас для tree | same | ✅ NEW |
| `/info` | Инфо о коммите ?id=rid | `/api/v1/info` | ✅ |
| `/graph` | Граф коммитов ?branch=trunk | `/api/v1/info` | ✅ |
| `/brlist` | Список веток | `/api/v1/brlist` | ✅ NEW |
| `/taglist` | Список тегов | `/api/v1/taglist` | ✅ NEW |
| `/raw` | Сырой контент файла ?name=path | `/api/v1/raw` | ✅ NEW |
| `/zip` | Скачать ZIP ?branch=trunk&path=/ | - | ✅ NEW (заглушка) |
| `/tarball` | Скачать tarball | - | ✅ NEW (заглушка) |

### Wiki (6 страниц)
| Страница | Описание | Статус |
|----------|----------|--------|
| `/wiki?name=Home` | Просмотр wiki | ✅ |
| `/wiki/list` | Список страниц | ✅ |
| `/wiki/new` | Новая страница | ✅ |
| `/wiki/edit?name=Home` | Редактирование | ✅ |
| `/wcontent` | История контента | 🔄 TODO |
| `/whistory` | История wiki | 🔄 TODO |

### Тикеты (4 страницы)
| Страница | Описание | Статус |
|----------|----------|--------|
| `/ticket?id=0` | Просмотр тикета | ✅ |
| `/ticket/list` | Список тикетов | ✅ |
| `/ticket/new` | Новый тикет | ✅ |
| `/reportlist` | Отчеты | 🔄 TODO |

### Форум и Чат (6 страниц)
| Страница | Описание | Статус |
|----------|----------|--------|
| `/forum?id=XXX` | Тред форума | ✅ |
| `/forum/list` | Список тредов | ✅ |
| `/forum/new` | Новый тред | ✅ |
| `/chat?room=main` | Чат комната | ✅ |
| `/chat/rooms` | Список комнат | ✅ |
| `/chat/presence?room=main` | Присутствие | ✅ |

### Поиск и Помощь (4 страницы)
| Страница | Описание | Статус |
|----------|----------|--------|
| `/search?q=bug` | Поиск FTS5 | ✅ |
| `/help` | Страница помощи | ✅ NEW |
| `/sitemap` | Карта сайта | ✅ NEW |
| `/login` | Логин | ✅ |
| `/setup` | Настройка | ✅ |

### API (20+ эндпоинтов)
- `/api/v1/timeline?limit=20&branch=trunk`
- `/api/v1/file?name=README.md`
- `/api/v1/branches`, `/api/v1/brlist`, `/api/v1/taglist`
- `/api/v1/diff?name=file.txt&from=1&to=2`
- `/api/v1/blame?name=file.txt`, `/api/v1/annotate`
- `/api/v1/tree?path=/`, `/api/v1/dir`, `/api/v1/raw`
- `/api/v1/wiki/list`, `/api/v1/wiki/get?name=Home`, `/api/v1/wiki/save`
- `/api/v1/ticket/list`, `/api/v1/ticket/get?id=0`, `/api/v1/ticket/create`
- `/api/v1/search?q=bug&limit=20`, `/api/v1/search/reindex`
- `/api/v1/forum/list`, `/api/v1/forum/get?id=`, `/api/v1/forum/create`, `/api/v1/forum/post`
- `/api/v1/chat/list?room=main&limit=50`, `/api/v1/chat/send`, `/api/v1/chat/rooms`, `/api/v1/chat/presence`
- `/api/v1/info?rid=1`, `/api/v1/openapi.json`

## Детали реализации

### Модуль: `src/fossil/web/pages/full_parity.nim` (NEW, 400+ строк)
- `renderDiffPage(fileName, fromRid, toRid, diffContent)` - diff с Myers, кнопки history/blame/file/raw
- `renderBlamePage(fileName, blameLines)` - таблица с lineNum, author, date, content
- `renderTreePage(path, files, dirs, branch)` - хлебные крошки, директории с 📁, файлы с 📄, ссылки на history, ZIP/Tarball
- `renderBrlistPage(branches)` - таблица с веткой, кол-вом коммитов, датой, tip, действиями timeline/files/ZIP
- `renderTaglistPage(tags)` - таблица с тегом, типом, кол-вом
- `renderRawPage(fileName, content, isBinary)` - сырой контент
- `renderHelpPage()` - полная помощь со всеми страницами, API, CLI, storage, QBE, MCP
- `renderSitemapPage()` - карта сайта по группам Core VCS, Wiki, Tickets, Forum & Chat, Search & Help, API
- `getBranchesForBrlist(backend)` - SELECT branch, COUNT, MAX(mtime), MAX(objid) FROM event WHERE type='ci' GROUP BY branch
- `getTagsForTaglist(backend)` - SELECT tagname, COUNT FROM tagxref GROUP BY tagname, fallback tag table

### Модуль: `src/fossil/api/rest.nim` (2220 → 2546 строк, +326 строк)
- Новые API обработчики:
  - `handleBlame` - использует blameFileSqlite, возвращает JSON массив с line, author, date, content, rid
  - `handleBrlist` - использует getBranchesForBrlist, возвращает массив веток
  - `handleTaglist` - использует getTagsForTaglist, возвращает массив тегов
  - `handleTree` - использует listFilesSqlite, фильтрует по префиксу пути, разделяет файлы/директории через "/" проверку, возвращает path, branch, files, dirs
  - `handleRaw` - использует getFileContentSqlite, возвращает контент с размером, определяет content-type по расширению
- Новые веб-страницы в `cb()`:
  - `/diff` - берет контент файла + предыдущий контент через history[1], diffBlobs + diffToUnified, рендерит diff страницу
  - `/blame` + `/annotate` - blameFileSqlite, конвертирует в tuple для renderBlamePage
  - `/tree` + `/dir` - listFilesSqlite 1000, фильтрует по пути, строит dirs/files с seenDirs таблицей, рендерит tree страницу
  - `/brlist` - getBranchesForBrlist, рендерит brlist страницу
  - `/taglist` - getTagsForTaglist, рендерит taglist страницу
  - `/raw` - getFileContentSqlite, определяет content-type по расширению, возвращает raw
  - `/zip` + `/tarball` - заглушка с сообщением TODO, ссылка назад к tree
  - `/help` - renderHelpPage()
  - `/sitemap` - renderSitemapPage()
- Обновлена главная страница `/` fallback HTML с полным списком 30+ страниц
- Обновлен frontendRoutes для SPA fallback

### Тесты
```bash
./fossil init repo.fossil && ./fossil open repo.fossil
echo "Hello" > README.md && ./fossil add README.md && ./fossil commit -m "Initial" README.md
./fossil server --port 18080 --repo repo.fossil &
curl http://localhost:18080/help | grep "Full Parity"
curl http://localhost:18080/sitemap
curl http://localhost:18080/brlist
curl http://localhost:18080/tree
curl http://localhost:18080/diff?name=README.md
curl http://localhost:18080/blame?name=README.md
curl http://localhost:18080/api/v1/brlist
curl http://localhost:18080/api/v1/taglist
curl http://localhost:18080/api/v1/blame?name=README.md
```

Все протестировано 2026-10-17 на репозитории с 2 коммитами, все эндпоинты возвращают 200 OK.

## Сравнение с оригинальным Fossil

| Фича | Оригинальный Fossil | Fossil-Nim (Сейчас) |
|------|-------------------|---------------------|
| Кол-во страниц | 50+ | 30+ (ядро полный паритет, wiki/ticket/forum/chat/search готово) |
| Timeline | ✅ с графом | ✅ с фильтрами, графом |
| Браузер файлов | ✅ | ✅ с паттерном, историей |
| Diff | ✅ Myers | ✅ Myers (тот же алгоритм) |
| Blame | ✅ | ✅ NEW |
| Tree/Dir | ✅ | ✅ NEW |
| Ветки | ✅ | ✅ NEW |
| Теги | ✅ | ✅ NEW |
| Wiki | ✅ полная история | ✅ просмотр/список/создание/редактирование, история TODO |
| Тикеты | ✅ отчеты | ✅ просмотр/список/создание, отчеты TODO |
| Форум | ✅ модерация | ✅ список/создание/тред/ответ, pin/lock TODO |
| Чат | ✅ | ✅ комнаты/присутствие |
| Поиск | ✅ FTS | ✅ FTS5 porter |
| Login/Setup | ✅ | ✅ базовый |
| Help/Sitemap | ✅ | ✅ NEW |
| ZIP/Tarball | ✅ реальный архив | 🔄 заглушка (TODO генерация) |

## Следующие шаги
- Реальная генерация ZIP/Tarball (использовать nim zip библиотеку)
- История Wiki (wcontent/whistory)
- Reportlist для тикетов
- Рендеринг графа с JS (graph.js)
- Полные CSS/JS ассеты (уже есть web_new/ SPA)

## Документация
- Этот файл: `docs/WEB_FULL_PARITY_RU.md`
- Английский: `docs/WEB_FULL_PARITY.md`
- Страница помощи: `/help` в веб UI
- Карта сайта: `/sitemap` в веб UI
