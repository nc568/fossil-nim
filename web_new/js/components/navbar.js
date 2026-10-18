// navbar.js - Navbar component, vanilla JS, modular - FIXED for login display bug
// BUG: User logged in but top-right still shows Login button, should show user and Logout

registerComponent('navbar', (props) => {
  const c = new Component('navbar', props);
  
  c.render = () => {
    // FIX: Check auth state from app state or localStorage
    const user = (window.app && window.app.state && window.app.state.currentUser) || localStorage.getItem('fossil_user') || '';
    const token = localStorage.getItem('fossil_token') || (user ? 'session-active' : '');
    const isAuth = !!(user && token);
    return `
      <div class="navbar-brand">
        <a href="/" data-link>🦖 Fossil-Nim</a>
        <span class="badge">2.26.0-nim</span>
      </div>
      <div class="navbar-menu" id="navbar-menu">
        <a href="/timeline" data-link>Timeline</a>
        <a href="/file" data-link>Files</a>
        <a href="/graph" data-link>Graph</a>
        <a href="/wiki" data-link>Wiki</a>
        <a href="/ticket" data-link>Tickets</a>
        <a href="/forum" data-link>Forum</a>
        <a href="/chat" data-link>Chat</a>
        <a href="/search" data-link>Search</a>
      </div>
      <div class="navbar-actions">
        <button id="theme-toggle" class="btn btn-icon" title="Toggle theme">🌙</button>
        <button id="theme-editor-btn" class="btn btn-icon" title="Theme editor">🎨</button>
        ${isAuth ? `
          <span class="badge badge-success" title="Logged in as ${user}">👤 ${user}</span>
          <a href="/logout" id="logout-btn" class="btn btn-secondary" onclick="localStorage.removeItem('fossil_user'); localStorage.removeItem('fossil_token'); window.location.href='/logout'; return false;">Logout</a>
        ` : `
          <a href="/login" data-link id="login-btn" class="btn btn-primary">Login</a>
        `}
        <a href="/setup" data-link class="btn btn-secondary">Setup</a>
      </div>
    `;
  };
  
  c.afterRender = () => {
    // Update auth UI after render
    const user = localStorage.getItem('fossil_user') || '';
    const token = localStorage.getItem('fossil_token') || '';
    if (window.app) {
      window.app.state.currentUser = user;
      window.app.state.isAuthenticated = !!(user && token);
    }
  };
  
  return c;
});

console.log('📦 navbar component loaded - fixed login display');
