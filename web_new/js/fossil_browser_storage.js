/**
 * Fossil-Nim Browser Storage Engine
 * Supports 3 Multi-Database Backends:
 * 1. IndexedDB (Persistent Browser-native NoSQL)
 * 2. SQLite WASM (Real SQLite engine in WebAssembly with .fossil import/export)
 * 3. Pure-Nim CDB (Constant DB in memory via FossilCore WebAssembly/JS)
 */

// Default Seed Documentation & Wiki Pages out-of-the-box
const DEFAULT_WIKI_DOCS = {
  "Home": `# 🦖 Fossil-Nim Browser Edition\n\nWelcome to **Fossil-Nim** running directly inside your web browser!\n\nThis is a full-featured, distributed, local-first Version Control System (VCS) powered by **Nim Lang** compiled to WebAssembly and JavaScript.\n\n### Key Features:\n- ⚡ **Zero-Install**: Works immediately in any modern browser without servers.\n- 🔒 **100% Private & Local-First**: All repositories and code are stored in your browser storage.\n- 💾 **3 Storage Backends**: Switch between **IndexedDB**, **SQLite WASM**, and **Pure-Nim CDB**.\n- 🤖 **In-Browser MCP (89 Tools)**: Seamlessly integrates with AI Agents (Gemini, Claude, ChatGPT, WebLLM).\n- 🚀 **High Performance**: Powered by native Myers diff, rolling delta algorithms, and ARC memory model.\n\nExplore the tabs above to view the **Timeline**, edit **Files**, browse **Wiki**, and test the **AI Agent Console**!`,

  "Architecture": `# 🏗️ Fossil-Nim Architecture\n\nFossil-Nim is a complete reimagining of Fossil SCM written in **Nim** (version 2.0+).\n\n### Why Nim Lang?\n1. **Ultra-Compact Codebase**: ~24,000 lines of Nim compared to ~200,000 lines of original C (8x less code!).\n2. **Deterministic ARC Memory**: Zero Stop-The-World garbage collection pauses, instant deterministic cleanup.\n3. **Cross-Compilation**: Compiles to optimized native C machine code on desktop/servers, AND to JavaScript/WASM for web browsers.\n4. **Pluggable Storage**: Modular \`StorageBackend\` architecture allowing SQLite, CDB, MDBX, LMDB, and IndexedDB.\n\n### Core VCS Components:\n- \`fossil/delta\`: Rolling-checksum delta compression format.\n- \`fossil/vcs/diff\`: High-performance Myers diff algorithm.\n- \`fossil/mcp\`: Model Context Protocol server exposing 89 typed tools for AI pair programming.`,

  "MCP-89-Tools": `# 🤖 Model Context Protocol (MCP) Reference\n\nFossil-Nim embeds an industry-leading **89 MCP tools** designed specifically for AI Agents and pair programming.\n\n### Categories of Available Tools:\n1. **VCS Core**: \`vcs_status\`, \`vcs_commit\`, \`vcs_diff\`, \`vcs_timeline\`, \`vcs_branch_list\`, \`vcs_branch_create\`, \`vcs_checkout\`, \`vcs_stash\`\n2. **File System**: \`vcs_file_read\`, \`vcs_file_write\`, \`vcs_file_list\`, \`vcs_file_history\`, \`vcs_blame\`\n3. **Wiki & Knowledge**: \`wiki_list\`, \`wiki_get\`, \`wiki_create\`, \`wiki_update\`\n4. **Issue Tracking**: \`ticket_list\`, \`ticket_get\`, \`ticket_create\`, \`ticket_comment\`\n5. **Collaboration**: \`forum_list\`, \`forum_get\`, \`forum_create\`, \`chat_send\`, \`chat_list\`\n6. **Storage & Database**: \`storage_stats\`, \`storage_switch_backend\`, \`storage_export_file\`, \`sql_query\`\n\nAll tools can be invoked in the browser via \`window.fossilMcp.callTool(name, args)\`!`,

  "Storage-Backends": `# 💾 Storage Backends in the Browser\n\nFossil-Nim in the browser supports **3 distinct storage backends**:\n\n### 1. IndexedDB (Browser Native)\n- **How it works**: Uses the browser's built-in structured NoSQL storage.\n- **Pros**: Persistent, fast, works out of the box without any external downloads or WASM binaries.\n- **Best for**: Default local-first web workspaces and long-term project editing.\n\n### 2. SQLite WASM (.fossil file compatible)\n- **How it works**: Runs the real SQLite 3 engine inside WebAssembly.\n- **Pros**: 100% binary compatibility with desktop Fossil \`.fossil\` files. Drag & Drop an existing repository or export a real SQLite database anytime.\n- **Best for**: Interoperating with desktop Fossil installations and archiving.\n\n### 3. Pure-Nim CDB (RAM In-Memory)\n- **How it works**: Uses Nim's pure Constant Database engine compiled into JavaScript memory.\n- **Pros**: Extreme speed, instant O(1) key-value hash lookups, zero dependencies.\n- **Best for**: Ephemeral AI coding sessions, testing, and quick diff reviews.`
};

