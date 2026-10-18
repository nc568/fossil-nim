# Docs Index - Fossil-Nim

## English

### Core
- [Architecture](ARCHITECTURE.md) - modular architecture overview (60+ modules, layered)
- [Storage Backends](STORAGE_BACKENDS.md) - SQLite vs LMDB/libmdbx/CDB deep dive
- [Storage Benchmarks 2026-10-17](STORAGE_BACKENDS_BENCH.md) - comprehensive benchmarks: SQLite 12k/s put, CDB 1.3M/s (104x), LMDB 1.28M/s (102x), migration, size
- [Build Guide](BUILD.md) - building from source, Nim -> C -> binary
- [Porting Plan](PORTING_PLAN.md) - full porting roadmap from original Fossil
- [Contributing](CONTRIBUTING.md) - how to contribute
- [Migration Guide](MIGRATION_GUIDE.md) - migrating from original Fossil
- [Benchmarks](BENCHMARKS.md) - performance benchmarks (updated with real results)
- [Gap Analysis](GAP_ANALYSIS.md) - what's missing vs original

### Features
- [Archive ZIP/TAR](ARCHIVE.md) - real ZIP STORE + TAR USTAR generation, /zip /tarball endpoints
- [Search FTS5](SEARCH.md) - full-text search with auto-indexing, reindex, MCP tool
- [Forum & Chat Enhanced](FORUM_CHAT_ENHANCED.md) - forum threads/posts, chat rooms/messages, WYSIWYG
- [Web Full Parity](WEB_FULL_PARITY.md) - web UI pages parity with original Fossil (30+ pages)
- [Web Extended](WEB_EXTENDED.md) - 8 new pages: stat, reportlist, report, attach, rss, wcontent, whistory, leaves (40+ total)
- [TH1 + Markdown + Wiki](TH1_MARKDOWN_WIKI.md) - TH1 interpreter, markdown parser, wiki
- [UI New](UI_NEW.md) - new UI components
- [LSP](LSP.md) - Language Server Protocol support

### API & MCP
- [REST API](API.md) - REST JSON API, /api/v1/*
- [MCP API](MCP_API.md) - Model Context Protocol server, 25 tools
- [MCP SSE API](MCP_SSE_API.md) - MCP over SSE, prompts, auth, OpenAPI
- [OpenCode Subagents](OPENCODE_SUBAGENTS.md) - AI subagents integration

### Compatibility
- [cproc/QBE Compatibility](CPROC_QBE.md) - building with minimal C compiler, QBE IR
- [Progress 2026-10-17](PROGRESS_2026-10-17.md) - progress report
- [Test Results](TEST_RESULTS.md) - test results

## Русский

### Основное
- [Архитектура](ARCHITECTURE_RU.md) - обзор модульной архитектуры (60+ модулей, слои)
- [Бэкенды хранения](STORAGE_BACKENDS_RU.md) - сравнение SQLite vs LMDB/libmdbx/CDB
- [Руководство по сборке](BUILD_RU.md) - сборка из исходников, Nim -> C -> бинарник
- [План портирования](PORTING_PLAN_RU.md) - полный план портирования оригинального Fossil
- [Полная документация](FULL_DOCUMENTATION_RU.md) - полная документация на русском
- [Анализ пробелов](GAP_ANALYSIS_RU.md) - что отсутствует по сравнению с оригиналом

### Функции
- [Архив ZIP/TAR](ARCHIVE_RU.md) - реальная генерация ZIP STORE + TAR USTAR, эндпоинты /zip /tarball
- [Поиск FTS5](SEARCH_RU.md) - полнотекстовый поиск с авто-индексацией, переиндексация, MCP инструмент
- [Форум и чат расширенные](FORUM_CHAT_ENHANCED_RU.md) - форум треды/посты, чат комнаты/сообщения, WYSIWYG
- [Полный паритет Web](WEB_FULL_PARITY_RU.md) - паритет web UI страниц с оригинальным Fossil (30+ страниц)
- [Web Расширенный](WEB_EXTENDED_RU.md) - 8 новых страниц: stat, reportlist, report, attach, rss, wcontent, whistory, leaves (40+ всего)
- [TH1 + Markdown + Wiki](TH1_MARKDOWN_WIKI_RU.md) - интерпретатор TH1, парсер markdown, wiki
- [Новый UI](UI_NEW_RU.md) - новые UI компоненты

### API и MCP
- [MCP API](MCP_API_RU.md) - сервер Model Context Protocol, 25 инструментов
- [MCP SSE API](MCP_SSE_API_RU.md) - MCP поверх SSE, промпты, аутентификация, OpenAPI

### Совместимость
- [Совместимость cproc/QBE](CPROC_QBE_RU.md) - сборка минимальным C компилятором, QBE IR

## Project Structure

```
src/fossil/
├── types.nim              # Core types: Blob, Rid, Uuid, Artifact
├── config.nim             # Global config
├── storage/               # Pluggable storage backends
│   ├── backend.nim        # Concept interface
│   ├── sqlite_backend.nim # Default, 100% compatible
│   ├── libmdbx_backend.nim
│   ├── lmdb_backend.nim
│   └── cdb_backend.nim
├── delta/                 # Fossil delta format
├── artifact/              # Manifest parsing, hashing
├── vcs/                   # VCS core: checkout, commit, branch, merge, diff, blame, archive, git_export
├── wiki/                  # Wiki subsystem
├── ticket/                # Ticket subsystem
├── forum/                 # Forum subsystem
├── chat/                  # Chat subsystem
├── search/                # FTS5 search with auto-index
├── sync/                  # Sync protocol + HTTP transport
├── web/                   # Web server & UI
├── th1/                   # TH1 interpreter
├── markdown/              # Markdown parser
├── api/                   # REST API + web pages
├── mcp/                   # MCP server (stdio + SSE)
└── cli/                   # CLI dispatcher
```

## Quick Links

- Main README: [/README.md](../README.md)
- Final Reports: [/FINAL_REPORT_*.md](../) - latest reports for ZIP/TAR and Search
- Build: `nim c -d:release --mm:refc --threads:off -o:/tmp/fossil src/fossil/cli/main.nim`
- Test: `/tmp/fossil search "bug" --repo repo.fossil`

## Documentation Standards

- Every module has EN + RU documentation
- Architecture is modular: each subsystem is independent Nim module with clear interface
- C interop: keep proven C libs (SQLite, zlib, OpenSSL) as importc, not rewrite
- API first: CLI is thin wrapper over library
- MCP first: AI agents can operate Fossil via structured tools
- QBE/cproc friendly: generated C must be portable C11
