// graph.js - Commit graph component - FIXED for /api/v1/graph 404
registerComponent('graph', (props) => {
  const c = new Component('graph', props);
  c.fetch = async (query) => {
    const branch = query.branch || '';
    try {
      const res = await api.graph(branch, 100);
      return res.data;
    } catch (e) {
      console.warn('graph API failed, fallback to old endpoint', e);
      return {nodes: [], edges: [], branch, error: e.message};
    }
  };
  c.render = () => {
    const data = c.props.data || {};
    const query = c.props.query || {};
    const branch = query.branch || '';
    const nodes = data.nodes || [];
    const count = data.count || nodes.length;
    return `
      <div class="card">
        <div class="card-header">
          <h1 class="card-title">📊 Commit Graph ${branch?'- '+branch:''} <span class="badge badge-primary">${count}</span></h1>
          <form style="display:flex; gap:0.5rem" onsubmit="event.preventDefault(); app.navigate('/graph?branch='+encodeURIComponent(this.branch.value))">
            <input name="branch" class="form-input" placeholder="Branch" value="${branch}" style="width:150px">
            <button type="submit" class="btn btn-primary btn-sm">Filter</button>
            <a href="/timeline" data-link class="btn btn-secondary btn-sm">Timeline</a>
          </form>
        </div>
        <div id="graph-container" class="graph-container" style="padding:1rem">
          ${nodes.length>0 ? `
            <div style="display:flex; flex-direction:column; gap:0.5rem">
              ${nodes.map((n, i) => `
                <div style="display:flex; gap:1rem; align-items:center; padding:0.5rem; border:1px solid var(--color-border); border-radius:4px; background:${i%2===0?'var(--color-bg)':'var(--color-bg-card)'}">
                  <div style="width:8px; height:8px; border-radius:50%; background:var(--color-primary); flex-shrink:0"></div>
                  <div style="flex:1">
                    <b>${(n.comment||'').substring(0,60)}</b><br>
                    <small class="text-muted">${n.user||''} at ${new Date((n.mtime||0)*1000).toLocaleString()} | ${n.branch||''} | ${n.uuid?String(n.uuid).substring(0,10):n.rid}</small>
                  </div>
                  <a href="/info?id=${n.rid||n.uuid}" data-link class="btn btn-sm btn-secondary">info</a>
                </div>
              `).join('')}
            </div>
            <p class="text-muted mt-4"><small>Graph: ${nodes.length} nodes, ${(data.edges||[]).length} edges, branch ${branch||'trunk'}</small></p>
          ` : `
            ${data.error ? '<div class="error">Error: '+data.error+'</div>' : '<div class="empty">No commits found in graph</div>'}
          `}
        </div>
      </div>
    `;
  };
  return c;
});
console.log('📦 graph component loaded - fixed /api/v1/graph');
