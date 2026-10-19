## configstore.nim -- where a config lives on this machine, and the configs
## the editor hands out.
##
## The parsing is `config.nim`'s; this is the other half of it. A config file
## is read at startup, written back on every edit that parses, and -- when a
## shipped one replaces one that was written by hand -- moved out of the way
## first. All of it is best effort: an unwritable config directory must not
## take an editor down, so nothing here raises and a caller that cares is told
## by an empty answer.

import std/strutils
import std/os
import uirelays/tinynif
import config

const
  ConfigDirName* = "focim"

proc configPath*(name: string): string =
  getConfigDir() / ConfigDirName / name

proc saveConfig*(name, text: string) =
  ## Best effort: an unwritable config dir must not take the editor down.
  try:
    createDir(configPath(name).parentDir)
    writeFile(configPath(name), text)
  except CatchableError:
    discard

proc loadConfig*(name: string): string =
  try:
    result = readFile(configPath(name))
  except CatchableError:
    result = ""

# ---------------------------------------------------------------------------
# The config the app ships with. Its layout and its tracking default are text,
# because they are the same whichever theme is picked; the theme in the middle
# is written out of a `Theme` by `themeText`, so a theme has to be a thing the
# program can *hold* before it can be a thing the file offers -- and the file
# can never fall behind the object it came from. `ShippedThemes` in `theme.nim`
# is the list; the first of them is what a fresh config says.
# ---------------------------------------------------------------------------

const defaultLayout* = """
# Where the widgets go, and the file the mouse writes: dragging a border
# between two panels rewrites the sizes below. A box states its size along the
# axis its parent divides -- (px N), (lines N), or (stretch N) shares of what
# is left over -- and `doc/config.md` has the rest of it. A comment down in
# the layout does not survive a drag; one up here does.
(layout
  (cols
    (rows (px 200)
      (tabs (lines 6))
      (explorer))
    (editor (stretch 4))
    (rows (stretch 2)
      (clipboard (lines 9))
      (history (lines 5))
      (terminal)))
  (status (lines 1)))
"""

const configHead = """
(config
  # Anything left out keeps the color it has; `doc/config.md` lists the
  # fields. Every token class is written out below, so any of them can be
  # recolored by editing its line rather than by first finding out that the
  # class exists. A color may be followed by (bold), by (italics), or by both.
"""

const configTail = """
  # Who answers a Ctrl+click on a name: "nim", "nimony", or "none" for nobody.
  # (exe "...") names the binary when it is not simply on the PATH.
  (track
    (compiler "nim")))
"""

proc shippedConfig*(t: Theme): string =
  ## One whole config file: the layout, `t`, and the tracking default.
  configHead & themeText(t) & "\n" & configTail

const ShippedConfigs* = block:
  # Made once, at compile time, so that recognizing the config in the tab as
  # one of them is a handful of string comparisons and not a re-render.
  var res: seq[string] = @[]
  for it in ShippedThemes:
    var t = default(Theme)
    doAssert findTheme(it.name, t), it.name
    res.add shippedConfig(t)
  res

const defaultConfig* = ShippedConfigs[0]

proc shippedName*(text: string): string =
  ## Which shipped config `text` is, "" for one that has been edited. Nothing
  ## more is asked of it than that: a config with a color changed in it is
  ## somebody's own, whichever theme it started life as.
  for i in 0 ..< ShippedThemes.len:
    if text == ShippedConfigs[i]: return ShippedThemes[i].name
  result = ""

proc backupConfig*(lane, text: string): string =
  ## Put `text` where it can be found again -- `lane` is the file it came
  ## from, without its extension -- and answer with the path it went to; ""
  ## when the config dir could not be written, which is the same silence
  ## `saveConfig` keeps.
  ##
  ## Numbered rather than overwritten: switching themes twice is a normal
  ## thing to do, and the second switch must not be what loses the config the
  ## first one was protecting. The hundredth reuses the last name, by which
  ## point the directory has said everything it has to say.
  var name = lane & "-backup.nif"
  var n = 2
  while fileExists(configPath(name)) and n <= 99:
    name = lane & "-backup" & $n & ".nif"
    inc n
  result = configPath(name)
  try:
    createDir(result.parentDir)
    writeFile(result, text)
  except CatchableError:
    result = ""

