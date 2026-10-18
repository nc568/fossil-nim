#!/bin/bash
set -e
CGEN_DIR=${1:-build/cgen}
BIN_OUT=${2:-bin/fossil-qbe}
mkdir -p bin build/qbe_exact

BIN_TOOLS_DIR="$(pwd)/bin-tools"
export PATH="$BIN_TOOLS_DIR:$PATH"

CPROC=cproc
if [ -f "$BIN_TOOLS_DIR/cproc" ]; then
    CPROC="$BIN_TOOLS_DIR/cproc"
fi

NIM_LIB=$(nim dump 2>&1 | grep -E "/lib$" | head -n1)
if [ -z "$NIM_LIB" ] || [ ! -f "$NIM_LIB/nimbase.h" ]; then
    if [ -f "/usr/lib/nim/lib/nimbase.h" ]; then
        NIM_LIB="/usr/lib/nim/lib"
    elif [ -f "$HOME/.choosenim/toolchains/nim-2.2.4/lib/nimbase.h" ]; then
        NIM_LIB="$HOME/.choosenim/toolchains/nim-2.2.4/lib"
    fi
fi

python3 - <<PY
import json, os, subprocess, sys

cgen_dir = "$CGEN_DIR"
bin_out = "$BIN_OUT"
cproc = "$CPROC"
nim_lib = "$NIM_LIB"

json_path = os.path.join(cgen_dir, "main_qbe.json")
if not os.path.exists(json_path):
    print(f"Error: {json_path} not found")
    sys.exit(1)

with open(json_path) as f:
    data = json.load(f)

c_files = [item[0] for item in data["compile"]]
obj_files = []

for i, src in enumerate(c_files):
    base = os.path.basename(src)
    obj = f"build/qbe_exact/obj_{i}_{base}.o"
    obj_files.append(obj)
    cmd = [
        cproc, "-c", "-O2", "-std=c11",
        "-D_GNU_SOURCE", "-D_XOPEN_SOURCE=700", "-DQBE_COMPAT=1",
        f"-I{cgen_dir}", "-Icinterop/include", "-Icinterop/sha3",
        "-Icinterop/sqlite", "-Icinterop/lmdb", f"-I{nim_lib}",
        "-o", obj, src
    ]
    res = subprocess.run(cmd)
    if res.returncode != 0:
        print(f"Failed to compile {src}")
        sys.exit(res.returncode)

link_cmd = ["gcc", "-o", bin_out] + obj_files + ["-lsqlite3", "-lz", "-lm", "-lcrypto", "-lssl"]
res = subprocess.run(link_cmd)
if res.returncode != 0:
    print("Link failed")
    sys.exit(res.returncode)

print(f"Successfully compiled and linked {bin_out} using cproc and qbe!")
PY
