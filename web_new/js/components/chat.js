// chat.js - Enhanced Chat with rooms, presence, typing, attachments, edit/delete, reactions

registerComponent('chat', (props) => {
  const c = new Component('chat', props);
  c.fetch = async (query) => {
    const room = query.room || 'main';
    const res = await api.chatList(room, 50);
    const presenceRes = await api.chatPresence(room).catch(()=>({data:{presence:[]}}));
    return {room, messages: res.data.messages||[], presence: presenceRes.data.presence||[]};
  };
  c.render = () => {
    const data = c.props.data || {};
    const room = data.room || 'main';
    const messages = data.messages || [];
    const presence = data.presence || [];
    const typingUsers = presence.filter(p=>p.typing).map(p=>p.user);
    const currentUser = (window.app && window.app.state && window.app.state.currentUser) || localStorage.getItem('fossil_user') || '';
    const authorUser = currentUser || 'web';
    const isAuth = !!(currentUser && currentUser !== 'web');
    return `
      <div class="grid grid-2">
        <div class="card" style="display:flex; flex-direction:column; height:80vh">
          <div class="card-header">
            <h1 class="card-title">💬 #${room} <span class="badge badge-primary">${messages.length}</span></h1>
            <div class="flex gap-2">
              <a href="/chat/rooms" data-link class="btn btn-secondary btn-sm">Rooms</a>
              <button class="btn btn-secondary btn-sm" onclick="document.getElementById('chat-messages').scrollTop=0">↑ Top</button>
              <button class="btn btn-secondary btn-sm" onclick="document.getElementById('chat-messages').scrollTop=document.getElementById('chat-messages').scrollHeight">↓ Bottom</button>
            </div>
          </div>
          <div class="chat-container" style="flex:1; display:flex; flex-direction:column; overflow:hidden">
            <div class="chat-messages" id="chat-messages" style="flex:1; overflow-y:auto; padding:0.5rem; display:flex; flex-direction:column; gap:0.5rem">
              ${messages.slice().reverse().map(m => `
                <div class="chat-message" id="msg-${m.id}" style="display:flex; gap:0.5rem; padding:0.5rem; border-radius:var(--radius); background:var(--color-bg-card); border:1px solid var(--color-border)">
                  <div class="chat-avatar" style="width:2rem; height:2rem; border-radius:50%; background:var(--color-primary); color:white; display:flex; align-items:center; justify-content:center; font-weight:bold; flex-shrink:0">${(m.user||'?')[0].toUpperCase()}</div>
                  <div class="chat-content" style="flex:1">
                    <div class="chat-meta" style="display:flex; justify-content:space-between; font-size:12px; color:var(--color-text-muted)">
                      <span><b style="color:var(--color-text)">${m.user||''}</b> at ${new Date((m.mtime||0)*1000).toLocaleTimeString()} ${m.edited?'<span class="badge badge-info">edited</span>':''}</span>
                      <span class="flex gap-2">
                        <button class="btn btn-sm btn-secondary" style="font-size:10px; padding:2px 4px" onclick="window.editMessage && window.editMessage('${m.id}', \`${(m.content||'').replace(/`/g,'\\`')}\`)">✏️</button>
                        <button class="btn btn-sm btn-danger" style="font-size:10px; padding:2px 4px" onclick="if(confirm('Delete?')) api.chatDelete('${m.id}').then(()=>location.reload())">🗑️</button>
                      </span>
                    </div>
                    <div id="msg-content-${m.id}" style="margin-top:4px; word-break:break-word">${(m.content||'').replace(/</g,'&lt;')}</div>
                    <div id="msg-preview-${m.id}" style="margin-top:4px"></div>
                    ${m.attachment?`
                      <div class="mt-4" style="margin-top:0.5rem">
                        <small>📎 <a href="${m.attachment}" target="_blank">${m.attachment}</a></small>
                        ${m.attachment.match(/\.(jpg|jpeg|png|gif|webp|svg)$/i)?`<br><img src="${m.attachment}" style="max-width:200px; max-height:200px; border-radius:8px; margin-top:4px; border:1px solid var(--color-border)" onerror="this.style.display='none'">`:''}
                        ${m.attachment.match(/\.(mp4|webm|ogg)$/i)?`<br><video src="${m.attachment}" controls style="max-width:250px; border-radius:8px; margin-top:4px"></video>`:''}
                      </div>
                    `:''}
                    <div class="flex gap-2 mt-4" style="margin-top:4px">
                      <button class="btn btn-sm" style="font-size:12px" onclick="window.react && window.react('${m.id}', '👍')">👍</button>
                      <button class="btn btn-sm" style="font-size:12px" onclick="window.react && window.react('${m.id}', '❤️')">❤️</button>
                      <button class="btn btn-sm" style="font-size:12px" onclick="window.react && window.react('${m.id}', '😂')">😂</button>
                      <button class="btn btn-sm btn-secondary" style="font-size:10px" onclick="document.getElementById('reply-to').value='${m.user}: '; document.getElementById('chat-content').focus()">Reply</button>
                    </div>
                    <div id="reactions-${m.id}" class="flex gap-2 mt-4" style="font-size:12px"></div>
                    <div id="edit-${m.id}" style="display:none; margin-top:0.5rem">
                      <textarea id="edit-content-${m.id}" class="form-input" style="width:100%; min-height:60px">${(m.content||'').replace(/</g,'&lt;')}</textarea>
                      <div class="flex gap-2 mt-4">
                        <button class="btn btn-sm btn-primary" onclick="window.saveEdit && window.saveEdit('${m.id}')">Save</button>
                        <button class="btn btn-sm btn-secondary" onclick="document.getElementById('edit-${m.id}').style.display='none'">Cancel</button>
                      </div>
                    </div>
                  </div>
                </div>
              `).join('')}
              ${messages.length===0?'<div class="empty">No messages yet<br><small>Be first to chat!</small></div>':''}
            </div>
            <div id="typing-indicator" class="text-sm text-muted" style="padding:0.5rem; min-height:1.5rem; font-style:italic">
              ${typingUsers.length?typingUsers.join(', ')+' typing...':''}
            </div>
            ${!isAuth ? '<div style="padding:0.5rem; background:#fff3cd; border:1px solid #ffeaa7; border-radius:4px; font-size:12px; margin:0.5rem">🔒 Вы вошли как гость <b>web</b>. <a href="/login" data-link>Войдите</a> чтобы иметь имя и права. Чат открыт для анонимов.</div>' : `<div style="padding:0.5rem; background:var(--color-bg-secondary); border:1px solid var(--color-border); border-radius:4px; font-size:12px; margin:0.5rem">👤 Вы вошли как <b>${authorUser}</b>. Сообщения публикуются от вашего имени.</div>`}
            <div class="chat-input" style="display:flex; gap:0.5rem; padding:0.5rem; border-top:1px solid var(--color-border); flex-wrap:wrap">
              <input id="reply-to" style="display:none">
              <input id="chat-content" class="form-input" placeholder="Message... (markdown supported, **bold**, *italic*, \`code\`, [link](url))" style="flex:1; min-width:200px" oninput="window.chatTyping && window.chatTyping(this.value)" onkeypress="if(event.key==='Enter' && !event.shiftKey){event.preventDefault(); window.sendChat && window.sendChat();}">
              <input id="chat-user" class="form-input" placeholder="user" style="width:100px" value="${authorUser}">
              <input id="chat-attachment" class="form-input" placeholder="Attachment URL (image/file)" style="width:180px">
              <button class="btn btn-primary" onclick="window.sendChat && window.sendChat()">Send</button>
            </div>
          </div>
          <div id="chat-result" style="padding:0.5rem"></div>
        </div>
        <div style="display:flex; flex-direction:column; gap:1rem">
          <div class="card">
            <div class="card-header"><h3 class="card-title">👥 Presence in #${room}</h3><span class="badge badge-success">${presence.length} online</span></div>
            <div class="list" style="max-height:200px; overflow-y:auto">
              ${presence.map(p => `
                <div class="list-item">
                  <div><b>${p.user}</b> <span class="badge ${p.status==='online'?'badge-success':'badge-secondary'}">${p.status||'online'}</span> ${p.typing?'<span class="badge badge-warning">typing...</span>':''}<br><small class="text-muted">last ${new Date((p.lastSeen||0)*1000).toLocaleTimeString()}</small></div>
                  <div class="chat-avatar" style="width:1.5rem; height:1.5rem; border-radius:50%; background:var(--color-success); color:white; display:flex; align-items:center; justify-content:center; font-size:10px">${(p.user||'?')[0].toUpperCase()}</div>
                </div>
              `).join('')}
            </div>
            ${presence.length===0?'<div class="empty">No one online<br><small>Last 5 min</small></div>':''}
            <div class="form-group mt-4">
              <label class="form-label">Update your presence</label>
              <div class="flex gap-2">
                <input id="presence-user" class="form-input" placeholder="your name" style="width:120px" value="${authorUser}">
                <select id="presence-status" class="form-select" style="width:120px">
                  <option value="online">online</option>
                  <option value="away">away</option>
                  <option value="busy">busy</option>
                </select>
                <button class="btn btn-sm btn-secondary" onclick="const u=document.getElementById('presence-user').value||'${authorUser}'; const s=document.getElementById('presence-status').value; api.chatPresenceUpdate('${room}', u, false).then(()=>location.reload())">Update</button>
              </div>
            </div>
          </div>
          
          <div class="card">
            <h3>💡 Chat Features - Enhanced</h3>
            <ul class="text-sm" style="line-height:1.8">
              <li>✅ Rooms: multiple, private, create/delete</li>
              <li>✅ Presence: online, last seen (5 min), status</li>
              <li>✅ Typing: indicator when user typing</li>
              <li>✅ Attachments: image preview, video, file URL</li>
              <li>✅ Edit/Delete: edit own messages, delete</li>
              <li>✅ Reactions: emoji reactions (👍❤️😂)</li>
              <li>✅ Markdown: **bold**, *italic*, \`code\`, [link]</li>
              <li>✅ Auto-scroll, reply, FTS5 search index</li>
            </ul>
            <div class="mt-4">
              <h4>Quick Actions</h4>
              <div class="flex gap-2" style="flex-wrap:wrap">
                <button class="btn btn-sm btn-secondary" onclick="api.chatList('${room}', 100).then(r=>console.log(r)).catch(e=>alert(e))">📋 Log JSON</button>
                <button class="btn btn-sm btn-secondary" onclick="if(confirm('Clear typing?')) presence.forEach(p=>api.chatPresenceUpdate('${room}', p.user, false))">🧹 Clear typing</button>
              </div>
            </div>
          </div>

          <div class="card">
            <h3>🔍 Search Chat</h3>
            <div class="search-box">
              <span class="search-icon">🔍</span>
              <input class="form-input search-input" placeholder="Search messages..." oninput="window.searchChat && window.searchChat(this.value)">
            </div>
            <div id="chat-search-results" class="mt-4"></div>
          </div>
        </div>
    `;
  };

  c.afterRender = () => {
    const data = c.props.data || {};
    const query = c.props.query || {};
    const room = query.room || data.room || 'main';
    const messages = data.messages || [];

    // Load markdown previews
    setTimeout(() => {
      messages.forEach(m => {
        const text = (m.content || '').substring(0, 500);
        api.markdown(text).then(r => {
          const el = document.getElementById('msg-preview-' + m.id);
          if (el && r.data && r.data.html) el.innerHTML = r.data.html;
        }).catch(() => {});
      });
      const el = document.getElementById('chat-messages');
      if (el) el.scrollTop = el.scrollHeight;
    }, 200);

    window.sendChat = () => {
      const content = document.getElementById('chat-content')?.value || '';
      const user = document.getElementById('chat-user')?.value || (window.app && window.app.state && window.app.state.currentUser) || localStorage.getItem('fossil_user') || 'web';
      const attachment = document.getElementById('chat-attachment')?.value || '';
      if (!content && !attachment) return;
      api.chatSend(room, content, user, attachment).then(r => {
        const resEl = document.getElementById('chat-result');
        if (resEl) resEl.innerHTML = '<div class="success">Sent!</div>';
        const cEl = document.getElementById('chat-content');
        if (cEl) cEl.value = '';
        const aEl = document.getElementById('chat-attachment');
        if (aEl) aEl.value = '';
        setTimeout(() => {
          if (window.app && window.app.loadRoute) window.app.loadRoute('/chat?room=' + encodeURIComponent(room), false);
          else location.reload();
        }, 500);
      }).catch(e => {
        const resEl = document.getElementById('chat-result');
        if (resEl) resEl.innerHTML = '<div class="error">Error: ' + e.message + '</div>';
      });
    };

    window.editMessage = (msgId, content) => {
      const el = document.getElementById('edit-' + msgId);
      if (el) el.style.display = 'block';
    };

    window.saveEdit = async (msgId) => {
      const el = document.getElementById('edit-content-' + msgId);
      if (!el) return;
      const content = el.value;
      try {
        await api.chatEdit(msgId, content);
        const resEl = document.getElementById('chat-result');
        if (resEl) resEl.innerHTML = '<div class="success">Edited!</div>';
        setTimeout(() => {
          if (window.app && window.app.loadRoute) window.app.loadRoute('/chat?room=' + encodeURIComponent(room), false);
          else location.reload();
        }, 500);
      } catch (e) {
        const resEl = document.getElementById('chat-result');
        if (resEl) resEl.innerHTML = '<div class="error">Error: ' + e.message + '</div>';
      }
    };

    window.react = (msgId, emoji) => {
      const el = document.getElementById('reactions-' + msgId);
      if (el) {
        const existing = el.innerHTML;
        el.innerHTML = existing + ' <span style="background:var(--color-bg-secondary); padding:2px 6px; border-radius:12px; border:1px solid var(--color-border)">' + emoji + '</span>';
      }
    };

    window.chatTyping = (val) => {
      clearTimeout(window._typingT);
      const user = document.getElementById('chat-user')?.value || 'web';
      if (val) api.chatPresenceUpdate(room, user, true).catch(() => {});
      window._typingT = setTimeout(() => { api.chatPresenceUpdate(room, user, false).catch(() => {}); }, 2000);
      const ind = document.getElementById('typing-indicator');
      if (val && ind) ind.textContent = user + ' typing...';
      else if (ind) ind.textContent = '';
    };

    window.searchChat = async (q) => {
      clearTimeout(window._chatSearchT);
      window._chatSearchT = setTimeout(async () => {
        const resultsEl = document.getElementById('chat-search-results');
        if (!resultsEl) return;
        if (q.length < 2) { resultsEl.innerHTML = ''; return; }
        try {
          const r = await api.search(q, 10, 'chat');
          const results = r.data.results || [];
          resultsEl.innerHTML = results.map(res => '<div class="search-result"><b>' + res.title + '</b><br><small>' + res.snippet + '</small></div>').join('') || '<div class="empty">No results</div>';
        } catch (e) {
          resultsEl.innerHTML = '<div class="error">' + e.message + '</div>';
        }
      }, 300);
    };

    // Poll presence every 3s while component is mounted
    const interval = setInterval(async () => {
      if (!document.getElementById('typing-indicator')) {
        clearInterval(interval);
        return;
      }
      try {
        const pres = await api.chatPresence(room);
        const typing = pres.data.presence.filter(p => p.typing).map(p => p.user);
        const ind = document.getElementById('typing-indicator');
        if (ind) ind.textContent = typing.length ? typing.join(', ') + ' typing...' : '';
      } catch (e) {}
    }, 3000);
  };
  return c;
});

