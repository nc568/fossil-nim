// forum.js - Enhanced Forum component with WYSIWYG, moderation, pinning, attachments, search

registerComponent('forum', (props) => {
  const c = new Component('forum', props);
  c.fetch = async (query) => {
    const id = query.id || query.threadId || '';
    if (!id) return null;
    const res = await api.forumGet(id);
    return res.data;
  };
  c.render = () => {
    const data = c.props.data;
    if (!data) return `<div class="card"><h1>Forum</h1><p>Use <a href="/forum/list" data-link>Forum List</a></p></div>`;
    const canModerate = true; // TODO: check auth
    return `
      <div class="card">
        <div class="card-header">
          <h1 class="card-title">${data.title||''} ${data.pinned?'<span class="badge badge-warning">📌 pinned</span>':''} ${data.locked?'<span class="badge badge-danger">🔒 locked</span>':''} ${data.deleted?'<span class="badge badge-danger">deleted</span>':''}</h1>
          <div class="flex gap-2" style="flex-wrap:wrap">
            <a href="/forum/list" data-link class="btn btn-secondary btn-sm">List</a>
            <button class="btn btn-sm ${data.pinned?'btn-warning':'btn-secondary'}" onclick="api.forumPin('${data.id}', ${!data.pinned}).then(()=>location.reload())">${data.pinned?'📌 Unpin':'📌 Pin'}</button>
            <button class="btn btn-sm ${data.locked?'btn-danger':'btn-secondary'}" onclick="api.forumLock('${data.id}', ${!data.locked}).then(()=>location.reload())">${data.locked?'🔓 Unlock':'🔒 Lock'}</button>
            <button class="btn btn-sm btn-danger" onclick="if(confirm('Delete thread?')) api.forumDelete('${data.id}').then(()=>app.navigate('/forum/list'))">🗑️ Delete</button>
          </div>
        </div>
        <p class="text-muted">by ${data.user||''} at ${new Date((data.created||0)*1000).toLocaleString()} | last: ${new Date((data.lastMtime||0)*1000).toLocaleString()}</p>
        <div class="list" id="forum-posts">
          ${(data.posts||[]).map((p, idx) => `
            <div class="card" style="margin:0.5rem 0" id="post-${p.id}">
              <div class="flex justify-between">
                <div><b>${p.user||''}</b> ${p.edited?'<span class="badge badge-info">edited</span>':''} ${p.deleted?'<span class="badge badge-danger">deleted</span>':''}</div>
                <small class="text-muted">${new Date((p.mtime||0)*1000).toLocaleString()}</small>
              </div>
              <div class="mt-4" id="post-content-${p.id}">${(p.content||'').replace(/</g,'&lt;').substring(0,1000)}</div>
              <div id="post-preview-${p.id}" class="mt-4" style="border:1px solid var(--color-border); padding:0.5rem; border-radius:var(--radius); display:none"></div>
              ${p.attachment ? `
    <div class="mt-4"><small>📎 Attachment: <a href="${p.attachment}" target="_blank">${p.attachment}</a>
    ${p.attachment.match(/\.(jpg|jpeg|png|gif|webp)$/i) ? `<br><img src="${p.attachment}" style="max-width:200px; max-height:200px; border-radius:4px; margin-top:4px">` : ''}
    </small></div>
  ` : ''}
              <div class="flex gap-2 mt-4">
                <button class="btn btn-sm btn-secondary" onclick="window.editPost && window.editPost('${p.id}')">✏️ Edit</button>
                <button class="btn btn-sm btn-secondary" onclick="window.replyTo && window.replyTo('${p.id}', '${p.user}')">💬 Reply</button>
                <input id="attach-${p.id}" class="form-input" placeholder="Attachment URL" style="width:200px; font-size:12px">
                <button class="btn btn-sm btn-secondary" onclick="const url=document.getElementById('attach-${p.id}').value; if(url) api.forumPost('${data.id}', 'Attachment: '+url, 'web', '${p.id}').then(()=>location.reload())">📎 Attach</button>
              </div>
              <div id="edit-${p.id}" style="display:none; margin-top:0.5rem">
                <textarea id="edit-content-${p.id}" class="form-textarea" style="min-height:100px">${(p.content||'').replace(/</g,'&lt;')}</textarea>
                <div id="edit-preview-${p.id}" class="editor-preview" style="min-height:50px; border:1px solid var(--color-border); padding:0.5rem; margin:0.5rem 0"></div>
                <div class="flex gap-2">
                  <button class="btn btn-sm btn-primary" onclick="window.saveEdit && window.saveEdit('${p.id}')">Save</button>
                  <button class="btn btn-sm btn-secondary" onclick="document.getElementById('edit-${p.id}').style.display='none'">Cancel</button>
                </div>
              </div>
            </div>
          `).join('')}
        </div>
        <hr>
        <h3>💬 Reply ${data.locked?'<span class="badge badge-danger">Thread locked</span>':''}</h3>
        ${data.locked?'<div class="empty">Thread is locked, cannot reply</div>':`
        <form id="reply-form">
          <div class="form-group">
            <label class="form-label">Content (Markdown, WYSIWYG)</label>
            <textarea id="reply-content" name="content" class="form-textarea" placeholder="Reply content with **markdown** support..." required style="min-height:150px"></textarea>
            <div id="reply-preview" class="editor-preview" style="min-height:80px; border:1px solid var(--color-border); padding:0.5rem; margin-top:0.5rem; border-radius:var(--radius)"></div>
          </div>
          <div class="flex gap-2" style="flex-wrap:wrap">
            <input name="user" class="form-input" placeholder="user" style="width:150px" value="${(window.app && window.app.state && window.app.state.currentUser) || localStorage.getItem('fossil_user') || 'web'}">
            <input id="reply-attachment" class="form-input" placeholder="Attachment URL (image, file)" style="width:250px">
            <button type="submit" class="btn btn-primary">Post Reply</button>
          </div>
        </form>
        `}
        <div id="forum-result" class="mt-4"></div>
      </div>
    `;
  };
  c.afterRender = () => {
    const data = c.props.data;
    if (!data) return;
    if (window.MarkdownEditor) {
      try { new MarkdownEditor('reply-content', 'reply-preview'); } catch(e){}
    }
    // Load markdown previews
    (data.posts || []).forEach(p => {
      api.markdown((p.content || '').substring(0, 500)).then(r => {
        const el = document.getElementById('post-content-' + p.id);
        if (el) el.innerHTML = r.data.html || r.data;
      }).catch(() => {});
    });
    window.editPost = (postId) => {
      const el = document.getElementById('edit-' + postId);
      if (el) el.style.display = 'block';
      if (window.MarkdownEditor) {
        try { new MarkdownEditor('edit-content-' + postId, 'edit-preview-' + postId); } catch(e){}
      }
    };
    window.saveEdit = async (postId) => {
      const editInput = document.getElementById('edit-content-' + postId);
      if (!editInput) return;
      const content = editInput.value;
      const resEl = document.getElementById('forum-result');
      try {
        await api.forumEditPost(postId, content);
        if (resEl) resEl.innerHTML = '<div class="success">Edited!</div>';
        setTimeout(() => location.reload(), 500);
      } catch (err) {
        if (resEl) resEl.innerHTML = '<div class="error">Error: ' + err.message + '</div>';
      }
    };
    window.replyTo = (postId, user) => {
      const ta = document.getElementById('reply-content');
      if (ta) {
        ta.value = '@' + user + ' (reply to ' + postId + ')\n\n' + ta.value;
        ta.focus();
      }
    };
    const replyForm = document.getElementById('reply-form');
    if (replyForm) {
      replyForm.addEventListener('submit', async (e) => {
        e.preventDefault();
        const content = replyForm.content.value;
        const user = replyForm.user.value || (window.app && window.app.state && window.app.state.currentUser) || localStorage.getItem('fossil_user') || 'web';
        const attachEl = document.getElementById('reply-attachment');
        const attachment = attachEl ? attachEl.value : '';
        const fullContent = attachment ? content + '\n\n📎 Attachment: ' + attachment : content;
        const resEl = document.getElementById('forum-result');
        try {
          await api.forumPost(data.id, fullContent, user);
          if (resEl) resEl.innerHTML = '<div class="success">Posted!</div>';
          setTimeout(() => location.reload(), 500);
        } catch (err) {
          if (resEl) resEl.innerHTML = '<div class="error">Error: ' + err.message + '</div>';
        }
      });
    }
  };
  return c;
});

