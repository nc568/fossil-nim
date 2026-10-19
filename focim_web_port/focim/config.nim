## config.nim -- one NIF file says what a window looks like and who answers a
## Ctrl+click in it.
##
##   (config
##     (theme
##       (bg "#15171B")
##       (fg "#E6DFD1"                        # every token class ...
##         (Keyword "#E5B94E" (bold))         # ... except the ones named here
##         (Comment "#7A7365" (italics)))
##       (selBg "#35474B"))
##     (track
##       (compiler "nim")))
##
## Where the widgets *go* is not in here: `(layout ...)` is a file of its own,
## parsed by `uirelays/layout`. The two were one file once, and that made the
## window's shape a hostage of its colors -- picking a theme rewrote the
## layout along with it, because the two arrived in the same text. A lane
## each, and neither can spend the other.
##
## The tags inside `(theme ...)` are the field names of `Theme`, the tags
## inside `(fg ...)` are the values of `TokenClass` and the ones behind a color
## are the values of `FontStyle`, all spelled exactly as they are in
## `theme.nim` and `screen.nim` -- so there is nothing to look up, and nothing
## can fall out of sync when a field is added.
##
## A color is `"#RRGGBB"` in a string literal -- what a palette hands you,
## quoted so that the `#` cannot start a comment. `"#RGB"` and `"#RRGGBBAA"`
## work too: the accepted spellings are exactly the ones SynEdit draws a color
## chip for, so anything that shows a chip in the editor also parses here.
## Whatever the theme leaves unsaid keeps the value it has in the theme passed
## to `parseConfig`.
##
## Nothing raises. A file that does not parse leaves its reason in `error`; a
## theme whose text would be unreadable on its own background is refused, and
## `note` says so while `theme` falls back. That way a config typed by hand can
## always be corrected -- it cannot lock the window it configures.

import std/strutils
import uirelays/[screen, tinynif]
import theme

export theme

type
  Compiler* = enum
    ## Who answers a "where is this name?" -- and, by saying nobody, that the
    ## question is not to be asked at all.
    compilerNone = "none"
    compilerNim = "nim"
    compilerNimony = "nimony"

  Track* = object
    ## `(track ...)`: which compiler a Ctrl+click asks, and what to run it by.
    compiler*: Compiler
    exe*: string     ## the binary; "" means the compiler's own name, found on
                     ## PATH like any other command

  Config* = object
    theme*: Theme    ## the fallback with whatever `(theme ...)` said applied
    track*: Track    ## what `(track ...)` said, or the default: `nim`
    error*: string   ## "line:col: why"; nothing in here can be used
    note*: string    ## the theme was refused and `theme` is the fallback

  Parser = object
    lex: Lexer
    tok: Token
    error: string

proc defaultTrack*(): Track =
  ## Nim, run as `nim`. A checkout that has none on the PATH says so the first
  ## time somebody Ctrl+clicks, which is a better introduction to the setting
  ## than a config that has to name it before anything works.
  Track(compiler: compilerNim, exe: "")

proc exeName*(t: Track): string =
  ## What to run: what the config named, or the compiler's own name.
  if t.exe.len > 0: t.exe else: $t.compiler

proc fail(p: var Parser; msg: string) =
  ## The first complaint is the one that gets reported: everything behind it is
  ## a consequence of it.
  if p.error.len == 0:
    p.error = p.tok.position & ": " & msg

proc failAt(p: var Parser; at: Token; msg: string) =
  ## Like `fail`, but pointing at a token the parser has already moved past.
  if p.error.len == 0:
    p.error = at.position & ": " & msg

proc advance(p: var Parser) =
  p.tok = next(p.lex)
  if p.tok.kind == tkError: p.fail p.tok.text

proc hexDigit(c: char): int =
  case c
  of '0'..'9': result = ord(c) - ord('0')
  of 'a'..'f': result = ord(c) - ord('a') + 10
  of 'A'..'F': result = ord(c) - ord('A') + 10
  else: result = -1

proc toColor(s: string; dest: var Color): bool =
  ## `#RGB`, `#RRGGBB` or `#RRGGBBAA`, in either case -- the same three
  ## spellings SynEdit draws a color chip for, so that a color which shows a
  ## chip in the editor is a color this understands.
  result = false
  if s.len == 0 or s[0] != '#': return
  let n = s.len - 1
  if n != 3 and n != 6 and n != 8: return
  var d: array[8, int]
  for i in 0 ..< n:
    d[i] = hexDigit(s[i + 1])
    if d[i] < 0: return
  if n == 3:
    # #RGB is #RRGGBB with every digit doubled: #f0c is #ff00cc.
    dest = color(uint8(d[0] * 17), uint8(d[1] * 17), uint8(d[2] * 17))
  else:
    let r = uint8(d[0] * 16 + d[1])
    let g = uint8(d[2] * 16 + d[3])
    let b = uint8(d[4] * 16 + d[5])
    if n == 8: dest = color(r, g, b, uint8(d[6] * 16 + d[7]))
    else: dest = color(r, g, b)
  result = true

