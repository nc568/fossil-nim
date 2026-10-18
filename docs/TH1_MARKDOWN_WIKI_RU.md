# TH1, Markdown, Wiki, Ticket - Реализация (RU)

## TH1 Интерпретатор (`src/fossil/th1/interp.nim`)

Fossil's TH1 - Tcl-подобный язык для хедеров, футеров, тикетов, wiki.

### Возможности

- Переменные: `set var value`, `$var`, `${var}`
- Вывод: `puts`, `append`, `incr`
- Управление: `if {cond} {then} ?else {else}?`, `foreach var list {body}`, `for {init} {cond} {next} {body}`, `while {cond} {body}`, `break`, `continue`
- Процедуры: `proc name {args} {body}`, `return`
- Выражения: `expr $x * 2` с `+ - * / % == != > < >= <=`
- Строки: `string length`, `tolower`, `toupper`, `trim`, `first`
- HTML: `htmlize` / `html` экранирует `& < > "`
- Списки: `list`, `llength`, `lindex`
- Вычисление в скобках: `[command]`
- Комментарии: `#`

Пример:

```th1
set greeting "Hello"
puts "$greeting, World!"
set x 10
if {$x > 5} { puts "x is big" } else { puts "x is small" }
foreach i {1 2 3} { puts "i=$i" }
proc double {x} { expr $x * 2 }
puts [double 21]
```

CLI: `fossil th1 eval 'set x 10; puts "x=$x"'`, `fossil th1 script.th1 var=val`

## Markdown Парсер (`src/fossil/markdown/parser.nim`)

Подмножество markdown совместимое с Fossil wiki.

Поддерживает:
- Заголовки `#` .. `######`
- Параграфы
- Inline: `**bold**`, `*italic*`, `` `code` ``, `[link](url)`, `![alt](url)`
- Списки: `-`, `*`, `+` для ul, `1.` для ol
- Код блоки: ``` ```lang ... ``` ```
- Цитаты: `> quote`
- Разделитель: `---`
- Экранирование HTML

CLI: `fossil markdown "# Hello **world**"` -> `<h1>Hello <strong>world</strong></h1>`

## Wiki (`src/fossil/wiki/wiki.nim`)

Wiki страницы как артефакты, форматы markdown/wiki/html/th1.

- `listWikiPages`, `getWikiPage`, `saveWikiPage`, `renderWikiPage` (TH1 + Markdown), `wikiPageToJson`
- Поддержка `<th1>...</th1>` и `<?th1 ... ?>` внутри wiki
- Сначала обрабатывает TH1 блоки через интерпретатор, потом markdown в HTML

Пример TH1 в wiki:

```markdown
# My Page
<th1>
set user $login
puts "Hello, $user!"
</th1>
This is **markdown**.
```

CLI: `fossil wiki list`, `fossil wiki get Home`, `fossil wiki render "# Test **bold**"`, `fossil wiki create Page file.md`

## Ticket (`src/fossil/ticket/ticket.nim`)

Тикеты с markdown, TH1, комментариями.

Типы: `TicketStatus` open/closed/fixed/verified, `TicketComment`, `Ticket` с tags.

- `listTickets`, `getTicket`, `createTicket`, `updateTicket`, `addComment`, `renderTicket`, `ticketToJson`, `renderTicketWithTh1`
- Markdown в описании и комментариях

CLI: `fossil ticket list`, `fossil ticket get 123`, `fossil ticket create "Title" "Desc"`, `fossil ticket comment 123 "text"`

## Интеграция

- API: через MCP tools `fossil_wiki_list`, `fossil_wiki_get`, `fossil_ticket_list` и т.д. уже используют markdown
- REST: можно добавить `/api/v1/wiki/list` и т.д.
- HTML индекс показывает wiki/ticket

## Тесты

```bash
./bin/fossil markdown "# Hello **world**"
./bin/fossil th1 eval 'set x 10; puts "x=$x"; expr $x * 2'
./bin/fossil wiki render "# Test **bold**"
./bin/fossil ticket list
```
