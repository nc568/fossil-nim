## TH1 Interpreter - Fossil's Tcl-like scripting language
## Minimal but functional: variables, set, puts, if, foreach, for, proc, return, expr, string, list, dict, html escaping, etc.

import std/[tables, strutils, sequtils, math, times]

type
  Th1Value* = object
    case isList*: bool
    of true:
      listVal*: seq[Th1Value]
    of false:
      strVal*: string

  Th1Interp* = object
    vars*: Table[string, Th1Value]
    procs*: Table[string, Th1Proc]
    output*: string
    returnFlag*: bool
    returnValue*: Th1Value
    error*: string
    stepCount*: int
    maxSteps*: int

  Th1Proc* = object
    args*: seq[string]
    body*: string

proc th1Str*(s: string): Th1Value = Th1Value(isList: false, strVal: s)
proc th1List*(l: seq[Th1Value]): Th1Value = Th1Value(isList: true, listVal: l)
proc th1Int*(i: int): Th1Value = th1Str($i)
proc th1Bool*(b: bool): Th1Value = th1Str(if b: "1" else: "0")

proc toStr*(v: Th1Value): string =
  if v.isList:
    v.listVal.mapIt(it.toStr).join(" ")
  else:
    v.strVal

proc toIntVal*(v: Th1Value): int =
  try: parseInt(v.toStr) except: 0

proc toBool*(v: Th1Value): bool =
  let s = v.toStr.toLowerAscii.strip()
  if s=="0" or s=="" or s=="false" or s=="no" or s=="off": false else: true

proc newInterp*(maxSteps: int = 50_000): Th1Interp =
  Th1Interp(vars: initTable[string, Th1Value](), procs: initTable[string, Th1Proc](), output: "", returnFlag: false, returnValue: th1Str(""), error: "", stepCount: 0, maxSteps: maxSteps)

proc setVar*(interp: var Th1Interp, name, value: string) =
  interp.vars[name] = th1Str(value)

proc getVar*(interp: Th1Interp, name: string): string =
  if interp.vars.hasKey(name): interp.vars[name].toStr else: ""

proc safeParseInt(s: string): int =
  try: parseInt(s.strip()) except: 0

# --- Tokenizer for TH1 (Tcl-like) ---

proc th1ParseWords(s: string): seq[string] =
  var words: seq[string] = @[]
  var i=0
  var cur=""
  var inQuote=false
  var braceDepth=0
  var bracketDepth=0
  var inWord=false
  while i<s.len:
    let ch = s[i]
    if not inWord and ch.isSpaceAscii():
      inc i; continue
    if not inWord:
      inWord=true
      cur=""
    if ch=='"' and braceDepth==0 and bracketDepth==0:
      if inQuote:
        inQuote=false
      else:
        inQuote=true
      inc i
      continue
    if not inQuote:
      if ch=='{' :
        if braceDepth==0 and cur.len==0:
          braceDepth=1
          inc i
          continue
        else:
          if braceDepth>0: braceDepth+=1
      elif ch=='}':
        if braceDepth>0:
          braceDepth-=1
          if braceDepth==0:
            words.add cur
            cur=""
            inWord=false
            inc i
            continue
      elif ch=='[' and braceDepth==0:
        if bracketDepth==0 and cur.len==0:
          bracketDepth=1
          var j=i+1
          var depth=1
          var cmd=""
          while j<s.len:
            if s[j]=='[': depth+=1
            elif s[j]==']':
              depth-=1
              if depth==0: break
            cmd.add s[j]
            inc j
          cur = "\x01" & cmd & "\x01"
          i=j+1
          continue
        else:
          if bracketDepth>0: bracketDepth+=1
      elif ch==']' and bracketDepth>0:
        bracketDepth-=1
      elif ch.isSpaceAscii() and braceDepth==0 and bracketDepth==0 and not inQuote:
        if cur.len>0:
          words.add cur
        cur=""
        inWord=false
        inc i
        continue
    cur.add ch
    inc i
  if cur.len>0:
    words.add cur
  words