registerComponent('forum-list', (props) => {
  const c = new Component('forum-list', props);
  c.fetch = async () => {
    const res = await api.forumList(50);
    const pinnedRes = await api.forumPinned(20).catch(()=>({data:{threads:[]}}));
    return {threads: res.data.threads||[], pinned: pinnedRes.data.threads||[]};
  };
  c.render = () => {
    const data = c.props.data || {};
    const threads = data.threads || [];
    const pinned = data.pinned || threads.filter(t=>t.pinned);
    const normal = threads.filter(t=>!t.pinned);
    return `
      <div class="card">
        <div class="card-header">
          <h1 class="card-title">💬 Forum Threads</h1>
          <div class="flex gap-2">
            <a href="/forum/new" data-link class="btn btn-primary btn-sm">New Thread</a>
            <a href="/api/v1/forum/list" target="_blank" class="btn btn-secondary btn-sm">JSON</a>
          </div>
        </div>
        <div class="form-group">
          <div class="search-box">
            <span class="search-icon">🔍</span>
            <input class="form-input search-input" placeholder="Search forum threads and posts..." oninput="window.forumSearch&&window.forumSearch(this.value)">
          </div>
          <div id="forum-search-results" class="mt-4"></div>
        </div>
        ${pinned.length>0?'<h3>📌 Pinned Threads</h3><div class="list">'+pinned.map(t=>`
          <div class="list-item">
            <div><a href="/forum?id=${t.id}" data-link><b>${t.title}</b></a> by ${t.user} <span class="badge badge-warning">📌 pinned</span><br><small class="text-muted">last ${new Date((t.lastMtime||0)*1000).toLocaleDateString()}</small></div>
            <div class="flex gap-2"><span class="badge badge-primary">${(t.posts||[]).length||1} posts</span><button class="btn btn-sm btn-secondary" onclick="api.forumPin('${t.id}', false).then(()=>location.reload())">Unpin</button></div>
          </div>
        `).join('')+'</div>':''}
        <h3>All Threads</h3>
        <div class="list">
          ${normal.map(t => `
            <div class="list-item">
              <div>
                <a href="/forum?id=${t.id}" data-link><b>${t.title||''}</b></a> ${t.pinned?'<span class="badge badge-warning">📌</span>':''} ${t.locked?'<span class="badge badge-danger">🔒</span>':''}<br>
                <small class="text-muted">by ${t.user||''} last ${new Date((t.lastMtime||0)*1000).toLocaleDateString()} ${t.deleted?'<span class="badge badge-danger">deleted</span>':''}</small>
              </div>
              <div class="flex gap-2">
                <span class="badge badge-primary">${(t.posts||[]).length||1} posts</span>
                <button class="btn btn-sm btn-secondary" onclick="api.forumPin('${t.id}', true).then(()=>location.reload())" title="Pin">📌</button>
                <button class="btn btn-sm btn-secondary" onclick="api.forumLock('${t.id}', ${!t.locked}).then(()=>location.reload())" title="${t.locked?'Unlock':'Lock'}">${t.locked?'🔓':'🔒'}</button>
              </div>
            </div>
          `).join('')}
        </div>
        ${threads.length===0?'<div class="empty">No threads<br><small>Be first to create!</small><br><a href="/forum/new" data-link class="btn btn-primary btn-sm mt-4">New Thread</a></div>':''}
      </div>
    `;
  };

  c.afterRender = () => {
    window.forumSearch = async (q) => {
      clearTimeout(window._forumSearchT);
      window._forumSearchT = setTimeout(async () => {
        const resultsEl = document.getElementById('forum-search-results');
        if (!resultsEl) return;
        if (q.length < 2) { resultsEl.innerHTML = ''; return; }
        resultsEl.innerHTML = '<div class="loading"><div class="spinner"></div></div>';
        try {
          const r = await api.forumSearch(q, 10);
          const posts = r.data.posts || [];
          resultsEl.innerHTML = posts.length ? posts.map(p => '<div class="search-result"><a href="/forum?id=' + p.threadId + '" data-link><b>' + (p.title || p.threadId) + '</b></a> by ' + p.user + '<br><small>' + (p.content || '').substring(0, 150).replace(/</g, '&lt;') + '</small></div>').join('') : '<div class="empty">No results for "' + q + '"</div>';
        } catch (e) { resultsEl.innerHTML = '<div class="error">' + e.message + '</div>'; }
      }, 300);
    };
  };

  return c;
});

