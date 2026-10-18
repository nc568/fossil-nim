# LSP Setup for Fossil-Nim

## What is LSP?

Language Server Protocol - provides IDE features: hover, goto definition, completion, etc.

For Nim, the LSP server is `nimsuggest`, which is installed via `choosenim` / `nimble`.

## Installation

```bash
# Install Nim via choosenim (already done)
curl -fsSL https://nim-lang.org/choosenim/init.sh -o /tmp/choosenim.sh
sh /tmp/choosenim.sh -y
export PATH=/home/user/.nimble/bin:$PATH

# Verify
nim --version
nimsuggest --version
```

`nimsuggest` is built automatically with Nim.

## VS Code

1. Install extension `saem.vscode-nim` or `nimsaem.nimvscode`

2. Project already has `.vscode/settings.json`:

```json
{
  "nim.nimsuggestPath": "/home/user/.nimble/bin/nimsuggest",
  "nim.nimPath": "/home/user/.nimble/bin/nim",
  "nim.projectMapping": [{"projectFile": "fossil.nimble", "fileRegex": ".*\\.nim"}]
}
```

3. Open folder `fossil-nim` in VS Code, extension will start `nimsuggest`.

4. Features:
   - Hover: see type of `Rid`, `Uuid`, `Blob`
   - Go to definition: jump to `StorageBackend` concept
   - Completion: `backend.` shows methods
   - References: find all uses of `putBlob`

## Neovim

With `nvim-lspconfig`:

```lua
require'lspconfig'.nimls.setup{
  cmd = {"/home/user/.nimble/bin/nim", "--verbosity:0", "--hints:off", "nimsuggest", "--stdin", "--v2"},
  filetypes = {"nim"},
  root_dir = require'lspconfig'.util.root_pattern("*.nimble", ".git"),
}
```

Or use `nimlsp` (newer, wrapper over nimsuggest):

```bash
nimble install nimlsp
```

```lua
require'lspconfig'.nim_lsp.setup{
  cmd = {"nimlsp"},
}
```

## Testing LSP

```bash
# Start nimsuggest manually
nimsuggest --stdin --v2 --log:/tmp/nimsuggest.log src/fossil/types.nim

# Then send JSON-RPC queries (via tool or via editor)
```

## Troubleshooting

- `nimsuggest` needs `config.nims` to find imports. We have `config.nims` that sets `passC -I./cinterop/include` and `passL -lsqlite3...`
- If `sqlite3.h not found` in IDE, add to `settings.json`:

```json
"nim.nimArgs": ["--passC:-I/usr/include", "--passL:-lsqlite3 -lcrypto"]
```

- For QBE mode, LSP will still work, but `qbe_nimbase.h` is only used when `-d:qbeCompat`. In normal mode, original `nimbase.h` is used.

- If `nimsuggest` crashes on large files, increase timeout:

```json
"nim.lsp.timeout": 10000
```

## What we tested

In this sandbox:

```bash
export PATH=/home/user/.nimble/bin:$PATH
nim check src/fossil/types.nim # OK
nim check src/fossil/cli/main.nim # OK (after fixing mdbx conditional)
nim c -r tests/all_tests.nim # All tests passed
nim c --outdir:bin src/fossil/cli/main.nim # Success, binary works
nim c --compileOnly -d:qbeCompat --mm:refc --threads:off --panics:on src/fossil/cli/main.nim # 52 C files generated, valid C11
```

All modules pass `nim check` (0 errors) — LSP will be happy.

## Future: Use `nimlangserver`

`nimlangserver` is alternative LSP implementation (uses nimsuggest under hood but more stable):

```bash
nimble install nimlangserver
nimlangserver
```

VS Code will auto-detect it if installed.

