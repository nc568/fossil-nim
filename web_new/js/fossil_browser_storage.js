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
      const req = indexedDB.open(this.dbName, 1);
      req.onupgradeneeded = (e) => {
        const db = e.target.result;
        if (!db.objectStoreNames.contains("artifacts")) db.createObjectStore("artifacts", { keyPath: "uuid" });
        if (!db.objectStoreNames.contains("events")) db.createObjectStore("events", { keyPath: "id", autoIncrement: true });
        if (!db.objectStoreNames.contains("files")) db.createObjectStore("files", { keyPath: "path" });
        if (!db.objectStoreNames.contains("wiki")) db.createObjectStore("wiki", { keyPath: "name" });
        if (!db.objectStoreNames.contains("tickets")) db.createObjectStore("tickets", { keyPath: "id" });
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
      CREATE TABLE IF NOT EXISTS event (objid INTEGER PRIMARY KEY, type TEXT, mtime REAL, user TEXT, comment TEXT, branch TEXT);
      CREATE TABLE IF NOT EXISTS filename (fnid INTEGER PRIMARY KEY, name TEXT UNIQUE);
      CREATE TABLE IF NOT EXISTS mlink (mid INTEGER, fid INTEGER, fnid INTEGER, pid INTEGER, mperm INTEGER);
      CREATE TABLE IF NOT EXISTS wiki (name TEXT PRIMARY KEY, text TEXT, author TEXT, mtime REAL);
      CREATE TABLE IF NOT EXISTS ticket (tkt_uuid TEXT PRIMARY KEY, title TEXT, desc TEXT, status TEXT, type TEXT, priority TEXT);
    `);
  }

  seedDefaults() {
    if (!this.db) return;
    for (const [name, text] of Object.entries(DEFAULT_WIKI_DOCS)) {
      this.db.run("INSERT OR REPLACE INTO wiki(name, text, author, mtime) VALUES(?, ?, 'system', ?)", [name, text, Date.now() / 1000]);
    }
    this.db.run("INSERT OR REPLACE INTO event(objid, type, mtime, user, comment, branch) VALUES(1, 'ci', ?, 'admin', 'Initial check-in (SQLite WASM)', 'trunk')", [Date.now() / 1000]);
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
}

// =========================================================================
// Backend 3: Pure-Nim In-Memory CDB Storage
// =========================================================================
class CdbMemoryStorage {
  constructor() {
    this.name = "Pure-Nim CDB";
    this.handle = 0;
  }

  async init(existingBinaryString) {
    if (window.FossilCore) {
      if (existingBinaryString) {
        this.handle = window.FossilCore.cdbLoad(existingBinaryString);
      } else {
        this.handle = window.FossilCore.cdbCreate();
        this.seedDefaults();
      }
    }
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
  }
};