registerComponent('forum-edit', (props) => {
  const c = new Component('forum-edit', props);
  c.render = () => {
    const currentUser = (window.app && window.app.state && window.app.state.currentUser) || localStorage.getItem('fossil_user') || 'web';
    return `
      <div class="card">
        <div class="card-header">
          <h1 class="card-title">➕ New Forum Thread</h1>
          <a href="/forum/list" data-link class="btn btn-secondary btn-sm">← Back to Threads</a>
        </div>
        <form id="forum-form" style="margin-top:1rem">
          <div class="form-group"><label class="form-label">Title</label><input name="title" class="form-input" required placeholder="Thread title..."></div>
          <div class="form-group">
            <label class="form-label">Content (Markdown with WYSIWYG)</label>
            <textarea id="forum-content" name="content" class="form-textarea" required placeholder="Write with **markdown** support...\n\n- Use toolbar above\n- Live preview below" style="min-height:200px"></textarea>
            <div id="forum-preview" class="editor-preview" style="min-height:100px; border:1px solid var(--color-border); padding:1rem; margin-top:0.5rem; border-radius:var(--radius); background:var(--color-bg-card)"></div>
          </div>
          <div class="flex gap-2" style="flex-wrap:wrap">
            <div class="form-group" style="flex:1; min-width:150px"><label class="form-label">User</label><input name="user" class="form-input" placeholder="your name" value="${currentUser}"></div>
            <div class="form-group" style="flex:1; min-width:200px"><label class="form-label">Attachment URL (optional)</label><input id="forum-attachment" name="attachment" class="form-input" placeholder="https://... image or file URL"></div>
          </div>
          <div class="form-group"><label class="form-label"><input type="checkbox" name="pinned"> 📌 Pin this thread (moderator)</label></div>
          <button type="submit" class="btn btn-primary">Create Thread</button>
          <div id="forum-result" class="mt-4"></div>
        </form>
      </div>
    `;
  };
  c.afterRender = () => {
    if (window.MarkdownEditor) {
      try { new MarkdownEditor('forum-content', 'forum-preview'); } catch(e){}
    }
    const form = document.getElementById('forum-form');
    if (form) {
      form.addEventListener('submit', async (e) => {
        e.preventDefault();
        let content = form.content.value;
        const attachment = document.getElementById('forum-attachment') ? document.getElementById('forum-attachment').value : '';
        if (attachment) content += '\n\n📎 Attachment: ' + attachment;
        const user = form.user.value || (window.app && window.app.state && window.app.state.currentUser) || localStorage.getItem('fossil_user') || 'web';
        const title = form.title.value;
        const isPinned = form.pinned ? form.pinned.checked : false;
        const resEl = document.getElementById('forum-result');
        if (resEl) resEl.innerHTML = '<div style="color:var(--color-text-muted)">Creating thread...</div>';
        try {
          const r = await api.forumCreate(title, content, user);
          if (resEl) resEl.innerHTML = '<div class="success">Thread created successfully!</div>';
          if (isPinned && r.data && r.data.id) await api.forumPin(r.data.id, true);
          setTimeout(() => {
            if (window.app && window.app.navigate) window.app.navigate('/forum/list');
            else window.location.href = '/forum/list';
          }, 800);
        } catch (err) {
          if (resEl) resEl.innerHTML = '<div class="error">Error: ' + err.message + '</div>';
        }
      });
    }
  };
  return c;
});
console.log('📦 forum component enhanced loaded - WYSIWYG, moderation, attachments, search');