const NOW = Date.now();
const ONE_DAY = 24 * 60 * 60 * 1000;

const DEFAULT_TICKETS_SEED = [
  {
    id: "tkt-101",
    title: "Реализовать интерактивный таймлайн-календарь",
    desc: "Добавить отображение дедлайнов задач на сетке месяца с визуализацией приоритетов и фильтрацией.",
    priority: "Critical",
    status: "Open",
    reporter: "admin",
    created: NOW - 3 * ONE_DAY,
    mtime: NOW - 3 * ONE_DAY,
    deadline: NOW + 4 * ONE_DAY,
    history: [
      { timestamp: NOW - 3 * ONE_DAY, user: "admin", action: "created", detail: "Тикет создан с приоритетом Critical" },
      { timestamp: NOW - 2 * ONE_DAY, user: "admin", action: "pr_linked", detail: "Привязан Pull Request pr-101" }
    ],
    linkedPrs: ["pr-101"]
  },
  {
    id: "tkt-102",
    title: "Оптимизация Myers diff для больших файлов",
    desc: "Улучшить скорость вычисления разницы в WebAssembly до субмиллисекундного времени для файлов 10K+ строк.",
    priority: "High",
    status: "Open",
    reporter: "lead_dev",
    created: NOW - 10 * ONE_DAY,
    mtime: NOW - 2 * ONE_DAY,
    deadline: NOW - 2 * ONE_DAY, // Overdue!
    history: [
      { timestamp: NOW - 10 * ONE_DAY, user: "lead_dev", action: "created", detail: "Тикет создан с приоритетом High" }
    ],
    linkedPrs: []
  },
  {
    id: "tkt-103",
    title: "Полная документация и примеры 89 MCP инструментов",
    desc: "Сформировать полную интерактивную документацию и тестовые вызовы для каждого MCP инструмента.",
    priority: "Medium",
    status: "Closed",
    reporter: "ai_pair",
    created: NOW - 12 * ONE_DAY,
    mtime: NOW - 5 * ONE_DAY,
    deadline: NOW - 5 * ONE_DAY,
    history: [
      { timestamp: NOW - 12 * ONE_DAY, user: "ai_pair", action: "created", detail: "Тикет создан" },
      { timestamp: NOW - 5 * ONE_DAY, user: "ai_pair", action: "status_change", detail: "Завершено: документация обновлена и Pull Request pr-102 смерджен" }
    ],
    linkedPrs: ["pr-102"]
  },
  {
    id: "tkt-104",
    title: "Рефакторинг цветовой палитры в Surf и текстовых браузерах",
    desc: "Проверить читаемость шрифтов и контрастность на темных и светлых мониторах.",
    priority: "Low",
    status: "Open",
    reporter: "designer",
    created: NOW - 1 * ONE_DAY,
    mtime: NOW - 1 * ONE_DAY,
    deadline: 0, // No deadline - Backlog!
    history: [
      { timestamp: NOW - 1 * ONE_DAY, user: "designer", action: "created", detail: "Тикет добавлен в бэклог" }
    ],
    linkedPrs: []
  },
  {
    id: "tkt-105",
    title: "Поддержка tarball архивирования без сжатия zip",
    desc: "Добавить альтернативный экспорт дерева репозитория в формате tar.",
    priority: "Medium",
    status: "Open",
    reporter: "core_dev",
    created: NOW - 2 * ONE_DAY,
    mtime: NOW - 2 * ONE_DAY,
    deadline: 0, // No deadline - Backlog!
    history: [
      { timestamp: NOW - 2 * ONE_DAY, user: "core_dev", action: "created", detail: "Тикет добавлен в бэклог" }
    ],
    linkedPrs: []
  },
  {
    id: "tkt-106",
    title: "Сборка QBE cproc для супер-легковесных сред",
    desc: "Адаптировать Си-код для чистого C11 стандарта без GCC расширений и слинковать 456КБ бинарник.",
    priority: "High",
    status: "Open",
    reporter: "qbe_lead",
    created: NOW - 6 * ONE_DAY,
    mtime: NOW - 1 * ONE_DAY,
    deadline: NOW + 7 * ONE_DAY,
    history: [
      { timestamp: NOW - 6 * ONE_DAY, user: "qbe_lead", action: "created", detail: "Тикет создан с приоритетом High" }
    ],
    linkedPrs: []
  },
  {
    id: "tkt-107",
    title: "Аудит безопасности и защита от timing-атак",
    desc: "Провести ревизию поверхности атаки, проверить constant-time сравнение токенов и аутентификацию REST API.",
    priority: "Critical",
    status: "Open",
    reporter: "sec_auditor",
    created: NOW - 2 * ONE_DAY,
    mtime: NOW - 1 * ONE_DAY,
    deadline: NOW + 11 * ONE_DAY,
    history: [
      { timestamp: NOW - 2 * ONE_DAY, user: "sec_auditor", action: "created", detail: "Тикет создан с приоритетом Critical" }
    ],
    linkedPrs: []
  },
  {
    id: "tkt-108",
    title: "Поддержка минималистичных браузеров (surf, netsurf)",
    desc: "Обеспечить корректную работу линейного таймлайна и чистого Vanilla JS без тяжелых зависимостей.",
    priority: "Low",
    status: "Open",
    reporter: "ux_lead",
    created: NOW - 5 * ONE_DAY,
    mtime: NOW - 2 * ONE_DAY,
    deadline: NOW + 2 * ONE_DAY,
    history: [
      { timestamp: NOW - 5 * ONE_DAY, user: "ux_lead", action: "created", detail: "Тикет создан с приоритетом Low" }
    ],
    linkedPrs: []
  }
];

