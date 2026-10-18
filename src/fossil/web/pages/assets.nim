## Assets - CSS/JS embedded, port of style.c, graph.js, etc.

import std/[strutils]

const DefaultCss* = """
/* Fossil-Nim default theme - port of Fossil's default CSS */
:root {
  --primary: #007bff;
  --secondary: #6c757d;
  --success: #28a745;
  --danger: #dc3545;
  --warning: #ffc107;
  --info: #17a2b8;
  --light: #f8f9fa;
  --dark: #343a40;
  --font-sans: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
  --font-mono: SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
}
* { box-sizing: border-box; }
body {
  font-family: var(--font-sans);
  line-height: 1.6;
  color: #212529;
  background: var(--light);
  margin: 0;
  padding: 0;
}
a { color: var(--primary); text-decoration: none; }
a:hover { text-decoration: underline; }
.container { max-width: 1200px; margin: 0 auto; padding: 0 20px; }
.card {
  background: white;
  border: 1px solid #dee2e6;
  border-radius: 6px;
  padding: 20px;
  margin: 15px 0;
  box-shadow: 0 1px 3px rgba(0,0,0,0.1);
}
.btn {
  display: inline-block;
  padding: 6px 12px;
  border: 1px solid transparent;
  border-radius: 4px;
  cursor: pointer;
  text-align: center;
  font-size: 14px;
  transition: all 0.15s;
}
.btn-primary { background: var(--primary); color: white; border-color: var(--primary); }
.btn-primary:hover { background: #0056b3; }
.btn-secondary { background: var(--secondary); color: white; }
.btn-danger { background: var(--danger); color: white; }
.badge {
  display: inline-block;
  padding: 2px 8px;
  border-radius: 10px;
  font-size: 11px;
  font-weight: bold;
  color: white;
}
.badge-primary { background: var(--primary); }
.badge-success { background: var(--success); }
.badge-danger { background: var(--danger); }
.badge-warning { background: var(--warning); color: #212529; }
.timeline { position: relative; }
.timeline::before {
  content: '';
  position: absolute;
  left: 20px;
  top: 0;
  bottom: 0;
  width: 2px;
  background: #dee2e6;
}
.timeline-item {
  position: relative;
  padding-left: 50px;
  margin-bottom: 20px;
}
.timeline-item::before {
  content: '';
  position: absolute;
  left: 12px;
  top: 5px;
  width: 16px;
  height: 16px;
  border-radius: 50%;
  background: var(--primary);
  border: 2px solid white;
  box-shadow: 0 1px 3px rgba(0,0,0,0.3);
}
pre { background: #f8f9fa; padding: 15px; border-radius: 4px; overflow-x: auto; border: 1px solid #e9ecef; }
code { font-family: var(--font-mono); background: #f1f3f5; padding: 2px 6px; border-radius: 3px; font-size: 0.9em; }
table { width: 100%; border-collapse: collapse; background: white; }
th, td { padding: 10px 12px; border: 1px solid #dee2e6; text-align: left; }
th { background: var(--dark); color: white; }
tr:hover { background: #f8f9fa; }
input, textarea, select {
  padding: 8px 12px;
  border: 1px solid #ced4da;
  border-radius: 4px;
  font-family: inherit;
  font-size: 14px;
}
input:focus, textarea:focus, select:focus {
  outline: none;
  border-color: var(--primary);
  box-shadow: 0 0 0 2px rgba(0,123,255,0.25);
}
.navbar {
  background: var(--dark);
  color: white;
  padding: 10px 20px;
  display: flex;
  justify-content: space-between;
  align-items: center;
}
.navbar a { color: white; margin: 0 10px; }
.navbar a:hover { color: #adb5bd; }
.footer {
  text-align: center;
  padding: 20px;
  color: var(--secondary);
  font-size: 14px;
  border-top: 1px solid #dee2e6;
  margin-top: 40px;
}
"""

const TimelineJs* = """
// Timeline JS - port of Fossil's timeline.js
function initTimeline() {
  const items = document.querySelectorAll('.timeline-item');
  items.forEach(item => {
    item.addEventListener('click', (e) => {
      if (e.target.tagName !== 'A') {
        const link = item.querySelector('a');
        if (link) window.location = link.href;
      }
    });
  });
}
document.addEventListener('DOMContentLoaded', initTimeline);
"""

