// diff.js - Diff component
registerComponent('diff', (props) => {
  const c = new Component('diff', props);
  c.fetch = async (query) => {
    const from = query.from || query.f || '';
    const to = query.to || query.t || '';
    if (!from && !to) return null;
    try {
      const res = await api.diff(from, to);
      return res.data;
    } catch { return null; }
  };
  c.render = () => {
    const query = c.props.query || {};
    const from = query.from || '';
    const to = query.to || '';
    const data = c.props.data;
    const diffText = data ? (data.diff || data.content || JSON.stringify(data, null, 2)) : '';
    return `
      <div class="card">
        <div class="card-header">
          <h1 class="card-title">📝 Diff ${from ? 'from ' + from : ''} ${to ? 'to ' + to : ''}</h1>
          <a href="/timeline" data-link class="btn btn-secondary btn-sm">Timeline</a>
        </div>
        <form style="display:flex; gap:0.5rem; margin-bottom:1rem" onsubmit="event.preventDefault(); app.navigate('/diff?from='+this.from.value+'&to='+this.to.value)">
          <input name="from" class="form-input" placeholder="From RID" value="${from}" style="width:100px">
          <input name="to" class="form-input" placeholder="To RID" value="${to}" style="width:100px">
          <button type="submit" class="btn btn-primary btn-sm">Diff</button>
        </form>
        <div id="diff-content" style="margin-top:1rem">
          ${diffText ? `<pre style="max-height:600px; overflow-y:auto"><code>${diffText.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')}</code></pre>` : '<div class="empty">Enter From/To RID or select check-in from timeline</div>'}
        </div>
      </div>
    `;
  };
  return c;
});

registerComponent('blame', (props) => {
  const c = new Component('blame', props);
  c.fetch = async (query) => {
    const name = query.name || '';
    if (!name) return {html: '<div class="empty">No file specified</div>'};
    try {
      const res = await fetch('/blame?name=' + encodeURIComponent(name));
      const html = await res.text();
      const parser = new DOMParser();
      const doc = parser.parseFromString(html, 'text/html');
      const content = doc.getElementById('main') || doc.body;
      return {name, html: content ? content.innerHTML : html};
    } catch (e) {
      return {name, html: '<div class="error">Error loading blame: ' + e.message + '</div>'};
    }
  };
  c.render = () => {
    const data = c.props.data || {};
    const name = data.name || c.props.query?.name || '';
    return `
      <div class="card">
        <div class="card-header">
          <h1 class="card-title">👤 Blame: ${name}</h1>
          <a href="/file?name=${encodeURIComponent(name)}" data-link class="btn btn-secondary btn-sm">← Back to File</a>
        </div>
        <div class="card-body" style="margin-top:1rem">
          ${data.html || '<div class="empty">No blame data available</div>'}
        </div>
      </div>
    `;
  };
  return c;
});
console.log('📦 diff & blame components loaded');
