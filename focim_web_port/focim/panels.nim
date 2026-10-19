## panels.nim -- which panels the window has, and what they are called.
##
## The layout says. A cell called `editor` is an editor panel, one called
## `editor2` is a second editor panel, and typing `(editor3)` into
## `layout.nif` is all it takes to have a third -- the same act as clicking
## the split button, which does no more than write that text. Nothing else
## anywhere keeps a list of the panels, so there is no second list to fall out
## of step with the file.
##
## A name is a stem and a number: `editor`, `editor2`, `editor3`. The first
## one has no number because a window with one editor in it should not have to
## explain itself, and because that is what every layout ever written already
## says.

import std/strutils

const
  EditorStem* = "editor"
  TerminalStem* = "terminal"

proc panelOf*(name, stem: string): bool =
  ## Whether `name` is one of `stem`'s panels: the stem itself, or the stem
  ## with a number behind it. `editorial` is neither, and neither is
  ## `editor0` -- a numbered name starts at 2, the way the second of anything
  ## does.
  if name == stem: return true
  if not name.startsWith(stem): return false
  let digits = name[stem.len .. ^1]
  # No leading zero and no `1`: a number that could be written another way
  # would give one panel two names, and the first panel is already `editor`.
  if digits.len == 0 or digits == "1" or digits[0] == '0': return false
  for c in digits:
    if c notin {'0'..'9'}: return false
  result = true

proc isEditor*(name: string): bool = panelOf(name, EditorStem)
proc isTerminal*(name: string): bool = panelOf(name, TerminalStem)

proc stemOf*(name: string): string =
  ## The stem a panel name belongs to, or "" for a cell that is neither an
  ## editor nor a terminal -- the tab list, the status bar, the explorer.
  if name.isEditor: EditorStem
  elif name.isTerminal: TerminalStem
  else: ""

proc freeName*(taken: openArray[string]; stem: string): string =
  ## A name of `stem`'s that nothing is called yet. Counting up from the
  ## lowest free number rather than from the highest taken one, so that
  ## splitting and closing a panel all afternoon does not end in `editor47`.
  if stem notin taken: return stem
  var n = 2
  while true:
    result = stem & $n
    if result notin taken: return
    inc n

proc panelsOf*(cells: openArray[string]; stem: string): seq[string] =
  ## The cells of the layout that are `stem`'s panels, in the order the layout
  ## writes them -- which is the order they are laid out in, so a window's
  ## panels are numbered the way they are read.
  result = @[]
  for c in cells:
    if panelOf(c, stem): result.add c
