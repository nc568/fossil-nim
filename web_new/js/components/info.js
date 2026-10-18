// info.js - Check-in info component
registerComponent('info', (props) => {
  const c = new Component('info', props);
  c.fetch = async (query) => {
    const rid = query.rid || query.id || '';
    if (!rid) return {rid: '', error: 'No RID or commit ID specified'};
    try {
      const res = await api.timeline(100);
      const events = res.data?.events || [];
      const match = events.find(e => String(e.rid) === String(rid) || String(e.uuid).startsWith(String(rid)));
      return {rid, event: match, events};
    } catch (e) {
      return {rid, error: e.message};
    }
  };
  c.render = () => {
    const data = c.props.data || {};
    const rid = data.rid || c.props.query?.rid || c.props.query?.id || '';
    const ev = data.event;
    return `
      <div class="card">
        <div class="card-header">
          <h1 class="card-title">🔍 Check-in Info ${rid ? `[${rid}]` : ''}</h1>
          <div class="flex gap-2">
            <a href="/timeline" data-link class="btn btn-secondary btn-sm">Timeline</a>
            <a href="/graph" data-link class="btn btn-secondary btn-sm">Graph</a>
          </div>
        </div>
        <div class="card-body" style="margin-top:1rem">
          ${ev ? `
            <table class="table" style="width:100%; border-collapse:collapse; margin-bottom:1rem">
              <tr><td style="font-weight:600; width:120px; padding:6px">RID:</td><td>${ev.rid}</td></tr>
              <tr><td style="font-weight:600; padding:6px">UUID:</td><td><code>${ev.uuid}</code></td></tr>
              <tr><td style="font-weight:600; padding:6px">Branch:</td><td><span class="badge badge-primary">${ev.branch || 'trunk'}</span></td></tr>
              <tr><td style="font-weight:600; padding:6px">User:</td><td>${ev.user}</td></tr>
              <tr><td style="font-weight:600; padding:6px">Date:</td><td>${new Date((ev.mtime||0)*1000).toLocaleString()}</td></tr>
              <tr><td style="font-weight:600; padding:6px">Comment:</td><td><b>${ev.comment || ''}</b></td></tr>
            </table>
            <div class="flex gap-2" style="margin-top:1rem">
              <a href="/diff?to=${ev.rid}" data-link class="btn btn-primary btn-sm">View Diff</a>
              <a href="/file" data-link class="btn btn-secondary btn-sm">Browse Files</a>
            </div>
          ` : `
            ${data.error ? `<div class="error">${data.error}</div>` : `<div class="empty">Check-in ${rid} not found in recent timeline.<br><a href="/timeline" data-link class="btn btn-sm btn-secondary mt-4">View Timeline</a></div>`}
          `}
        </div>
      </div>
    `;
  };
  return c;
});
console.log('📦 info component loaded');