proc th1SplitCommands(script: string): seq[string] =
  var cmds: seq[string] = @[]
  var cur=""
  var braceDepth=0
  var inQuote=false
  var i=0
  while i<script.len:
    let ch = script[i]
    if ch=='"' and braceDepth==0:
      inQuote = not inQuote
      cur.add ch
    elif not inQuote:
      if ch=='{': braceDepth+=1; cur.add ch
      elif ch=='}': braceDepth-=1; cur.add ch
      elif ch==';' and braceDepth==0:
        if cur.strip().len>0: cmds.add cur.strip()
        cur=""
      elif ch=='\n' and braceDepth==0:
        if cur.strip().len>0: cmds.add cur.strip()
        cur=""
      else:
        cur.add ch
    else:
      cur.add ch
    inc i
  if cur.strip().len>0: cmds.add cur.strip()
  cmds

# Forward decl
proc evalScript*(interp: var Th1Interp, script: string): Th1Value {.gcsafe.}
proc evalWord*(interp: var Th1Interp, word: string): string {.gcsafe.}
proc evalCondition*(interp: var Th1Interp, condWord: string): bool {.gcsafe.}

proc evalWord*(interp: var Th1Interp, word: string): string {.gcsafe.} =
  if word.len>=2 and word[0]=='\x01' and word[^1]=='\x01':
    let inner = word[1..^2]
    let res = interp.evalScript(inner)
    return res.toStr
  var res=""
  var i=0
  while i<word.len:
    let ch = word[i]
    if ch=='$':
      if i+1<word.len and word[i+1]=='{':
        let j = word.find('}', i+2)
        if j != -1:
          let varName = word[i+2..<j]
          res.add interp.getVar(varName)
          i=j+1
          continue
      else:
        var j=i+1
        while j<word.len and (word[j].isAlphaNumeric() or word[j]=='_' or word[j]==':'):
          inc j
        let varName = word[i+1..<j]
        if varName.len>0:
          res.add interp.getVar(varName)
          i=j
          continue
        else:
          res.add ch; inc i
    elif ch=='[':
      var depth=1
      var j=i+1
      var cmd=""
      while j<word.len:
        if word[j]=='[':
          depth+=1
        elif word[j]==']':
          depth-=1
          if depth==0: break
        cmd.add word[j]
        inc j
      let evalRes = interp.evalScript(cmd)
      res.add evalRes.toStr
      i=j+1
    elif ch=='\\' and i+1<word.len:
      let nxt = word[i+1]
      case nxt
      of 'n': res.add '\n'
      of 't': res.add '\t'
      of 'r': res.add '\r'
      of '\\': res.add '\\'
      of '$': res.add '$'
      of '"': res.add '"'
      of '[': res.add '['
      of ']': res.add ']'
      of '{': res.add '{'
      of '}': res.add '}'
      else: res.add nxt
      i+=2
    else:
      res.add ch; inc i
  res

proc evalCondition*(interp: var Th1Interp, condWord: string): bool {.gcsafe.} =
  var condStr = interp.evalWord(condWord).strip()
  if condStr.startsWith("[") and condStr.endsWith("]"):
    condStr = interp.evalScript(condStr[1..^2]).toStr.strip()
  elif condStr.startsWith("expr ") or condStr == "expr":
    condStr = interp.evalScript(condStr).toStr.strip()
  if condStr == "1" or condStr.toLowerAscii() == "true" or condStr == "yes":
    return true
  elif condStr == "0" or condStr.toLowerAscii() == "false" or condStr == "" or condStr == "no":
    return false
  try:
    if condStr.contains("=="):
      let parts = condStr.split("==")
      return parts[0].strip() == parts[1].strip()
    elif condStr.contains("!="):
      let parts = condStr.split("!=")
      return parts[0].strip() != parts[1].strip()
    elif condStr.contains(">="):
      let parts = condStr.split(">=")
      return safeParseInt(parts[0]) >= safeParseInt(parts[1])
    elif condStr.contains("<="):
      let parts = condStr.split("<=")
      return safeParseInt(parts[0]) <= safeParseInt(parts[1])
    elif condStr.contains(">"):
      let parts = condStr.split(">")
      return safeParseInt(parts[0]) > safeParseInt(parts[1])
    elif condStr.contains("<"):
      let parts = condStr.split("<")
      return safeParseInt(parts[0]) < safeParseInt(parts[1])
    else:
      return safeParseInt(condStr) != 0
  except:
    return condStr.len > 0