# ---------------------------------------------------------------------------
# Moving a layout out of a config written when the two shared a file. One
# startup's worth of work, kept here because it is about files rather than
# about windows -- and because a thing that runs once on somebody's only copy
# of a config they have been shaping for a year is a thing to have tests for.
# ---------------------------------------------------------------------------

proc offsetOf(text: string; line, col: int): int =
  ## The byte the token at `line:col` starts on. tinynif says where a token is
  ## in a file, which is what an error message wants; moving a block of text
  ## wants where it is in the string. Both counts are in bytes, so this is a
  ## walk to the line and then a step along it.
  var atLine = 1
  var i = 0
  while atLine < line and i < text.len:
    if text[i] == '\n': inc atLine
    inc i
  result = min(text.len, i + col - 1)

proc dedent(text: string; by: int): string =
  ## Every line but the first loses up to `by` leading spaces -- a layout that
  ## sat inside a `(config ...)` is written one level in, and a file of its
  ## own starts at the margin.
  result = ""
  var first = true
  for line in text.splitLines:
    if first:
      result.add line
      first = false
    else:
      result.add '\n'
      var drop = 0
      while drop < by and drop < line.len and line[drop] == ' ': inc drop
      result.add line.substr(drop)

proc takeLayout*(text: string; layout: var string): string =
  ## Cut the `(layout ...)` out of `text`, hand back what is left, and leave
  ## the block in `layout`. When there is none, `text` comes back unchanged
  ## and `layout` is empty.
  ##
  ## Text in and text out, rather than parse-and-render: this runs on a config
  ## somebody may have been keeping for a year, and both halves have to stay
  ## the file they were -- the comments in them, the order they were written
  ## in, the spelling of every color. What a rendering would hand back is the
  ## same window described by a stranger.
  layout = ""
  var lex = initLexer(text)
  var tok = next(lex)
  var depth = 0
  while tok.kind != tkEof and tok.kind != tkError:
    if tok.kind == tkParLe:
      if tok.text == "layout" and depth > 0:
        # Found it. From here the parens are counted until this one closes.
        let start = offsetOf(text, tok.line, tok.col)
        var inner = 1
        var last = tok
        while inner > 0:
          tok = next(lex)
          if tok.kind == tkEof or tok.kind == tkError: return text
          if tok.kind == tkParLe: inc inner
          elif tok.kind == tkParRi:
            dec inner
            last = tok
        # The ')' is one byte, and what follows it on that line -- nothing,
        # in every config this has to read -- stays where it is.
        var stop = offsetOf(text, last.line, last.col) + 1
        # The indentation in front of it goes with it, and so does the line
        # break behind: what is cut out is whole lines, so the config that is
        # left does not keep an empty one where the layout used to be.
        var head = start
        while head > 0 and (text[head - 1] == ' ' or text[head - 1] == '\t'):
          dec head
        if stop < text.len and text[stop] == '\r': inc stop
        if stop < text.len and text[stop] == '\n': inc stop
        layout = dedent(text.substr(start, stop - 1), 2).strip(
          leading = false) & "\n"
        return text.substr(0, head - 1) & text.substr(stop)
      inc depth
    elif tok.kind == tkParRi:
      dec depth
    tok = next(lex)
  result = text

proc withHeader*(old, fresh: string): string =
  ## `fresh` under whatever comment the text it replaces opened with.
  ##
  ## A layout the mouse rewrites cannot keep the comments *inside* it: what is
  ## written back is the tree, and a tree has nowhere to hold a remark about
  ## one of its boxes. The block at the top of the file is another matter --
  ## it is a header rather than a remark, it is what the file ships with, and
  ## keeping it costs one loop.
  var head = ""
  var blanks = ""
  for line in old.splitLines:
    let t = line.strip
    if t.len == 0:
      # Blank lines belong to the header only once there is one: they are the
      # line it is separated from the layout by, and a file that opens with
      # one has no header to separate.
      if head.len > 0: blanks.add line & "\n"
    elif t[0] == '#':
      head.add blanks
      blanks = ""
      head.add line & "\n"
    else: break
  result = head & blanks & fresh
