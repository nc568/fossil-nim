## Graph page - port of graph.c, graph.js visualization

import ../../types
import ../../storage/sqlite_backend
import std/[strutils, times, json, sequtils, tables]

type
  GraphNode* = object
    rid*: Rid
    uuid*: string
    mtime*: int64
    user*: string
    comment*: string
    branch*: string
    parents*: seq[Rid]
    children*: seq[Rid]
    x*: int
    y*: int
    color*: string

proc getGraphDataSqlite*(backend: SqliteBackend, limit: int = 100, branch: string = ""): FossilResult[seq[GraphNode]] =
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_column_text(pStmt: ptr sqlite3_stmt, iCol: cint): cstring {.importc.}
  proc sqlite3_column_int64(pStmt: ptr sqlite3_stmt, iCol: cint): int64 {.importc.}
  proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
  proc sqlite3_bind_int(pStmt: ptr sqlite3_stmt, i: cint, v: cint): cint {.importc.}
  {.pop.}
  const SQLITE_ROW = 100
  var nodes: seq[GraphNode] = @[]
  var sql = "SELECT blob.rid, blob.uuid, event.mtime, event.user, event.comment, event.branch FROM event JOIN blob ON event.objid=blob.rid ORDER BY event.mtime DESC LIMIT ?1"
  if branch.len>0:
    sql = "SELECT blob.rid, blob.uuid, event.mtime, event.user, event.comment, event.branch FROM event JOIN blob ON event.objid=blob.rid WHERE event.branch=?2 ORDER BY event.mtime DESC LIMIT ?1"
  var stmt: ptr sqlite3_stmt
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return ok(nodes)
  discard sqlite3_bind_int(stmt, 1, cint(limit))
  if branch.len>0:
    discard sqlite3_bind_text(stmt, 2, branch.cstring, -1, nil)
  while sqlite3_step(stmt) == SQLITE_ROW:
    let rid = sqlite3_column_int64(stmt, 0)
    let uuidPtr = sqlite3_column_text(stmt, 1)
    let mtime = sqlite3_column_int64(stmt, 2)
    let userPtr = sqlite3_column_text(stmt, 3)
    let commentPtr = sqlite3_column_text(stmt, 4)
    let branchPtr = sqlite3_column_text(stmt, 5)
    let uuid = if uuidPtr!=nil: $uuidPtr else: ""
    let user = if userPtr!=nil: $userPtr else: ""
    let comment = if commentPtr!=nil: $commentPtr else: ""
    let br = if branchPtr!=nil: $branchPtr else: "trunk"
    # Simple color by branch hash
    var hash = 0
    for c in br: hash = hash*31 + int(c)
    let colors = ["#007bff","#28a745","#dc3545","#ffc107","#6f42c1","#fd7e14","#20c997","#e83e8c"]
    let color = colors[abs(hash) mod colors.len]
    nodes.add GraphNode(rid: Rid(rid), uuid: uuid, mtime: mtime, user: user, comment: comment, branch: br, color: color)
  discard sqlite3_finalize(stmt)

  # Get parents for each node via plink or mlink parent approximation
  for i in 0..<nodes.len:
    let sqlParents = "SELECT pid FROM plink WHERE cid=?1"
    var stmt2: ptr sqlite3_stmt
    if sqlite3_prepare_v2(backend.db, sqlParents.cstring, -1, addr stmt2, nil) == 0:
      discard sqlite3_bind_int(stmt2, 1, cint(int(nodes[i].rid)))
      # Actually bind int64
      {.push header: "<sqlite3.h>".}
      proc sqlite3_bind_int64(pStmt: ptr sqlite3_stmt, i: cint, v: int64): cint {.importc.}
      {.pop.}
      discard sqlite3_bind_int64(stmt2, 1, int64(nodes[i].rid))
      while sqlite3_step(stmt2) == SQLITE_ROW:
        let pid = sqlite3_column_int64(stmt2, 0)
        nodes[i].parents.add Rid(pid)
      discard sqlite3_finalize(stmt2)
    # Layout: simple y = index, x = branch offset
    nodes[i].y = i * 60 + 20
    # x based on branch
    var branchIdx = 0
    for j in 0..<i:
      if nodes[j].branch == nodes[i].branch:
        branchIdx.inc
        break
    # Use hash for x
    var bhash = 0
    for c in nodes[i].branch: bhash = bhash*7 + int(c)
    nodes[i].x = 50 + (abs(bhash) mod 5) * 120

  ok(nodes)

