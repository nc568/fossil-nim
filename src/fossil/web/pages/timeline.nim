## Timeline page

import ../../types
import ../../vcs/timeline
import std/[strutils, times]

proc renderTimelinePage*(entries: seq[TimelineEntry]): string =
  var html = "<html><head><title>Timeline</title></head><body>"
  html.add "<h1>Timeline</h1><ul>"
  for e in entries:
    html.add "<li>" & e.date.format("yyyy-MM-dd") & " [" & ($e.uuid)[0..9] & "] " & e.comment & " - " & e.user & "</li>"
  html.add "</ul></body></html>"
  html
