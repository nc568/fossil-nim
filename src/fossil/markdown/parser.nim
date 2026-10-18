## Markdown parser - Fossil compatible subset
## Supports: headers, paragraphs, bold, italic, code, code blocks, links, images, lists, blockquote, hr, tables (basic)

import std/[strutils, sequtils]

type
  MdOptions* = object
    safeMode*: bool
    enableTables*: bool

proc escapeHtml(s: string): string =
  result = s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;").replace("'", "&#39;")

proc sanitizeUrl*(rawUrl: string): string =
  let trimmed = rawUrl.strip()
  var clean = ""
  for c in trimmed:
    if ord(c) >= 32 and ord(c) != 127:
      clean.add c
  let lower = clean.toLowerAscii()
  var noSpace = ""
  for c in lower:
    if not c.isSpaceAscii():
      noSpace.add c
  if noSpace.startsWith("javascript:") or noSpace.startsWith("vbscript:") or
     noSpace.startsWith("data:") or noSpace.startsWith("file:"):
    return "#unsafe-link"
  let colonPos = lower.find(':')
  if colonPos != -1:
    let slashPos = lower.find('/')
    let queryPos = lower.find('?')
    let hashPos = lower.find('#')
    var firstSep = int.high
    if slashPos != -1 and slashPos < firstSep: firstSep = slashPos
    if queryPos != -1 and queryPos < firstSep: firstSep = queryPos
    if hashPos != -1 and hashPos < firstSep: firstSep = hashPos
    if colonPos < firstSep:
      let scheme = lower[0..<colonPos]
      if scheme notin ["http", "https", "mailto", "ftp", "irc"]:
        return "#unsafe-link"
  escapeHtml(clean)

proc parseInline*(text: string): string {.gcsafe.} =
  ## Inline parsing: **bold**, *italic*, `code`, [link](url), ![alt](url)
  var res = ""
  var i=0
  while i<text.len:
    if text[i]=='`':
      let j = text.find('`', i+1)
      if j != -1:
        res.add "<code>" & escapeHtml(text[i+1..<j]) & "</code>"
        i=j+1
      else:
        res.add escapeHtml($text[i]); inc i
    elif i+1<text.len and text[i]=='*' and text[i+1]=='*':
      let j = text.find("**", i+2)
      if j != -1:
        res.add "<strong>" & parseInline(text[i+2..<j]) & "</strong>"
        i=j+2
      else:
        res.add escapeHtml($text[i]); inc i
    elif text[i]=='*' or text[i]=='_':
      let ch = text[i]
      let j = text.find($ch, i+1)
      if j != -1 and j>i+1:
        res.add "<em>" & parseInline(text[i+1..<j]) & "</em>"
        i=j+1
      else:
        res.add escapeHtml($text[i]); inc i
    elif text[i]=='!' and i+1<text.len and text[i+1]=='[':
      # ![alt](url)
      let altEnd = text.find(']', i+2)
      if altEnd != -1 and altEnd+1<text.len and text[altEnd+1]=='(':
        let urlEnd = text.find(')', altEnd+2)
        if urlEnd != -1:
          let alt = text[i+2..<altEnd]
          let url = text[altEnd+2..<urlEnd]
          res.add "<img src=\"" & sanitizeUrl(url) & "\" alt=\"" & escapeHtml(alt) & "\">"
          i=urlEnd+1
        else:
          res.add escapeHtml($text[i]); inc i
      else:
        res.add escapeHtml($text[i]); inc i
    elif text[i]=='[':
      let labelEnd = text.find(']', i+1)
      if labelEnd != -1 and labelEnd+1<text.len and text[labelEnd+1]=='(':
        let urlEnd = text.find(')', labelEnd+2)
        if urlEnd != -1:
          let label = text[i+1..<labelEnd]
          let url = text[labelEnd+2..<urlEnd]
          res.add "<a href=\"" & sanitizeUrl(url) & "\">" & parseInline(label) & "</a>"
          i=urlEnd+1
        else:
          res.add escapeHtml($text[i]); inc i
      else:
        res.add escapeHtml($text[i]); inc i
    else:
      res.add escapeHtml($text[i]); inc i
  res