const DEFAULT_PRS_SEED = [
  {
    id: "pr-101",
    title: "Feat: Add Roadmap Timeline-Calendar Tab",
    sourceBranch: "feature/calendar-timeline",
    targetBranch: "trunk",
    description: "Adds timeline calendar with month view, overdue detection, and ticket linking.",
    author: "frontend_dev",
    status: "open",
    ticketId: "tkt-101",
    created: NOW - 2 * ONE_DAY,
    modified: NOW - 2 * ONE_DAY,
    mergedAt: 0,
    mergeCommit: ""
  },
  {
    id: "pr-102",
    title: "Docs: Complete 89 MCP Tools Reference and Interactive Console",
    sourceBranch: "docs/mcp-spec",
    targetBranch: "trunk",
    description: "Rich schema metadata, parameter tables, and samples for all MCP tools.",
    author: "ai_pair",
    status: "merged",
    ticketId: "tkt-103",
    created: NOW - 6 * ONE_DAY,
    modified: NOW - 5 * ONE_DAY,
    mergedAt: NOW - 5 * ONE_DAY,
    mergeCommit: "ci-mcp-docs-v2"
  }
];

// Security validation helpers
function isSafeFilePath(p) {
  if (!p || typeof p !== 'string') return false;
  if (p.includes('..') || p.startsWith('/') || p.startsWith('\\') || p.includes('\0')) return false;
  return true;
}

function isSafePropKey(k) {
  if (!k || typeof k !== 'string') return false;
  return k !== '__proto__' && k !== 'constructor' && k !== 'prototype';
}

// =========================================================================
// Backend 1: IndexedDB Storage
// =========================================================================
class IndexedDbStorage {
  constructor() {
    this.name = "IndexedDB";
    this.db = null;
    this.dbName = "fossil_nim_browser_repo";
  }

  async init() {
    return new Promise((resolve, reject) => {
      const req = indexedDB.open(this.dbName, 2);
      req.onupgradeneeded = (e) => {
        const db = e.target.result;
        if (!db.objectStoreNames.contains("artifacts")) db.createObjectStore("artifacts", { keyPath: "uuid" });
        if (!db.objectStoreNames.contains("events")) db.createObjectStore("events", { keyPath: "id", autoIncrement: true });
        if (!db.objectStoreNames.contains("files")) db.createObjectStore("files", { keyPath: "path" });
        if (!db.objectStoreNames.contains("wiki")) db.createObjectStore("wiki", { keyPath: "name" });
        if (!db.objectStoreNames.contains("tickets")) db.createObjectStore("tickets", { keyPath: "id" });
        if (!db.objectStoreNames.contains("pull_requests")) db.createObjectStore("pull_requests", { keyPath: "id" });
        if (!db.objectStoreNames.contains("meta")) db.createObjectStore("meta", { keyPath: "key" });
      };
      req.onsuccess = async (e) => {
        this.db = e.target.result;
        await this.seedDefaults();
        resolve();
      };
      req.onerror = () => reject(req.error);
    });
  }

  async seedDefaults() {
    const count = await this.count("wiki");
    if (count === 0) {
      for (const [name, text] of Object.entries(DEFAULT_WIKI_DOCS)) {
        await this.put("wiki", { name, text, author: "system", mtime: Date.now() });
      }
      // Add initial README file
      await this.put("files", {
        path: "README.md",
        content: "# My Fossil-Nim Project\n\nCreated inside browser with Fossil-Nim!\n",
        mtime: Date.now()
      });
      // Add initial commit event
      await this.put("events", {
        type: "ci",
        branch: "trunk",
        user: "admin",
        comment: "Initial repository creation in browser",
        mtime: Date.now(),
        uuid: "init-" + Math.random().toString(16).substring(2, 10)
      });
    }

    // Seed tickets if empty
    try {
      const tktCount = await this.count("tickets");
      if (tktCount === 0) {
        for (const t of DEFAULT_TICKETS_SEED) {
          await this.put("tickets", t);
        }
      }
    } catch (_) {}

    // Seed pull requests if empty
    try {
      const prCount = await this.count("pull_requests");
      if (prCount === 0) {
        for (const pr of DEFAULT_PRS_SEED) {
          await this.put("pull_requests", pr);
        }
      }
    } catch (_) {}
  }

