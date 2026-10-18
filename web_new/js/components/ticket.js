// ticket.js - Ticket component
registerComponent('ticket', (props) => {
  const c = new Component('ticket', props);
  c.fetch = async (query) => {
    const id = query.id || '';
    if (!id) {
      // FIX: When no id, show list instead of trying to fetch ticket 0 which doesn't exist
      try {
        const res = await api.ticketList(20);
        return {isList: true, tickets: res.data.tickets||[], data: res.data};
      } catch {
        return {isList: true, tickets: [], data: {}};
      }
    }
    const res = await api.ticketGet(id);
    return res.data;
  };
  c.render = () => {
    const data = c.props.data || {};
    // FIX: If isList, render ticket list
    if (data.isList) {
      const tickets = data.tickets || [];
      return `
      <div class="card">
        <div class="card-header"><h1 class="card-title">🎫 Tickets</h1><a href="/ticket/new" data-link class="btn btn-primary btn-sm">New Ticket</a></div>
        <div class="list">
          ${tickets.map(t => `<div class="list-item"><div><a href="/ticket?id=${t.id}" data-link><b>${t.id}</b> [${t.status||'open'}] ${t.title||''}</a><br><small class="text-muted">${t.owner||''} priority ${t.priority||''}</small></div><span class="badge badge-${(t.status==='open'?'success':'secondary')}">${t.status||''}</span></div>`).join('')}
        </div>
        ${tickets.length===0?'<div class="empty">No tickets<br><a href="/ticket/new" data-link class="btn btn-primary btn-sm mt-4">New Ticket</a></div>':''}
      </div>
    `;
    }
    const html = data.html || '<p>Ticket not found</p>';
    return `<div class="card"><div class="card-header"><h1 class="card-title">🎫 Ticket</h1><a href="/ticket/list" data-link class="btn btn-secondary btn-sm">List</a></div><div>${html}</div></div>`;
  };
  return c;
});

registerComponent('ticket-list', (props) => {
  const c = new Component('ticket-list', props);
  c.fetch = async (query) => {
    const res = await api.ticketList(query.limit||20);
    return res.data;
  };
  c.render = () => {
    const data = c.props.data || {};
    const tickets = data.tickets || [];
    return `
      <div class="card">
        <div class="card-header"><h1 class="card-title">🎫 Tickets</h1><a href="/ticket/new" data-link class="btn btn-primary btn-sm">New Ticket</a></div>
        <div class="list">
          ${tickets.map(t => `<div class="list-item"><div><a href="/ticket?id=${t.id}" data-link><b>${t.id}</b> [${t.status||'open'}] ${t.title||''}</a><br><small class="text-muted">${t.owner||''} priority ${t.priority||''}</small></div><span class="badge badge-${(t.status==='open'?'success':'secondary')}">${t.status||''}</span></div>`).join('')}
        </div>
        ${tickets.length===0?'<div class="empty">No tickets</div>':''}
      </div>
    `;
  };
  return c;
});

registerComponent('ticket-edit', (props) => {
  const c = new Component('ticket-edit', props);
  c.render = () => {
    return `
      <div class="card">
        <div class="card-header">
          <h1 class="card-title">➕ New Ticket</h1>
          <a href="/ticket/list" data-link class="btn btn-secondary btn-sm">← Back to Tickets</a>
        </div>
        <form id="ticket-form" style="margin-top:1rem">
          <div class="form-group"><label class="form-label">Title</label><input name="title" class="form-input" required placeholder="Brief ticket summary..."></div>
          <div class="form-group"><label class="form-label">Description (markdown)</label><textarea name="description" class="form-textarea" required placeholder="Detailed description..." style="min-height:150px"></textarea></div>
          <div class="flex gap-2" style="flex-wrap:wrap">
            <div class="form-group" style="flex:1; min-width:140px"><label class="form-label">Type</label><select name="type" class="form-select"><option value="bug">bug</option><option value="feature">feature</option><option value="task">task</option></select></div>
            <div class="form-group" style="flex:1; min-width:140px"><label class="form-label">Priority</label><input name="priority" type="number" min="1" max="3" value="2" class="form-input"></div>
          </div>
          <button type="submit" class="btn btn-primary" style="margin-top:0.5rem">Create Ticket</button>
          <div id="ticket-result" style="margin-top:1rem"></div>
        </form>
      </div>
    `;
  };
  c.afterRender = () => {
    const form = document.getElementById('ticket-form');
    if (form) {
      form.addEventListener('submit', async (e) => {
        e.preventDefault();
        const data = {
          title: form.title.value.trim(),
          description: form.description.value,
          type: form.type.value,
          priority: parseInt(form.priority.value) || 2
        };
        const resultEl = document.getElementById('ticket-result');
        if (resultEl) resultEl.innerHTML = '<div style="color:var(--color-text-muted)">Creating ticket...</div>';
        try {
          const r = await api.ticketCreate(data.title, data.description, data.type, data.priority);
          if (resultEl) resultEl.innerHTML = '<div class="success">Ticket created successfully!</div>';
          setTimeout(() => {
            if (window.app && window.app.navigate) window.app.navigate('/ticket/list');
            else window.location.href = '/ticket/list';
          }, 800);
        } catch (err) {
          if (resultEl) resultEl.innerHTML = '<div class="error">Error: ' + err.message + '</div>';
        }
      });
    }
  };
  return c;
});
console.log('📦 ticket component loaded');
