# TH1, Markdown, Wiki, Ticket - Implementation

## TH1 Interpreter (`src/fossil/th1/interp.nim`)

Fossil's TH1 is a Tcl-like language used for headers, footers, ticket pages, wiki templates.

### Features implemented

- Variables: `set var value`, `$var`, `${var}`
- Output: `puts`, `append`, `incr`
- Control: `if {cond} {then} ?else {else}?`, `foreach var list {body}`, `for {init} {cond} {next} {body}`, `while {cond} {body}`, `break`, `continue`
- Procedures: `proc name {args} {body}`, `return`
- Expressions: `expr $x * 2`, supports `+ - * / % == != > < >= <=`
- String: `string length`, `tolower`, `toupper`, `trim`, `first`
- HTML: `htmlize` / `html` escapes `& < > "`
- List: `list`, `llength`, `lindex`
- Bracket evaluation: `[command]` and `puts [double 21]`
- Comments: `#`

### Example

```th1
set greeting "Hello"
puts "$greeting, World!"
set x 10
if {$x > 5} {
  puts "x is big"
} else {
  puts "x is small"
}
foreach i {1 2 3} {
  puts "i=$i"
}
proc double {x} {
  expr $x * 2
}
puts [double 21]
```

CLI:

```bash
fossil th1 eval 'set x 10; puts "x=$x"'
fossil th1 script.th1 var1=value1
```

## Markdown Parser (`src/fossil/markdown/parser.nim`)

Fossil supports wiki markup, markdown, and plain text. We implement markdown subset compatible with Fossil's wiki.

### Supported

- Headers: `# H1` .. `###### H6`
- Paragraphs
- Inline: `**bold**`, `*italic*`, `_italic_`, `` `code` ``, `[link](url)`, `![alt](url)`
- Lists: `-`, `*`, `+` for ul, `1.` for ol
- Code blocks: ```` ```lang ... ``` ````
- Blockquote: `> quote`
- Horizontal rule: `---`, `***`, `___`
- Escaping HTML

CLI:

```bash
fossil markdown "# Hello **world**"
# <h1>Hello <strong>world</strong></h1>
fossil markdown README.md --html
```

API:

```nim
import fossil/markdown/parser
let html = markdownToHtml("# Hello **world**")
```

## Wiki (`src/fossil/wiki/wiki.nim`)

Wiki pages stored as artifacts, with format: markdown, wiki, html, th1.

### Features

- `listWikiPages`: list pages (from tag table or static)
- `getWikiPage`: get page content
- `saveWikiPage`: save as blob
- `renderWikiPage`: render with TH1 + Markdown
  - First processes `<th1>...</th1>` or `<?th1 ... ?>` blocks via TH1 interpreter
  - Then markdown to HTML
- `wikiPageToJson`: JSON with html field

TH1 in wiki:

```markdown
# My Page

<th1>
set user $login
puts "Hello, $user!"
</th1>

This is **markdown** after TH1.
```

CLI:

```bash
fossil wiki list
fossil wiki get Home
fossil wiki render Home
fossil wiki render "# Test **bold**"
fossil wiki create MyPage content.md
```

## Ticket (`src/fossil/ticket/ticket.nim`)

Ticket system with markdown, TH1, comments.

### Types

- `TicketStatus`: open, closed, fixed, verified
- `TicketComment`: id, ticketId, user, date, content, format
- `Ticket`: id, title, description, status, type, priority, owner, reporter, created, modified, uuid, rid, comments, tags

### Features

- `listTickets`: list with status filter
- `getTicket`: get ticket
- `createTicket`: create
- `updateTicket`: update fields
- `addComment`: add comment
- `renderTicket`: markdown to HTML for description + comments
- `ticketToJson`: JSON with html
- `renderTicketWithTh1`: TH1 template + ticket

Markdown in tickets:

```markdown
# Bug report

**Steps to reproduce**

1. Do X
2. See error

```
Error log
```
```

CLI:

```bash
fossil ticket list
fossil ticket list open
fossil ticket get 123
fossil ticket create "Bug title" "Description"
fossil ticket comment 123 "This is a comment"
```

## Integration with API and MCP

- API: `/api/v1/wiki/list`, `/api/v1/wiki/get?name=Home`, `/api/v1/ticket/list` could be added (currently via MCP tools)
- MCP tools: `fossil_wiki_list`, `fossil_wiki_get`, `fossil_wiki_create`, `fossil_ticket_list`, etc. already use markdown rendering
- REST HTML index shows wiki/ticket endpoints

## Testing

```bash
./bin/fossil markdown "# Hello **world**"
# <h1>Hello <strong>world</strong></h1>

./bin/fossil th1 eval 'set x 10; puts "x=$x"; expr $x * 2'
# x=10
# 20

./bin/fossil wiki render "# Test **bold**"
# <h1># Test <strong>bold</strong></h1> (or <h1>Test <strong>bold</strong></h1>)

./bin/fossil ticket list
# 0 [open] Sample ticket 0
```

## Future work

- Full Fossil wiki syntax (links, attachments)
- TH1: add `query`, `artifact`, `anon` commands that Fossil uses
- Ticket: schema-driven fields (like Fossil's ticket table config)
- Store wiki/ticket as real artifacts with manifest parsing