proc readColor(p: var Parser; dest: var Color) =
  ## One color, stopping in front of whatever follows it.
  if p.tok.kind != tkStringLit:
    p.fail "expected a color like \"#1E1E2E\" but found " & $p.tok
    return
  if not toColor(p.tok.text, dest):
    p.fail "a color is \"#RRGGBB\" -- or \"#RGB\", or \"#RRGGBBAA\" -- " &
           "not \"" & p.tok.text & "\""
    return
  p.advance

proc parseColor(p: var Parser; dest: var Color) =
  ## A color that fills its whole tag: `(bg "#1E1E2E")`.
  p.readColor(dest)
  if p.error.len > 0: return
  if p.tok.kind != tkParRi:
    p.fail "expected ')' after the color but found " & $p.tok
    return
  p.advance

proc toFontStyle(s: string; fs: var FontStyle): bool =
  ## Like `toTokenClass`: the tag is the enum value's own name.
  result = false
  for st in low(FontStyle)..high(FontStyle):
    if $st == s:
      fs = st
      return true

proc parseStyled(p: var Parser; fg: var Color; style: var FontStyles) =
  ## What one token class looks like: `(Comment "#7A7365" (italics))`. The
  ## color first, then how the text is cut -- neither, either or both.
  p.readColor(fg)
  if p.error.len > 0: return
  # A class that names its color says everything about itself, so the style
  # starts empty instead of carrying over from the fallback theme.
  style = {}
  while p.tok.kind == tkParLe:
    var fs = FontStyle.bold
    if not toFontStyle(p.tok.text, fs):
      p.fail "'" & p.tok.text & "' is not a font style; expected (bold) or " &
             "(italics)"
      return
    style.incl fs
    p.advance
    if p.error.len > 0: return
    if p.tok.kind != tkParRi:
      p.fail "(" & $fs & ") takes nothing; expected ')' but found " & $p.tok
      return
    p.advance
    if p.error.len > 0: return
  if p.tok.kind != tkParRi:
    p.fail "expected ')' or a style like (italics) but found " & $p.tok
    return
  p.advance

proc toTokenClass(s: string; tc: var TokenClass): bool =
  ## The tag is the enum value's own name, so this can never go out of date.
  result = false
  for c in low(TokenClass)..high(TokenClass):
    if $c == s:
      tc = c
      return true

proc parseFg(p: var Parser; t: var Theme) =
  ## `(fg base? (Class "#RRGGBB")*)`: the leading color, if there is one, is
  ## every token class at once, and each child overrides one of them.
  p.advance
  if p.error.len > 0: return
  if p.tok.kind == tkStringLit:
    # The leading color is `fg`'s own, so it stops in front of the children
    # instead of eating a ')' that belongs to `fg`.
    var base = default(Color)
    p.readColor(base)
    if p.error.len > 0: return
    for tc in low(TokenClass)..high(TokenClass): t.fg[tc] = base
  while p.tok.kind == tkParLe:
    var tc = TokenClass.None
    if not toTokenClass(p.tok.text, tc):
      var fs = FontStyle.bold
      if toFontStyle(p.tok.text, fs):
        # A style at this level would have to mean "all of them", which is not
        # a thing anyone wants; say where it does belong.
        p.fail "(" & p.tok.text & ") belongs behind a token class's color, " &
               "as in (Comment \"#7A7365\" (" & p.tok.text & "))"
      else:
        p.fail "'" & p.tok.text & "' is not a token class"
      return
    p.advance
    if p.error.len > 0: return
    p.parseStyled(t.fg[tc], t.style[tc])
    if p.error.len > 0: return
  if p.tok.kind != tkParRi:
    p.fail "expected ')' or a token class but found " & $p.tok
    return
  p.advance

