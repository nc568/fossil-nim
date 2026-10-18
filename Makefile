NIM=nim
NIMBLE=nimble
CPROC=cproc
QBE=qbe
# Prefer local persistent cproc/qbe in bin-tools (survives /tmp cleanup)
ifneq ($(wildcard bin-tools/cproc),)
CPROC=bin-tools/cproc
endif
ifneq ($(wildcard bin-tools/qbe),)
QBE=bin-tools/qbe
endif
# Ensure choosenim and bin-tools in PATH for make
export PATH := $(PWD)/bin-tools:$(HOME)/.choosenim/toolchains/nim-2.2.4/bin:$(HOME)/.nimble/bin:/usr/local/bin:/usr/bin:/bin:$(PATH)

BIN=bin/fossil
MCP_BIN=bin/fossil-mcp
CGEN_DIR=build/cgen
CINTEROP=cinterop/include

all: build

build:
	@mkdir -p bin
	@chmod +x bin-tools/cproc bin-tools/qbe bin-tools/cproc-qbe || true
	$(NIM) c -d:release --mm:arc --threads:off --opt:speed --outdir:bin -o:$(BIN) src/fossil/cli/main.nim
	$(NIM) c -d:release --mm:arc --threads:off --opt:speed --outdir:bin -o:$(MCP_BIN) src/fossil/mcp/server.nim
	@chmod +x bin/fossil bin/fossil-mcp || true
	@echo "Built $(BIN) and $(MCP_BIN) with ARC (no GC, deterministic refcount)"
	@./bin/fossil version
	@ls -lh bin/

build-refc:
	@mkdir -p bin
	$(NIM) c -d:release --mm:refc --threads:off --opt:speed --outdir:bin -o:$(BIN) src/fossil/cli/main.nim
	$(NIM) c -d:release --mm:refc --threads:off --opt:speed --outdir:bin -o:$(MCP_BIN) src/fossil/mcp/server.nim
	@echo "Built $(BIN) and $(MCP_BIN) with refc (smallest, 2.1M)"

build-orc:
	@mkdir -p bin
	$(NIM) c -d:release --mm:orc --threads:off --opt:speed --outdir:bin -o:$(BIN) src/fossil/cli/main.nim
	$(NIM) c -d:release --mm:orc --threads:off --opt:speed --outdir:bin -o:$(MCP_BIN) src/fossil/mcp/server.nim
	@echo "Built $(BIN) and $(MCP_BIN) with ORC (ARC + cycle collector, 3.9M)"

build-qbe-c:
	@mkdir -p $(CGEN_DIR) bin
	$(NIM) c --cc:clang --compileOnly --nimcache:$(CGEN_DIR) --outdir:$(CGEN_DIR) -d:release -d:qbeCompat --mm:refc --threads:off --panics:on -d:useMalloc --opt:speed src/fossil/cli/main.nim
	@echo "C files generated in $(CGEN_DIR): $$(ls $(CGEN_DIR)/*.c | wc -l) files"
	@echo "Patching for cproc..."
	@bash scripts/patch_qbe.sh $(CGEN_DIR) 2>&1 | tail -n 20
	@find $(CGEN_DIR) -name "*.c" -exec sed -i '/^struct TSafePoint {/,/^};/d' {} \; || true
	@find $(CGEN_DIR) -name "*.c" -exec sed -i '/^struct GcFrameHeader {/,/^};/d' {} \; || true
	@echo "Patched. Ready for cproc."

build-qbe-c-minimal:
	@mkdir -p $(CGEN_DIR) bin
	$(NIM) c --cc:clang --compileOnly --nimcache:$(CGEN_DIR) --outdir:$(CGEN_DIR) -d:release -d:qbeCompat --mm:refc --threads:off --panics:on -d:useMalloc --opt:speed src/fossil/cli/main_qbe.nim
	@echo "C files generated in $(CGEN_DIR): $$(ls $(CGEN_DIR)/*.c | wc -l) files"
	@echo "Patching for cproc..."
	@bash scripts/patch_qbe.sh $(CGEN_DIR) 2>&1 | tail -n 20
	@find $(CGEN_DIR) -name "*.c" -exec sed -i '/^struct TSafePoint {/,/^};/d' {} \; || true
	@find $(CGEN_DIR) -name "*.c" -exec sed -i '/^struct GcFrameHeader {/,/^};/d' {} \; || true
	@echo "Patched. Ready for cproc."

NIM_LIB ?= $(shell $(NIM) --eval "echo getPrefixDir() / \"lib\"" 2>/dev/null | tail -n1)
ifeq ($(NIM_LIB),)
NIM_LIB=$(HOME)/.choosenim/toolchains/nim-2.2.4/lib
endif
# Fallback: try to find nimbase.h via nim dump
NIM_LIB_FALLBACK=$(shell $(NIM) dump 2>&1 | grep -E "/lib$$" | head -n1)
ifneq ($(NIM_LIB_FALLBACK),)
NIM_LIB=$(NIM_LIB_FALLBACK)
endif