registerComponent('chat-rooms', (props) => {
  const c = new Component('chat-rooms', props);
  c.fetch = async () => {
    const res = await api.chatRooms();
    return res.data;
  };
  c.render = () => {
    const data = c.props.data || {};
    const rooms = data.rooms || [];
    return `
      <div class="card">
        <div class="card-header"><h1 class="card-title">🏠 Chat Rooms</h1><a href="/chat?room=main" data-link class="btn btn-secondary btn-sm">Main</a></div>
        <div class="list">
          ${rooms.map(r => `
            <div class="list-item">
              <div>
                <a href="/chat?room=${encodeURIComponent(r.room)}" data-link><b>#${r.room}</b></a> owner: ${r.owner} ${r.private?'<span class="badge badge-warning">private</span>':''}<br>
                <small class="text-muted">created ${new Date((r.created||0)*1000).toLocaleDateString()}</small>
              </div>
              <div class="flex gap-2">
                <a href="/chat?room=${encodeURIComponent(r.room)}" data-link class="btn btn-sm btn-primary">Join</a>
                <a href="/chat/presence?room=${encodeURIComponent(r.room)}" data-link class="btn btn-sm btn-secondary">presence</a>
                ${r.room!=='main'?`<button class="btn btn-sm btn-danger" onclick="if(confirm('Delete room ${r.room}?')) api.chatDeleteRoom('${r.room}').then(()=>location.reload())">Delete</button>`:''}
              </div>
            </div>
          `).join('')}
        </div>
        ${rooms.length===0?'<div class="empty">No rooms, main always exists</div>':''}
        <hr>
        <h3>Create Room</h3>
        <form id="room-form" style="display:flex; gap:0.5rem; flex-wrap:wrap">
          <input name="room" class="form-input" placeholder="Room name (e.g. dev, random)" required style="flex:1; min-width:150px">
          <input name="owner" class="form-input" placeholder="owner" style="width:120px">
          <label style="display:flex; align-items:center; gap:0.25rem"><input type="checkbox" name="private"> 🔒 Private</label>
          <button type="submit" class="btn btn-primary">Create Room</button>
        </form>
        <div id="room-result" class="mt-4"></div>
        <hr>
        <h3>Room Features</h3>
        <ul class="text-sm">
          <li>Public rooms visible to all</li>
          <li>Private rooms only for invited (owner check TODO)</li>
          <li>Main room cannot be deleted</li>
          <li>Presence per room, typing per room</li>
        </ul>
      </div>
    `;
  };

  c.afterRender = () => {
    const form = document.getElementById('room-form');
    if (form) {
      form.addEventListener('submit', async (e) => {
        e.preventDefault();
        const data = {room: form.room.value.trim(), owner: form.owner.value || 'web', privateRoom: form.private.checked};
        const resEl = document.getElementById('room-result');
        try {
          const r = await api.chatCreateRoom(data.room, data.owner, data.privateRoom);
          if (resEl) resEl.innerHTML = '<div class="success">Created room ' + data.room + '!</div>';
          setTimeout(() => {
            if (window.app && window.app.navigate) window.app.navigate('/chat/rooms');
            else location.reload();
          }, 500);
        } catch (err) {
          if (resEl) resEl.innerHTML = '<div class="error">Error: ' + err.message + '</div>';
        }
      });
    }
  };

  return c;
});
console.log('📦 chat component enhanced loaded - edit/delete, attachments with preview, reactions, rooms CRUD, presence, typing');