proc graphToJson*(nodes: seq[GraphNode]): JsonNode =
  var arr = newJArray()
  for n in nodes:
    var obj = newJObject()
    obj["rid"] = newJInt(int(n.rid))
    obj["uuid"] = newJString(n.uuid)
    obj["mtime"] = newJInt(int(n.mtime))
    obj["user"] = newJString(n.user)
    obj["comment"] = newJString(n.comment)
    obj["branch"] = newJString(n.branch)
    obj["color"] = newJString(n.color)
    obj["x"] = newJInt(n.x)
    obj["y"] = newJInt(n.y)
    var parents = newJArray()
    for p in n.parents:
      parents.add newJInt(int(p))
    obj["parents"] = parents
    arr.add obj
  arr

proc renderGraphPage*(nodes: seq[GraphNode], branch: string = ""): string =
  let jsonData = $graphToJson(nodes)
  # Build branch legend
  var branchSet = initTable[string, string]()
  for n in nodes:
    if not branchSet.hasKey(n.branch):
      branchSet[n.branch] = n.color
  var legendHtml = ""
  for br, col in branchSet:
    legendHtml.add "<span style='display:inline-flex;align-items:center;gap:6px;margin-right:12px'><span style='width:12px;height:12px;border-radius:50%;background:" & col & ";display:inline-block'></span>" & br & "</span>"

  var html = """<html><head><meta charset="UTF-8"><title>Commit Graph - Fossil-Nim</title>
<style>
body{font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif;margin:0;padding:0;background:#f8f9fa;color:#212529}
header{background:#343a40;color:white;padding:14px 20px;display:flex;justify-content:space-between;align-items:center;box-shadow:0 2px 4px rgba(0,0,0,0.2)}
header h1{margin:0;font-size:20px;font-weight:600}
header a{color:#adb5bd;text-decoration:none;margin-left:12px}
header a:hover{color:white;text-decoration:underline}
.controls{padding:12px 20px;background:white;border-bottom:1px solid #dee2e6;display:flex;gap:12px;align-items:center;flex-wrap:wrap;position:sticky;top:0;z-index:10;box-shadow:0 1px 3px rgba(0,0,0,0.05)}
#graphContainer{position:relative;width:calc(100% - 40px);margin:20px;background:white;border:1px solid #dee2e6;border-radius:8px;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,0.06)}
#graph{position:relative;width:100%;min-height:600px;overflow:auto}
#svgLayer{position:absolute;top:0;left:0;width:100%;height:100%;pointer-events:none;z-index:1}
.node{position:absolute;width:16px;height:16px;border-radius:50%;border:3px solid white;box-shadow:0 2px 6px rgba(0,0,0,0.25);cursor:pointer;z-index:3;transition:transform 0.15s, box-shadow 0.15s}
.node:hover{transform:scale(1.4);box-shadow:0 4px 12px rgba(0,0,0,0.35);z-index:5}
.node-label{position:absolute;font-size:12px;white-space:nowrap;background:rgba(255,255,255,0.95);padding:4px 8px;border-radius:6px;border:1px solid #e9ecef;max-width:320px;overflow:hidden;text-overflow:ellipsis;box-shadow:0 1px 4px rgba(0,0,0,0.08);z-index:2;cursor:pointer;transition:background 0.15s}
.node-label:hover{background:#fff;border-color:#0d6efd;box-shadow:0 2px 8px rgba(13,110,253,0.15)}
.tooltip{position:fixed;background:#212529;color:white;padding:10px 14px;border-radius:8px;font-size:12px;max-width:400px;z-index:100;pointer-events:none;opacity:0;transition:opacity 0.15s;box-shadow:0 4px 16px rgba(0,0,0,0.3);line-height:1.4}
.tooltip.show{opacity:1}
.legend{display:flex;flex-wrap:wrap;gap:4px;align-items:center}
.btn{padding:6px 12px;border:1px solid #ced4da;border-radius:6px;background:white;cursor:pointer;font-size:13px;transition:all 0.15s}
.btn:hover{background:#f8f9fa;border-color:#adb5bd}
.btn-primary{background:#0d6efd;color:white;border-color:#0d6efd}
.btn-primary:hover{background:#0b5ed7}
input{padding:6px 10px;border:1px solid #ced4da;border-radius:6px;font-size:13px}
input:focus{outline:none;border-color:#0d6efd;box-shadow:0 0 0 3px rgba(13,110,253,0.15)}
.zoom-controls{position:absolute;top:12px;right:12px;z-index:20;display:flex;flex-direction:column;gap:6px;background:white;padding:8px;border-radius:8px;box-shadow:0 2px 8px rgba(0,0,0,0.12);border:1px solid #e9ecef}
.zoom-controls button{width:32px;height:32px;display:flex;align-items:center;justify-content:center;font-weight:bold;font-size:16px}
.minimap{position:absolute;bottom:12px;right:12px;width:160px;height:120px;background:rgba(255,255,255,0.95);border:1px solid #dee2e6;border-radius:6px;z-index:20;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,0.1)}
</style></head><body>"""
  html.add "<header><h1>📊 Commit Graph" & (if branch.len>0: " - " & branch else: "") & "</h1><div><a href='/timeline'>Timeline</a><a href='/brlist'>Branches</a><a href='/'>Home</a><a href='/help'>Help</a></div></header>"
  html.add "<div class='controls'><form method='get' action='/graph' style='display:flex;gap:8px;align-items:center'><label>Branch: <input name='branch' value='" & branch & "' placeholder='trunk' style='width:140px'></label><button class='btn btn-primary' type='submit'>Filter</button></form><div class='legend'>" & legendHtml & "</div><span style='margin-left:auto;color:#6c757d;font-size:13px'>" & $nodes.len & " commits</span><button class='btn' onclick='resetZoom()'>Reset Zoom</button><button class='btn' onclick='toggleLabels()'>Toggle Labels</button></div>"
  html.add "<div id='graphContainer'><div id='graph'><svg id='svgLayer'></svg></div><div class='zoom-controls'><button class='btn' onclick='zoom(1.2)' title='Zoom In'>+</button><button class='btn' onclick='zoom(0.8)' title='Zoom Out'>−</button><button class='btn' onclick='resetZoom()' title='Reset'>⟲</button></div></div><div id='tooltip' class='tooltip'></div>"
  html.add "<script>const nodes=" & jsonData & ";\n"
  html.add """
let scale=1, panX=0, panY=0, showLabels=true;
const graphEl=document.getElementById('graph');
const svgEl=document.getElementById('svgLayer');
const tooltip=document.getElementById('tooltip');
const maxY = nodes.length>0 ? Math.max(...nodes.map(n=>n.y))+120 : 800;
const maxX = nodes.length>0 ? Math.max(...nodes.map(n=>n.x))+400 : 1200;
graphEl.style.height = maxY+'px';
graphEl.style.width = Math.max(maxX, 800)+'px';
svgEl.setAttribute('width', maxX);
svgEl.setAttribute('height', maxY);

function render() {
  // Clear previous
  graphEl.querySelectorAll('.node, .node-label').forEach(e=>e.remove());
  svgEl.innerHTML='';
  // Draw edges as SVG paths with curves
  nodes.forEach(n=>{
    n.parents.forEach(pid=>{
      const parent=nodes.find(x=>x.rid===pid);
      if(parent){
        const path=document.createElementNS('http://www.w3.org/2000/svg','path');
        const x1=n.x+8, y1=n.y+8, x2=parent.x+8, y2=parent.y+8;
        const midY = (y1+y2)/2;
        // Bezier curve for nicer look
        const d = `M ${x1} ${y1} C ${x1} ${midY}, ${x2} ${midY}, ${x2} ${y2}`;
        path.setAttribute('d', d);
        path.setAttribute('fill','none');
        path.setAttribute('stroke', n.color);
        path.setAttribute('stroke-width','2.5');
        path.setAttribute('stroke-opacity','0.45');
        path.setAttribute('stroke-linecap','round');
        svgEl.appendChild(path);
      }
    });
  });
  // Draw nodes
  nodes.forEach(n=>{
    const dot=document.createElement('div');
    dot.className='node';
    dot.style.left=n.x+'px';
    dot.style.top=n.y+'px';
    dot.style.background=n.color;
    dot.dataset.rid=n.rid;
    dot.addEventListener('mouseenter', (e)=>showTooltip(e, n));
    dot.addEventListener('mouseleave', hideTooltip);
    dot.addEventListener('click', ()=>{window.location='/info?id='+n.rid;});
    graphEl.appendChild(dot);

    if(showLabels){
      const label=document.createElement('div');
      label.className='node-label';
      label.style.left=(n.x+26)+'px';
      label.style.top=(n.y-2)+'px';
      const date = new Date(n.mtime*1000).toISOString().slice(0,10);
      label.innerHTML=`<b style="color:${n.color}">${n.branch}</b> <span style="color:#212529">${esc(n.comment.substring(0,70))}</span> <small style="color:#6c757d">by ${esc(n.user)} ${date}</small>`;
      label.addEventListener('mouseenter', (e)=>showTooltip(e, n));
      label.addEventListener('mouseleave', hideTooltip);
      label.addEventListener('click', ()=>{window.location='/info?id='+n.rid;});
      graphEl.appendChild(label);
    }
  });
}
function esc(s){return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');}
function showTooltip(e, n){
  const date = new Date(n.mtime*1000).toLocaleString();
  tooltip.innerHTML=`<div style="font-weight:600;margin-bottom:4px">${esc(n.branch)} @ ${n.uuid.substring(0,10)}</div><div>${esc(n.comment)}</div><div style="margin-top:6px;color:#adb5bd;font-size:11px">by ${esc(n.user)} • ${date}<br>rid=${n.rid} parents=${n.parents.join(', ')}</div>`;
  tooltip.style.left=(e.clientX+14)+'px';
  tooltip.style.top=(e.clientY+14)+'px';
  tooltip.classList.add('show');
}
function hideTooltip(){tooltip.classList.remove('show');}
function zoom(factor){
  scale*=factor;
  scale=Math.max(0.3, Math.min(3, scale));
  graphEl.style.transform=`scale(${scale})`;
  graphEl.style.transformOrigin='0 0';
}
function resetZoom(){scale=1; graphEl.style.transform='scale(1)';}
function toggleLabels(){showLabels=!showLabels; render();}
let isPanning=false, startX, startY;
graphEl.addEventListener('mousedown', (e)=>{if(e.target===graphEl || e.target===svgEl){isPanning=true; startX=e.clientX-panX; startY=e.clientY-panY; graphEl.style.cursor='grabbing';}});
window.addEventListener('mousemove', (e)=>{if(isPanning){panX=e.clientX-startX; panY=e.clientY-startY; graphEl.style.transform=`translate(${panX}px, ${panY}px) scale(${scale})`;}});
window.addEventListener('mouseup', ()=>{isPanning=false; graphEl.style.cursor='';});
document.addEventListener('mousemove', (e)=>{if(tooltip.classList.contains('show')){tooltip.style.left=(e.clientX+14)+'px'; tooltip.style.top=(e.clientY+14)+'px';}});
render();
// Keyboard shortcuts
document.addEventListener('keydown', (e)=>{
  if(e.key==='+'){zoom(1.2);}
  else if(e.key==='-'){zoom(0.8);}
  else if(e.key==='0'){resetZoom();}
  else if(e.key==='l'){toggleLabels();}
});
</script>"""
  html.add "</body></html>"
  html

proc renderGraphJson*(nodes: seq[GraphNode]): string =
  $graphToJson(nodes)