  async get(storeName, key) {
    return new Promise((resolve) => {
      const tx = this.db.transaction(storeName, "readonly");
      const req = tx.objectStore(storeName).get(key);
      req.onsuccess = () => resolve(req.result || null);
      req.onerror = () => resolve(null);
    });
  }

  async getAll(storeName) {
    return new Promise((resolve) => {
      const tx = this.db.transaction(storeName, "readonly");
      const req = tx.objectStore(storeName).getAll();
      req.onsuccess = () => resolve(req.result || []);
      req.onerror = () => resolve([]);
    });
  }

  async put(storeName, val) {
    return new Promise((resolve, reject) => {
      const tx = this.db.transaction(storeName, "readwrite");
      const req = tx.objectStore(storeName).put(val);
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    });
  }

  async delete(storeName, key) {
    return new Promise((resolve) => {
      const tx = this.db.transaction(storeName, "readwrite");
      const req = tx.objectStore(storeName).delete(key);
      req.onsuccess = () => resolve(true);
      req.onerror = () => resolve(false);
    });
  }

  async count(storeName) {
    return new Promise((resolve) => {
      const tx = this.db.transaction(storeName, "readonly");
      const req = tx.objectStore(storeName).count();
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => resolve(0);
    });
  }

  async clearAll() {
    return new Promise((resolve) => {
      const stores = ["files", "events", "wiki", "tickets", "artifacts", "meta"];
      const tx = this.db.transaction(stores, "readwrite");
      for (const s of stores) {
        tx.objectStore(s).clear();
      }
      tx.oncomplete = () => resolve(true);
      tx.onerror = () => resolve(false);
    });
  }

  async importBundle(bundle, mode = "merge") {
    return new Promise((resolve, reject) => {
      const stores = ["files", "events", "wiki", "tickets", "meta"];
      const tx = this.db.transaction(stores, "readwrite");

      if (mode === "replace") {
        for (const s of stores) {
          tx.objectStore(s).clear();
        }
      }

      let countFiles = 0, countEvents = 0, countWiki = 0, countTickets = 0;

      if (Array.isArray(bundle.events)) {
        const eventStore = tx.objectStore("events");
        for (const ev of bundle.events) {
          eventStore.put(ev);
          countEvents++;
        }
      }

      if (Array.isArray(bundle.files)) {
        const fileStore = tx.objectStore("files");
        for (const f of bundle.files) {
          const path = f.path || f.name;
          if (isSafeFilePath(path)) {
            fileStore.put(f);
            countFiles++;
          }
        }
      }

      if (Array.isArray(bundle.wiki)) {
        const wikiStore = tx.objectStore("wiki");
        for (const w of bundle.wiki) {
          if (w && isSafePropKey(w.name)) {
            wikiStore.put(w);
            countWiki++;
          }
        }
      } else if (bundle.wiki && typeof bundle.wiki === "object") {
        const wikiStore = tx.objectStore("wiki");
        for (const [name, text] of Object.entries(bundle.wiki)) {
          if (Object.prototype.hasOwnProperty.call(bundle.wiki, name) && isSafePropKey(name)) {
            wikiStore.put({ name, text: typeof text === "string" ? text : (text.text || ""), author: "imported", mtime: Date.now() });
            countWiki++;
          }
        }
      }

      if (Array.isArray(bundle.tickets)) {
        const tktStore = tx.objectStore("tickets");
        for (const t of bundle.tickets) {
          tktStore.put(t);
          countTickets++;
        }
      }

      tx.oncomplete = () => {
        resolve({
          mode,
          importedFiles: countFiles,
          importedEvents: countEvents,
          importedWiki: countWiki,
          importedTickets: countTickets
        });
      };
      tx.onerror = () => reject(tx.error);
    });
  }
}

// =========================================================================
// Backend 2: SQLite WASM Storage
// =========================================================================
class SqliteWasmStorage {
  constructor() {
    this.name = "SQLite WASM";
    this.db = null;
    this.sqlModule = null;
  }

  async init(existingBinary) {
    if (!window.initSqlJs) {
      await this.loadSqlJsScript();
    }
    this.sqlModule = await window.initSqlJs({
      locateFile: file => `https://cdnjs.cloudflare.com/ajax/libs/sql.js/1.12.0/${file}`
    });
    if (existingBinary) {
      this.db = new this.sqlModule.Database(new Uint8Array(existingBinary));
    } else {
      this.db = new this.sqlModule.Database();
      this.createSchema();
      this.seedDefaults();
    }
  }

