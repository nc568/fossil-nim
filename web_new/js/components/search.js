// search.js - Enhanced Search with live preview, auto-index, files/commits/branches

registerComponent('search', (props) => {
  const c = new Component('search', props);
  c.results = [];
  c.query = '';

  c.fetch = async (query) => {
    const q = query.q || query.query || '';
    if (!q) return {results: [], query: ''};
    const kind = query.kind || '';
    const res = await api.search(q, 20, kind);
    return res.data;
  };

  c.render = () => {
    const data = c.props.data || {};
    const query = c.props.query || {};
    const q = query.q || query.query || data.query || '';
    const results = data.results || c.results || [];
    const count = data.count || results.length;

    return `
      <div class="card">
        <div class="card-header">
          <h1 class="card-title">🔍 Search (FTS5) - Enhanced</h1>
          <span class="badge badge-primary">${count} results</span>
        </div>
        
        <div class="form-group">
          <div class="search-box">
            <span class="search-icon">🔍</span>
            <input id="search-input" class="form-input search-input" placeholder="Search wiki, tickets, files, commits, forum, chat, branches..." value="${q}" oninput="window.liveSearch && window.liveSearch(this.value)">
          </div>
          <div class="flex gap-2 mt-4" style="flex-wrap:wrap">
            <select id="kind-filter" class="form-select" style="width:150px" onchange="window.liveSearch && window.liveSearch(document.getElementById('search-input').value)">
              <option value="">All kinds</option>
              <option value="wiki" ${query.kind==='wiki'?'selected':''}>Wiki</option>
              <option value="ticket" ${query.kind==='ticket'?'selected':''}>Tickets</option>
              <option value="file" ${query.kind==='file'?'selected':''}>Files</option>
              <option value="commit" ${query.kind==='commit'?'selected':''}>Commits</option>
              <option value="forum" ${query.kind==='forum'?'selected':''}>Forum</option>
              <option value="chat" ${query.kind==='chat'?'selected':''}>Chat</option>
              <option value="branch" ${query.kind==='branch'?'selected':''}>Branches</option>
            </select>
            <button class="btn btn-secondary btn-sm" onclick="window.doReindex && window.doReindex()">🔄 Reindex All (files, commits, branches, wiki, tickets, forum, chat)</button>
            <button class="btn btn-secondary btn-sm" onclick="api.searchReindex().then(()=>alert('Reindexed search only')).catch(e=>alert('Error: '+e.message))">Reindex Search Only</button>
          </div>
          <div id="reindex-result" class="mt-4"></div>
        </div>
        
        <div id="search-results" class="search-results">
          ${results.map(r => `
            <div class="search-result">
              <div class="flex justify-between">
                <span class="badge badge-info">${r.kind||''}</span>
                <small class="text-muted">${r.mtime ? new Date(r.mtime*1000).toLocaleDateString() : ''}</small>
              </div>
              <div style="margin:0.5rem 0">
                <a href="${c.getLink(r)}" data-link><b>${r.title||r.id||''}</b></a>
              </div>
              <div class="text-sm text-muted">${r.snippet||''}</div>
              <small class="text-muted"><code>${r.id||''}</code> rank: ${(r.rank||0).toFixed(2)}</small>
            </div>
          `).join('')}
        </div>
        
        ${q && results.length===0 ? '<div class="empty">No results for "'+q+'"<br><small>Try different kind or reindex</small></div>' : ''}
        ${!q ? `
          <div class="empty">
            Enter query to search<br>
            <small>Supports FTS5 with auto-index:</small>
            <ul style="text-align:left; max-width:400px; margin:1rem auto; font-size:12px">
              <li>✅ Wiki - auto-index on save</li>
              <li>✅ Tickets - auto-index on create</li>
              <li>✅ Forum - auto-index on thread/post create</li>
              <li>✅ Chat - auto-index on message send</li>
              <li>✅ Files - reindex all indexes file contents (first 50k chars, skip binary)</li>
              <li>✅ Commits - reindex all indexes commit messages, branch, user</li>
              <li>✅ Branches - reindex all indexes branch names</li>
            </ul>
            <small>Live search with debounce 300ms, snippet with &lt;b&gt; highlight, rank sorting</small>
          </div>
        ` : ''}
      </div>

      <div class="grid grid-2 mt-4">
        <div class="card">
          <h3>📊 Index Stats</h3>
          <div id="index-stats"><div class="loading"><div class="spinner"></div></div></div>
          <button class="btn btn-sm btn-secondary mt-4" onclick="window.loadStats && window.loadStats()">Refresh Stats</button>
        </div>
        <div class="card">
          <h3>💡 Search Tips</h3>
          <ul class="text-sm" style="line-height:1.8">
            <li><code>bug</code> - simple term</li>
            <li><code>"exact phrase"</code> - phrase search</li>
            <li><code>bug AND feature</code> - boolean</li>
            <li><code>title:bug</code> - field search (if FTS5 supports)</li>
            <li>Filter by kind using dropdown</li>
            <li>Auto-index: wiki/ticket/forum/chat indexed on save</li>
            <li>Files/commits/branches need Reindex All</li>
            <li>Uses porter tokenizer, unicode61, snippet &lt;b&gt;</li>
          </ul>
        </div>
      </div>
    `;
  };

  c.getLink = (r) => {
    const kind = r.kind || '';
    const id = r.id || '';
    if (kind === 'wiki') return '/wiki?name=' + encodeURIComponent(id.replace(/^wiki-/, ''));
    if (kind === 'ticket') return '/ticket?id=' + encodeURIComponent(id);
    if (kind === 'file') return '/file?name=' + encodeURIComponent(id.replace(/^file-/, ''));
    if (kind === 'commit') return '/info?rid=' + encodeURIComponent(id.replace(/^commit-/, '').substring(0,10));
    if (kind === 'forum') return '/forum?id=' + encodeURIComponent(id);
    if (kind === 'chat') return '/chat?room=' + encodeURIComponent(id.split('_')[0]||'main');
    if (kind === 'branch') return '/timeline?branch=' + encodeURIComponent(id.replace(/^branch-/, ''));
    return '#';
  };

  c.afterRender = () => {
    window.liveSearch = (query) => {
      clearTimeout(window._searchTimeout);
      window._searchTimeout = setTimeout(async () => {
        if (query.length < 2 && query.length !== 0) return;
        const kind = document.getElementById('kind-filter')?.value || '';
        const resultsEl = document.getElementById('search-results');
        if (!resultsEl) return;
        if (!query) {
          resultsEl.innerHTML = '<div class="empty">Enter query to search<br><small>Supports FTS5: wiki, tickets, files, commits, forum, branches, chat</small></div>';
          return;
        }
        resultsEl.innerHTML = '<div class="loading"><div class="spinner"></div></div>';
        try {
          const res = await api.search(query, 20, kind);
          const results = res.data.results || [];
          resultsEl.innerHTML = results.map(r => `
            <div class="search-result">
              <div class="flex justify-between"><span class="badge badge-info">${r.kind}</span><small>${r.mtime ? new Date(r.mtime*1000).toLocaleDateString() : ''}</small></div>
              <div style="margin:0.5rem 0"><a href="${c.getLink(r)}" data-link><b>${r.title||r.id}</b></a></div>
              <div class="text-sm text-muted">${r.snippet||''}</div>
              <small class="text-muted"><code>${r.id}</code> rank: ${(r.rank||0).toFixed(2)}</small>
            </div>
          `).join('') || '<div class="empty">No results for "' + query + '"</div>';
          if (window.xhttp) window.xhttp.process(resultsEl);
        } catch (e) {
          resultsEl.innerHTML = '<div class="error">Error: ' + e.message + '</div>';
        }
      }, 300);
    };

    window.doReindex = async () => {
      const resultEl = document.getElementById('reindex-result');
      if (!resultEl) return;
      resultEl.innerHTML = '<div class="loading"><div class="spinner"></div> Reindexing files, commits, branches...</div>';
      try {
        const res = await api.searchReindex();
        resultEl.innerHTML = '<div class="success">Reindexed! ' + JSON.stringify(res.data) + '</div>';
        setTimeout(() => window.loadStats && window.loadStats(), 500);
      } catch (e) {
        resultEl.innerHTML = '<div class="error">Error: ' + e.message + '</div>';
      }
    };

    window.loadStats = async () => {
      const statsEl = document.getElementById('index-stats');
      if (!statsEl) return;
      try {
        statsEl.innerHTML = '<div>Index contains mixed kinds: wiki, ticket, file, commit, forum, chat, branch<br><small>Use search to see counts</small></div>';
      } catch (e) {
        statsEl.innerHTML = '<div class="error">' + e.message + '</div>';
      }
    };

    window.searchComponent = {
      getLink: (r) => c.getLink(r)
    };
    setTimeout(() => window.loadStats && window.loadStats(), 300);
  };

  return c;
});

console.log('📦 search component enhanced loaded - auto-index, files/commits/branches, live preview');
