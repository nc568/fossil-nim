# Package
version       = "2.26.0-nim"
author        = "Fossil-Nim Port"
description   = "Fossil SCM rewritten in Nim - modular, with MCP and modern storage backends"
license       = "BSD-2-Clause"
srcDir        = "src"
bin           = @["fossil/cli/main=fossil"]
binDir        = "bin"

# Dependencies
requires "nim >= 2.0.0"

# Tasks
task build, "Build fossil binary":
  exec "nim c -d:release --mm:orc --opt:speed --outdir:bin -o:bin/fossil src/fossil/cli/main.nim"
  exec "nim c -d:release --mm:orc --opt:speed --outdir:bin -o:bin/fossil-mcp src/fossil/mcp/server.nim"
  echo "Built bin/fossil and bin/fossil-mcp"

task buildQbe, "Build C sources for cproc/QBE compilation":
  exec "rm -rf build/cgen && mkdir -p build/cgen"
  exec "nim c --cc:clang --compileOnly --nimcache:build/cgen --outdir:build/cgen -d:release -d:qbeCompat --mm:refc --threads:off --panics:on -d:useMalloc --opt:speed src/fossil/cli/main.nim"
  echo "C files in build/cgen: $(ls build/cgen/*.c | wc -l) files"
  echo "Patching for cproc (remove __attribute__ and __builtin_unreachable)..."
  exec "find build/cgen -name '*.c' -exec sed -i 's/__attribute__(([^)]*))//g' {} \\; || true"
  exec "find build/cgen -name '*.c' -exec sed -i 's/__builtin_unreachable()/abort()/g' {} \\; || true"
  echo "Ready for: cproc -O2 -std=c11 -D_XOPEN_SOURCE=700 -DQBE_COMPAT=1 -Ibuild/cgen -Icinterop/include -o bin/fossil-qbe build/cgen/*.c -lsqlite3 -lz -lm -lcrypto -lssl"

task mcp, "Build MCP server standalone":
  exec "nim c -d:release --mm:orc -o:bin/fossil-mcp src/fossil/mcp/server.nim"

task test, "Run tests":
  exec "nim c -r tests/all_tests.nim"
  exec "nim c -r tests/test_storage_real.nim"

task testAll, "Run all tests including real storage":
  exec "nim c -r tests/all_tests.nim"
  exec "nim c -r tests/test_storage_real.nim"

task docs, "Generate docs":
  exec "nim doc --project --outdir:docs/html src/fossil/types.nim"

task checkAll, "Check all modules with nim check":
  exec "for f in $(find src -name '*.nim' | sort); do echo \"Checking $f\"; nim check $f 2>&1 | grep -q 'Error:' && echo \"FAIL $f\" && exit 1; done; echo \"All modules OK\""
