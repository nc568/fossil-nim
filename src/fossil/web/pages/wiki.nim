## Wiki page rendering

import ../../types
import ../../wiki/wiki as wikiMod
import ../../markdown/parser as mdParser
import std/[strutils]

proc renderWikiPageHtml*(page: wikiMod.WikiPage): string =
  let rendered = wikiMod.renderWikiPage(page)
  var html = "<html><head><title>" & page.name & " - Wiki</title>"
  html.add "<style>body{font-family:sans-serif;max-width:800px;margin:40px auto;padding:0 20px} h1{border-bottom:1px solid #ccc}</style>"
  html.add "</head><body>"
  html.add "<h1>" & page.name & "</h1>"
  html.add "<div class='meta'>Last modified: " & $page.mtime & " by " & page.user & "</div>"
  html.add "<div class='content'>" & rendered & "</div>"
  html.add "<hr><a href='/wiki'>Back to wiki list</a>"
  html.add "</body></html>"
  html

proc renderWikiListPage*(pages: seq[string]): string =
  var html = "<html><head><title>Wiki Pages</title></head><body>"
  html.add "<h1>Wiki Pages</h1><ul>"
  for p in pages:
    html.add "<li><a href='/wiki/" & p & "'>" & p & "</a></li>"
  html.add "</ul>"
  html.add "<form method='post' action='/wiki/create'><input name='name' placeholder='New page name'><textarea name='content' placeholder='Content'></textarea><button>Create</button></form>"
  html.add "</body></html>"
  html
