// app.js - Main application, vanilla JS, modular, no frameworks
// Router, theme init, xhttp integration, decoupled from backend

(function() {
  'use strict';

  const app = {
    version: '2.26.0-nim',
    state: {
      currentRoute: '/',
      currentUser: localStorage.getItem('fossil_user') || '',
      isAuthenticated: !!localStorage.getItem('fossil_token'),
      theme: localStorage.getItem('fossil_theme') || 'light',
      repoPath: '',
      branch: 'trunk',
      loading: false
    },

    routes: {
      '/': { component: 'home', title: 'Home' },
      '/timeline': { component: 'timeline', title: 'Timeline' },
      '/file': { component: 'file', title: 'Files' },
      '/finfo': { component: 'file-history', title: 'File History' },
      '/info': { component: 'info', title: 'Check-in Info' },
      '/graph': { component: 'graph', title: 'Graph' },
      '/wiki': { component: 'wiki', title: 'Wiki' },
      '/wiki/list': { component: 'wiki-list', title: 'Wiki Pages' },
      '/wiki/new': { component: 'wiki-edit', title: 'New Wiki' },
      '/wiki/edit': { component: 'wiki-edit', title: 'Edit Wiki' },
      '/ticket': { component: 'ticket-list', title: 'Tickets' },
      '/ticket/list': { component: 'ticket-list', title: 'Tickets' },
      '/ticket/new': { component: 'ticket-edit', title: 'New Ticket' },
      '/forum': { component: 'forum-list', title: 'Forum Threads' },
      '/forum/list': { component: 'forum-list', title: 'Forum Threads' },
      '/forum/new': { component: 'forum-edit', title: 'New Thread' },
      '/chat': { component: 'chat', title: 'Chat' },
      '/chat/rooms': { component: 'chat-rooms', title: 'Chat Rooms' },
      '/search': { component: 'search', title: 'Search' },
      '/login': { component: 'login', title: 'Login' },
      '/setup': { component: 'setup', title: 'Setup' },
      '/diff': { component: 'diff', title: 'Diff' },
      '/blame': { component: 'blame', title: 'Blame' }
    },

    async init() {
      console.log('🦖 Fossil-Nim App initializing - vanilla JS, modular, beautiful');
      this.bindEvents();
      this.initRouter();
      this.loadInitialRoute();
      this.updateAuthUI();
      // Synchronize auth state with server session cookie
      try {
        const res = await fetch('/api/v1/status');
        if (res.ok) {
          const data = await res.json();
          const serverUser = data?.data?.user || '';
          if (serverUser) {
            this.state.currentUser = serverUser;
            this.state.isAuthenticated = true;
            localStorage.setItem('fossil_user', serverUser);
            localStorage.setItem('fossil_token', 'session-active');
          }
          this.updateAuthUI();
        }
      } catch (_) {}
    },

    bindEvents() {
      // Burger menu
      const burger = document.getElementById('burger');
      const menu = document.getElementById('navbar-menu');
      if (burger && menu) {
        burger.addEventListener('click', () => {
          menu.classList.toggle('open');
        });
      }

      // Handle all data-link clicks for SPA
      document.addEventListener('click', (e) => {
        let el = e.target;
        while (el && el !== document) {
          if (el.hasAttribute('data-link')) {
            const href = el.getAttribute('href') || el.getAttribute('data-link');
            if (href && href.startsWith('/') && !href.startsWith('//') && !href.startsWith('/api/')) {
              e.preventDefault();
              this.navigate(href);
              // Close mobile menu
              if (menu) menu.classList.remove('open');
              break;
            }
          }
          el = el.parentElement;
        }
      });

      // Handle theme changes
      document.addEventListener('theme:changed', (e) => {
        this.state.theme = e.detail.theme;
      });
    },

    initRouter() {
      window.addEventListener('popstate', (e) => {
        const path = e.state?.path || location.pathname + location.search;
        this.loadRoute(path, false);
      });
    },

    loadInitialRoute() {
      const path = location.pathname + location.search;
      this.loadRoute(path, false);
    },

    navigate(path) {
      if (path === this.state.currentRoute) return;
      history.pushState({path}, '', path);
      this.loadRoute(path, false);
    },

    async loadRoute(path, pushState = true) {
      const main = document.getElementById('main');
      if (!main) return;

      this.state.currentRoute = path;
      this.state.loading = true;

      // Parse path and query
      const url = new URL(path, window.location.origin);
      const basePath = url.pathname;
      const query = Object.fromEntries(url.searchParams.entries());
      
      if (basePath === '/browser') {
        window.location.href = '/browser.html';
        return;
      }

      let route = this.routes[basePath] || this.routes[basePath.split('?')[0]];
      if (basePath === '/forum' && query.id) {
        route = { component: 'forum', title: 'Forum Thread' };
      } else if (basePath === '/ticket' && query.id) {
        route = { component: 'ticket', title: 'Ticket' };
      } else if (!route) {
        route = { component: 'not-found', title: 'Not Found' };
      }
      
      document.title = `${route.title} - Fossil-Nim`;

      // Update active nav
      document.querySelectorAll('.navbar-menu a').forEach(a => {
        a.classList.remove('active');
        if (a.getAttribute('href') === basePath) a.classList.add('active');
      });

      main.innerHTML = '<div class="loading"><div class="spinner"></div></div>';

      try {
        // Try to create component
        const componentName = route.component;
        let html = '';

        // Use xhttp for API-driven components, or direct component render
        if (window.components[componentName]) {
          const comp = window.createComponent(componentName, {query, path});
          if (comp.fetch) {
            const data = await comp.fetch(query);
            comp.props.data = data;
          }
          html = comp.render();
          main.innerHTML = html;
          comp.element = main;
          // Execute scripts embedded in component templates
          const scripts = main.querySelectorAll('script');
          scripts.forEach(s => {
            try {
              const scr = document.createElement('script');
              scr.textContent = s.textContent;
              document.body.appendChild(scr);
              scr.remove();
            } catch (err) {
              try {
                const runScript = new Function('comp', 'app', 'api', s.textContent);
                runScript(comp, window.app, window.api);
              } catch (e2) {
                console.warn('Script execution hint:', e2);
              }
            }
          });
          if (comp.afterRender) comp.afterRender();
        } else {
          // Fallback: try to fetch HTML from old server endpoints
          // For backward compat with existing REST API that returns HTML
          try {
            const res = await fetch(path, {headers: {'X-Requested-With': 'xhttp'}});
            const text = await res.text();
            if (text.includes('<html')) {
              const parser = new DOMParser();
              const doc = parser.parseFromString(text, 'text/html');
              const mainContent = doc.getElementById('main') || doc.body;
              // SEC FIX: Detect SPA shell returning spinner - avoid infinite spinner loop
              const hasSpinner = mainContent.querySelector && mainContent.querySelector('.spinner');
              const isSpaShell = text.includes('id="navbar"') || text.includes('id="main"') && hasSpinner;
              if (isSpaShell || (mainContent.innerHTML && mainContent.innerHTML.includes('class="spinner"'))) {
                console.warn(`Component ${componentName} not registered, server returned SPA shell with spinner for ${path}`);
                html = this.renderNotFound(path, componentName);
              } else {
                html = mainContent.innerHTML;
              }
            } else {
              html = text;
            }
            main.innerHTML = html;
          } catch (e) {
            // If fetch fails, show component not found with helpful message
            html = this.renderNotFound(path, componentName);
            main.innerHTML = html;
          }
        }

        // Process xhttp attributes in new content
        if (window.xhttp) window.xhttp.process(main);

      } catch (err) {
        console.error('Route load error:', err);
        main.innerHTML = `<div class="error">Failed to load ${path}: ${err.message}</div>`;
      } finally {
        this.state.loading = false;
      }
    },

    renderNotFound(path, component) {
      return `
        <div class="card">
          <h1>404 - Not Found</h1>
          <p>Route <code>${path}</code> (component: ${component}) not found.</p>
          <p>Available routes:</p>
          <ul>
            ${Object.keys(this.routes).map(r => `<li><a href="${r}" data-link>${r}</a> - ${this.routes[r].title}</li>`).join('')}
          </ul>
          <p><a href="/" data-link>← Home</a></p>
        </div>
      `;
    },

    renderHome() {
      return `
        <div class="grid">
          <div class="card">
            <h1>🦖 Fossil-Nim 2.26.0</h1>
            <p>Modern, minimalistic, beautiful SCM - complete rewrite of Fossil in Nim</p>
            <p><span class="badge badge-primary">Storage: SQLite/LMDB/MDBX/CDB</span> <span class="badge badge-success">QBE compatible</span> <span class="badge badge-info">MCP 89 tools</span></p>
          </div>
          
          <div class="grid grid-2">
            <div class="card">
              <div class="card-header"><h3 class="card-title">📊 VCS</h3></div>
              <ul class="list">
                <li class="list-item"><a href="/timeline" data-link>Timeline</a><span>History</span></li>
                <li class="list-item"><a href="/file" data-link>Files</a><span>Browser</span></li>
                <li class="list-item"><a href="/graph" data-link>Graph</a><span>Commits</span></li>
                <li class="list-item"><a href="/diff" data-link>Diff</a><span>Changes</span></li>
              </ul>
            </div>
            
            <div class="card">
              <div class="card-header"><h3 class="card-title">📝 Wiki & Tickets</h3></div>
              <ul class="list">
                <li class="list-item"><a href="/wiki/list" data-link>Wiki Pages</a><a href="/wiki/new" data-link class="btn btn-sm btn-primary">New</a></li>
                <li class="list-item"><a href="/ticket/list" data-link>Tickets</a><a href="/ticket/new" data-link class="btn btn-sm btn-primary">New</a></li>
              </ul>
            </div>
            
            <div class="card">
              <div class="card-header"><h3 class="card-title">💬 Forum & Chat</h3></div>
              <ul class="list">
                <li class="list-item"><a href="/forum/list" data-link>Forum Threads</a><a href="/forum/new" data-link class="btn btn-sm btn-primary">New</a></li>
                <li class="list-item"><a href="/chat?room=main" data-link>Chat Main</a><a href="/chat/rooms" data-link class="btn btn-sm btn-secondary">Rooms</a></li>
              </ul>
            </div>
            
            <div class="card">
              <div class="card-header"><h3 class="card-title">🔍 Search & Setup</h3></div>
              <ul class="list">
                <li class="list-item"><a href="/search" data-link>Search FTS5</a><span>Wiki, tickets, files, commits</span></li>
                <li class="list-item"><a href="/setup" data-link>Setup</a><span>Admin</span></li>
                <li class="list-item"><a href="/login" data-link>Login</a><span>Auth</span></li>
              </ul>
            </div>
          </div>
          
          <div class="card">
            <h3>🎨 Themes - Easy palette editing</h3>
            <p>Click 🎨 to open theme editor. Edit colors, save custom themes, export/import JSON. All themes use CSS variables for easy customization.</p>
            <div class="theme-grid" style="display:grid; grid-template-columns:repeat(auto-fill,minmax(100px,1fr)); gap:0.5rem; margin-top:1rem">
              <div class="theme-preset" onclick="themeSystem.setTheme('light')" style="padding:0.5rem; border:1px solid var(--color-border); border-radius:var(--radius); cursor:pointer; text-align:center"><div style="width:100%; height:30px; background:#f8f9fa; border:1px solid #dee2e6; border-radius:3px"></div><small>Light</small></div>
              <div class="theme-preset" onclick="themeSystem.setTheme('dark')" style="padding:0.5rem; border:1px solid var(--color-border); border-radius:var(--radius); cursor:pointer; text-align:center"><div style="width:100%; height:30px; background:#111827; border-radius:3px"></div><small>Dark</small></div>
              <div class="theme-preset" onclick="themeSystem.setTheme('nord')" style="padding:0.5rem; border:1px solid var(--color-border); border-radius:var(--radius); cursor:pointer; text-align:center"><div style="width:100%; height:30px; background:#2e3440; border-radius:3px"></div><small>Nord</small></div>
              <div class="theme-preset" onclick="themeSystem.setTheme('monokai')" style="padding:0.5rem; border:1px solid var(--color-border); border-radius:var(--radius); cursor:pointer; text-align:center"><div style="width:100%; height:30px; background:#272822; border-radius:3px"></div><small>Monokai</small></div>
            </div>
          </div>
          
          <div class="card">
            <h3>🧩 Modular Architecture - Decoupled from Web</h3>
            <p>UI core in <code>src/fossil/ui/core.nim</code> is platform agnostic. Same logic can be used for:</p>
            <ul>
              <li><b>Web</b> - current vanilla JS implementation (this UI)</li>
              <li><b>TUI</b> - future terminal UI using same core</li>
              <li><b>Desktop</b> - future desktop app (Electron/Tauri) with same core</li>
              <li><b>Mobile</b> - future mobile app</li>
              <li><b>CLI</b> - already works via <code>fossil</code> CLI</li>
            </ul>
            <p>Components are modular: each in <code>web_new/js/components/*.js</code> with <code>render()</code>, <code>init()</code>, <code>fetch()</code>. Easy to add new.</p>
            <p>xhttp.js is minimal htmx-like library (~5KB) for server-driven HTML fragments via <code>data-get</code>, <code>data-post</code>, <code>data-target</code> attributes.</p>
          </div>
        </div>
      `;
    },

    updateAuthUI() {
      // FIX: Update auth state from localStorage and re-render navbar if needed
      const user = localStorage.getItem('fossil_user') || this.state.currentUser || '';
      const token = localStorage.getItem('fossil_token') || (user ? 'session-active' : '');
      this.state.currentUser = user;
      this.state.isAuthenticated = !!(user && token);
      const navbar = document.getElementById('navbar');
      if (navbar && window.components && window.components['navbar']) {
        const comp = window.createComponent('navbar', {});
        navbar.innerHTML = comp.render();
        if (comp.afterRender) comp.afterRender();
      }
    }
  };

  // Register home component
  if (window.registerComponent) {
    registerComponent('home', (props) => {
      const c = new Component('home', props);
      c.render = () => app.renderHome();
      return c;
    });
    registerComponent('not-found', (props) => {
      const c = new Component('not-found', props);
      c.render = () => app.renderNotFound(props.path || '/', 'not-found');
      return c;
    });
  }

  window.app = app;

  console.log('🚀 app.js loaded - modular, vanilla JS, beautiful');
})();
