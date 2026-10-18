// theme.js - Modular theme system, vanilla JS, easy palette editing
// Works with CSS variables, localStorage, no frameworks

(function() {
  'use strict';

  const themeSystem = {
    version: '1.0.0-nim',
    currentTheme: 'light',
    customTheme: null,

    // Default themes - mirrors Nim theme.nim
    themes: {
      light: {
        name: 'light',
        displayName: 'Light',
        description: 'Default light theme, clean and minimal',
        isDark: false,
        palette: {
          primary: '#0d6efd',
          primaryHover: '#0b5ed7',
          primaryLight: '#cfe2ff',
          secondary: '#6c757d',
          success: '#198754',
          danger: '#dc3545',
          warning: '#ffc107',
          info: '#0dcaf0',
          bg: '#f8f9fa',
          bgSecondary: '#e9ecef',
          bgCard: '#ffffff',
          bgCode: '#f1f3f5',
          bgHover: '#e9ecef',
          text: '#212529',
          textSecondary: '#495057',
          textMuted: '#6c757d',
          textInverse: '#ffffff',
          border: '#dee2e6',
          borderLight: '#e9ecef',
          borderDark: '#343a40',
          shadow: '0 1px 3px rgba(0,0,0,0.1)',
          shadowLg: '0 4px 12px rgba(0,0,0,0.15)',
          radius: '6px',
          radiusLg: '12px'
        }
      },
      dark: {
        name: 'dark',
        displayName: 'Dark',
        description: 'Dark theme for low light',
        isDark: true,
        palette: {
          primary: '#3b82f6',
          primaryHover: '#2563eb',
          primaryLight: '#1e3a5f',
          secondary: '#6b7280',
          success: '#10b981',
          danger: '#ef4444',
          warning: '#f59e0b',
          info: '#06b6d4',
          bg: '#111827',
          bgSecondary: '#1f2937',
          bgCard: '#1f2937',
          bgCode: '#374151',
          bgHover: '#374151',
          text: '#f9fafb',
          textSecondary: '#d1d5db',
          textMuted: '#9ca3af',
          textInverse: '#111827',
          border: '#374151',
          borderLight: '#4b5563',
          borderDark: '#6b7280',
          shadow: '0 1px 3px rgba(0,0,0,0.3)',
          shadowLg: '0 4px 12px rgba(0,0,0,0.4)',
          radius: '6px',
          radiusLg: '12px'
        }
      },
      'solarized-light': {
        name: 'solarized-light',
        displayName: 'Solarized Light',
        description: 'Solarized light, easy on eyes',
        isDark: false,
        palette: {
          primary: '#268bd2',
          primaryHover: '#2075b5',
          primaryLight: '#d6e9f5',
          secondary: '#93a1a1',
          success: '#859900',
          danger: '#dc322f',
          warning: '#b58900',
          info: '#2aa198',
          bg: '#fdf6e3',
          bgSecondary: '#eee8d5',
          bgCard: '#ffffff',
          bgCode: '#eee8d5',
          bgHover: '#eee8d5',
          text: '#586e75',
          textSecondary: '#657b83',
          textMuted: '#93a1a1',
          textInverse: '#fdf6e3',
          border: '#93a1a1',
          borderLight: '#eee8d5',
          borderDark: '#586e75',
          shadow: '0 1px 3px rgba(88,110,117,0.1)',
          shadowLg: '0 4px 12px rgba(88,110,117,0.15)',
          radius: '6px',
          radiusLg: '12px'
        }
      },
      nord: {
        name: 'nord',
        displayName: 'Nord',
        description: 'Nord dark, arctic bluish',
        isDark: true,
        palette: {
          primary: '#88c0d0',
          primaryHover: '#81a1c1',
          primaryLight: '#4c566a',
          secondary: '#4c566a',
          success: '#a3be8c',
          danger: '#bf616a',
          warning: '#ebcb8b',
          info: '#88c0d0',
          bg: '#2e3440',
          bgSecondary: '#3b4252',
          bgCard: '#3b4252',
          bgCode: '#4c566a',
          bgHover: '#4c566a',
          text: '#eceff4',
          textSecondary: '#d8dee9',
          textMuted: '#4c566a',
          textInverse: '#2e3440',
          border: '#4c566a',
          borderLight: '#5e81ac',
          borderDark: '#2e3440',
          shadow: '0 1px 3px rgba(0,0,0,0.3)',
          shadowLg: '0 4px 12px rgba(0,0,0,0.4)',
          radius: '6px',
          radiusLg: '12px'
        }
      },
      monokai: {
        name: 'monokai',
        displayName: 'Monokai',
        description: 'Vibrant dark',
        isDark: true,
        palette: {
          primary: '#a6e22e',
          primaryHover: '#8ac627',
          primaryLight: '#3e4a2d',
          secondary: '#75715e',
          success: '#a6e22e',
          danger: '#f92672',
          warning: '#fd971f',
          info: '#66d9ef',
          bg: '#272822',
          bgSecondary: '#3e3d32',
          bgCard: '#3e3d32',
          bgCode: '#49483e',
          bgHover: '#49483e',
          text: '#f8f8f2',
          textSecondary: '#cfcfc2',
          textMuted: '#75715e',
          textInverse: '#272822',
          border: '#49483e',
          borderLight: '#75715e',
          borderDark: '#f8f8f2',
          shadow: '0 1px 3px rgba(0,0,0,0.4)',
          shadowLg: '0 4px 12px rgba(0,0,0,0.5)',
          radius: '6px',
          radiusLg: '12px'
        }
      },
      'github-light': {
        name: 'github-light',
        displayName: 'GitHub Light',
        description: 'GitHub light theme',
        isDark: false,
        palette: {
          primary: '#0969da',
          primaryHover: '#0550ae',
          primaryLight: '#ddf4ff',
          secondary: '#656d76',
          success: '#1a7f37',
          danger: '#cf222e',
          warning: '#9a6700',
          info: '#0969da',
          bg: '#ffffff',
          bgSecondary: '#f6f8fa',
          bgCard: '#ffffff',
          bgCode: '#f6f8fa',
          bgHover: '#f6f8fa',
          text: '#24292f',
          textSecondary: '#57606a',
          textMuted: '#8c959f',
          textInverse: '#ffffff',
          border: '#d0d7de',
          borderLight: '#d8dee4',
          borderDark: '#24292f',
          shadow: '0 1px 0 rgba(27,31,36,0.04)',
          shadowLg: '0 3px 6px rgba(140,149,159,0.15)',
          radius: '6px',
          radiusLg: '12px'
        }
      }
    },

    init() {
      // Load saved theme
      const saved = localStorage.getItem('fossil_theme') || 'light';
      const custom = localStorage.getItem('fossil_custom_theme');
      if (custom) {
        try {
          this.customTheme = JSON.parse(custom);
          this.themes.custom = this.customTheme;
        } catch (e) {}
      }
      this.setTheme(saved);
      this.bindEvents();
      console.log('🎨 theme.js initialized - current:', this.currentTheme);
    },

    bindEvents() {
      document.addEventListener('click', (e) => {
        const toggle = e.target.closest('#theme-toggle');
        if (toggle) {
          this.toggle();
          return;
        }
        const editorBtn = e.target.closest('#theme-editor-btn');
        if (editorBtn) {
          this.openEditor();
          return;
        }
      });
    },

    setTheme(name) {
      if (!this.themes[name]) {
        console.warn('Theme not found:', name);
        return;
      }
      this.currentTheme = name;
      document.documentElement.setAttribute('data-theme', name);
      localStorage.setItem('fossil_theme', name);
      
      // Update CSS variables
      const palette = this.themes[name].palette;
      const root = document.documentElement;
      for (const [key, value] of Object.entries(palette)) {
        const cssVar = '--color-' + key.replace(/([A-Z])/g, '-$1').toLowerCase();
        // Map JS keys to CSS vars
        const mapping = {
          primary: '--color-primary',
          primaryHover: '--color-primary-hover',
          primaryLight: '--color-primary-light',
          secondary: '--color-secondary',
          success: '--color-success',
          danger: '--color-danger',
          warning: '--color-warning',
          info: '--color-info',
          bg: '--color-bg',
          bgSecondary: '--color-bg-secondary',
          bgCard: '--color-bg-card',
          bgCode: '--color-bg-code',
          bgHover: '--color-bg-hover',
          text: '--color-text',
          textSecondary: '--color-text-secondary',
          textMuted: '--color-text-muted',
          textInverse: '--color-text-inverse',
          border: '--color-border',
          borderLight: '--color-border-light',
          borderDark: '--color-border-dark',
          shadow: '--shadow',
          shadowLg: '--shadow-lg',
          radius: '--radius',
          radiusLg: '--radius-lg'
        };
        const varName = mapping[key] || '--color-' + key;
        root.style.setProperty(varName, value);
      }

      // Update toggle icon
      const toggle = document.getElementById('theme-toggle');
      if (toggle) {
        toggle.textContent = this.themes[name].isDark ? '☀️' : '🌙';
      }

      // Dispatch event
      document.dispatchEvent(new CustomEvent('theme:changed', {detail: {theme: name}}));
    },

    toggle() {
      // Toggle between light and dark
      const isDark = this.themes[this.currentTheme]?.isDark;
      if (isDark) this.setTheme('light');
      else this.setTheme('dark');
    },

    openEditor() {
      const modal = document.getElementById('theme-editor');
      if (!modal) return;
      modal.classList.remove('hidden');
      this.renderEditor();
    },

    renderEditor() {
      // Render presets
      const grid = document.getElementById('theme-presets-grid');
      if (grid) {
        grid.innerHTML = Object.values(this.themes).map(theme => {
          const isActive = theme.name === this.currentTheme ? 'active' : '';
          return `
            <div class="theme-preset ${isActive}" onclick="themeSystem.setTheme('${theme.name}'); themeSystem.renderEditor()">
              <div class="theme-preset-preview" style="background:${theme.palette.bg}; border:1px solid ${theme.palette.border}; display:flex">
                <div style="width:30%; background:${theme.palette.primary}; height:100%"></div>
                <div style="flex:1; padding:4px; font-size:10px; color:${theme.palette.text}">${theme.displayName}</div>
              </div>
              <div style="font-weight:600; font-size:12px">${theme.displayName}</div>
              <div style="font-size:10px; color:var(--color-text-muted)">${theme.description}</div>
            </div>
          `;
        }).join('');
      }

      // Render color editor for current theme
      const colorGrid = document.getElementById('color-grid');
      if (colorGrid) {
        const current = this.themes[this.currentTheme];
        if (!current) return;
        colorGrid.innerHTML = Object.entries(current.palette).map(([key, value]) => {
          // Only show color inputs for colors, not shadow/radius
          if (key.includes('shadow') || key.includes('radius')) {
            return `<div class="color-item"><label>${key}</label><input type="text" value="${value}" onchange="themeSystem.updateColor('${key}', this.value)" style="width:100%; padding:6px; border:1px solid var(--color-border); border-radius:4px"></div>`;
          }
          return `<div class="color-item"><label>${key}</label><input type="color" value="${this.toHex(value) || '#000000'}" onchange="themeSystem.updateColor('${key}', this.value)"><input type="text" value="${value}" onchange="themeSystem.updateColor('${key}', this.value)" style="margin-top:4px; width:100%; padding:4px; font-size:12px; border:1px solid var(--color-border); border-radius:4px"></div>`;
        }).join('');
      }
    },

    toHex(color) {
      // Convert any color to hex for color input
      if (color.startsWith('#')) return color;
      // For rgb/rgba, create temp element
      const ctx = document.createElement('canvas').getContext('2d');
      ctx.fillStyle = color;
      return ctx.fillStyle;
    },

    updateColor(key, value) {
      const theme = this.themes[this.currentTheme];
      if (!theme) return;
      theme.palette[key] = value;
      this.setTheme(this.currentTheme);
    },

    save() {
      const theme = this.themes[this.currentTheme];
      const custom = {
        name: 'custom',
        displayName: 'Custom',
        description: 'Custom theme edited ' + new Date().toISOString(),
        isDark: theme.isDark,
        palette: {...theme.palette}
      };
      localStorage.setItem('fossil_custom_theme', JSON.stringify(custom));
      this.themes.custom = custom;
      this.setTheme('custom');
      this.renderEditor();
      alert('Custom theme saved!');
    },

    reset() {
      if (confirm('Reset custom theme?')) {
        localStorage.removeItem('fossil_custom_theme');
        delete this.themes.custom;
        this.setTheme('light');
        this.renderEditor();
      }
    },

    export() {
      const theme = this.themes[this.currentTheme];
      const data = JSON.stringify(theme, null, 2);
      const blob = new Blob([data], {type: 'application/json'});
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `theme-${theme.name}.json`;
      a.click();
      URL.revokeObjectURL(url);
    },

    import(event) {
      const file = event.target.files[0];
      if (!file) return;
      const reader = new FileReader();
      reader.onload = (e) => {
        try {
          const theme = JSON.parse(e.target.result);
          if (!theme.name || !theme.palette) throw new Error('Invalid theme file');
          this.themes[theme.name] = theme;
          localStorage.setItem('fossil_custom_theme', JSON.stringify(theme));
          this.setTheme(theme.name);
          this.renderEditor();
          alert('Theme imported: ' + theme.displayName);
        } catch (err) {
          alert('Failed to import theme: ' + err.message);
        }
      };
      reader.readAsText(file);
    }
  };

  // Theme editor helper
  window.themeEditor = {
    save: () => themeSystem.save(),
    reset: () => themeSystem.reset(),
    export: () => themeSystem.export(),
    import: (e) => themeSystem.import(e)
  };

  window.themeSystem = themeSystem;
  themeSystem.init();
})();