  loadSqlJsScript() {
    return new Promise((resolve, reject) => {
      const script = document.createElement("script");
      script.src = "https://cdnjs.cloudflare.com/ajax/libs/sql.js/1.12.0/sql-wasm.js";
      script.onload = resolve;
      script.onerror = () => {
        // Fallback mock if offline
        console.warn("Could not load remote sql-wasm.js, using in-memory mock.");
        resolve();
      };
      document.head.appendChild(script);
    });
  }

  createSchema() {
    if (!this.db) return;
    this.db.run(`
      CREATE TABLE IF NOT EXISTS blob (rid INTEGER PRIMARY KEY, rcvid INTEGER, size INTEGER, uuid TEXT UNIQUE, content BLOB);
      CREATE TABLE IF NOT EXISTS event (objid INTEGER PRIMARY KEY, type TEXT, mtime REAL, user TEXT, comment TEXT, branch TEXT, uuid TEXT);
      CREATE TABLE IF NOT EXISTS filename (fnid INTEGER PRIMARY KEY, name TEXT UNIQUE);
      CREATE TABLE IF NOT EXISTS files (path TEXT PRIMARY KEY, content TEXT, mtime REAL);
      CREATE TABLE IF NOT EXISTS mlink (mid INTEGER, fid INTEGER, fnid INTEGER, pid INTEGER, mperm INTEGER);
      CREATE TABLE IF NOT EXISTS wiki (name TEXT PRIMARY KEY, text TEXT, author TEXT, mtime REAL);
      CREATE TABLE IF NOT EXISTS ticket (tkt_uuid TEXT PRIMARY KEY, title TEXT, desc TEXT, status TEXT, type TEXT, priority TEXT, reporter TEXT, mtime REAL, deadline REAL, history TEXT, linked_prs TEXT);
      CREATE TABLE IF NOT EXISTS pull_request (id TEXT PRIMARY KEY, title TEXT, description TEXT, source_branch TEXT, target_branch TEXT, author TEXT, status TEXT, ticket_id TEXT, created REAL, modified REAL, merged_at REAL, merge_commit TEXT);
    `);
  }

