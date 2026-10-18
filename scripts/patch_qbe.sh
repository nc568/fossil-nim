#!/bin/bash
set -e
DIR=${1:-/tmp/cgen_qbe}
echo "Patching $DIR"
perl -0777 -i -pe 's/\}\s*\n\s*;/};/g' $DIR/*.c
sed -i 's/__builtin_unreachable()/abort()/g' $DIR/*.c
sed -i 's/__builtin_unreachable/abort/g' $DIR/*.c
sed -i 's/__builtin_expect(\([^,]*\),[^)]*)/\1/g' $DIR/*.c
sed -i 's/__attribute__(([^)]*))//g' $DIR/*.c
sed -i 's/__attribute__//g' $DIR/*.c
sed -i 's/__thread/_Thread_local/g' $DIR/*.c
sed -i '/^[[:space:]]*;[[:space:]]*$/d' $DIR/*.c
python3 - "$DIR" <<'PY'
import glob, re, sys, os
dir_path = sys.argv[1] if len(sys.argv)>1 else "/tmp/cgen_qbe"
for path in glob.glob(f"{dir_path}/*.c"):
    with open(path, 'r') as f:
        text = f.read()
    def expand_case(m):
        start = int(m.group(1))
        end = int(m.group(2))
        cases = " ".join([f"case {i}:" for i in range(start, end+1)])
        return cases
    text = re.sub(r'case\s+(\d+)\s*\.\.\.\s*(\d+)\s*:', expand_case, text)
    text = text.replace("__uint128_t r = a_p0; r *= b_p1; result = (r >> 64) ^ r;", "NU64 r = a_p0 * b_p1; r = (r >> 33) ^ r; result = r;")
    text = text.replace("__uint128_t", "unsigned long long")
    text = re.sub(r'(\w+)\s*=\s*sqlite3_column_text\(', r'\1 = (void*)sqlite3_column_text(', text)
    text = re.sub(r'(\w+)\s*=\s*sqlite3_column_blob\(', r'\1 = (void*)sqlite3_column_blob(', text)
    text = re.sub(r'(\w+)\s*=\s*sqlite3_column_name\(', r'\1 = (void*)sqlite3_column_name(', text)
    # Also handle direct cstring assignments from column_text without intermediate var
    text = re.sub(r'sqlite3_column_text', 'sqlite3_column_text', text)  # keep
    text = text.replace("void* volatile", "void*")
    text = text.replace("(*volatile", "(*")
    text = re.sub(r'\bvolatile\b', '', text)
    # Remove TSafePoint and GcFrameHeader struct definitions that conflict with qbe_nimbase.h
    text = re.sub(r'struct TSafePoint\s*\{[^}]*\}\s*;\s*', '', text)
    text = re.sub(r'struct GcFrameHeader\s*\{[^}]*\}\s*;\s*', '', text)
    with open(path, 'w') as f:
        f.write(text)
PY
python3 - "$DIR" <<'PY'
import glob, re, sys
dir_path = sys.argv[1] if len(sys.argv)>1 else "/tmp/cgen_qbe"
for path in glob.glob(f"{dir_path}/*.c"):
    with open(path, 'r') as f:
        lines = f.readlines()
    seen = {}
    out = []
    for line in lines:
        m = re.match(r'^\s*N_LIB_PRIVATE\s+[^=()]*\s+(\w+)\s*;\s*$', line)
        if m:
            var = m.group(1)
            if var in seen:
                continue
            seen[var]=True
        m2 = re.match(r'^\s*static\s+TNimType\*\s+(\w+)\s*\[.*\]\s*;\s*$', line)
        if m2:
            var = m2.group(1)
            if var in seen:
                continue
            seen[var]=True
        out.append(line)
    with open(path, 'w') as f:
        f.writelines(out)
PY
echo "Patched $(ls $DIR/*.c | wc -l) files"