proc parseTheme(p: var Parser; t: var Theme) =
  ## Already positioned on `(theme`.
  p.advance
  if p.error.len > 0: return
  while p.tok.kind == tkParLe:
    let field = p.tok.text
    let fieldAt = p.tok
    if field == "fg":
      p.parseFg(t)
      if p.error.len > 0: return
      continue
    p.advance
    if p.error.len > 0: return
    case field
    of "bg": p.parseColor(t.bg)
    of "panelBg": p.parseColor(t.panelBg)
    of "selBg": p.parseColor(t.selBg)
    of "bracketBg": p.parseColor(t.bracketBg)
    of "cursorColor": p.parseColor(t.cursorColor)
    of "lineNumColor": p.parseColor(t.lineNumColor)
    of "markerBg": p.parseColor(t.markerBg)
    of "scrollBarColor": p.parseColor(t.scrollBarColor)
    of "scrollBarActiveColor": p.parseColor(t.scrollBarActiveColor)
    of "scrollTrackColor": p.parseColor(t.scrollTrackColor)
    of "activeLineBg": p.parseColor(t.activeLineBg)
    of "actionColor": p.parseColor(t.actionColor)
    of "closeColor": p.parseColor(t.closeColor)
    of "focusColor": p.parseColor(t.focusColor)
    else:
      p.failAt fieldAt, "'" & field & "' is not a theme field"
      return
    if p.error.len > 0: return
  if p.tok.kind != tkParRi:
    p.fail "expected ')' or a theme field but found " & $p.tok
    return
  p.advance

# ---------------------------------------------------------------------------
# Writing one back. A config file is a thing to edit, so the editor has to be
# able to hand one over -- `themeText` is what a shipped theme looks like as
# text, and what it says is read back by `parseTheme` above. The two are kept
# honest by a round trip in the test suite: write a theme, parse it, and get
# the same theme.
# ---------------------------------------------------------------------------

const CommentCol = 38
  ## Where a trailing comment starts, for the lines short enough to reach it.
  ## A line longer than this keeps its comment one space behind it rather than
  ## pushing every other comment to the right.

proc colorText*(c: Color): string =
  ## `"#RRGGBB"`, or `"#RRGGBBAA"` when the color is not opaque -- always one
  ## of the spellings `toColor` reads back.
  const Hex = "0123456789ABCDEF"
  result = "\"#"
  for v in [c.r, c.g, c.b]:
    result.add Hex[int(v) shr 4]
    result.add Hex[int(v) and 15]
  if c.a != 255:
    result.add Hex[int(c.a) shr 4]
    result.add Hex[int(c.a) and 15]
  result.add '"'

proc classNote(tc: TokenClass): string =
  ## The few remarks worth carrying into a written config: where one group of
  ## token classes ends and the next begins. The rest of them are their own
  ## explanation.
  case tc
  of TokenClass.TagStart: "markup"
  of TokenClass.Key: "ini, nif, config files"
  of TokenClass.Green: "the three the terminal colors by name"
  of TokenClass.Black: "the sixteen a program can ask for by name"
  else: ""

proc themeText*(t: Theme; indent = 2): string =
  ## `t` as the `(theme ...)` block of a config file, indented by `indent`
  ## spaces and ending without a newline.
  ##
  ## Every field and every token class is written out -- nothing is left to
  ## the fallback theme. A written theme therefore replaces the one it is
  ## written over completely, which is the point: a file that named only the
  ## colors it happened to differ in would leave the rest of an earlier theme
  ## standing, and the two together are a theme nobody chose.
  let i0 = spaces(indent)
  let i1 = spaces(indent + 2)
  let i2 = spaces(indent + 4)
  template say(text, note: string) =
    var ln = text
    if note.len > 0:
      if ln.len < CommentCol: ln.add spaces(CommentCol - ln.len)
      else: ln.add ' '
      ln.add "# " & note
    result.add ln
    result.add '\n'

  result = i0 & "(theme\n"
  say i1 & "(bg " & colorText(t.bg) & ")", "the editor background"
  say i1 & "(panelBg " & colorText(t.panelBg) & ")", "the panels around it"
  say i1 & "(selBg " & colorText(t.selBg) & ")", "selected text"
  say i1 & "(bracketBg " & colorText(t.bracketBg) & ")", "the matching bracket"
  say i1 & "(cursorColor " & colorText(t.cursorColor) & ")", "the caret"
  say i1 & "(lineNumColor " & colorText(t.lineNumColor) & ")", "line numbers"
  say i1 & "(markerBg " & colorText(t.markerBg) & ")", "search hits"
  say i1 & "(scrollBarColor " & colorText(t.scrollBarColor) & ")", "the grip"
  say i1 & "(scrollBarActiveColor " & colorText(t.scrollBarActiveColor) & ")",
      "the grip while dragged"
  say i1 & "(scrollTrackColor " & colorText(t.scrollTrackColor) & ")",
      "the track behind it"
  say i1 & "(activeLineBg " & colorText(t.activeLineBg) & ")",
      "the line the caret is on"
  say i1 & "(actionColor " & colorText(t.actionColor) & ")",
      "a row that acts on click"
  say i1 & "(closeColor " & colorText(t.closeColor) & ")", "the (x) on it"
  say i1 & "(focusColor " & colorText(t.focusColor) & ")",
      "the frame around the focused panel"
  # `fg` last: it is the long one, and its ')' is the one that ends the theme.
  say i1 & "(fg " & colorText(t.fg[TokenClass.None]),
      "the base color, for anything unnamed"
  for tc in low(TokenClass)..high(TokenClass):
    var ln = i2 & "(" & $tc & " " & colorText(t.fg[tc])
    if FontStyle.bold in t.style[tc]: ln.add " (bold)"
    if FontStyle.italics in t.style[tc]: ln.add " (italics)"
    ln.add ")"
    if tc == high(TokenClass): ln.add "))"
    say ln, classNote(tc)
  result.setLen result.len - 1   # the block ends where its ')' does