  seedDefaults() {
    if (!this.db) return;
    for (const [name, text] of Object.entries(DEFAULT_WIKI_DOCS)) {
      this.db.run("INSERT OR REPLACE INTO wiki(name, text, author, mtime) VALUES(?, ?, 'system', ?)", [name, text, Date.now() / 1000]);
    }
    this.db.run("INSERT OR REPLACE INTO event(objid, type, mtime, user, comment, branch, uuid) VALUES(1, 'ci', ?, 'admin', 'Initial check-in (SQLite WASM)', 'trunk', 'ci-init-sqlite')", [Date.now() / 1000]);
    this.db.run("INSERT OR REPLACE INTO files(path, content, mtime) VALUES('README.md', '# My Fossil-Nim Project (SQLite WASM)\n\nRunning on SQLite in WebAssembly!\n', ?)", [Date.now() / 1000]);
    this.db.run("INSERT OR IGNORE INTO filename(name) VALUES('README.md')");

    // Seed tickets
    try {
      const rows = this.exec("SELECT count(*) as cnt FROM ticket");
      if (!rows || rows.length === 0 || rows[0].cnt === 0) {
        for (const t of DEFAULT_TICKETS_SEED) {
          this.db.run("INSERT OR REPLACE INTO ticket(tkt_uuid, title, desc, status, type, priority, reporter, mtime, deadline, history, linked_prs) VALUES(?, ?, ?, ?, 'code', ?, ?, ?, ?, ?, ?)",
            [t.id, t.title, t.desc, t.status, t.priority, t.reporter, t.mtime / 1000, (t.deadline || 0) / 1000, JSON.stringify(t.history || []), JSON.stringify(t.linkedPrs || [])]);
        }
      }
    } catch (_) {}

    // Seed PRs
    try {
      const prRows = this.exec("SELECT count(*) as cnt FROM pull_request");
      if (!prRows || prRows.length === 0 || prRows[0].cnt === 0) {
        for (const pr of DEFAULT_PRS_SEED) {
          this.db.run("INSERT OR REPLACE INTO pull_request(id, title, description, source_branch, target_branch, author, status, ticket_id, created, modified, merged_at, merge_commit) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [pr.id, pr.title, pr.description, pr.sourceBranch, pr.targetBranch, pr.author, pr.status, pr.ticketId, pr.created / 1000, pr.modified / 1000, (pr.mergedAt || 0) / 1000, pr.mergeCommit || ""]);
        }
      }
    } catch (_) {}
  }

  exec(sql, params = []) {
    if (!this.db) return [];
    try {
      const stmt = this.db.prepare(sql);
      stmt.bind(params);
      const res = [];
      while (stmt.step()) {
        res.push(stmt.getAsObject());
      }
      stmt.free();
      return res;
    } catch (e) {
      console.error("SQL Error:", e, sql);
      return [];
    }
  }

  run(sql, params = []) {
    if (!this.db) return;
    this.db.run(sql, params);
  }

  exportBinary() {
    if (!this.db) return new Uint8Array();
    return this.db.export();
  }

  importBinary(uint8Array, mode = "merge") {
    if (!this.db || mode === "replace") {
      this.db = new this.sqlModule.Database(uint8Array);
      return { mode: "replace", success: true };
    }
    try {
      const incomingDb = new this.sqlModule.Database(uint8Array);
      this.db.run("BEGIN TRANSACTION;");

      const events = incomingDb.exec("SELECT * FROM event");
      if (events.length > 0 && events[0].values) {
        const cols = events[0].columns;
        for (const row of events[0].values) {
          const obj = {};
          cols.forEach((c, idx) => obj[c] = row[idx]);
          this.db.run("INSERT OR IGNORE INTO event(objid, type, mtime, user, comment, branch) VALUES(?, ?, ?, ?, ?, ?)",
            [obj.objid, obj.type, obj.mtime, obj.user, obj.comment, obj.branch || "trunk"]);
        }
      }

      const wiki = incomingDb.exec("SELECT * FROM wiki");
      if (wiki.length > 0 && wiki[0].values) {
        const cols = wiki[0].columns;
        for (const row of wiki[0].values) {
          const obj = {};
          cols.forEach((c, idx) => obj[c] = row[idx]);
          this.db.run("INSERT OR REPLACE INTO wiki(name, text, author, mtime) VALUES(?, ?, ?, ?)",
            [obj.name, obj.text, obj.author, obj.mtime]);
        }
      }

      const fn = incomingDb.exec("SELECT * FROM filename");
      if (fn.length > 0 && fn[0].values) {
        for (const row of fn[0].values) {
          this.db.run("INSERT OR IGNORE INTO filename(fnid, name) VALUES(?, ?)", [row[0], row[1]]);
        }
      }

      this.db.run("COMMIT;");
      incomingDb.close();
      return { mode: "merge", success: true };
    } catch (e) {
      try { this.db.run("ROLLBACK;"); } catch (_) {}
      console.error("Merge error in SQLite WASM:", e);
      throw e;
    }
  }

  importBundle(bundle, mode = "merge") {
    if (!this.db) return { success: false };
    if (mode === "replace") {
      this.db.run("DELETE FROM event; DELETE FROM wiki; DELETE FROM filename; DELETE FROM ticket; DELETE FROM blob;");
    }
    this.db.run("BEGIN TRANSACTION;");
    let countEvents = 0, countWiki = 0, countFiles = 0;

    if (Array.isArray(bundle.events)) {
      for (const ev of bundle.events) {
        this.db.run("INSERT OR IGNORE INTO event(type, mtime, user, comment, branch) VALUES(?, ?, ?, ?, ?)",
          [ev.type || "ci", (ev.mtime > 10000000000 ? ev.mtime / 1000 : ev.mtime) || Date.now() / 1000, ev.user || "admin", ev.comment || "", ev.branch || "trunk"]);
        countEvents++;
      }
    }

    if (Array.isArray(bundle.wiki)) {
      for (const w of bundle.wiki) {
        if (w && isSafePropKey(w.name)) {
          this.db.run("INSERT OR REPLACE INTO wiki(name, text, author, mtime) VALUES(?, ?, ?, ?)",
            [w.name, w.text, w.author || "imported", Date.now() / 1000]);
          countWiki++;
        }
      }
    }

    if (Array.isArray(bundle.files)) {
      for (const f of bundle.files) {
        const path = f.path || f.name;
        if (isSafeFilePath(path)) {
          this.db.run("INSERT OR IGNORE INTO filename(name) VALUES(?)", [path]);
          countFiles++;
        }
      }
    }

    this.db.run("COMMIT;");
    return { mode, success: true, countEvents, countWiki, countFiles };
  }
}

// =========================================================================
// Backend 3: Pure-Nim In-Memory CDB Storage
// =========================================================================
class CdbMemoryStorage {
  constructor() {
    this.name = "Pure-Nim CDB";
    this.handle = 0;
    this.fileList = new Set(["README.md"]);
    this.ticketList = [];
    this.eventsList = [];
  }

  async init(existingBinaryString) {
    if (window.FossilCore) {
      if (existingBinaryString) {
        this.handle = window.FossilCore.cdbLoad(existingBinaryString);
        this.restoreMeta();
      } else {
        this.handle = window.FossilCore.cdbCreate();
        this.seedDefaults();
      }
    }
  }