const GraphJs* = """
// Graph JS - port of graph.js
class CommitGraph {
  constructor(container, nodes) {
    this.container = container;
    this.nodes = nodes;
    this.init();
  }
  init() {
    this.container.innerHTML = '';
    const svgNS = "http://www.w3.org/2000/svg";
    const svg = document.createElementNS(svgNS, "svg");
    svg.setAttribute("width", "100%");
    svg.setAttribute("height", Math.max(800, this.nodes.length * 60));
    this.nodes.forEach(n => {
      // Draw edges to parents
      n.parents.forEach(pid => {
        const parent = this.nodes.find(x => x.rid === pid);
        if (parent) {
          const line = document.createElementNS(svgNS, "line");
          line.setAttribute("x1", n.x + 7);
          line.setAttribute("y1", n.y + 7);
          line.setAttribute("x2", parent.x + 7);
          line.setAttribute("y2", parent.y + 7);
          line.setAttribute("stroke", n.color);
          line.setAttribute("stroke-width", "2");
          line.setAttribute("opacity", "0.5");
          svg.appendChild(line);
        }
      });
      // Draw node
      const circle = document.createElementNS(svgNS, "circle");
      circle.setAttribute("cx", n.x + 7);
      circle.setAttribute("cy", n.y + 7);
      circle.setAttribute("r", "7");
      circle.setAttribute("fill", n.color);
      circle.setAttribute("stroke", "white");
      circle.setAttribute("stroke-width", "2");
      circle.style.cursor = "pointer";
      circle.addEventListener("click", () => window.location = '/info?rid=' + n.rid);
      svg.appendChild(circle);
    });
    this.container.appendChild(svg);
    // Labels
    this.nodes.forEach(n => {
      const div = document.createElement("div");
      div.style.position = "absolute";
      div.style.left = (n.x + 25) + "px";
      div.style.top = (n.y - 2) + "px";
      div.style.fontSize = "12px";
      div.style.background = "rgba(255,255,255,0.9)";
      div.style.padding = "2px 6px";
      div.style.borderRadius = "3px";
      div.style.border = "1px solid #dee2e6";
      div.style.maxWidth = "300px";
      div.style.overflow = "hidden";
      div.style.textOverflow = "ellipsis";
      div.style.whiteSpace = "nowrap";
      div.style.cursor = "pointer";
      div.innerHTML = `<b>${n.branch}</b> ${n.comment.substring(0,60)} <small>by ${n.user}</small>`;
      div.addEventListener("click", () => window.location = '/info?rid=' + n.rid);
      this.container.appendChild(div);
    });
  }
}
"""

const WysiwygJs* = """
// WYSIWYG editor - toolbar for wiki
function insertMd(open, close, placeholder) {
  const ta = document.getElementById('editor');
  if (!ta) return;
  const start = ta.selectionStart;
  const end = ta.selectionEnd;
  const selected = ta.value.substring(start, end) || placeholder || 'text';
  const before = ta.value.substring(0, start);
  const after = ta.value.substring(end);
  ta.value = before + open + selected + close + after;
  ta.selectionStart = start + open.length;
  ta.selectionEnd = start + open.length + selected.length;
  ta.focus();
  updatePreview();
}
function updatePreview() {
  const content = document.getElementById('editor')?.value || '';
  fetch('/api/v1/markdown', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({text: content})
  }).then(r=>r.json()).then(j=>{
    const preview = document.getElementById('preview');
    if (preview && j.data) preview.innerHTML = j.data.html || j.data;
  }).catch(()=>{});
}
document.addEventListener('DOMContentLoaded', ()=>{
  const ed = document.getElementById('editor');
  if (ed) ed.addEventListener('input', updatePreview);
});
"""

const SearchJs* = """
// Search with live preview
let searchTimeout;
function liveSearch(query) {
  clearTimeout(searchTimeout);
  searchTimeout = setTimeout(()=>{
    if (query.length < 2) return;
    fetch('/api/v1/search?q='+encodeURIComponent(query))
      .then(r=>r.json()).then(j=>{
        const results = document.getElementById('search-results');
        if (!results) return;
        results.innerHTML = '';
        (j.data?.results || []).forEach(r=>{
          const div = document.createElement('div');
          div.className = 'card';
          div.innerHTML = `<b>[${r.kind}]</b> <a href="/${r.kind}/${r.id}">${r.title}</a><br><small>${r.snippet||''}</small>`;
          results.appendChild(div);
        });
      });
  }, 300);
}
"""

proc renderBasePage*(title: string, body: string, currentUser: string = "", extraHead: string = ""): string =
  var html = "<html><head><title>" & title & " - Fossil</title>"
  html.add "<meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>"
  html.add "<style>" & DefaultCss & "</style>"
  html.add extraHead
  html.add "</head><body>"
  html.add "<nav class='navbar'><div><a href='/'><b>🦖 Fossil-Nim</b></a><a href='/timeline'>Timeline</a><a href='/file'>Files</a><a href='/wiki'>Wiki</a><a href='/ticket'>Tickets</a><a href='/forum'>Forum</a><a href='/chat'>Chat</a><a href='/graph'>Graph</a><a href='/search'>Search</a></div><div>"
  if currentUser.len>0:
    html.add "<span>" & currentUser & "</span><a href='/setup'>Setup</a><a href='/logout'>Logout</a>"
  else:
    html.add "<a href='/login'>Login</a><a href='/setup'>Setup</a>"
  html.add "</div></nav>"
  html.add "<div class='container'>" & body & "</div>"
  html.add "<footer class='footer'>Fossil-Nim " & "2.26.0-nim" & " | <a href='/help'>Help</a> | <a href='/api/v1/openapi.json'>API</a> | Storage: SQLite/LMDB/MDBX/CDB | QBE compatible</footer>"
  html.add "</body></html>"
  html

proc getAsset*(name: string): string =
  case name
  of "style.css", "default.css": DefaultCss
  of "timeline.js": TimelineJs
  of "graph.js": GraphJs
  of "wysiwyg.js": WysiwygJs
  of "search.js": SearchJs
  else: ""
