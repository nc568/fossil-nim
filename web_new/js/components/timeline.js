// timeline.js - Timeline component, vanilla JS, xhttp style

registerComponent('timeline', (props) => {
  const c = new Component('timeline', props);
  c.data = null;

  c.fetch = async (query) => {
    const limit = query.limit || 20;
    const branch = query.branch || '';
    const res = await api.timeline(limit, branch);
    return res.data;
  };

  c.render = () => {
    const data = c.props.data || c.data;
    if (!data || !data.timeline) {
      return `
        <div class="card">
          <h1>📅 Timeline</h1>
          <div class="loading"><div class="spinner"></div></div>
        </div>
      `;
    }

    const entries = data.timeline || [];
    const limit = data.limit || 20;
    const query = c.props.query || {};
    const currentBranch = query.branch || '';

    return `
      <div class="card">
        <div class="card-header">
          <h1 class="card-title">📅 Timeline</h1>
          <div class="flex gap-2">
            <a href="/graph" data-link class="btn btn-secondary btn-sm">Graph</a>
            <a href="/api/v1/timeline?limit=${limit}" class="btn btn-secondary btn-sm" target="_blank">JSON</a>
          </div>
        </div>
        
        <div class="form-group">
          <form id="timeline-filter-form" style="display:flex; gap:0.5rem">
            <input name="limit" type="number" value="${limit}" min="1" max="100" class="form-input" style="width:80px" placeholder="Limit">
            <input name="branch" value="${currentBranch}" placeholder="Branch (e.g. trunk)" class="form-input" style="flex:1">
            <button type="submit" class="btn btn-primary">Filter</button>
          </form>
        </div>
        
        <div id="timeline-list" class="timeline">
          ${entries.map(e => `
            <div class="timeline-item">
              <div class="timeline-meta">
                <span><code>${(e.uuid||'').substring(0,10)}</code></span>
                <span>by ${e.user||''}</span>
                <span class="badge badge-primary">${e.branch||'trunk'}</span>
                <span>${new Date((e.mtime||0)*1000).toLocaleString()}</span>
              </div>
              <div class="timeline-comment">
                <a href="/info?rid=${e.rid||''}" data-link>${(e.comment||'').substring(0,200)}</a>
              </div>
              <div class="flex gap-2 mt-4">
                <a href="/info?rid=${e.rid}" data-link class="btn btn-sm btn-secondary">Info</a>
                <a href="/file?rid=${e.rid}" data-link class="btn btn-sm btn-secondary">Files</a>
                <a href="/diff?from=${e.rid}" data-link class="btn btn-sm btn-secondary">Diff</a>
              </div>
            </div>
          `).join('')}
        </div>
        
        ${entries.length===0 ? '<div class="empty">No timeline entries</div>' : ''}
        
        <div class="card-footer">
          <button class="btn btn-secondary" onclick="app.navigate('/timeline?limit=${limit+20}${currentBranch ? '&branch=' + encodeURIComponent(currentBranch) : ''}')">Load more</button>
        </div>
      </div>
    `;
  };

  c.afterRender = () => {
    const form = document.getElementById('timeline-filter-form');
    if (form) {
      form.addEventListener('submit', (e) => {
        e.preventDefault();
        const limitVal = form.limit.value || 20;
        const branchVal = form.branch.value.trim();
        let url = '/timeline?limit=' + encodeURIComponent(limitVal);
        if (branchVal) url += '&branch=' + encodeURIComponent(branchVal);
        if (window.app && window.app.navigate) {
          window.app.navigate(url);
        } else {
          window.location.href = url;
        }
      });
    }
  };

  return c;
});

console.log('📦 timeline component loaded');