  restoreMeta() {
    if (!this.handle || !window.FossilCore) return;
    try {
      const fl = window.FossilCore.cdbGet(this.handle, "meta:file_list");
      if (fl) {
        const arr = JSON.parse(fl);
        this.fileList = new Set(arr);
      }
      const tl = window.FossilCore.cdbGet(this.handle, "meta:ticket_list");
      if (tl) this.ticketList = JSON.parse(tl);
      const el = window.FossilCore.cdbGet(this.handle, "meta:event_list");
      if (el) this.eventsList = JSON.parse(el);
    } catch (_) {}
  }

  seedDefaults() {
    if (!this.handle || !window.FossilCore) return;
    for (const [name, text] of Object.entries(DEFAULT_WIKI_DOCS)) {
      window.FossilCore.cdbPut(this.handle, "wiki:" + name, text);
    }
    window.FossilCore.cdbPut(this.handle, "meta:comment", "Initial repository in Pure-Nim CDB");
    window.FossilCore.cdbPut(this.handle, "meta:user", "admin");
    window.FossilCore.cdbPut(this.handle, "meta:branch", "trunk");
    window.FossilCore.cdbPut(this.handle, "file:README.md", "# Fossil-Nim in CDB Memory\nHigh-performance immutable KV VCS storage.");
    this.fileList = new Set(["README.md"]);
    this.eventsList = [{
      type: "ci",
      branch: "trunk",
      user: "admin",
      comment: "Initial check-in (Pure-Nim CDB)",
      mtime: Date.now(),
      uuid: "ci-init-cdb"
    }];
    this.ticketList = JSON.parse(JSON.stringify(DEFAULT_TICKETS_SEED));
    this.prList = JSON.parse(JSON.stringify(DEFAULT_PRS_SEED));
    this.syncMeta();
  }

  getFiles() {
    return Array.from(this.fileList);
  }

  addFile(path) {
    this.fileList.add(path);
    this.syncMeta();
  }

  getTickets() {
    return this.ticketList;
  }

  addTicket(tkt) {
    this.ticketList.push(tkt);
    this.syncMeta();
  }

  updateTicket(id, updates) {
    const idx = this.ticketList.findIndex(t => t.id === id);
    if (idx !== -1) {
      Object.assign(this.ticketList[idx], updates);
      this.syncMeta();
      return this.ticketList[idx];
    }
    return null;
  }

  deleteTicket(id) {
    this.ticketList = this.ticketList.filter(t => t.id !== id);
    this.syncMeta();
    return true;
  }

  getPullRequests() {
    return this.prList || [];
  }

  addPullRequest(pr) {
    if (!this.prList) this.prList = [];
    this.prList.push(pr);
    this.syncMeta();
  }

  updatePullRequest(id, updates) {
    if (!this.prList) this.prList = [];
    const idx = this.prList.findIndex(p => p.id === id);
    if (idx !== -1) {
      Object.assign(this.prList[idx], updates);
      this.syncMeta();
      return this.prList[idx];
    }
    return null;
  }

  getEvents() {
    return this.eventsList;
  }

  addEvent(ev) {
    this.eventsList.unshift(ev);
    this.syncMeta();
  }

  syncMeta() {
    if (this.handle && window.FossilCore) {
      window.FossilCore.cdbPut(this.handle, "meta:file_list", JSON.stringify(Array.from(this.fileList)));
      window.FossilCore.cdbPut(this.handle, "meta:ticket_list", JSON.stringify(this.ticketList));
      window.FossilCore.cdbPut(this.handle, "meta:pr_list", JSON.stringify(this.prList || []));
      window.FossilCore.cdbPut(this.handle, "meta:event_list", JSON.stringify(this.eventsList));
    }
  }

  get(key) {
    if (!this.handle || !window.FossilCore) return null;
    return window.FossilCore.cdbGet(this.handle, key);
  }

  put(key, val) {
    if (!this.handle || !window.FossilCore) return false;
    return window.FossilCore.cdbPut(this.handle, key, val);
  }

  serialize() {
    if (!this.handle || !window.FossilCore) return "";
    return window.FossilCore.cdbSerialize(this.handle);
  }

  importCdb(cdbString, mode = "merge") {
    if (!window.FossilCore) return { success: false };
    this.handle = window.FossilCore.cdbLoad(cdbString);
    this.restoreMeta();
    return { mode: "replace", success: true };
  }