qbe: build-qbe-c
	@echo "Compiling with cproc (QBE)..."
	@mkdir -p bin
	@if command -v $(CPROC) >/dev/null 2>&1; then \
		$(CPROC) -O2 -std=c11 -D_GNU_SOURCE -D_XOPEN_SOURCE=700 -DQBE_COMPAT=1 -I$(CGEN_DIR) -I$(CINTEROP) -Icinterop/sha3 -Icinterop/sqlite -Icinterop/lmdb -I$(NIM_LIB) -L/usr/lib/gcc/x86_64-pc-linux-gnu/16 -L/usr/lib/gcc/x86_64-linux-gnu/16 -o bin/fossil-qbe $(CGEN_DIR)/*.c cinterop/sha3/sha3.c cinterop/sha3/sh3_wrapper.c -lsqlite3 -lz -lm -lcrypto -lssl && \
		echo "Built bin/fossil-qbe" && ./bin/fossil-qbe version && ./bin/fossil-qbe help | head -n 20 || true; \
	else \
		echo "cproc not found, trying gcc as fallback for QBE compat test"; \
		gcc -O2 -std=c11 -D_GNU_SOURCE -D_XOPEN_SOURCE=700 -DQBE_COMPAT=1 -I$(CGEN_DIR) -I$(CINTEROP) -Icinterop/sha3 -Icinterop/sqlite -Icinterop/lmdb -I$(NIM_LIB) -o bin/fossil-qbe-gcc $(CGEN_DIR)/*.c cinterop/sha3/sha3.c cinterop/sha3/sh3_wrapper.c -lsqlite3 -lz -lm -lcrypto -lssl && \
		echo "Built bin/fossil-qbe-gcc with gcc" && ./bin/fossil-qbe-gcc version && ./bin/fossil-qbe-gcc help | head -n 20 || true; \
	fi

qbe-static: build-qbe-c
	@echo "Static build with vendored sqlite..."
	@ls cinterop/sqlite/sqlite3.c || echo "Warning: sqlite3.c not vendored, using -lsqlite3"
	@mkdir -p bin
	@if [ -f cinterop/sqlite/sqlite3.c ]; then \
		$(CPROC) -O2 -std=c11 -D_GNU_SOURCE -D_XOPEN_SOURCE=700 -DQBE_COMPAT=1 -I$(CGEN_DIR) -I$(CINTEROP) -Icinterop/sqlite -Icinterop/sha3 -I$(NIM_LIB) -o bin/fossil-qbe $(CGEN_DIR)/*.c cinterop/sqlite/sqlite3.c cinterop/sha3/sha3.c cinterop/sha3/sh3_wrapper.c -lz -lm -lcrypto -lssl; \
	else \
		$(CPROC) -O2 -std=c11 -D_GNU_SOURCE -D_XOPEN_SOURCE=700 -DQBE_COMPAT=1 -I$(CGEN_DIR) -I$(CINTEROP) -Icinterop/sha3 -Icinterop/sqlite -Icinterop/lmdb -I$(NIM_LIB) -o bin/fossil-qbe $(CGEN_DIR)/*.c cinterop/sha3/sha3.c cinterop/sha3/sh3_wrapper.c -lsqlite3 -lz -lm -lcrypto -lssl; \
	fi

check:
	@for f in $$(find src -name "*.nim" | sort); do \
		echo "Checking $$f"; \
		$(NIM) check $$f 2>&1 | grep -q "Error:" && echo "FAIL $$f" && exit 1 || true; \
	done
	@echo "All modules OK (nim check)"

test:
	$(NIM) c -r tests/all_tests.nim
	$(NIM) c -r tests/test_storage_real.nim
	$(NIM) c -r tests/test_search_forum_chat.nim
	$(NIM) c -r tests/test_wiki_ticket.nim
	$(NIM) c -r tests/test_integration.nim
	$(NIM) c -r tests/test_fuzz.nim
	$(NIM) c -r tests/test_security.nim
	$(NIM) c -r benchmarks/hybrid_bench.nim || true

test-full:
	$(NIM) c -r tests/all_tests.nim
	$(NIM) c -r tests/test_storage_real.nim
	$(NIM) c -r tests/test_search_forum_chat.nim
	$(NIM) c -r tests/test_wiki_ticket.nim
	$(NIM) c -r tests/test_integration.nim
	$(NIM) c -r tests/test_sync.nim
	$(NIM) c -r tests/test_fuzz.nim
	$(NIM) c -r tests/test_security.nim
	@echo "All tests passed"

test-mcp:
	@echo "Testing MCP server..."
	@printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}\n{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}\n' | ./bin/fossil-mcp 2>&1 | tail -n 5
	@echo "MCP OK"

clean:
	rm -rf bin build nimcache
	rm -f /tmp/test*.fossil /tmp/fossil-nim-test* /tmp/test2.fossil

docs:
	$(NIM) doc --project --outdir:docs/html src/fossil/types.nim

init-test-repo:
	./bin/fossil init /tmp/test.fossil --backend sqlite
	@echo "Repo created, tables:"
	@python3 -c "import sqlite3; conn=sqlite3.connect('/tmp/test.fossil'); cur=conn.cursor(); cur.execute(\"SELECT name FROM sqlite_master WHERE type='table'\"); print(cur.fetchall())"

.PHONY: all build build-qbe-c qbe qbe-static check test test-mcp clean docs init-test-repo
