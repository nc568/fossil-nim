// xhttp.js - Minimal htmx-like library, vanilla JS, no frameworks
// Inspired by htmx but written in Nim-style, <5KB, modular
// Handles data-get, data-post, data-target, data-swap via fetch (xhttp)

(function() {
  'use strict';

  const xhttp = {
    version: '1.0.0-nim',
    
    // Config
    config: {
      history: true,
      selfRequestsOnly: false,
      timeout: 10000
    },

    // Init - bind events
    init() {
      document.addEventListener('click', this.handleClick.bind(this));
      document.addEventListener('submit', this.handleSubmit.bind(this));
      document.addEventListener('DOMContentLoaded', () => {
        this.process(document);
      });
      // Handle popstate for SPA navigation
      window.addEventListener('popstate', (e) => {
        if (window.app) return; // app.js handles SPA popstate routing
        if (e.state && e.state.path) {
          this.load(e.state.path, document.getElementById('main') || document.body, 'innerHTML', false);
        }
      });
      console.log('🦖 xhttp initialized - vanilla JS, no frameworks');
    },

    // Process element and children for xhttp attributes
    process(root = document) {
      // Auto-bind elements with data-get/data-post
      const elements = root.querySelectorAll('[data-get], [data-post], [data-put], [data-delete]');
      elements.forEach(el => {
        if (!el._xhttpBound) {
          el._xhttpBound = true;
          // Add indicator
          if (!el.hasAttribute('data-indicator')) {
            el.style.cursor = 'pointer';
          }
        }
      });
    },

    // Handle clicks - data-get, data-post etc
    async handleClick(e) {
      let el = e.target;
      // Find closest element with xhttp attributes
      while (el && el !== document) {
        if (el.hasAttribute('data-get') || el.hasAttribute('data-post') || el.hasAttribute('data-link')) {
          break;
        }
        el = el.parentElement;
      }
      if (!el || el === document) return;

      // data-link is for SPA navigation (pushState)
      if (el.hasAttribute('data-link')) {
        const href = el.getAttribute('href') || el.getAttribute('data-link');
        if (href && href.startsWith('/') && !href.startsWith('//') && !href.startsWith('/api/')) {
          e.preventDefault();
          if (window.app && typeof window.app.navigate === 'function') {
            window.app.navigate(href);
            return;
          }
          const target = el.getAttribute('data-target') || '#main';
          const swap = el.getAttribute('data-swap') || 'innerHTML';
          const targetEl = document.querySelector(target);
          if (targetEl) {
            // Update active state in navbar
            document.querySelectorAll('.navbar-menu a').forEach(a => a.classList.remove('active'));
            if (el.closest('.navbar-menu')) el.classList.add('active');
            
            await this.load(href, targetEl, swap, true);
            // Update URL
            if (this.config.history) {
              history.pushState({path: href}, '', href);
            }
          }
        }
        return;
      }

      const method = el.hasAttribute('data-get') ? 'GET' :
                     el.hasAttribute('data-post') ? 'POST' :
                     el.hasAttribute('data-put') ? 'PUT' :
                     el.hasAttribute('data-delete') ? 'DELETE' : null;
      if (!method) return;

      e.preventDefault();
      const url = el.getAttribute('data-' + method.toLowerCase());
      const target = el.getAttribute('data-target') || '#main';
      const swap = el.getAttribute('data-swap') || 'innerHTML';
      const targetEl = document.querySelector(target);
      if (!targetEl) return;

      await this.request(method, url, null, targetEl, swap, el);
    },

    // Handle form submits - data-post etc
    async handleSubmit(e) {
      const form = e.target;
      if (!form.hasAttribute('data-post') && !form.hasAttribute('data-get') && !form.hasAttribute('data-put')) return;
      
      e.preventDefault();
      const method = form.hasAttribute('data-post') ? 'POST' :
                     form.hasAttribute('data-get') ? 'GET' :
                     form.hasAttribute('data-put') ? 'PUT' : 'POST';
      const url = form.getAttribute('data-' + method.toLowerCase()) || form.action;
      const target = form.getAttribute('data-target') || '#main';
      const swap = form.getAttribute('data-swap') || 'innerHTML';
      const targetEl = document.querySelector(target);
      
      const formData = new FormData(form);
      const data = {};
      for (const [k,v] of formData.entries()) data[k] = v;
      
      await this.request(method, url, data, targetEl, swap, form);
    },

    // Core request - xhttp style
    async request(method, url, data, targetEl, swap = 'innerHTML', triggerEl = null) {
      if (triggerEl) {
        triggerEl.classList.add('xhttp-request');
        const indicator = triggerEl.getAttribute('data-indicator');
        if (indicator) {
          const indEl = document.querySelector(indicator);
          if (indEl) indEl.classList.remove('hidden');
        }
      }

      if (targetEl) {
        // Show loading
        const loadingHtml = targetEl.getAttribute('data-loading') || '<div class="loading"><div class="spinner"></div></div>';
        if (swap === 'innerHTML') targetEl.innerHTML = loadingHtml;
      }

      try {
        const opts = {method, headers: {}};
        if (window.api && window.api.token) {
          opts.headers['Authorization'] = 'Bearer ' + window.api.token;
        }
        
        if (data && method !== 'GET') {
          opts.headers['Content-Type'] = 'application/json';
          opts.body = JSON.stringify(data);
        } else if (data && method === 'GET') {
          const params = new URLSearchParams(data);
          url += (url.includes('?') ? '&' : '?') + params.toString();
        }

        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), this.config.timeout);
        opts.signal = controller.signal;

        const res = await fetch(url, opts);
        clearTimeout(timeoutId);
        
        const contentType = res.headers.get('content-type') || '';
        let result;
        
        if (contentType.includes('application/json')) {
          const json = await res.json();
          if (json.ok === false) throw new Error(json.error || 'Request failed');
          result = json.data || json;
          // If result is JSON but target expects HTML, render it
          if (typeof result === 'object' && targetEl) {
            // Try to use component renderer if available
            const component = targetEl.getAttribute('data-component');
            if (component && window.components && window.components[component]) {
              const comp = window.createComponent(component, result);
              result = comp.render();
            } else {
              result = `<pre>${JSON.stringify(result, null, 2)}</pre>`;
            }
          }
        } else {
          result = await res.text();
        }

        if (!res.ok) throw new Error(result);

        // Swap
        this.swap(targetEl, result, swap);

        // Trigger events
        if (triggerEl) {
          triggerEl.dispatchEvent(new CustomEvent('xhttp:afterRequest', {detail: {result, targetEl}}));
        }
        targetEl.dispatchEvent(new CustomEvent('xhttp:afterSwap', {detail: {result}}));

        this.process(targetEl);

      } catch (err) {
        console.error('xhttp error:', err);
        if (targetEl) {
          targetEl.innerHTML = `<div class="error">Error: ${err.message}<br><small>${url}</small></div>`;
        }
        if (triggerEl) {
          triggerEl.dispatchEvent(new CustomEvent('xhttp:error', {detail: {error: err}}));
        }
      } finally {
        if (triggerEl) {
          triggerEl.classList.remove('xhttp-request');
          const indicator = triggerEl.getAttribute('data-indicator');
          if (indicator) {
            const indEl = document.querySelector(indicator);
            if (indEl) indEl.classList.add('hidden');
          }
        }
      }
    },

    // Load URL into target - for SPA navigation
    async load(url, targetEl, swap = 'innerHTML', pushState = true) {
      // If url is API endpoint, try to find corresponding component
      // For now, if url starts with /api/, use request, else fetch HTML
      if (url.startsWith('/api/')) {
        await this.request('GET', url, null, targetEl, swap);
      } else {
        // For HTML pages, fetch and extract main content or use full HTML
        try {
          const res = await fetch(url, {headers: {'X-Requested-With': 'xhttp'}});
          const html = await res.text();
          // If response is full HTML page, extract #main or body
          if (html.includes('<html')) {
            const parser = new DOMParser();
            const doc = parser.parseFromString(html, 'text/html');
            const main = doc.getElementById('main') || doc.body;
            if (main && (main.innerHTML.includes('class="spinner"') || (main.querySelector && main.querySelector('.spinner')))) {
              if (window.app && typeof window.app.loadRoute === 'function') {
                window.app.loadRoute(url, false);
                return;
              }
            }
            this.swap(targetEl, main.innerHTML, swap);
          } else {
            this.swap(targetEl, html, swap);
          }
          this.process(targetEl);
        } catch (err) {
          targetEl.innerHTML = `<div class="error">Failed to load ${url}: ${err.message}</div>`;
        }
      }
    },

    // Swap content into target
    swap(targetEl, content, mode = 'innerHTML') {
      if (!targetEl) return;
      switch (mode) {
        case 'innerHTML':
          targetEl.innerHTML = content;
          break;
        case 'outerHTML':
          targetEl.outerHTML = content;
          break;
        case 'beforeend':
          targetEl.insertAdjacentHTML('beforeend', content);
          break;
        case 'afterbegin':
          targetEl.insertAdjacentHTML('afterbegin', content);
          break;
        case 'beforebegin':
          targetEl.insertAdjacentHTML('beforebegin', content);
          break;
        case 'afterend':
          targetEl.insertAdjacentHTML('afterend', content);
          break;
        case 'none':
          break;
        default:
          targetEl.innerHTML = content;
      }
      // Re-process for new xhttp attributes
      this.process(targetEl);
    }
  };

  // Expose globally - vanilla JS, no module system needed but also support ES modules
  window.xhttp = xhttp;
  if (typeof module !== 'undefined' && module.exports) module.exports = xhttp;

  // Auto-init
  xhttp.init();

  console.log('🦖 xhttp.js loaded - Nim-style, vanilla JS, <5KB');
})();
