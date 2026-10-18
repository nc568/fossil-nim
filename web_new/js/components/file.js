// file.js - File browser component, vanilla JS

registerComponent('file', (props) => {
  const c = new Component('file', props);
  
  c.fetch = async (query) => {
    const name = query.name || '';
    const pattern = query.pattern || '';
    if (name) {
      try {
        const res = await api.fileGet(name);
        return res.data;
      } catch {
        // Fallback to tree if fileGet fails
        const treeRes = await api.get('/api/v1/tree', {path: '/', pattern});
        return treeRes.data;
      }
    } else {
      // FIX: Use /api/v1/tree for file list, more reliable than /api/v1/file with empty path
      try {
        const res = await api.get('/api/v1/tree', {path: '/', pattern});
        return res.data;
      } catch {
        const res = await api.fileList(pattern, 100);
        return res.data;
      }
    }
  };

  c.render = () => {
    const data = c.props.data;
    const query = c.props.query || {};
    const name = query.name || '';
    
    if (name && data && data.content !== undefined) {
      // Single file view
      const isBinary = data.content && data.content.includes('\0');
      const esc = (s) => (s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
      return `
        <div class="card">
          <div class="card-header">
            <h1 class="card-title">📄 ${name}</h1>
            <div class="flex gap-2">
              <a href="/file" data-link class="btn btn-secondary btn-sm">← Files</a>
              <a href="/finfo?name=${encodeURIComponent(name)}" data-link class="btn btn-secondary btn-sm">History</a>
              <a href="/blame?name=${encodeURIComponent(name)}" data-link class="btn btn-secondary btn-sm">Blame</a>
            </div>
          </div>
          <div class="card-body">
            ${isBinary ? 
              `<div class="empty">Binary file, ${data.content.length} bytes</div>` :
              `<pre><code>${esc(data.content)}</code></pre>`
            }
          </div>
        </div>
      `;
    } else {
      // File list
      const files = (data && (data.files || data)) || [];
      let fileArray = Array.isArray(files) ? files : (files.files || []);
      const pattern = (query.pattern || '').trim();
      if (pattern) {
        fileArray = fileArray.filter(f => (typeof f === 'string' ? f : f.name || '').toLowerCase().includes(pattern.toLowerCase()));
      }
      
      return `
        <div class="card">
          <div class="card-header">
            <h1 class="card-title">📁 File Browser</h1>
            <span class="badge badge-primary">${fileArray.length} files</span>
          </div>
          
          <div class="form-group">
            <div class="search-box">
              <span class="search-icon">🔍</span>
              <input id="file-search" class="form-input search-input" placeholder="Search files..." value="${pattern}" oninput="window.fileSearch && window.fileSearch(this.value)">
            </div>
          </div>
          
          <div class="list" id="file-list">
            ${fileArray.map(f => {
              const fname = typeof f === 'string' ? f : f.name || f;
              return `<div class="list-item">
                <a href="/file?name=${encodeURIComponent(fname)}" data-link>📄 ${fname}</a>
                <div class="flex gap-2">
                  <a href="/finfo?name=${encodeURIComponent(fname)}" data-link class="btn btn-sm btn-secondary">history</a>
                  <a href="/blame?name=${encodeURIComponent(fname)}" data-link class="btn btn-sm btn-secondary">blame</a>
                </div>
              </div>`;
            }).join('')}
          </div>
          
          ${fileArray.length===0 ? '<div class="empty">No files found</div>' : ''}
        </div>
      `;
    }
  };

  c.afterRender = () => {
    window.fileSearch = (q) => {
      clearTimeout(window._fileSearchTimeout);
      window._fileSearchTimeout = setTimeout(() => {
        if (window.app && window.app.navigate) {
          window.app.navigate('/file?pattern=' + encodeURIComponent(q));
        } else {
          window.location.href = '/file?pattern=' + encodeURIComponent(q);
        }
      }, 300);
    };
  };

  return c;
});

registerComponent('file-history', (props) => {
  const c = new Component('file-history', props);
  
  c.fetch = async (query) => {
    const name = query.name || '';
    if (!name) return {name: '', events: []};
    try {
      const res = await api.timeline(50, '', name);
      return {name, events: res.data?.events || []};
    } catch {
      return {name, events: []};
    }
  };

  c.render = () => {
    const data = c.props.data || {};
    const name = data.name || '';
    const events = data.events || [];
    return `
      <div class="card">
        <div class="card-header">
          <h1 class="card-title">📜 History of ${name}</h1>
          <div class="flex gap-2">
            <a href="/file?name=${encodeURIComponent(name)}" data-link class="btn btn-secondary btn-sm">View file</a>
            <a href="/file" data-link class="btn btn-secondary btn-sm">File list</a>
          </div>
        </div>
        <div class="list" style="margin-top:1rem">
          ${events.map(e => `
            <div class="list-item">
              <div>
                <b>${e.comment || 'commit'}</b><br>
                <small class="text-muted">${e.user || ''} at ${new Date((e.mtime||0)*1000).toLocaleString()} (${e.branch || 'trunk'})</small>
              </div>
              <a href="/info?id=${e.rid || e.uuid}" data-link class="btn btn-sm btn-secondary">info</a>
            </div>
          `).join('')}
        </div>
        ${events.length === 0 ? '<div class="empty">No history entries found for this file</div>' : ''}
      </div>
    `;
  };

  return c;
});

console.log('📦 file component loaded');
