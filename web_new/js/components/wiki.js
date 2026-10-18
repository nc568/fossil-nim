// wiki.js - Wiki component
registerComponent('wiki', (props) => {
  const c = new Component('wiki', props);
  c.fetch = async (query) => {
    const name = query.name || query.page || 'Home';
    const res = await api.wikiGet(name);
    return res.data;
  };
  c.render = () => {
    const data = c.props.data || {};
    const query = c.props.query || {};
    const name = query.name || 'Home';
    const html = data.html || '<p>Wiki page not found</p>';
    const content = data.content || '';
    return `
      <div class="card">
        <div class="card-header">
          <h1 class="card-title">📖 ${name}</h1>
          <div class="flex gap-2">
            <a href="/wiki/list" data-link class="btn btn-secondary btn-sm">List</a>
            <a href="/wiki/edit?name=${encodeURIComponent(name)}" data-link class="btn btn-primary btn-sm">Edit</a>
            <a href="/wiki/new" data-link class="btn btn-secondary btn-sm">New</a>
          </div>
        </div>
        <div class="card-body">
          <div class="wiki-content">${html}</div>
          <details style="margin-top:1rem"><summary>Raw markdown</summary><pre><code>${(content||'').replace(/</g,'&lt;')}</code></pre></details>
        </div>
      </div>
    `;
  };
  return c;
});

registerComponent('wiki-list', (props) => {
  const c = new Component('wiki-list', props);
  c.fetch = async () => {
    const res = await api.wikiList();
    return res.data;
  };
  c.render = () => {
    const data = c.props.data || {};
    const pages = data.pages || [];
    return `
      <div class="card">
        <div class="card-header"><h1 class="card-title">📚 Wiki Pages</h1><a href="/wiki/new" data-link class="btn btn-primary btn-sm">New Page</a></div>
        <div class="list">
          ${pages.map(p => `<div class="list-item"><a href="/wiki?name=${encodeURIComponent(p)}" data-link>📄 ${p}</a><a href="/wiki/edit?name=${encodeURIComponent(p)}" data-link class="btn btn-sm btn-secondary">edit</a></div>`).join('')}
        </div>
        ${pages.length===0?'<div class="empty">No wiki pages</div>':''}
      </div>
    `;
  };
  return c;
});

registerComponent('wiki-edit', (props) => {
  const c = new Component('wiki-edit', props);
  c.fetch = async (query) => {
    const name = query.name || '';
    if (!name) return {name: '', content: ''};
    try {
      const res = await api.wikiGet(name);
      return res.data;
    } catch { return {name, content: ''}; }
  };
  c.render = () => {
    const data = c.props.data || {};
    const query = c.props.query || {};
    const name = query.name || data.name || '';
    const content = data.content || '';
    const isNew = !query.name;
    return `
      <div class="card">
        <div class="card-header">
          <h1 class="card-title">${isNew ? '➕ New Wiki Page' : '✏️ Edit Wiki: ' + name}</h1>
          <a href="/wiki/list" data-link class="btn btn-secondary btn-sm">← Back to Wiki</a>
        </div>
        <div class="editor-toolbar" style="margin-top:1rem">
          <button type="button" onclick="window.insertMd && window.insertMd('**','**','bold')">B</button>
          <button type="button" onclick="window.insertMd && window.insertMd('*','*','italic')">I</button>
          <button type="button" onclick="window.insertMd && window.insertMd('\`','\`','code')">Code</button>
          <button type="button" onclick="window.insertMd && window.insertMd('[','](url)','link')">Link</button>
          <button type="button" onclick="window.insertMd && window.insertMd('\\n- ','','list')">List</button>
          <button type="button" onclick="window.insertMd && window.insertMd('\\n\`\`\`\\n','\\n\`\`\`\\n','code block')">CB</button>
        </div>
        <div class="editor" style="margin-top:0.5rem">
          <div class="editor-pane">
            <input id="wiki-name" class="form-input" placeholder="Page name" value="${name}" ${!isNew?'readonly':''} required>
            <textarea id="wiki-content" class="form-textarea editor-textarea" placeholder="# Markdown content" oninput="window.updateWikiPreview && window.updateWikiPreview()">${content.replace(/</g,'&lt;')}</textarea>
            <input id="wiki-message" class="form-input" placeholder="Commit message" value="${isNew?'create via web':'update via web'}">
            <button type="button" class="btn btn-primary" onclick="window.saveWiki && window.saveWiki()">Save Page</button>
            <div id="wiki-result" style="margin-top:1rem"></div>
          </div>
          <div class="editor-pane">
            <div id="wiki-preview" class="editor-preview">Preview will appear here</div>
          </div>
        </div>
      </div>
    `;
  };
  c.afterRender = () => {
    window.insertMd = (b, a, p) => {
      const ta = document.getElementById('wiki-content');
      if (!ta) return;
      const s = ta.selectionStart, e = ta.selectionEnd, sel = ta.value.substring(s, e) || p;
      ta.value = ta.value.substring(0, s) + b + sel + a + ta.value.substring(e);
      ta.focus();
      ta.setSelectionRange(s + b.length, s + b.length + sel.length);
      window.updateWikiPreview && window.updateWikiPreview();
    };
    window.updateWikiPreview = async () => {
      const ta = document.getElementById('wiki-content');
      const prev = document.getElementById('wiki-preview');
      if (!ta || !prev) return;
      const t = ta.value;
      if (!t) { prev.innerHTML = '<i>empty</i>'; return; }
      try {
        const r = await api.markdown(t);
        prev.innerHTML = r.data.html || r.data;
      } catch (e) { prev.innerText = 'error: ' + e; }
    };
    window.saveWiki = async () => {
      const nameEl = document.getElementById('wiki-name');
      const contentEl = document.getElementById('wiki-content');
      const msgEl = document.getElementById('wiki-message');
      const resEl = document.getElementById('wiki-result');
      if (!nameEl || !contentEl) return;
      const name = nameEl.value.trim();
      const content = contentEl.value;
      const message = msgEl ? msgEl.value : 'web edit';
      if (!name) { if (resEl) resEl.innerHTML = '<div class="error">Page name is required</div>'; return; }
      if (resEl) resEl.innerHTML = '<div style="color:var(--color-text-muted)">Saving page...</div>';
      try {
        const r = await api.wikiSave(name, content, message);
        if (resEl) resEl.innerHTML = '<div class="success">Saved! Redirecting...</div>';
        setTimeout(() => {
          if (window.app && window.app.navigate) window.app.navigate('/wiki?name=' + encodeURIComponent(name));
          else window.location.href = '/wiki?name=' + encodeURIComponent(name);
        }, 800);
      } catch (e) {
        if (resEl) resEl.innerHTML = '<div class="error">Error: ' + e.message + '</div>';
      }
    };
    window.updateWikiPreview();
  };
  return c;
});
console.log('📦 wiki component loaded');