proc parseString(p: var Parser; dest: var string) =
  ## A tag whose whole content is one string: `(exe "nim")`.
  if p.tok.kind != tkStringLit:
    p.fail "expected a string but found " & $p.tok
    return
  dest = p.tok.text
  p.advance
  if p.error.len > 0: return
  if p.tok.kind != tkParRi:
    p.fail "expected ')' after the string but found " & $p.tok
    return
  p.advance

proc parseTrack(p: var Parser; t: var Track) =
  ## Already positioned on `(track`.
  p.advance
  if p.error.len > 0: return
  while p.tok.kind == tkParLe:
    let field = p.tok.text
    let fieldAt = p.tok
    p.advance
    if p.error.len > 0: return
    case field
    of "compiler":
      var name = ""
      let nameAt = p.tok
      p.parseString(name)
      if p.error.len > 0: return
      var found = false
      for c in low(Compiler)..high(Compiler):
        if $c == name:
          t.compiler = c
          found = true
      if not found:
        var known = ""
        for c in low(Compiler)..high(Compiler):
          if known.len > 0: known.add ", "
          known.add '"' & $c & '"'
        p.failAt nameAt, "'" & name & "' is not a compiler; expected " & known
        return
    of "exe": p.parseString(t.exe)
    else:
      p.failAt fieldAt, "'" & field & "' does not belong in a track; " &
               "expected (compiler ...) or (exe ...)"
      return
    if p.error.len > 0: return
  if p.tok.kind != tkParRi:
    p.fail "expected ')' or a track field but found " & $p.tok
    return
  p.advance

proc parseConfig*(s: string; fallback = defaultTheme()): Config =
  ## Parse a `(config ...)`. Never raises: check `error`, then `note`.
  result = Config(theme: fallback, track: defaultTrack(), error: "", note: "")
  var p = Parser(lex: initLexer(s), tok: Token(), error: "")
  p.advance
  if p.tok.kind == tkEof:
    result.error = p.tok.position & ": nothing here; expected (config ...)"
    return
  if p.tok.kind != tkParLe:
    result.error = p.tok.position & ": expected (config ...) but found " & $p.tok
    return
  if p.tok.text != "config":
    result.error = p.tok.position & ": expected (config ...) but found (" &
                   p.tok.text
    return
  p.advance

  var themed = false
  var tracked = false
  var t = fallback
  var tr = defaultTrack()
  while p.error.len == 0 and p.tok.kind == tkParLe:
    case p.tok.text
    of "layout":
      # It was in here once. Say where it went rather than "does not belong":
      # a config carried over from then is the likeliest way to arrive at this
      # message, and it is one move away from working again.
      p.fail "the layout has a file of its own now -- put (layout ...) in " &
             "layout.nif, beside this one"
      break
    of "theme":
      if themed:
        p.fail "only one (theme ...) per config"
        break
      themed = true
      p.parseTheme(t)
    of "track":
      if tracked:
        p.fail "only one (track ...) per config"
        break
      tracked = true
      p.parseTrack(tr)
    else:
      p.fail "'" & p.tok.text & "' does not belong in a config; expected " &
             "(theme ...) or (track ...)"
      break

  if p.error.len == 0 and p.tok.kind != tkParRi:
    p.fail "expected ')' but found " & $p.tok
  if p.error.len == 0:
    p.advance
    if p.tok.kind != tkEof:
      p.fail "unexpected " & $p.tok & " behind the config"
  if p.error.len > 0:
    result.error = p.error
    result.theme = fallback
    result.track = defaultTrack()
    return
  result.track = tr

  # A theme nobody can read is worse than no theme at all, and the file that
  # would have to be corrected is shown in these very colors.
  if themed:
    let problem = contrastProblem(t)
    if problem.len > 0:
      result.note = "too low contrast between colors, used default settings " &
                    "instead -- " & problem
    else:
      result.theme = t
