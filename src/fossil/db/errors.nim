## Error model for Foccil DB.
##
## Design rules (security & energy):
##  * errors carry a stable numeric code (SQLite-compatible numbering where it
##    makes sense) so callers can branch without string matching;
##  * no message contains user data unless explicitly marked `safe`;
##  * errors are raised, never abort the process (no `quit`, no `assert`).

type
  DbCode* = enum
    ok = 0
    generic = 1
    noMem = 7
    readOnly = 8
    interrupt = 9
    ioErr = 10
    corrupt = 11
    notFound = 12
    full = 13
    busy = 5
    locked = 6
    schemaChanged = 17
    tooBig = 18
    constraint = 19
    mismatch = 20
    misuse = 21
    auth = 23
    range = 25
    syntax = 1_0001
    unsupported = 1_0002
    typeErr = 1_0003
    limit = 1_0004
    badParam = 1_0005
    injection = 1_0006   ## dynamic SQL rejected by the strict-SQL guard

  DbError* = object of CatchableError
    code*: DbCode
    ## Optional machine-readable context. Must never contain row data.
    context*: string

proc dbErr*(code: DbCode; msg: string; context = ""): ref DbError =
  ## Allocate (or reuse) an error. `newException` is not used on purpose:
  ## it does a stack trace walk on some backends, which costs energy in the
  ## common "expected" failure paths.
  result = (ref DbError)(code: code, msg: msg, context: context)

template fail*(code: DbCode; msg: string) =
  raise dbErr(code, msg)

template failf*(code: DbCode; fmt: string; args: varargs[untyped]) =
  raise dbErr(code, fmt % args)

proc codeName*(c: DbCode): string =
  ## Stable textual code, safe for logs and wire protocols.
  case c
  of ok: "OK"
  of generic: "GENERIC"
  of noMem: "NOMEM"
  of readOnly: "READONLY"
  of interrupt: "INTERRUPT"
  of ioErr: "IOERR"
  of corrupt: "CORRUPT"
  of notFound: "NOTFOUND"
  of full: "FULL"
  of busy: "BUSY"
  of locked: "LOCKED"
  of schemaChanged: "SCHEMA"
  of tooBig: "TOOBIG"
  of constraint: "CONSTRAINT"
  of mismatch: "MISMATCH"
  of misuse: "MISUSE"
  of auth: "AUTH"
  of range: "RANGE"
  of syntax: "SYNTAX"
  of unsupported: "UNSUPPORTED"
  of typeErr: "TYPE"
  of limit: "LIMIT"
  of badParam: "PARAM"
  of injection: "INJECTION"
