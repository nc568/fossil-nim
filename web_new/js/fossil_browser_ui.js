/**
 * Fossil-Nim Browser UI Controller
 * Powers the interactive in-browser VCS workspace with:
 * - 3 Storage Backends (IndexedDB, SQLite WASM, Pure-Nim CDB)
 * - Timeline, File Explorer, In-Browser Editor, Myers Diff Viewer
 * - Wiki & Documentation reader/editor
 * - Issue / Ticket Tracker
 * - 89-Tool MCP Agent Console
 * Pure Vanilla JavaScript, zero heavy frameworks.
 */

(function () {
  'use strict';

  // State
  const state = {
    currentTab: 'timeline',
    activeBackend: 'indexeddb',
    activeFile: 'README.md',
    activeWiki: 'Home',
    activeMcpTool: 'vcs_status',
    wikiEditMode: false,
    fileOriginalContent: ''
  };

  // Helper functions
  function $(id) {
    return document.getElementById(id);
  }

  function escapeHtml(str) {
    if (!str) return '';
    return str
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  function formatDiffHtml(unifiedDiff) {
    if (!unifiedDiff) return '<div class="empty">No differences found (files are identical)</div>';
    const lines = unifiedDiff.split('\n');
    let html = '<div class="diff-view">';
    for (const line of lines) {
      if (line.startsWith('+++') || line.startsWith('---')) {
        html += `<div class="diff-line diff-line-chunk">${escapeHtml(line)}</div>`;
      } else if (line.startsWith('@@')) {
        html += `<div class="diff-line diff-line-chunk">${escapeHtml(line)}</div>`;
      } else if (line.startsWith('+')) {
        html += `<div class="diff-line diff-line-add">${escapeHtml(line)}</div>`;
      } else if (line.startsWith('-')) {
        html += `<div class="diff-line diff-line-del">${escapeHtml(line)}</div>`;
      } else {
        html += `<div class="diff-line">${escapeHtml(line)}</div>`;
      }
    }
    html += '</div>';
    return html;
  }

  // UI Controller Object
  window.FossilBrowserUI = {
    async init() {
      console.log('🦖 Fossil-Nim Browser Edition UI Initializing...');
      
      // Initialize Storage
      if (window.FossilStorageManager) {
        await window.FossilStorageManager.init();
      }

      this.bindTabs();
      this.bindStorageSwitcher();
      this.bindTheme();
      this.bindTimelineActions();
      this.bindEditorActions();
      this.bindDiffTool();
      this.bindWikiActions();
      this.bindTicketActions();
      this.bindMcpActions();
      this.bindStorageDiagnostics();

      // Initial Render
      await this.refreshAll();
      console.log('✅ Fossil-Nim Browser Edition UI Ready!');
    },

    bindTabs() {
      const tabButtons = document.querySelectorAll('.tab-btn[data-tab]');
      tabButtons.forEach(btn => {
        btn.addEventListener('click', () => {
          const targetTab = btn.getAttribute('data-tab');
          this.switchTab(targetTab);
        });
      });
    },

    switchTab(tabName) {
      state.currentTab = tabName;
      document.querySelectorAll('.tab-btn').forEach(b => {
        b.classList.toggle('active', b.getAttribute('data-tab') === tabName);
      });
      document.querySelectorAll('.tab-content').forEach(p => {
        p.classList.toggle('active', p.id === `tab-${tabName}`);
      });

      // Lazy refresh for specific tab
      if (tabName === 'timeline') this.renderTimeline();
      if (tabName === 'files') this.renderFiles();
      if (tabName === 'wiki') this.renderWiki();
      if (tabName === 'tickets') this.renderTickets();
      if (tabName === 'mcp') this.renderMcp();
      if (tabName === 'storage') this.renderStorageDiagnostics();
    },

    bindStorageSwitcher() {
      const select = $('storage-backend-select');
      if (!select) return;
      select.value = state.activeBackend;
      select.addEventListener('change', async (e) => {
        const newBackend = e.target.value;
        $('loading-indicator').classList.remove('hidden');
        try {
          await window.FossilStorageManager.switchBackend(newBackend);
          state.activeBackend = newBackend;
          $('active-backend-name').innerText = window.FossilStorageManager.getActiveBackend().name;
          await this.refreshAll();
        } catch (err) {
          alert('Failed to switch storage backend: ' + err.message);
        } finally {
          $('loading-indicator').classList.add('hidden');
        }
      });
    },

    bindTheme() {
      const toggle = $('theme-toggle-btn');
      if (!toggle) return;
      const current = localStorage.getItem('fossil_theme') || 'light';
      document.documentElement.setAttribute('data-theme', current);
      toggle.innerText = current === 'dark' ? '☀️' : '🌙';

      toggle.addEventListener('click', () => {
        const theme = document.documentElement.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
        document.documentElement.setAttribute('data-theme', theme);
        localStorage.setItem('fossil_theme', theme);
        toggle.innerText = theme === 'dark' ? '☀️' : '🌙';
      });
    },

    async refreshAll() {
      await Promise.all([
        this.renderTimeline(),
        this.renderFiles(),
        this.renderWiki(),
        this.renderTickets(),
        this.renderMcp(),
        this.renderStorageDiagnostics()
      ]);
    },

    // -------------------------------------------------------------
    // Tab 1: Timeline
    // -------------------------------------------------------------
    async renderTimeline() {
      const listEl = $('timeline-list');
      if (!listEl) return;
      listEl.innerHTML = '<div class="loading"><div class="spinner"></div></div>';

      const res = await window.fossilMcp.callTool('vcs_timeline', { limit: 50 });
      const events = res.events || [];

      if (events.length === 0) {
        listEl.innerHTML = '<div class="empty">No commits yet in this repository backend.</div>';
        return;
      }

      let html = '<div style="display:flex; flex-direction:column; gap:0.75rem;">';
      for (const ev of events) {
        const dateStr = new Date(ev.mtime > 10000000000 ? ev.mtime : ev.mtime * 1000).toLocaleString();
        const shortHash = ev.uuid ? ev.uuid.substring(0, 10) : (ev.objid ? `obj-${ev.objid}` : 'ci-init');
        html += `
          <div class="card" style="padding:1rem;">
            <div style="display:flex; justify-content:space-between; align-items:flex-start; margin-bottom:0.4rem;">
              <div style="font-weight:600; font-size:1.05rem; display:flex; align-items:center; gap:0.5rem;">
                <span class="badge badge-primary">${escapeHtml(ev.branch || 'trunk')}</span>
                <span>${escapeHtml(ev.comment || 'Check-in')}</span>
              </div>
              <span class="badge badge-secondary" style="font-family:var(--font-mono); font-size:0.75rem;">${shortHash}</span>
            </div>
            <div style="display:flex; gap:1rem; font-size:0.85rem; color:var(--color-text-muted);">
              <span>👤 User: <b>${escapeHtml(ev.user || 'admin')}</b></span>
              <span>📅 ${dateStr}</span>
            </div>
          </div>
        `;
      }
      html += '</div>';
      listEl.innerHTML = html;
    },

    bindTimelineActions() {
      const newCommitBtn = $('btn-new-commit-modal');
      const modal = $('modal-commit');
      const form = $('form-commit');
      const cancelBtn = $('btn-commit-cancel');

      if (newCommitBtn && modal) {
        newCommitBtn.addEventListener('click', () => modal.classList.remove('hidden'));
      }
      if (cancelBtn && modal) {
        cancelBtn.addEventListener('click', () => modal.classList.add('hidden'));
      }
      if (form && modal) {
        form.addEventListener('submit', async (e) => {
          e.preventDefault();
          const comment = $('commit-comment').value.trim();
          const branch = $('commit-branch').value.trim() || 'trunk';
          const user = $('commit-user').value.trim() || 'developer';

          if (!comment) return;

          await window.fossilMcp.callTool('vcs_commit', { message: comment, branch });
          $('commit-comment').value = '';
          modal.classList.add('hidden');
          await this.renderTimeline();
          this.switchTab('timeline');
        });
      }
    },

    // -------------------------------------------------------------
    // Tab 2: Files & In-Browser Code Editor
    // -------------------------------------------------------------
    async renderFiles() {
      const treeEl = $('files-tree');
      const editorEl = $('code-editor-text');
      const fileLabel = $('active-file-label');
      if (!treeEl) return;

      const res = await window.fossilMcp.callTool('vcs_file_list');
      let files = res.files || [];
      if (files.length === 0) {
        files = ['README.md'];
      }

      let treeHtml = '';
      for (const filePath of files) {
        const isActive = filePath === state.activeFile;
        treeHtml += `
          <div class="file-tree-item ${isActive ? 'active' : ''}" data-file="${escapeHtml(filePath)}">
            📄 <span>${escapeHtml(filePath)}</span>
          </div>
        `;
      }
      treeEl.innerHTML = treeHtml;

      // Bind file click
      treeEl.querySelectorAll('.file-tree-item').forEach(item => {
        item.addEventListener('click', async () => {
          const path = item.getAttribute('data-file');
          await this.loadFileIntoEditor(path);
        });
      });

      // Load active file
      await this.loadFileIntoEditor(state.activeFile);
    },

    async loadFileIntoEditor(filePath) {
      state.activeFile = filePath;
      const editorEl = $('code-editor-text');
      const fileLabel = $('active-file-label');
      const diffContainer = $('editor-diff-preview');
      if (diffContainer) diffContainer.classList.add('hidden');

      if (fileLabel) fileLabel.innerText = filePath;

      document.querySelectorAll('.file-tree-item').forEach(el => {
        el.classList.toggle('active', el.getAttribute('data-file') === filePath);
      });

      const res = await window.fossilMcp.callTool('vcs_file_read', { path: filePath });
      const content = res.content || '';
      state.fileOriginalContent = content;
      if (editorEl) editorEl.value = content;
    },

    bindEditorActions() {
      const saveBtn = $('btn-editor-save');
      const diffBtn = $('btn-editor-diff');
      const commitBtn = $('btn-editor-commit');
      const newFileBtn = $('btn-new-file');
      const editorEl = $('code-editor-text');
      const diffContainer = $('editor-diff-preview');

      if (saveBtn) {
        saveBtn.addEventListener('click', async () => {
          const content = editorEl.value;
          await window.fossilMcp.callTool('vcs_file_write', { path: state.activeFile, content });
          state.fileOriginalContent = content;
          alert(`Saved ${state.activeFile} to ${state.activeBackend}!`);
          if (diffContainer) diffContainer.classList.add('hidden');
        });
      }

      if (diffBtn) {
        diffBtn.addEventListener('click', () => {
          if (!diffContainer) return;
          const currentText = editorEl.value;
          let diffOutput = '';
          if (window.FossilCore && window.FossilCore.diffUnified) {
            diffOutput = window.FossilCore.diffUnified(state.fileOriginalContent, currentText, state.activeFile);
          } else {
            diffOutput = `--- a/${state.activeFile}\n+++ b/${state.activeFile}\n(Diff engine loading...)`;
          }
          diffContainer.innerHTML = `
            <div style="font-weight:600; margin-bottom:0.5rem; display:flex; justify-content:space-between; align-items:center;">
              <span>⚡ Myers Unified Diff (Pure Nim JS Engine):</span>
              <button class="btn btn-secondary btn-sm" onclick="document.getElementById('editor-diff-preview').classList.add('hidden')">Hide Diff</button>
            </div>
            ${formatDiffHtml(diffOutput)}
          `;
          diffContainer.classList.remove('hidden');
        });
      }

      if (commitBtn) {
        commitBtn.addEventListener('click', async () => {
          const content = editorEl.value;
          await window.fossilMcp.callTool('vcs_file_write', { path: state.activeFile, content });
          state.fileOriginalContent = content;
          const msg = prompt(`Enter commit message for ${state.activeFile}:`, `Update ${state.activeFile}`);
          if (msg) {
            await window.fossilMcp.callTool('vcs_commit', { message: msg });
            alert(`Committed changes to ${state.activeFile}!`);
            await this.renderTimeline();
          }
        });
      }

      if (newFileBtn) {
        newFileBtn.addEventListener('click', async () => {
          const name = prompt('Enter new file name (e.g. src/app.nim or notes.md):');
          if (name && name.trim()) {
            const cleanName = name.trim();
            await window.fossilMcp.callTool('vcs_file_write', { path: cleanName, content: `# ${cleanName}\n\nCreated in Fossil-Nim Browser Edition.\n` });
            state.activeFile = cleanName;
            await this.renderFiles();
          }
        });
      }
    },

    // -------------------------------------------------------------
    // Tab 3: Myers Diff Engine Tool
    // -------------------------------------------------------------
    bindDiffTool() {
      const btn = $('btn-run-standalone-diff');
      const textA = $('diff-input-a');
      const textB = $('diff-input-b');
      const resultEl = $('standalone-diff-result');
      const presetSelect = $('diff-preset-select');

      const presets = {
        code: {
          a: `import std/[strutils, tables]\n\nproc processTask(id: int): string =\n  result = "Task #" & $id\n  echo "Starting..."\n`,
          b: `import std/[strutils, tables, os]\n\nproc processTask(id: int): string =\n  result = "Task #" & $id & " [OPTIMIZED]"\n  echo "Starting high-speed processing..."\n  echo "Completed!"\n`
        },
        doc: {
          a: `# Version 1.0\nFossil-Nim is a fast version control system.\nRuns natively on Linux/macOS.\n`,
          b: `# Version 2.0 (Browser Edition)\nFossil-Nim is a fast distributed version control system.\nRuns natively on Linux/macOS and directly in modern web browsers via Nim JS/WASM!\nIncludes 89 MCP Tools for AI Agents.\n`
        }
      };

      if (presetSelect) {
        presetSelect.addEventListener('change', (e) => {
          const p = presets[e.target.value];
          if (p && textA && textB) {
            textA.value = p.a;
            textB.value = p.b;
            if (btn) btn.click();
          }
        });
      }

      if (btn && textA && textB && resultEl) {
        btn.addEventListener('click', () => {
          const t0 = performance.now();
          let diffStr = '';
          if (window.FossilCore && window.FossilCore.diffUnified) {
            diffStr = window.FossilCore.diffUnified(textA.value, textB.value, 'diff_test.nim');
          } else {
            diffStr = 'Diff engine not loaded.';
          }
          const t1 = performance.now();
          const elapsed = (t1 - t0).toFixed(2);

          resultEl.innerHTML = `
            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:0.5rem;">
              <span style="font-weight:600; font-size:0.9rem;">Myers Diff Output</span>
              <span class="badge badge-success">Computed in ${elapsed} ms via Nim Engine</span>
            </div>
            ${formatDiffHtml(diffStr)}
          `;
        });
      }
    },

    // -------------------------------------------------------------
    // Tab 4: Wiki & Documentation
    // -------------------------------------------------------------
    async renderWiki() {
      const listEl = $('wiki-pages-list');
      if (!listEl) return;

      const res = await window.fossilMcp.callTool('wiki_list');
      const pages = res.pages || [];

      let listHtml = '';
      for (const p of pages) {
        const isActive = p.name === state.activeWiki;
        listHtml += `
          <div class="file-tree-item ${isActive ? 'active' : ''}" data-wiki="${escapeHtml(p.name)}">
            📖 <span>${escapeHtml(p.name)}</span>
          </div>
        `;
      }
      listEl.innerHTML = listHtml;

      listEl.querySelectorAll('.file-tree-item').forEach(item => {
        item.addEventListener('click', async () => {
          const name = item.getAttribute('data-wiki');
          await this.loadWikiPage(name);
        });
      });

      await this.loadWikiPage(state.activeWiki);
    },

    async loadWikiPage(name) {
      state.activeWiki = name;
      const titleEl = $('wiki-view-title');
      const contentEl = $('wiki-view-content');
      const editorWrap = $('wiki-editor-wrap');
      const viewWrap = $('wiki-reader-wrap');
      const textarea = $('wiki-markdown-input');

      if (titleEl) titleEl.innerText = name;

      document.querySelectorAll('#wiki-pages-list .file-tree-item').forEach(el => {
        el.classList.toggle('active', el.getAttribute('data-wiki') === name);
      });

      const res = await window.fossilMcp.callTool('wiki_get', { name });
      const markdown = res.text || '# Empty Page';

      if (textarea) textarea.value = markdown;

      if (contentEl) {
        let html = '';
        if (window.FossilCore && window.FossilCore.markdownToHtml) {
          html = window.FossilCore.markdownToHtml(markdown);
        } else {
          html = `<pre>${escapeHtml(markdown)}</pre>`;
        }
        contentEl.innerHTML = html;
      }

      if (editorWrap && viewWrap) {
        editorWrap.classList.add('hidden');
        viewWrap.classList.remove('hidden');
        state.wikiEditMode = false;
      }
    },

    bindWikiActions() {
      const editBtn = $('btn-wiki-edit');
      const saveBtn = $('btn-wiki-save');
      const cancelBtn = $('btn-wiki-cancel');
      const newPageBtn = $('btn-wiki-new');
      const editorWrap = $('wiki-editor-wrap');
      const viewWrap = $('wiki-reader-wrap');
      const textarea = $('wiki-markdown-input');
      const previewEl = $('wiki-live-preview');

      if (editBtn) {
        editBtn.addEventListener('click', () => {
          state.wikiEditMode = true;
          editorWrap.classList.remove('hidden');
          viewWrap.classList.add('hidden');
          if (textarea && previewEl && window.FossilCore) {
            previewEl.innerHTML = window.FossilCore.markdownToHtml(textarea.value);
          }
        });
      }

      if (cancelBtn) {
        cancelBtn.addEventListener('click', () => {
          state.wikiEditMode = false;
          editorWrap.classList.add('hidden');
          viewWrap.classList.remove('hidden');
        });
      }

      if (textarea && previewEl) {
        textarea.addEventListener('input', () => {
          if (window.FossilCore && window.FossilCore.markdownToHtml) {
            previewEl.innerHTML = window.FossilCore.markdownToHtml(textarea.value);
          }
        });
      }

      if (saveBtn) {
        saveBtn.addEventListener('click', async () => {
          const text = textarea.value;
          await window.fossilMcp.callTool('wiki_create', { name: state.activeWiki, content: text });
          alert(`Saved wiki page "${state.activeWiki}"!`);
          await this.loadWikiPage(state.activeWiki);
        });
      }

      if (newPageBtn) {
        newPageBtn.addEventListener('click', async () => {
          const name = prompt('Enter new Wiki Page name (e.g. Quickstart):');
          if (name && name.trim()) {
            const cleanName = name.trim();
            await window.fossilMcp.callTool('wiki_create', { name: cleanName, content: `# ${cleanName}\n\nWrite documentation here in Markdown.\n` });
            state.activeWiki = cleanName;
            await this.renderWiki();
          }
        });
      }
    },

    // -------------------------------------------------------------
    // Tab 5: Tickets / Issue Tracker
    // -------------------------------------------------------------
    async renderTickets() {
      const listEl = $('tickets-list');
      if (!listEl) return;

      const res = await window.fossilMcp.callTool('ticket_list');
      const tickets = res.tickets || [];

      if (tickets.length === 0) {
        listEl.innerHTML = '<div class="empty">No tickets created yet. Click "+ New Ticket" to add one!</div>';
        return;
      }

      let html = '<div style="display:flex; flex-direction:column; gap:0.75rem;">';
      for (const t of tickets) {
        const priColor = t.priority === 'Critical' ? 'badge-danger' : (t.priority === 'High' ? 'badge-warning' : 'badge-info');
        html += `
          <div class="card" style="padding:1rem;">
            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:0.5rem;">
              <div style="display:flex; align-items:center; gap:0.5rem;">
                <span class="badge ${priColor}">${escapeHtml(t.priority || 'Medium')}</span>
                <span style="font-weight:600; font-size:1.05rem;">${escapeHtml(t.title)}</span>
              </div>
              <span class="badge badge-success">${escapeHtml(t.status || 'Open')}</span>
            </div>
            <p style="font-size:0.9rem; margin-bottom:0.5rem; color:var(--color-text);">${escapeHtml(t.desc)}</p>
            <div style="font-size:0.8rem; color:var(--color-text-muted);">
              ID: <code>${escapeHtml(t.id)}</code> | Reported by: <b>${escapeHtml(t.reporter || 'user')}</b>
            </div>
          </div>
        `;
      }
      html += '</div>';
      listEl.innerHTML = html;
    },

    bindTicketActions() {
      const newBtn = $('btn-ticket-modal');
      const modal = $('modal-ticket');
      const form = $('form-ticket');
      const cancelBtn = $('btn-ticket-cancel');

      if (newBtn && modal) newBtn.addEventListener('click', () => modal.classList.remove('hidden'));
      if (cancelBtn && modal) cancelBtn.addEventListener('click', () => modal.classList.add('hidden'));

      if (form && modal) {
        form.addEventListener('submit', async (e) => {
          e.preventDefault();
          const title = $('ticket-title').value.trim();
          const desc = $('ticket-desc').value.trim();
          const priority = $('ticket-priority').value;

          if (!title) return;

          await window.fossilMcp.callTool('ticket_create', { title, desc, priority });
          $('ticket-title').value = '';
          $('ticket-desc').value = '';
          modal.classList.add('hidden');
          await this.renderTickets();
        });
      }
    },

    // -------------------------------------------------------------
    // Tab 6: 89-Tool MCP Agent Console
    // -------------------------------------------------------------
    async renderMcp() {
      const toolsListEl = $('mcp-tools-list');
      if (!toolsListEl) return;

      const serverInfo = window.fossilMcp.listTools();
      const tools = serverInfo.tools || [];

      let html = '';
      for (const t of tools) {
        const isActive = t.name === state.activeMcpTool;
        html += `
          <div class="mcp-tool-item ${isActive ? 'active' : ''}" data-tool="${t.name}">
            <code>${t.name}</code>
          </div>
        `;
      }
      toolsListEl.innerHTML = html;

      toolsListEl.querySelectorAll('.mcp-tool-item').forEach(item => {
        item.addEventListener('click', () => {
          const toolName = item.getAttribute('data-tool');
          this.selectMcpTool(toolName);
        });
      });

      this.selectMcpTool(state.activeMcpTool);
    },

    selectMcpTool(toolName) {
      state.activeMcpTool = toolName;
      document.querySelectorAll('.mcp-tool-item').forEach(el => {
        el.classList.toggle('active', el.getAttribute('data-tool') === toolName);
      });

      const serverInfo = window.fossilMcp.listTools();
      const tool = serverInfo.tools.find(t => t.name === toolName) || { name: toolName, description: 'Tool' };

      const nameEl = $('mcp-active-tool-name');
      const descEl = $('mcp-active-tool-desc');
      const paramsEl = $('mcp-params-input');

      if (nameEl) nameEl.innerText = tool.name;
      if (descEl) descEl.innerText = tool.description || 'No description';

      // Preset sample parameters
      let sampleParams = {};
      if (tool.parameters) {
        for (const [key, type] of Object.entries(tool.parameters)) {
          if (key === 'path') sampleParams[key] = 'README.md';
          else if (key === 'message') sampleParams[key] = 'Commit message';
          else if (key === 'limit') sampleParams[key] = 10;
          else if (key === 'name') sampleParams[key] = 'Home';
          else if (key === 'backend') sampleParams[key] = 'indexeddb';
          else sampleParams[key] = 'value';
        }
      }
      if (paramsEl) paramsEl.value = JSON.stringify(sampleParams, null, 2);
    },

    bindMcpActions() {
      const runBtn = $('btn-mcp-invoke');
      const outputEl = $('mcp-output-json');
      const copyPromptBtn = $('btn-copy-mcp-prompt');

      if (runBtn && outputEl) {
        runBtn.addEventListener('click', async () => {
          outputEl.innerText = 'Calling tool...';
          const toolName = state.activeMcpTool;
          let params = {};
          try {
            params = JSON.parse($('mcp-params-input').value || '{}');
          } catch (e) {
            outputEl.innerText = 'Invalid JSON in Parameters input: ' + e.message;
            return;
          }

          const t0 = performance.now();
          const res = await window.fossilMcp.callTool(toolName, params);
          const t1 = performance.now();
          const elapsed = (t1 - t0).toFixed(2);

          outputEl.innerText = JSON.stringify({
            _timing: `${elapsed}ms`,
            tool: toolName,
            result: res
          }, null, 2);
        });
      }

      if (copyPromptBtn) {
        copyPromptBtn.addEventListener('click', () => {
          const snippet = `You have access to Fossil-Nim in-browser MCP server with 89 tools exposed via:
await window.fossilMcp.callTool(name, params);

Key tools:
- vcs_status: Get working copy status
- vcs_diff: Compute Myers unified diff via Nim engine
- vcs_file_read / vcs_file_write: Access repository files
- vcs_commit: Commit changes to IndexedDB / SQLite WASM / Pure-Nim CDB
- wiki_get / wiki_create: Access & write repository documentation`;
          navigator.clipboard.writeText(snippet);
          alert('Copied AI Agent System Prompt snippet to clipboard!');
        });
      }
    },

    // -------------------------------------------------------------
    // Tab 7: Storage Diagnostics & SQL Query
    // -------------------------------------------------------------
    async renderStorageDiagnostics() {
      const statsEl = $('storage-stats-container');
      if (!statsEl) return;

      const mgr = window.FossilStorageManager;
      const stats = await window.fossilMcp.callTool('storage_stats');

      statsEl.innerHTML = `
        <div class="grid grid-3" style="margin-bottom:1.5rem;">
          <div class="card">
            <div style="font-size:0.85rem; color:var(--color-text-muted);">Active Backend</div>
            <div style="font-size:1.3rem; font-weight:700; color:var(--color-primary);">${mgr.getActiveBackend().name}</div>
          </div>
          <div class="card">
            <div style="font-size:0.85rem; color:var(--color-text-muted);">MCP Tools Available</div>
            <div style="font-size:1.3rem; font-weight:700; color:#10b981;">89 Tools</div>
          </div>
          <div class="card">
            <div style="font-size:0.85rem; color:var(--color-text-muted);">Engine Runtime</div>
            <div style="font-size:1.3rem; font-weight:700;">Nim 2.0+ (JS/WASM)</div>
          </div>
        </div>
      `;
    },

    bindStorageDiagnostics() {
      const exportBtn = $('btn-export-repo');
      const runSqlBtn = $('btn-run-sql');
      const sqlInput = $('sql-query-input');
      const sqlResult = $('sql-query-output');

      if (exportBtn) {
        exportBtn.addEventListener('click', async () => {
          const mgr = window.FossilStorageManager;
          if (mgr.backendType === 'sqlite_wasm') {
            const bin = mgr.sqliteWasm.exportBinary();
            const blob = new Blob([bin], { type: 'application/x-sqlite3' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = 'repository.fossil';
            a.click();
            URL.revokeObjectURL(url);
          } else if (mgr.backendType === 'cdb') {
            const ser = mgr.cdb.serialize();
            const blob = new Blob([ser], { type: 'text/plain' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = 'repository.cdb';
            a.click();
            URL.revokeObjectURL(url);
          } else {
            // IndexedDB JSON export
            const files = await mgr.indexedDB.getAll('files');
            const events = await mgr.indexedDB.getAll('events');
            const wiki = await mgr.indexedDB.getAll('wiki');
            const tickets = await mgr.indexedDB.getAll('tickets');
            const exportData = { files, events, wiki, tickets, exportedAt: new Date().toISOString() };
            const blob = new Blob([JSON.stringify(exportData, null, 2)], { type: 'application/json' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = 'fossil_backup.json';
            a.click();
            URL.revokeObjectURL(url);
          }
        });
      }

      if (runSqlBtn && sqlInput && sqlResult) {
        runSqlBtn.addEventListener('click', async () => {
          const q = sqlInput.value.trim();
          if (!q) return;
          const res = await window.fossilMcp.callTool('sql_query', { query: q });
          if (res.error) {
            sqlResult.innerHTML = `<div class="error">${escapeHtml(res.error)}</div>`;
          } else {
            const rows = res.rows || [];
            if (rows.length === 0) {
              sqlResult.innerHTML = '<div class="empty">Query executed successfully (0 rows returned).</div>';
              return;
            }
            const keys = Object.keys(rows[0]);
            let table = '<table class="table" style="width:100%; border-collapse:collapse; margin-top:0.5rem;"><thead><tr style="border-bottom:2px solid var(--color-border);">';
            for (const k of keys) table += `<th style="padding:0.5rem; text-align:left;">${escapeHtml(k)}</th>`;
            table += '</tr></thead><tbody>';
            for (const r of rows) {
              table += '<tr style="border-bottom:1px solid var(--color-border);">';
              for (const k of keys) table += `<td style="padding:0.5rem;">${escapeHtml(String(r[k]))}</td>`;
              table += '</tr>';
            }
            table += '</tbody></table>';
            sqlResult.innerHTML = table;
          }
        });
      }
    }
  };

  // Auto-init on DOMContentLoaded
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => window.FossilBrowserUI.init());
  } else {
    window.FossilBrowserUI.init();
  }
})();