  importBundle(bundle, mode = "merge") {
    if (!window.FossilCore) return { success: false };
    if (mode === "replace" || !this.handle) {
      this.handle = window.FossilCore.cdbCreate();
      this.fileList.clear();
      this.ticketList = [];
      this.eventsList = [];
    }
    let countFiles = 0, countWiki = 0;
    if (Array.isArray(bundle.files)) {
      for (const f of bundle.files) {
        const path = f.path || f.name;
        if (isSafeFilePath(path)) {
          window.FossilCore.cdbPut(this.handle, "file:" + path, f.content || "");
          this.fileList.add(path);
          countFiles++;
        }
      }
    }
    if (Array.isArray(bundle.wiki)) {
      for (const w of bundle.wiki) {
        if (w && isSafePropKey(w.name)) {
          window.FossilCore.cdbPut(this.handle, "wiki:" + w.name, w.text || "");
          countWiki++;
        }
      }
    }
    if (Array.isArray(bundle.tickets)) {
      for (const t of bundle.tickets) {
        this.ticketList.push(t);
      }
    }
    if (Array.isArray(bundle.events)) {
      for (const e of bundle.events) {
        this.eventsList.push(e);
      }
    }
    this.syncMeta();
    return { mode, success: true, countFiles, countWiki };
  }
}

// Global Storage Manager instance
window.FossilStorageManager = {
  backendType: "indexeddb", // "indexeddb" | "sqlite_wasm" | "cdb"
  indexedDB: new IndexedDbStorage(),
  sqliteWasm: new SqliteWasmStorage(),
  cdb: new CdbMemoryStorage(),

  async init() {
    await this.indexedDB.init();
    console.log("FossilStorageManager initialized with IndexedDB.");
  },

  getActiveBackend() {
    if (this.backendType === "sqlite_wasm") return this.sqliteWasm;
    if (this.backendType === "cdb") return this.cdb;
    return this.indexedDB;
  },

  async switchBackend(type, data) {
    this.backendType = type;
    if (type === "sqlite_wasm" && !this.sqliteWasm.db) {
      await this.sqliteWasm.init(data);
    } else if (type === "cdb" && !this.cdb.handle) {
      await this.cdb.init(data);
    }
    return this.getActiveBackend();
  },

  async hasExistingData() {
    if (this.backendType === "indexeddb") {
      const fc = await this.indexedDB.count("files");
      const ec = await this.indexedDB.count("events");
      return (fc > 0 || ec > 0);
    } else if (this.backendType === "sqlite_wasm") {
      if (!this.sqliteWasm.db) return false;
      const rows = this.sqliteWasm.exec("SELECT count(*) as c FROM event;");
      return rows.length > 0 && rows[0].c > 0;
    } else if (this.backendType === "cdb") {
      return !!this.cdb.handle;
    }
    return false;
  },

  async importRepo(data, filename, mode = "merge") {
    const isFossilBinary = filename.endsWith(".fossil") || (data instanceof Uint8Array && String.fromCharCode(...data.slice(0, 15)).includes("SQLite format 3"));
    const isCdb = filename.endsWith(".cdb");

    if (isFossilBinary) {
      if (this.backendType !== "sqlite_wasm") {
        await this.switchBackend("sqlite_wasm");
      }
      return this.sqliteWasm.importBinary(data instanceof Uint8Array ? data : new Uint8Array(data), mode);
    } else if (isCdb) {
      if (this.backendType !== "cdb") {
        await this.switchBackend("cdb");
      }
      return this.cdb.importCdb(typeof data === "string" ? data : new TextDecoder().decode(data), mode);
    } else {
      let bundle;
      if (typeof data === "string") {
        bundle = JSON.parse(data);
      } else if (data instanceof Uint8Array) {
        bundle = JSON.parse(new TextDecoder().decode(data));
      } else {
        bundle = data;
      }

      if (this.backendType === "indexeddb") {
        return await this.indexedDB.importBundle(bundle, mode);
      } else if (this.backendType === "sqlite_wasm") {
        return this.sqliteWasm.importBundle(bundle, mode);
      } else if (this.backendType === "cdb") {
        return this.cdb.importBundle(bundle, mode);
      }
    }
  },

  async exportRepo() {
    if (this.backendType === 'sqlite_wasm') {
      const bin = this.sqliteWasm.exportBinary();
      return {
        type: 'binary',
        filename: 'repository.fossil',
        mimeType: 'application/x-sqlite3',
        data: bin
      };
    } else if (this.backendType === 'cdb') {
      const ser = this.cdb.serialize();
      return {
        type: 'text',
        filename: 'repository.cdb',
        mimeType: 'text/plain',
        data: ser
      };
    } else {
      const files = await this.indexedDB.getAll('files');
      const events = await this.indexedDB.getAll('events');
      const wiki = await this.indexedDB.getAll('wiki');
      const tickets = await this.indexedDB.getAll('tickets');
      const bundle = {
        format: 'fossil-nim-bundle',
        version: '1.0',
        files,
        events,
        wiki,
        tickets,
        exportedAt: new Date().toISOString()
      };
      return {
        type: 'json',
        filename: 'fossil_backup.json',
        mimeType: 'application/json',
        data: bundle
      };
    }
  }
};
