## Ticket page rendering

import ../../types
import ../../ticket/ticket as ticketMod
import std/[strutils]

proc htmlEscape(s: string): string =
  result = s
  result = result.replace("&", "&amp;")
  result = result.replace("<", "&lt;")
  result = result.replace(">", "&gt;")
  result = result.replace("\"", "&quot;")
  result = result.replace("'", "&#39;")

proc renderTicketPageHtml*(ticket: ticketMod.Ticket): string =
  var html = "<html><head><title>Ticket " & ticket.id & " - " & ticket.title & "</title>"
  html.add "<style>body{font-family:sans-serif;max-width:800px;margin:40px auto;padding:0 20px} .status{padding:4px 8px;border-radius:4px} .open{background:#d4edda} .closed{background:#f8d7da} .comment{border:1px solid #ddd;padding:10px;margin:10px 0}</style>"
  html.add "</head><body>"
  html.add "<h1>[" & htmlEscape(ticket.id) & "] " & htmlEscape(ticket.title) & "</h1>"
  html.add "<div><span class='status " & htmlEscape($ticket.status) & "'>" & htmlEscape($ticket.status) & "</span> Priority: " & $ticket.priority & " Type: " & htmlEscape($ticket.ticketType) & "</div>"
  html.add "<div>Reported by " & htmlEscape(ticket.reporter) & " on " & $ticket.created & "</div>"
  html.add "<div class='description'><h3>Description</h3><p>" & htmlEscape(ticket.description) & "</p></div>"
  if ticket.comments.len>0:
    html.add "<h3>Comments</h3>"
    for c in ticket.comments:
      html.add "<div class='comment'><b>" & htmlEscape(c.user) & "</b> at " & $c.date & "<br>" & htmlEscape(c.content) & "</div>"
  html.add "<hr><a href='/ticket'>Back to tickets</a>"
  html.add "</body></html>"
  html

proc renderTicketListPage*(tickets: seq[ticketMod.Ticket]): string =
  var html = "<html><head><title>Tickets</title></head><body>"
  html.add "<h1>Tickets</h1><table border='1' cellpadding='5'><tr><th>ID</th><th>Title</th><th>Status</th><th>Priority</th><th>Reporter</th></tr>"
  for t in tickets:
    html.add "<tr><td><a href='/ticket/" & htmlEscape(t.id) & "'>" & htmlEscape(t.id) & "</a></td><td>" & htmlEscape(t.title) & "</td><td>" & htmlEscape($t.status) & "</td><td>" & $t.priority & "</td><td>" & htmlEscape(t.reporter) & "</td></tr>"
  html.add "</table>"
  html.add "<h3>Create Ticket</h3><form method='post' action='/ticket/create'><input name='title' placeholder='Title'><br><textarea name='description' placeholder='Description'></textarea><br><button>Create</button></form>"
  html.add "</body></html>"
  html
