#!/bin/sh
# Frees the workspace budget. Safe to run any time: everything removed here is
# either regenerable (build output, toolchain docs) or already pushed.
set -e
cd "$(dirname "$0")/../.."
rm -rf build/db/*.js build/db/x86_64 build/db/*.o build/db/btreetmp 2>/dev/null || true
rm -rf ~/.cache/tc/nim-2.2.12/doc ~/.cache/tc/nim-2.2.12/tools \
       ~/.cache/tc/nim-2.2.12/tests ~/.cache/tc/nim-2.2.12/examples \
       ~/.cache/tc/nim-2.2.12/dist ~/.cache/tc/nim-2.2.12/pkgs 2>/dev/null || true
rm -f ~/.cache/tc/*.tar.xz 2>/dev/null || true
echo "workspace: $(du -sh "$HOME" 2>/dev/null | cut -f1), files: $(find "$HOME" -type f 2>/dev/null | wc -l)"