proc parseMarkdown*(input: string, opts: MdOptions = MdOptions(safeMode: true, enableTables: true)): string {.gcsafe.} =
  ## Block parser
  let lines = input.splitLines()
  var html = ""
  var i=0
  var inCodeBlock=false
  var codeLang=""
  var listStack: seq[string] = @[] # "ul" or "ol"
  var inParagraph=false

  proc closeParagraph() =
    if inParagraph:
      html.add "</p>\n"
      inParagraph=false
  proc closeLists() =
    while listStack.len>0:
      html.add "</" & listStack[^1] & ">\n"
      discard listStack.pop()

  while i<lines.len:
    let line = lines[i]
    let trimmed = line.strip()
    if inCodeBlock:
      if trimmed.startsWith("```"):
        html.add "</code></pre>\n"
        inCodeBlock=false
      else:
        html.add escapeHtml(line) & "\n"
      inc i
      continue
    if trimmed.startsWith("```"):
      closeParagraph()
      closeLists()
      codeLang = trimmed[3..^1].strip()
      html.add "<pre><code class=\"language-" & escapeHtml(codeLang) & "\">"
      inCodeBlock=true
      inc i
      continue
    if trimmed.len==0:
      closeParagraph()
      # Don't close lists on empty line? Fossil keeps them open, we close paragraph only
      inc i
      continue
    if trimmed.startsWith("# "):
      closeParagraph(); closeLists()
      html.add "<h1>" & parseInline(trimmed[2..^1].strip()) & "</h1>\n"
    elif trimmed.startsWith("## "):
      closeParagraph(); closeLists()
      html.add "<h2>" & parseInline(trimmed[3..^1].strip()) & "</h2>\n"
    elif trimmed.startsWith("### "):
      closeParagraph(); closeLists()
      html.add "<h3>" & parseInline(trimmed[4..^1].strip()) & "</h3>\n"
    elif trimmed.startsWith("#### "):
      closeParagraph(); closeLists()
      html.add "<h4>" & parseInline(trimmed[5..^1].strip()) & "</h4>\n"
    elif trimmed.startsWith("##### "):
      closeParagraph(); closeLists()
      html.add "<h5>" & parseInline(trimmed[6..^1].strip()) & "</h5>\n"
    elif trimmed.startsWith("###### "):
      closeParagraph(); closeLists()
      html.add "<h6>" & parseInline(trimmed[7..^1].strip()) & "</h6>\n"
    elif trimmed=="---" or trimmed=="***" or trimmed=="___":
      closeParagraph(); closeLists()
      html.add "<hr>\n"
    elif trimmed.startsWith("> "):
      closeParagraph(); closeLists()
      html.add "<blockquote>" & parseInline(trimmed[2..^1]) & "</blockquote>\n"
    elif trimmed.startsWith("- ") or trimmed.startsWith("* ") or trimmed.startsWith("+ "):
      closeParagraph()
      let content = trimmed[2..^1]
      if listStack.len==0 or listStack[^1]!="ul":
        html.add "<ul>\n"
        listStack.add "ul"
      html.add "<li>" & parseInline(content) & "</li>\n"
      # Look ahead: if next line not list, close
      if i+1>=lines.len or not (lines[i+1].strip().startsWith("- ") or lines[i+1].strip().startsWith("* ") or lines[i+1].strip().startsWith("+ ")):
        # keep open for now? We'll close on non-list block
        discard
    elif trimmed.len>=2 and trimmed[0].isDigit():
      # Ordered list: "1. "
      var dotPos = trimmed.find(". ")
      if dotPos != -1 and trimmed[0..dotPos-1].allIt(it.isDigit()):
        closeParagraph()
        let content = trimmed[dotPos+2..^1]
        if listStack.len==0 or listStack[^1]!="ol":
          html.add "<ol>\n"
          listStack.add "ol"
        html.add "<li>" & parseInline(content) & "</li>\n"
      else:
        if not inParagraph:
          # Check if next non-empty is list continuation? For simplicity, close lists before paragraph
          if listStack.len>0:
            # If next line is not list, close
            if i+1<lines.len:
              let nxt = lines[i+1].strip()
              if not (nxt.startsWith("- ") or nxt.startsWith("* ") or nxt.startsWith("+ ") or (nxt.len>0 and nxt[0].isDigit())):
                closeLists()
          html.add "<p>"
          inParagraph=true
        else:
          html.add " "
        html.add parseInline(trimmed)
    else:
      if listStack.len>0:
        # If line is not list item, close lists
        if not (trimmed.startsWith("- ") or trimmed.startsWith("* ") or trimmed.startsWith("+ ")):
          closeLists()
      if not inParagraph:
        html.add "<p>"
        inParagraph=true
      else:
        html.add " "
      html.add parseInline(trimmed)
    inc i
  closeParagraph()
  closeLists()
  if inCodeBlock:
    html.add "</code></pre>\n"
  html

proc markdownToHtml*(md: string): string {.gcsafe.} =
  parseMarkdown(md)

proc markdownToText*(md: string): string =
  ## Strip markdown to plain text (very naive)
  var res = md
  res = res.replace("**", "").replace("*", "").replace("`", "").replace("#", "")
  res

when isMainModule:
  let sample = """
# Hello

This is **bold** and *italic* with `code`.

- item 1
- item 2 with [link](http://example.com)

```nim
echo "hi"
```

> quote

---

More text.
"""
  echo parseMarkdown(sample)