proc evalScript*(interp: var Th1Interp, script: string): Th1Value {.gcsafe.} =
  if interp.returnFlag:
    return interp.returnValue
  inc interp.stepCount
  if interp.maxSteps > 0 and interp.stepCount > interp.maxSteps:
    interp.error = "TH1 execution limit exceeded: maximum step count reached (" & $interp.maxSteps & ")"
    interp.returnFlag = true
    return th1Str("")
  var last = th1Str("")
  let commands = th1SplitCommands(script)
  for cmdStr in commands:
    if cmdStr.strip().len==0: continue
    if cmdStr.strip().startsWith("#"): continue
    let rawWords = th1ParseWords(cmdStr)
    if rawWords.len==0: continue
    let cmdName = interp.evalWord(rawWords[0]).toLowerAscii()
    var args: seq[string] = @[]
    for k in 1..<rawWords.len:
      args.add rawWords[k]
    case cmdName
    of "set":
      if args.len==1:
        let varName = interp.evalWord(args[0])
        last = th1Str(interp.getVar(varName))
      elif args.len>=2:
        let varName = interp.evalWord(args[0])
        let value = interp.evalWord(args[1])
        interp.vars[varName] = th1Str(value)
        last = th1Str(value)
      else:
        last = th1Str("")
    of "puts":
      var what = ""
      if args.len==0: what=""
      elif args.len==1: what = interp.evalWord(args[0])
      else:
        what = interp.evalWord(args[^1])
      interp.output.add what & "\n"
      last = th1Str(what)
    of "append":
      if args.len>=1:
        let varName = interp.evalWord(args[0])
        var cur = interp.getVar(varName)
        for idx in 1..<args.len:
          cur.add interp.evalWord(args[idx])
        interp.vars[varName] = th1Str(cur)
        last = th1Str(cur)
    of "incr":
      if args.len>=1:
        let varName = interp.evalWord(args[0])
        let incVal = if args.len>=2: safeParseInt(interp.evalWord(args[1])) else: 1
        let cur = safeParseInt(interp.getVar(varName)) + incVal
        interp.vars[varName] = th1Int(cur)
        last = th1Int(cur)
    of "if":
      if args.len>=2:
        let condTrue = interp.evalCondition(args[0])
        if condTrue:
          last = interp.evalScript(args[1])
        else:
          if args.len>=4 and args[2].toLowerAscii()=="else":
            last = interp.evalScript(args[3])
          elif args.len>=3:
            if args.len==3:
              last = interp.evalScript(args[2])
    of "expr":
      if args.len>=1:
        let exprStr = args.mapIt(interp.evalWord(it)).join(" ")
        var res=0
        try:
          let tokens = exprStr.splitWhitespace()
          if tokens.len==1:
            res = safeParseInt(tokens[0])
          elif tokens.len==3:
            let a = safeParseInt(tokens[0])
            let b = safeParseInt(tokens[2])
            case tokens[1]
            of "+": res = a+b
            of "-": res = a-b
            of "*": res = a*b
            of "/": res = if b!=0: a div b else: 0
            of "%": res = if b!=0: a mod b else: 0
            of "==": res = if a==b: 1 else: 0
            of "!=": res = if a!=b: 1 else: 0
            of ">": res = if a>b: 1 else: 0
            of "<": res = if a<b: 1 else: 0
            of ">=": res = if a>=b: 1 else: 0
            of "<=": res = if a<=b: 1 else: 0
            else: res=0
          else:
            res = safeParseInt(exprStr)
        except:
          res=0
        last = th1Int(res)
    of "foreach":
      if args.len>=3:
        let varName = interp.evalWord(args[0])
        let listStr = interp.evalWord(args[1])
        let body = args[2]
        let items = listStr.splitWhitespace()
        for item in items:
          interp.vars[varName] = th1Str(item)
          last = interp.evalScript(body)
          if interp.returnFlag: break
    of "for":
      if args.len>=4:
        let initScript = args[0]
        let condScript = args[1]
        let nextScript = args[2]
        let body = args[3]
        discard interp.evalScript(initScript)
        var iter = 0
        while true:
          inc iter
          if iter > 10_000 or (interp.maxSteps > 0 and interp.stepCount > interp.maxSteps):
            interp.error = "TH1 loop iteration limit exceeded"
            interp.returnFlag = true
            break
          if not interp.evalCondition(condScript): break
          last = interp.evalScript(body)
          if interp.returnFlag: break
          discard interp.evalScript(nextScript)
    of "while":
      if args.len>=2:
        let condScript = args[0]
        let body = args[1]
        var iter = 0
        while true:
          inc iter
          if iter > 10_000 or (interp.maxSteps > 0 and interp.stepCount > interp.maxSteps):
            interp.error = "TH1 loop iteration limit exceeded"
            interp.returnFlag = true
            break
          if not interp.evalCondition(condScript): break
          last = interp.evalScript(body)
          if interp.returnFlag: break
    of "proc":
      if args.len>=3:
        let procName = interp.evalWord(args[0])
        let argListStr = args[1]
        let body = args[2]
        let argNames = argListStr.splitWhitespace()
        interp.procs[procName] = Th1Proc(args: argNames, body: body)
        last = th1Str("")
    of "return":
      if args.len>=1:
        interp.returnValue = th1Str(interp.evalWord(args[0]))
      else:
        interp.returnValue = th1Str("")
      interp.returnFlag=true
      last = interp.returnValue
      return last
    of "break":
      break
    of "continue":
      continue
    of "string":
      if args.len>=2:
        let sub = interp.evalWord(args[0]).toLowerAscii()
        case sub
        of "length":
          last = th1Int(interp.evalWord(args[1]).len)
        of "tolower":
          last = th1Str(interp.evalWord(args[1]).toLowerAscii())
        of "toupper":
          last = th1Str(interp.evalWord(args[1]).toUpperAscii())
        of "trim":
          last = th1Str(interp.evalWord(args[1]).strip())
        of "first":
          let needle = interp.evalWord(args[1])
          let hay = if args.len>=3: interp.evalWord(args[2]) else: ""
          last = th1Int(hay.find(needle))
        else:
          last = th1Str(interp.evalWord(args[1]))
    of "htmlize", "html":
      if args.len>=1:
        let s = interp.evalWord(args[0])
        last = th1Str(s.replace("&","&amp;").replace("<","&lt;").replace(">","&gt;").replace("\"","&quot;"))
    of "list":
      var lst: seq[Th1Value]= @[]
      for a in args:
        lst.add th1Str(interp.evalWord(a))
      last = th1List(lst)
    of "llength":
      if args.len>=1:
        let l = interp.evalWord(args[0]).splitWhitespace()
        last = th1Int(l.len)
    of "lindex":
      if args.len>=2:
        let l = interp.evalWord(args[0]).splitWhitespace()
        let idx = safeParseInt(interp.evalWord(args[1]))
        if idx>=0 and idx<l.len:
          last = th1Str(l[idx])
        else:
          last = th1Str("")
    of "dict":
      last = th1Str(args.mapIt(interp.evalWord(it)).join(" "))
    else:
      if interp.procs.hasKey(cmdName):
        let p = interp.procs[cmdName]
        var oldVars = initTable[string, Th1Value]()
        for idx, argName in p.args:
          if idx<args.len:
            let val = interp.evalWord(args[idx])
            if interp.vars.hasKey(argName):
              oldVars[argName]=interp.vars[argName]
            interp.vars[argName]=th1Str(val)
        let savedReturn = interp.returnFlag
        let savedRetVal = interp.returnValue
        interp.returnFlag=false
        last = interp.evalScript(p.body)
        if interp.returnFlag:
          last = interp.returnValue
        interp.returnFlag=savedReturn
        if savedReturn:
          interp.returnValue=savedRetVal
        else:
          interp.returnFlag=false
        for argName in p.args:
          if oldVars.hasKey(argName):
            interp.vars[argName]=oldVars[argName]
          else:
            interp.vars.del(argName)
      else:
        last = th1Str("")
    if interp.returnFlag:
      return interp.returnValue
  last

proc evalTh1*(script: string, vars: Table[string, string] = initTable[string, string]()): string =
  var interp = newInterp()
  for k,v in vars:
    interp.vars[k]=th1Str(v)
  discard interp.evalScript(script)
  interp.output

when isMainModule:
  var interp = newInterp()
  interp.setVar("name", "World")
  let script = """
set greeting "Hello"
puts "$greeting, $name!"
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
"""
  discard interp.evalScript(script)
  echo interp.output
