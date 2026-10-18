## Required by `--os:standalone`: Nim calls these instead of libc/stdout.
## On wasm a "panic" must not trap the instance (a trap kills every subsequent
## call), so it degrades to an internal error code.
proc panic*(msg: string) {.noreturn.} =
  {.emit: """__builtin_trap();""".}
  while true: discard

proc rawoutput*(s: cstring) = discard
