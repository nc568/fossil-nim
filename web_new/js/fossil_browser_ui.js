/**
 * Fossil-Nim Browser UI Controller (Professional Edition)
 * Pure Vanilla JavaScript, zero frameworks, maximum performance.
 * Features:
 * - Full i18n Localization Engine with extensible language config packs (RU, EN, Custom)
 * - Complete UI Configuration System (Themes, Custom Color Palettes, Density, Fonts, Radius)
 * - Responsive Layout for Mobile, Tablet, Desktop, and Ultrawide
 * - 3 Storage Backends (IndexedDB, SQLite WASM, Pure-Nim CDB)
 * - VCS Timeline, Virtual File Tree & Editor, Myers Diff Engine
 * - Wiki & Built-in Docs, Ticket Tracker, 89-Tool MCP AI Agent Console
 * - High-speed Snapshot Export & Smart Conflict Resolution Import (Merge vs Replace)
 */

(function () {
  'use strict';

  // =========================================================================
  // 1. Localization / i18n Engine & Language Configs
  // =========================================================================
  const I18N_DICTIONARIES = {
    ru: {
      "app.name": "🦖 Fossil-Nim",
      "app.edition": "Browser Edition",
      "app.tools_badge": "89 MCP Инструментов",
      "app.hero_desc": "Распределённая система контроля версий, работающая на 100% внутри браузера. Сервер не требуется.",
      "app.active_backend": "Активное хранилище:",
      "nav.storage": "Хранилище:",
      "nav.export": "💾 Экспорт",
      "nav.import": "📥 Импорт",
      "nav.server_ui": "🖥️ Серверный UI",
      "nav.settings": "⚙️ Настройки",
      "tab.timeline": "📜 Таймлайн",
      "tab.files": "📁 Файлы и редактор",
      "tab.diff": "🔍 Myers Diff",
      "tab.wiki": "📖 Wiki и документация",
      "tab.tickets": "🎫 Тикеты",
      "tab.mcp": "🤖 ИИ-агент MCP (89)",
      "tab.storage": "💾 Мульти-БД диагностика",
      "timeline.title": "Таймлайн репозитория",
      "timeline.desc": "История фиксаций и коммитов в текущем браузерном хранилище.",
      "timeline.new_commit": "+ Новый коммит",
      "timeline.empty": "Нет записей в таймлайне. Создайте первый коммит!",
      "files.title": "Виртуальная файловая система",
      "files.desc": "Редактируйте файлы репозитория в браузере с live-diff Myers и коммитами.",
      "files.new_file": "+ Новый файл",
      "files.repo_tree": "Дерево репозитория",
      "files.compare_diff": "⚡ Сравнить Diff",
      "files.save": "💾 Сохранить",
      "files.commit": "🚀 Закоммитить",
      "files.toggle_tree": "📁 Дерево файлов",
      "diff.title": "Движок Myers Diff (Pure Nim в JS)",
      "diff.desc": "Алгоритм Myers diff, скомпилированный напрямую из Nim Lang в JavaScript.",
      "diff.sample": "Пример:",
      "diff.original": "Исходный текст (v1)",
      "diff.modified": "Изменённый текст (v2)",
      "diff.compute": "⚡ Рассчитать Myers Diff (через Nim)",
      "diff.preset_code": "Nim Code Diff",
      "diff.preset_doc": "Markdown Doc Diff",
      "wiki.title": "Wiki и встроенная документация",
      "wiki.desc": "Поставляется из коробки с архитектурой Fossil-Nim и документацией.",
      "wiki.new_page": "+ Новая страница",
      "wiki.pages": "Страницы Wiki",
      "wiki.edit": "✏️ Редактировать",
      "wiki.preview": "👁️ Предпросмотр",
      "wiki.save": "💾 Сохранить страницу",
      "wiki.cancel": "Отмена",
      "tickets.title": "Трекер задач и тикетов",
      "tickets.desc": "Встроенный баг-трекер с приоритетами, фильтрацией и локальным сохранением.",
      "tickets.new_ticket": "+ Новый тикет",
      "tickets.filter_all": "Все задачи",
      "tickets.filter_open": "Открытые",
      "tickets.filter_closed": "Закрытые",
      "tickets.empty": "Нет тикетов",
      "mcp.title": "Консоль ИИ-агента (89 MCP Tools)",
      "mcp.desc": "Полный набор инструментов Model Context Protocol для автономных агентов.",
      "mcp.tools_count": "Доступные инструменты (89)",
      "mcp.invoke": "⚡ Вызвать инструмент",
      "mcp.copy_prompt": "📋 Скопировать системный промпт",
      "mcp.params": "JSON параметры вызова:",
      "mcp.response": "JSON ответ инструмента:",
      "storage.title": "Диагностика Мульти-БД и SQL",
      "storage.desc": "Инспекция 3 браузерных бэкендов: IndexedDB, SQLite WASM и Pure-Nim CDB.",
      "storage.sql_console": "Интерактивная SQL-консоль (SQLite WASM)",
      "storage.run_query": "▶ Выполнить SQL",
      "storage.stats": "Статистика хранилища",
      "modal.commit_title": "Новый коммит репозитория",
      "modal.commit_comment": "Комментарий коммита:",
      "modal.commit_user": "Автор / Пользователь:",
      "modal.commit_branch": "Ветка:",
      "modal.commit_cancel": "Отмена",
      "modal.commit_submit": "Зафиксировать коммит",
      "modal.ticket_title": "Создать новый тикет",
      "modal.ticket_heading": "Заголовок задачи:",
      "modal.ticket_priority": "Приоритет:",
      "modal.ticket_desc": "Описание:",
      "modal.ticket_cancel": "Отмена",
      "modal.ticket_submit": "Создать тикет",
      "modal.import_title": "Импорт репозитория",
      "modal.import_prompt": "Текущий репозиторий уже содержит данные. Выберите способ импорта:",
      "modal.merge_title": "🔄 Merge / Continue Project (Слияние / Дополнить)",
      "modal.merge_desc": "Сохраняет существующие коммиты и файлы. Дополняет новыми коммитами, обновляет файлы, объединяет wiki и тикеты без потерь.",
      "modal.replace_title": "⚠️ Clean Overwrite (Заменить полностью)",
      "modal.replace_desc": "Очищает текущие коммиты, файлы, wiki и тикеты, полностью заменяя их содержимым снапшота.",
      "modal.import_abort": "Отмена",
      "modal.import_proceed": "Продолжить импорт",
      "settings.title": "Настройки интерфейса и конфигурация",
      "settings.theme_tab": "🎨 Темы и цвета",
      "settings.layout_tab": "📐 Макет и плотность",
      "settings.lang_tab": "🌐 Язык (i18n)",
      "settings.config_tab": "💾 Конфигурация",
      "settings.theme_preset": "Готовые темы оформления:",
      "settings.custom_palette": "Пользовательская цветовая палитра:",
      "settings.primary_color": "Основной цвет (Primary):",
      "settings.bg_color": "Цвет фона (Background):",
      "settings.card_color": "Цвет карточек (Card/Surface):",
      "settings.border_color": "Цвет границ (Borders):",
      "settings.text_color": "Цвет текста (Text):",
      "settings.density_label": "Плотность интерфейса:",
      "settings.density_compact": "Компактный (высокая плотность для профи)",
      "settings.density_comfortable": "Комфортный (стандартный)",
      "settings.fontsize_label": "Размер шрифта:",
      "settings.fontfamily_label": "Семейство шрифтов:",
      "settings.radius_label": "Скругление углов (Border Radius):",
      "settings.show_hero_label": "Показывать верхний баннер-дэшборд",
      "settings.lang_select": "Язык интерфейса:",
      "settings.custom_lang_pack": "Пользовательский языковой пакет (JSON):",
      "settings.export_lang": "📥 Экспорт языкового пакета",
      "settings.import_lang": "📤 Загрузить перевод (JSON)",
      "settings.full_config": "Полный файл конфигурации UI (JSON):",
      "settings.export_config": "💾 Экспорт конфигурации UI",
      "settings.import_config": "📂 Импорт конфигурации UI",
      "settings.reset_config": "🔄 Сброс к умолчаниям",
      "settings.close": "Закрыть",
      "settings.apply": "Применить",
      "notif.saved": "Настройки успешно сохранены!",
      "notif.reset": "Настройки сброшены к значениям по умолчанию!"
    },
    en: {
      "app.name": "🦖 Fossil-Nim",
      "app.edition": "Browser Edition",
      "app.tools_badge": "89 MCP Tools",
      "app.hero_desc": "Distributed Version Control running 100% inside your browser. No server required.",
      "app.active_backend": "Active backend:",
      "nav.storage": "Storage:",
      "nav.export": "💾 Export",
      "nav.import": "📥 Import",
      "nav.server_ui": "🖥️ Server UI",
      "nav.settings": "⚙️ Settings",
      "tab.timeline": "📜 Timeline",
      "tab.files": "📁 Files & Editor",
      "tab.diff": "🔍 Myers Diff",
      "tab.wiki": "📖 Wiki & Docs",
      "tab.tickets": "🎫 Tickets",
      "tab.mcp": "🤖 AI Agent MCP (89)",
      "tab.storage": "💾 Multi-DB Diagnostics",
      "timeline.title": "Repository Timeline",
      "timeline.desc": "History of check-ins and commits saved in current browser storage backend.",
      "timeline.new_commit": "+ New Commit",
      "timeline.empty": "No timeline records found. Make your first commit!",
      "files.title": "In-Browser Virtual File System",
      "files.desc": "Edit repository files directly in browser with live Myers diff and commits.",
      "files.new_file": "+ New File",
      "files.repo_tree": "Repository Tree",
      "files.compare_diff": "⚡ Compare Diff",
      "files.save": "💾 Save File",
      "files.commit": "🚀 Commit",
      "files.toggle_tree": "📁 File Tree",
      "diff.title": "Myers Diff Engine (Pure Nim in JS)",
      "diff.desc": "Unified Myers diff algorithm compiled directly from Nim Lang to JavaScript.",
      "diff.sample": "Sample:",
      "diff.original": "Original Text (v1)",
      "diff.modified": "Modified Text (v2)",
      "diff.compute": "⚡ Compute Myers Diff (via Nim)",
      "diff.preset_code": "Nim Code Diff",
      "diff.preset_doc": "Markdown Doc Diff",
      "wiki.title": "Wiki & Built-in Documentation",
      "wiki.desc": "Shipped out-of-the-box with complete Fossil-Nim architecture and reference docs.",
      "wiki.new_page": "+ New Wiki Page",
      "wiki.pages": "Wiki Pages",
      "wiki.edit": "✏️ Edit Page",
      "wiki.preview": "👁️ Live Preview",
      "wiki.save": "💾 Save Page",
      "wiki.cancel": "Cancel",
      "tickets.title": "Issue & Ticket Tracker",
      "tickets.desc": "Built-in bug tracking with priority badges, status filters, and local persistence.",
      "tickets.new_ticket": "+ New Ticket",
      "tickets.filter_all": "All Tickets",
      "tickets.filter_open": "Open",
      "tickets.filter_closed": "Closed",
      "tickets.empty": "No tickets found",
      "mcp.title": "AI Agent Console (89 MCP Tools)",
      "mcp.desc": "Comprehensive Model Context Protocol server exposing 89 tools for autonomous agents.",
      "mcp.tools_count": "Available Tools (89)",
      "mcp.invoke": "⚡ Invoke Tool",
      "mcp.copy_prompt": "📋 Copy System Prompt",
      "mcp.params": "JSON Parameters:",
      "mcp.response": "JSON Response:",
      "storage.title": "Multi-DB Diagnostics & SQL",
      "storage.desc": "Inspect and manage 3 browser storage backends: IndexedDB, SQLite WASM, and Pure-Nim CDB.",
      "storage.sql_console": "Interactive SQL Console (SQLite WASM)",
      "storage.run_query": "▶ Run SQL Query",
      "storage.stats": "Storage Stats",
      "modal.commit_title": "New Repository Commit",
      "modal.commit_comment": "Commit Comment:",
      "modal.commit_user": "Author / User:",
      "modal.commit_branch": "Branch:",
      "modal.commit_cancel": "Cancel",
      "modal.commit_submit": "Commit Check-in",
      "modal.ticket_title": "Create New Ticket",
      "modal.ticket_heading": "Ticket Title:",
      "modal.ticket_priority": "Priority:",
      "modal.ticket_desc": "Description:",
      "modal.ticket_cancel": "Cancel",
      "modal.ticket_submit": "Create Ticket",
      "modal.import_title": "Import Repository Snapshot",
      "modal.import_prompt": "Your current repository already contains data. How would you like to handle the imported content?",
      "modal.merge_title": "🔄 Merge / Continue Project",
      "modal.merge_desc": "Preserves existing check-ins and data. Appends new commits, updates modified files, and merges wiki & tickets without loss.",
      "modal.replace_title": "⚠️ Clean Overwrite",
      "modal.replace_desc": "Wipes existing files, commits, wiki, and tickets in current storage, replacing everything with the imported snapshot.",
      "modal.import_abort": "Cancel",
      "modal.import_proceed": "Proceed with Import",
      "settings.title": "Interface Settings & Configuration",
      "settings.theme_tab": "🎨 Themes & Colors",
      "settings.layout_tab": "📐 Layout & Density",
      "settings.lang_tab": "🌐 Language (i18n)",
      "settings.config_tab": "💾 Configuration",
      "settings.theme_preset": "Theme Presets:",
      "settings.custom_palette": "Custom Color Palette:",
      "settings.primary_color": "Primary Color:",
      "settings.bg_color": "Background Color:",
      "settings.card_color": "Card / Surface Color:",
      "settings.border_color": "Border Color:",
      "settings.text_color": "Text Color:",
      "settings.density_label": "Interface Density:",
      "settings.density_compact": "Compact (High information density for pros)",
      "settings.density_comfortable": "Comfortable (Standard)",
      "settings.fontsize_label": "Base Font Size:",
      "settings.fontfamily_label": "Font Family:",
      "settings.radius_label": "Border Radius:",
      "settings.show_hero_label": "Show top dashboard hero banner",
      "settings.lang_select": "Interface Language:",
      "settings.custom_lang_pack": "Custom Language Pack (JSON):",
      "settings.export_lang": "📥 Export Language Pack",
      "settings.import_lang": "📤 Import Translation (JSON)",
      "settings.full_config": "Full UI Config File (JSON):",
      "settings.export_config": "💾 Export UI Config",
      "settings.import_config": "📂 Import UI Config",
      "settings.reset_config": "🔄 Reset to Defaults",
      "settings.close": "Close",
      "settings.apply": "Apply",
      "notif.saved": "Settings successfully applied!",
      "notif.reset": "Settings reset to defaults!"
    }
  };

  window.FossilI18n = {
    currentLang: 'ru',
    dictionaries: I18N_DICTIONARIES,

    init() {
      const savedCustom = localStorage.getItem('fossil_custom_lang_pack');
      if (savedCustom) {
        try {
          this.dictionaries['custom'] = JSON.parse(savedCustom);
        } catch (_) {}
      }
    },

    t(key, fallback = '') {
      const dict = this.dictionaries[this.currentLang] || this.dictionaries['ru'];
      return dict[key] || this.dictionaries['en'][key] || fallback || key;
    },

    setLanguage(lang) {
      if (this.dictionaries[lang]) {
        this.currentLang = lang;
        this.applyAll();
        return true;
      }
      return false;
    },

    applyAll() {
      document.querySelectorAll('[data-i18n]').forEach(el => {
        const key = el.getAttribute('data-i18n');
        el.innerText = this.t(key, el.innerText);
      });
      document.querySelectorAll('[data-i18n-title]').forEach(el => {
        const key = el.getAttribute('data-i18n-title');
        el.setAttribute('title', this.t(key, el.getAttribute('title')));
      });
      document.querySelectorAll('[data-i18n-placeholder]').forEach(el => {
        const key = el.getAttribute('data-i18n-placeholder');
        el.setAttribute('placeholder', this.t(key, el.getAttribute('placeholder')));
      });
      const langBtn = $('btn-lang-toggle');
      if (langBtn) {
        langBtn.innerText = this.currentLang === 'ru' ? '🇷🇺 RU' : (this.currentLang === 'en' ? '🇬🇧 EN' : '🌐 ' + this.currentLang.toUpperCase());
      }
    },

    importLangPack(code, dict) {
      this.dictionaries[code] = dict;
      if (code === 'custom') {
        localStorage.setItem('fossil_custom_lang_pack', JSON.stringify(dict));
      }
      this.setLanguage(code);
    },

    exportLangPack(code) {
      return JSON.stringify(this.dictionaries[code] || this.dictionaries['en'], null, 2);
    }
  };

  // =========================================================================
  // 2. Full UI Configuration System
  // =========================================================================
  const DEFAULT_UI_CONFIG = {
    theme: 'dark', // 'dark' | 'light' | 'nord' | 'dracula' | 'gruvbox' | 'cyberpunk' | 'monokai' | 'custom'
    density: 'comfortable', // 'compact' | 'comfortable'
    fontSize: '15px', // '13px' | '14px' | '15px' | '16px'
    fontFamily: 'system', // 'system' | 'mono' | 'inter'
    radius: '8px', // '0px' | '4px' | '8px' | '12px'
    showHero: true,
    lang: 'ru',
    customColors: {
      primary: '#3b82f6',
      primaryHover: '#60a5fa',
      bg: '#0b0f19',
      bgCard: '#151d2e',
      border: '#1e293b',
      text: '#f1f5f9'
    }
  };

  window.FossilUIConfig = {
    config: { ...DEFAULT_UI_CONFIG },

    load() {
      const saved = localStorage.getItem('fossil_ui_config');
      if (saved) {
        try {
          this.config = Object.assign({}, DEFAULT_UI_CONFIG, JSON.parse(saved));
        } catch (_) {
          this.config = { ...DEFAULT_UI_CONFIG };
        }
      }
      return this.config;
    },

    save(newConfig) {
      this.config = Object.assign(this.config, newConfig);
      localStorage.setItem('fossil_ui_config', JSON.stringify(this.config));
      this.apply();
    },

    apply() {
      const c = this.config;
      const root = document.documentElement;

      root.setAttribute('data-theme', c.theme);
      root.setAttribute('data-density', c.density);
      root.setAttribute('data-font', c.fontFamily);
      root.setAttribute('data-font-size', c.fontSize);
      root.setAttribute('data-radius', c.radius);

      // Custom color palette application
      if (c.theme === 'custom' && c.customColors) {
        root.style.setProperty('--color-primary', c.customColors.primary);
        root.style.setProperty('--color-primary-hover', c.customColors.primaryHover || c.customColors.primary);
        root.style.setProperty('--color-bg', c.customColors.bg);
        root.style.setProperty('--color-bg-card', c.customColors.bgCard);
        root.style.setProperty('--color-border', c.customColors.border);
        root.style.setProperty('--color-text', c.customColors.text);
      } else {
        root.style.removeProperty('--color-primary');
        root.style.removeProperty('--color-primary-hover');
        root.style.removeProperty('--color-bg');
        root.style.removeProperty('--color-bg-card');
        root.style.removeProperty('--color-border');
        root.style.removeProperty('--color-text');
      }

      const hero = $('browser-hero');
      if (hero) {
        hero.classList.toggle('hidden', !c.showHero);
      }

      window.FossilI18n.setLanguage(c.lang);
    },

    exportConfig() {
      return JSON.stringify(this.config, null, 2);
    },

    importConfig(jsonStr) {
      try {
        const parsed = JSON.parse(jsonStr);
        this.save(parsed);
        return { success: true };
      } catch (err) {
        return { success: false, error: err.message };
      }
    },

    reset() {
      this.config = JSON.parse(JSON.stringify(DEFAULT_UI_CONFIG));
      localStorage.removeItem('fossil_ui_config');
      this.apply();
    }
  };

  // State
  const state = {
    currentTab: 'timeline',
    activeBackend: 'indexeddb',
    activeFile: 'README.md',
    activeWiki: 'Home',
    activeMcpTool: 'vcs_status',
    wikiEditMode: false,
    fileOriginalContent: ''
  };

  // Helper functions
  function $(id) {
    return document.getElementById(id);
  }

  function escapeHtml(str) {
    if (!str) return '';
    return str
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  function showToast(message, type = 'info', duration = 3000) {
    let container = $('toast-container');
    if (!container) {
      container = document.createElement('div');
      container.id = 'toast-container';
      document.body.appendChild(container);
    }
    const toast = document.createElement('div');
    toast.className = 'toast';
    toast.innerText = message;
    container.appendChild(toast);
    setTimeout(() => {
      toast.style.opacity = '0';
      toast.style.transform = 'translateX(100%)';
      toast.style.transition = 'all 0.25s';
      setTimeout(() => toast.remove(), 250);
    }, duration);
  }

  function formatDiffHtml(unifiedDiff) {
    if (!unifiedDiff) return `<div class="empty">${window.FossilI18n.t('diff.identical', 'No differences found (files are identical)')}</div>`;
    const lines = unifiedDiff.split('\n');
    let html = '<div class="diff-view">';
    for (const line of lines) {
      if (line.startsWith('+++') || line.startsWith('---')) {
        html += `<div class="diff-line diff-line-chunk">${escapeHtml(line)}</div>`;
      } else if (line.startsWith('@@')) {
        html += `<div class="diff-line diff-line-chunk">${escapeHtml(line)}</div>`;
      } else if (line.startsWith('+')) {
        html += `<div class="diff-line diff-line-add">${escapeHtml(line)}</div>`;
      } else if (line.startsWith('-')) {
        html += `<div class="diff-line diff-line-del">${escapeHtml(line)}</div>`;
      } else {
        html += `<div class="diff-line">${escapeHtml(line)}</div>`;
      }
    }
    html += '</div>';
    return html;
  }

  // =========================================================================
  // 3. UI Controller Object
  // =========================================================================
  window.FossilBrowserUI = {
    async init() {
      console.log('🦖 Fossil-Nim Browser Edition UI Initializing...');
      
      // Init i18n and Config first
      window.FossilI18n.init();
      window.FossilUIConfig.load();
      window.FossilUIConfig.apply();

      // Initialize Storage
      if (window.FossilStorageManager) {
        await window.FossilStorageManager.init();
      }

      this.bindTabs();
      this.bindStorageSwitcher();
      this.bindTheme();
      this.bindSettingsModal();
      this.bindMobileNavigation();
      this.bindTimelineActions();
      this.bindEditorActions();
      this.bindDiffTool();
      this.bindWikiActions();
      this.bindTicketActions();
      this.bindMcpActions();
      this.bindStorageDiagnostics();

      // Initial Render
      await this.refreshAll();
      window.FossilI18n.applyAll();
      console.log('✅ Fossil-Nim Professional Browser Edition Ready!');
    },

    bindTabs() {
      const tabButtons = document.querySelectorAll('.tab-btn[data-tab]');
      tabButtons.forEach(btn => {
        btn.addEventListener('click', () => {
          const targetTab = btn.getAttribute('data-tab');
          this.switchTab(targetTab);
        });
      });
    },

    switchTab(tabName) {
      state.currentTab = tabName;
      document.querySelectorAll('.tab-btn').forEach(b => {
        b.classList.toggle('active', b.getAttribute('data-tab') === tabName);
      });
      document.querySelectorAll('.tab-content').forEach(c => {
        c.classList.toggle('active', c.id === 'tab-' + tabName);
      });
      if (tabName === 'timeline') this.refreshTimeline();
      else if (tabName === 'files') this.refreshFiles();
      else if (tabName === 'wiki') this.refreshWiki();
      else if (tabName === 'tickets') this.refreshTickets();
    },

    bindStorageSwitcher() {
      const select = $('storage-backend-select');
      if (!select) return;
      select.value = state.activeBackend;
      select.addEventListener('change', async (e) => {
        const newBackend = e.target.value;
        const spinner = $('loading-indicator');
        if (spinner) spinner.classList.remove('hidden');
        try {
          await window.FossilStorageManager.switchBackend(newBackend);
          state.activeBackend = newBackend;
          const activeNameEl = $('active-backend-name');
          if (activeNameEl) activeNameEl.innerText = window.FossilStorageManager.getActiveBackend().name;
          await this.refreshAll();
        } catch (err) {
          alert('Failed to switch storage backend: ' + err.message);
        } finally {
          if (spinner) spinner.classList.add('hidden');
        }
      });
    },

    bindTheme() {
      // Direct quick theme toggle button in navbar
      const toggle = $('theme-toggle-btn');
      if (!toggle) return;

      toggle.addEventListener('click', () => {
        const current = window.FossilUIConfig.config.theme;
        const next = current === 'dark' ? 'light' : 'dark';
        window.FossilUIConfig.save({ theme: next });
        toggle.innerText = next === 'dark' ? '☀️' : '🌙';
      });

      // Quick language toggle button in navbar
      const langToggle = $('btn-lang-toggle');
      if (langToggle) {
        langToggle.addEventListener('click', () => {
          const cur = window.FossilI18n.currentLang;
          const next = cur === 'ru' ? 'en' : 'ru';
          window.FossilUIConfig.save({ lang: next });
        });
      }
    },

    bindMobileNavigation() {
      const menuBtn = $('btn-mobile-menu');
      const navActions = document.querySelector('.navbar-actions');
      if (menuBtn && navActions) {
        menuBtn.addEventListener('click', () => {
          navActions.classList.toggle('open');
        });
      }

      // Mobile file tree toggle in editor
      const toggleTreeBtn = $('btn-toggle-file-tree');
      const fileTree = document.querySelector('.file-tree');
      if (toggleTreeBtn && fileTree) {
        toggleTreeBtn.addEventListener('click', () => {
          fileTree.classList.toggle('collapsed');
        });
      }
    },

    bindSettingsModal() {
      const settingsBtn = $('btn-ui-settings');
      const modal = $('modal-ui-settings');
      const closeBtn = $('btn-settings-close');
      const applyBtn = $('btn-settings-apply');

      if (settingsBtn && modal) {
        settingsBtn.addEventListener('click', () => {
          this.syncSettingsModalInputs();
          modal.classList.remove('hidden');
        });
      }

      if (closeBtn && modal) {
        closeBtn.addEventListener('click', () => modal.classList.add('hidden'));
      }

      // Tab switching inside Settings modal
      const settingsTabBtns = document.querySelectorAll('.settings-tab-btn');
      settingsTabBtns.forEach(b => {
        b.addEventListener('click', () => {
          settingsTabBtns.forEach(x => x.classList.remove('active'));
          b.classList.add('active');
          const tabKey = b.getAttribute('data-tab');
          document.querySelectorAll('.settings-tab-pane').forEach(p => {
            p.classList.toggle('active', p.id === 'settings-pane-' + tabKey);
          });
        });
      });

      // Theme Chips click
      document.querySelectorAll('.theme-chip').forEach(chip => {
        chip.addEventListener('click', () => {
          document.querySelectorAll('.theme-chip').forEach(c => c.classList.remove('active'));
          chip.classList.add('active');
          const themeName = chip.getAttribute('data-theme-name');
          window.FossilUIConfig.save({ theme: themeName });
          const customRow = $('custom-colors-container');
          if (customRow) customRow.classList.toggle('hidden', themeName !== 'custom');
        });
      });

      // Custom Color Inputs live apply
      const bindColorInput = (id, propKey) => {
        const input = $(id);
        if (input) {
          input.addEventListener('input', (e) => {
            const colors = Object.assign({}, window.FossilUIConfig.config.customColors);
            colors[propKey] = e.target.value;
            window.FossilUIConfig.save({ theme: 'custom', customColors: colors });
          });
        }
      };
      bindColorInput('picker-color-primary', 'primary');
      bindColorInput('picker-color-bg', 'bg');
      bindColorInput('picker-color-card', 'bgCard');
      bindColorInput('picker-color-border', 'border');
      bindColorInput('picker-color-text', 'text');

      // Density selection
      const densitySelect = $('select-ui-density');
      if (densitySelect) {
        densitySelect.addEventListener('change', (e) => {
          window.FossilUIConfig.save({ density: e.target.value });
        });
      }

      // Font size selection
      const fontSizeSelect = $('select-ui-fontsize');
      if (fontSizeSelect) {
        fontSizeSelect.addEventListener('change', (e) => {
          window.FossilUIConfig.save({ fontSize: e.target.value });
        });
      }

      // Font family selection
      const fontFamilySelect = $('select-ui-fontfamily');
      if (fontFamilySelect) {
        fontFamilySelect.addEventListener('change', (e) => {
          window.FossilUIConfig.save({ fontFamily: e.target.value });
        });
      }

      // Border radius selection
      const radiusSelect = $('select-ui-radius');
      if (radiusSelect) {
        radiusSelect.addEventListener('change', (e) => {
          window.FossilUIConfig.save({ radius: e.target.value });
        });
      }

      // Show Hero toggle
      const showHeroToggle = $('checkbox-ui-hero');
      if (showHeroToggle) {
        showHeroToggle.addEventListener('change', (e) => {
          window.FossilUIConfig.save({ showHero: e.target.checked });
        });
      }

      // Language selection inside Settings
      const langSelect = $('select-ui-lang');
      if (langSelect) {
        langSelect.addEventListener('change', (e) => {
          window.FossilUIConfig.save({ lang: e.target.value });
          this.syncSettingsModalInputs();
        });
      }

      // Export Language Pack
      const exportLangBtn = $('btn-export-lang-pack');
      if (exportLangBtn) {
        exportLangBtn.addEventListener('click', () => {
          const json = window.FossilI18n.exportLangPack(window.FossilI18n.currentLang);
          const langArea = $('textarea-custom-lang-pack');
          if (langArea) langArea.value = json;
          const blob = new Blob([json], { type: 'application/json' });
          const url = URL.createObjectURL(blob);
          const a = document.createElement('a');
          a.href = url;
          a.download = `lang_${window.FossilI18n.currentLang}.json`;
          a.click();
          URL.revokeObjectURL(url);
          showToast('Language pack exported successfully!');
        });
      }

      // Import Custom Language Pack
      const importLangBtn = $('btn-import-lang-pack');
      if (importLangBtn) {
        importLangBtn.addEventListener('click', () => {
          const langArea = $('textarea-custom-lang-pack');
          if (langArea && langArea.value.trim()) {
            try {
              const pack = JSON.parse(langArea.value.trim());
              window.FossilI18n.importLangPack('custom', pack);
              window.FossilUIConfig.save({ lang: 'custom' });
              showToast('Custom language pack applied!');
            } catch (err) {
              alert('Invalid language pack JSON: ' + err.message);
            }
          }
        });
      }

      // Export UI Config
      const exportConfigBtn = $('btn-export-ui-config');
      if (exportConfigBtn) {
        exportConfigBtn.addEventListener('click', () => {
          const json = window.FossilUIConfig.exportConfig();
          const cfgArea = $('textarea-full-ui-config');
          if (cfgArea) cfgArea.value = json;
          const blob = new Blob([json], { type: 'application/json' });
          const url = URL.createObjectURL(blob);
          const a = document.createElement('a');
          a.href = url;
          a.download = 'fossil_ui_config.json';
          a.click();
          URL.revokeObjectURL(url);
          showToast('UI config exported!');
        });
      }

      // Import UI Config
      const importConfigBtn = $('btn-import-ui-config');
      if (importConfigBtn) {
        importConfigBtn.addEventListener('click', () => {
          const cfgArea = $('textarea-full-ui-config');
          if (cfgArea && cfgArea.value.trim()) {
            const res = window.FossilUIConfig.importConfig(cfgArea.value.trim());
            if (res.success) {
              this.syncSettingsModalInputs();
              showToast(window.FossilI18n.t('notif.saved'));
            } else {
              alert('Error importing UI config: ' + res.error);
            }
          }
        });
      }

      // Reset UI Config
      const resetConfigBtn = $('btn-reset-ui-config');
      if (resetConfigBtn) {
        resetConfigBtn.addEventListener('click', () => {
          if (confirm('Reset UI settings to default?')) {
            window.FossilUIConfig.reset();
            this.syncSettingsModalInputs();
            showToast(window.FossilI18n.t('notif.reset'));
          }
        });
      }

      if (applyBtn && modal) {
        applyBtn.addEventListener('click', () => {
          modal.classList.add('hidden');
          showToast(window.FossilI18n.t('notif.saved'));
        });
      }
    },

    syncSettingsModalInputs() {
      const c = window.FossilUIConfig.config;
      document.querySelectorAll('.theme-chip').forEach(chip => {
        chip.classList.toggle('active', chip.getAttribute('data-theme-name') === c.theme);
      });

      const customContainer = $('custom-colors-container');
      if (customContainer) customContainer.classList.toggle('hidden', c.theme !== 'custom');

      if (c.customColors) {
        if ($('picker-color-primary')) $('picker-color-primary').value = c.customColors.primary || '#3b82f6';
        if ($('picker-color-bg')) $('picker-color-bg').value = c.customColors.bg || '#0b0f19';
        if ($('picker-color-card')) $('picker-color-card').value = c.customColors.bgCard || '#151d2e';
        if ($('picker-color-border')) $('picker-color-border').value = c.customColors.border || '#1e293b';
        if ($('picker-color-text')) $('picker-color-text').value = c.customColors.text || '#f1f5f9';
      }

      if ($('select-ui-density')) $('select-ui-density').value = c.density;
      if ($('select-ui-fontsize')) $('select-ui-fontsize').value = c.fontSize;
      if ($('select-ui-fontfamily')) $('select-ui-fontfamily').value = c.fontFamily;
      if ($('select-ui-radius')) $('select-ui-radius').value = c.radius;
      if ($('checkbox-ui-hero')) $('checkbox-ui-hero').checked = !!c.showHero;
      if ($('select-ui-lang')) $('select-ui-lang').value = c.lang;

      if ($('textarea-full-ui-config')) {
        $('textarea-full-ui-config').value = window.FossilUIConfig.exportConfig();
      }
      if ($('textarea-custom-lang-pack')) {
        $('textarea-custom-lang-pack').value = window.FossilI18n.exportLangPack(c.lang);
      }
    },

    async refreshAll() {
      await Promise.all([
        this.refreshTimeline(),
        this.refreshFiles(),
        this.refreshWiki(),
        this.refreshTickets()
      ]);
    },

    // --- Timeline ---
    bindTimelineActions() {
      const newCommitBtn = $('btn-new-commit-modal');
      const modal = $('modal-commit');
      const closeBtn = $('btn-modal-commit-close');
      const form = $('form-commit');

      if (newCommitBtn && modal) {
        newCommitBtn.addEventListener('click', () => modal.classList.remove('hidden'));
      }
      if (closeBtn && modal) {
        closeBtn.addEventListener('click', () => modal.classList.add('hidden'));
      }
      if (form) {
        form.addEventListener('submit', async (e) => {
          e.preventDefault();
          const comment = $('commit-comment').value.trim();
          const user = $('commit-user').value.trim() || 'admin';
          const branch = $('commit-branch').value.trim() || 'trunk';
          if (!comment) return;

          const res = await window.fossilMcp.callTool('vcs_commit', { comment, user, branch });
          if (res.success) {
            $('commit-comment').value = '';
            modal.classList.add('hidden');
            await this.refreshTimeline();
            showToast('Check-in committed successfully!');
          }
        });
      }
    },

    async refreshTimeline() {
      const list = $('timeline-list');
      if (!list) return;
      const res = await window.fossilMcp.callTool('vcs_timeline', { limit: 20 });
      const timeline = res.timeline || res.events || [];
      if (timeline.length === 0) {
        list.innerHTML = `<div class="empty">${window.FossilI18n.t('timeline.empty')}</div>`;
        return;
      }
      let html = '<div style="display:flex; flex-direction:column; gap:0.75rem;">';
      for (const item of timeline) {
        const d = new Date(item.mtime);
        const timeStr = !isNaN(d.getTime()) ? d.toLocaleString() : String(item.mtime);
        const branchBadge = item.branch ? `<span class="badge badge-primary">${escapeHtml(item.branch)}</span>` : '';
        const idLabel = item.uuid ? item.uuid.substring(0, 10) : (item.id != null ? '#' + item.id : '#ci');
        html += `
          <div class="card" style="padding:0.85rem 1.15rem;">
            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:0.35rem;">
              <div style="display:flex; gap:0.5rem; align-items:center;">
                <b style="font-family:var(--font-mono); font-size:0.9rem; color:var(--color-primary);">${escapeHtml(idLabel)}</b>
                ${branchBadge}
              </div>
              <span style="font-size:0.78rem; color:var(--color-text-muted);">${escapeHtml(timeStr)}</span>
            </div>
            <div style="font-weight:600; font-size:0.95rem; margin-bottom:0.25rem;">${escapeHtml(item.comment)}</div>
            <div style="font-size:0.8rem; color:var(--color-text-secondary);">Author: <b>${escapeHtml(item.user || 'anonymous')}</b></div>
          </div>
        `;
      }
      html += '</div>';
      list.innerHTML = html;
    },

    // --- Files Explorer & Editor ---
    bindEditorActions() {
      const saveBtn = $('btn-editor-save');
      const diffBtn = $('btn-editor-diff');
      const commitBtn = $('btn-editor-commit');
      const newFileBtn = $('btn-new-file');
      const textarea = $('code-editor-text');

      if (saveBtn) {
        saveBtn.addEventListener('click', async () => {
          const content = textarea.value;
          await window.fossilMcp.callTool('vcs_file_write', { path: state.activeFile, content });
          state.fileOriginalContent = content;
          showToast(`File ${state.activeFile} saved!`);
        });
      }

      if (diffBtn) {
        diffBtn.addEventListener('click', () => {
          const current = textarea.value;
          const diffOutput = window.FossilCore.myersDiff(state.fileOriginalContent, current);
          const diffPreview = $('editor-diff-preview');
          if (diffPreview) {
            diffPreview.innerHTML = `
              <div style="margin-bottom:0.5rem; font-weight:600; font-size:0.85rem; color:var(--color-text-secondary);">
                ⚡ Myers Unified Diff Preview (${state.activeFile}):
              </div>
              ${formatDiffHtml(diffOutput)}
            `;
            diffPreview.classList.remove('hidden');
          }
        });
      }

      if (commitBtn) {
        commitBtn.addEventListener('click', async () => {
          const comment = prompt('Enter commit message for file ' + state.activeFile + ':', 'Update ' + state.activeFile);
          if (!comment) return;
          const content = textarea.value;
          await window.fossilMcp.callTool('vcs_file_write', { path: state.activeFile, content });
          state.fileOriginalContent = content;
          const res = await window.fossilMcp.callTool('vcs_commit', { comment, files: [state.activeFile] });
          if (res.success) {
            await this.refreshTimeline();
            showToast(`Committed ${state.activeFile} successfully!`);
          }
        });
      }

      if (newFileBtn) {
        newFileBtn.addEventListener('click', async () => {
          const fileName = prompt('Enter new file name (e.g. src/app.nim):', 'newfile.nim');
          if (!fileName) return;
          await window.fossilMcp.callTool('vcs_file_write', { path: fileName, content: '# New file in Fossil-Nim\n' });
          await this.refreshFiles();
          this.loadFile(fileName);
        });
      }
    },

    async refreshFiles() {
      const tree = $('files-tree');
      if (!tree) return;
      const res = await window.fossilMcp.callTool('vcs_file_list', {});
      const files = res.files || [];
      if (files.length === 0) {
        tree.innerHTML = '<div class="empty">No files in repository</div>';
        return;
      }
      let html = '';
      for (const f of files) {
        const filePath = typeof f === 'string' ? f : (f.path || f.name || String(f));
        const isActive = filePath === state.activeFile;
        html += `
          <div class="file-tree-item ${isActive ? 'active' : ''}" data-file="${escapeHtml(filePath)}">
            <span>📄</span>
            <span>${escapeHtml(filePath)}</span>
          </div>
        `;
      }
      tree.innerHTML = html;

      tree.querySelectorAll('.file-tree-item').forEach(el => {
        el.addEventListener('click', () => {
          const f = el.getAttribute('data-file');
          this.loadFile(f);
        });
      });

      const getFilePath = (item) => typeof item === 'string' ? item : (item.path || item.name || String(item));
      if (!files.some(f => getFilePath(f) === state.activeFile) && files.length > 0) {
        this.loadFile(getFilePath(files[0]));
      } else if (state.activeFile) {
        this.loadFile(state.activeFile);
      }
    },

    async loadFile(filePath) {
      state.activeFile = filePath;
      const label = $('active-file-label');
      if (label) label.innerText = filePath;

      document.querySelectorAll('#files-tree .file-tree-item').forEach(el => {
        el.classList.toggle('active', el.getAttribute('data-file') === filePath);
      });

      const res = await window.fossilMcp.callTool('vcs_file_read', { path: filePath });
      const textarea = $('code-editor-text');
      if (textarea) {
        const text = res.content || '';
        textarea.value = text;
        state.fileOriginalContent = text;
      }
      const diffPreview = $('editor-diff-preview');
      if (diffPreview) diffPreview.classList.add('hidden');
    },

    // --- Myers Diff Tool ---
    bindDiffTool() {
      const runBtn = $('btn-run-standalone-diff');
      const presetSelect = $('diff-preset-select');
      const inputA = $('diff-input-a');
      const inputB = $('diff-input-b');
      const result = $('standalone-diff-result');

      const presets = {
        code: {
          a: "import std/[strutils, tables]\n\nproc processTask(id: int): string =\n  result = \"Task #\" & $id\n  echo \"Starting...\"\n",
          b: "import std/[strutils, tables, os]\n\nproc processTask(id: int): string =\n  result = \"Task #\" & $id & \" [OPTIMIZED]\"\n  echo \"Starting high-speed processing...\"\n  echo \"Completed!\"\n"
        },
        doc: {
          a: "# Architecture Overview\nFossil-Nim is a 100% pure Nim VCS.\nFeatures:\n- Fast Delta Compression\n- Hybrid CDB Storage\n",
          b: "# Architecture Overview\nFossil-Nim is a 100% pure Nim VCS.\nFeatures:\n- Version 2.0 WebAssembly & In-Browser Support!\n- Fast Delta Myers Algorithm\n- Hybrid CDB Storage\n- 89 MCP Tools for AI Agents\n"
        }
      };

      if (presetSelect) {
        presetSelect.addEventListener('change', () => {
          const p = presets[presetSelect.value];
          if (p && inputA && inputB) {
            inputA.value = p.a;
            inputB.value = p.b;
            if (runBtn) runBtn.click();
          }
        });
      }

      if (runBtn && inputA && inputB && result) {
        runBtn.addEventListener('click', () => {
          const t0 = performance.now();
          const diffOutput = window.FossilCore.myersDiff(inputA.value, inputB.value);
          const t1 = performance.now();
          const elapsed = (t1 - t0).toFixed(2);
          result.innerHTML = `
            <div style="margin-bottom:0.5rem; font-size:0.85rem; color:var(--color-text-secondary); display:flex; justify-content:space-between;">
              <b>Myers Diff Output:</b>
              <span class="badge badge-success">Computed in ${elapsed}ms (Nim Engine)</span>
            </div>
            ${formatDiffHtml(diffOutput)}
          `;
        });
      }
    },

    // --- Wiki & Built-in Docs ---
    bindWikiActions() {
      const editBtn = $('btn-wiki-edit');
      const saveBtn = $('btn-wiki-save');
      const newPageBtn = $('btn-wiki-new');
      const cancelBtn = $('btn-wiki-cancel');
      const mdInput = $('wiki-markdown-input');
      const preview = $('wiki-live-preview');

      if (editBtn) {
        editBtn.addEventListener('click', () => {
          state.wikiEditMode = true;
          $('wiki-view-mode').classList.add('hidden');
          $('wiki-edit-mode').classList.remove('hidden');
          if (mdInput) {
            const curText = $('wiki-view-content').innerText;
            mdInput.value = curText;
            if (preview) preview.innerHTML = window.FossilCore.markdownToHtml(curText);
          }
        });
      }

      if (cancelBtn) {
        cancelBtn.addEventListener('click', () => {
          state.wikiEditMode = false;
          $('wiki-view-mode').classList.remove('hidden');
          $('wiki-edit-mode').classList.add('hidden');
        });
      }

      if (mdInput && preview) {
        mdInput.addEventListener('input', () => {
          preview.innerHTML = window.FossilCore.markdownToHtml(mdInput.value);
        });
      }

      if (saveBtn && mdInput) {
        saveBtn.addEventListener('click', async () => {
          const text = mdInput.value;
          await window.fossilMcp.callTool('wiki_create', { name: state.activeWiki, content: text });
          state.wikiEditMode = false;
          $('wiki-view-mode').classList.remove('hidden');
          $('wiki-edit-mode').classList.add('hidden');
          await this.loadWikiPage(state.activeWiki);
          showToast(`Wiki page "${state.activeWiki}" saved!`);
        });
      }

      if (newPageBtn) {
        newPageBtn.addEventListener('click', async () => {
          const name = prompt('Enter new Wiki Page name (e.g. ArchitectureDoc):');
          if (!name) return;
          await window.fossilMcp.callTool('wiki_create', { name, content: `# ${name}\n\nStart writing documentation here.\n` });
          await this.refreshWiki();
          await this.loadWikiPage(name);
        });
      }
    },

    async refreshWiki() {
      const list = $('wiki-pages-list');
      if (!list) return;
      const res = await window.fossilMcp.callTool('wiki_list', {});
      const pages = res.pages || [];
      let html = '';
      for (const p of pages) {
        const isActive = p.name === state.activeWiki;
        html += `
          <div class="file-tree-item ${isActive ? 'active' : ''}" data-wiki="${escapeHtml(p.name)}">
            <span>📖</span>
            <span>${escapeHtml(p.name)}</span>
          </div>
        `;
      }
      list.innerHTML = html;

      list.querySelectorAll('.file-tree-item').forEach(el => {
        el.addEventListener('click', () => {
          const name = el.getAttribute('data-wiki');
          this.loadWikiPage(name);
        });
      });

      if (pages.length > 0 && !pages.some(p => p.name === state.activeWiki)) {
        await this.loadWikiPage(pages[0].name);
      } else if (state.activeWiki) {
        await this.loadWikiPage(state.activeWiki);
      }
    },

    async loadWikiPage(name) {
      state.activeWiki = name;
      const title = $('wiki-view-title');
      if (title) title.innerText = name;

      document.querySelectorAll('#wiki-pages-list .file-tree-item').forEach(el => {
        el.classList.toggle('active', el.getAttribute('data-wiki') === name);
      });

      const res = await window.fossilMcp.callTool('wiki_get', { name });
      const rawText = res.text || '';
      const content = $('wiki-view-content');
      if (content) {
        content.innerHTML = window.FossilCore.markdownToHtml(rawText);
      }
    },

    // --- Tickets ---
    bindTicketActions() {
      const newTktBtn = $('btn-new-ticket-modal');
      const modal = $('modal-ticket');
      const closeBtn = $('btn-modal-ticket-close');
      const form = $('form-ticket');

      if (newTktBtn && modal) {
        newTktBtn.addEventListener('click', () => modal.classList.remove('hidden'));
      }
      if (closeBtn && modal) {
        closeBtn.addEventListener('click', () => modal.classList.add('hidden'));
      }
      if (form) {
        form.addEventListener('submit', async (e) => {
          e.preventDefault();
          const title = $('ticket-title').value.trim();
          const priority = $('ticket-priority').value;
          const desc = $('ticket-desc').value.trim();
          if (!title) return;

          const res = await window.fossilMcp.callTool('ticket_create', { title, priority, desc });
          if (res.success) {
            $('ticket-title').value = '';
            $('ticket-desc').value = '';
            modal.classList.add('hidden');
            await this.refreshTickets();
            showToast('Ticket created successfully!');
          }
        });
      }
    },

    async refreshTickets() {
      const list = $('tickets-list');
      if (!list) return;
      const res = await window.fossilMcp.callTool('ticket_list', {});
      const tickets = res.tickets || [];
      if (tickets.length === 0) {
        list.innerHTML = `<div class="empty">${window.FossilI18n.t('tickets.empty')}</div>`;
        return;
      }
      let html = '<div style="display:flex; flex-direction:column; gap:0.75rem;">';
      for (const t of tickets) {
        const badgeClass = t.priority === 'Critical' ? 'badge-danger' : (t.priority === 'High' ? 'badge-warning' : 'badge-info');
        html += `
          <div class="card" style="padding:1rem;">
            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:0.4rem;">
              <div style="display:flex; gap:0.5rem; align-items:center;">
                <span class="badge ${badgeClass}">${escapeHtml(t.priority || 'Medium')}</span>
                <b style="font-size:1rem;">${escapeHtml(t.title)}</b>
              </div>
              <span class="badge badge-secondary">${escapeHtml(t.status || 'Open')}</span>
            </div>
            <p style="margin:0; font-size:0.88rem; color:var(--color-text-secondary);">${escapeHtml(t.desc || 'No description provided')}</p>
          </div>
        `;
      }
      html += '</div>';
      list.innerHTML = html;
    },

    // --- MCP Tools Console ---
    bindMcpActions() {
      const list = $('mcp-tools-list');
      if (!list) return;

      const serverInfo = window.fossilMcp.listTools();
      const tools = serverInfo.tools;

      let html = '';
      for (const tool of tools) {
        const isActive = tool.name === state.activeMcpTool;
        html += `
          <div class="mcp-tool-item ${isActive ? 'active' : ''}" data-tool="${escapeHtml(tool.name)}">
            <b>${escapeHtml(tool.name)}</b>
          </div>
        `;
      }
      list.innerHTML = html;

      list.querySelectorAll('.mcp-tool-item').forEach(item => {
        item.addEventListener('click', () => {
          const toolName = item.getAttribute('data-tool');
          this.selectMcpTool(toolName);
        });
      });

      this.selectMcpTool(state.activeMcpTool);

      const runBtn = $('btn-mcp-invoke');
      const outputEl = $('mcp-output-json');
      const copyPromptBtn = $('btn-copy-mcp-prompt');

      if (runBtn && outputEl) {
        runBtn.addEventListener('click', async () => {
          outputEl.innerText = 'Calling tool...';
          const toolName = state.activeMcpTool;
          let params = {};
          try {
            params = JSON.parse($('mcp-params-input').value || '{}');
          } catch (e) {
            outputEl.innerText = 'JSON Parse Error: ' + e.message;
            return;
          }
          const res = await window.fossilMcp.callTool(toolName, params);
          outputEl.innerText = JSON.stringify(res, null, 2);
        });
      }

      if (copyPromptBtn) {
        copyPromptBtn.addEventListener('click', () => {
          const promptText = `You are connected to Fossil-Nim In-Browser Distributed VCS via Model Context Protocol.\nAvailable MCP Tools: 89.\nActive Storage Backend: ${window.FossilStorageManager.backendType}.\nSupported Endpoints: window.fossilMcp.callTool(name, params).`;
          navigator.clipboard.writeText(promptText).then(() => {
            showToast('Agent prompt copied to clipboard!');
          });
        });
      }
    },

    selectMcpTool(toolName) {
      state.activeMcpTool = toolName;
      document.querySelectorAll('.mcp-tool-item').forEach(el => {
        el.classList.toggle('active', el.getAttribute('data-tool') === toolName);
      });

      const serverInfo = window.fossilMcp.listTools();
      const tool = serverInfo.tools.find(t => t.name === toolName) || { name: toolName, description: 'Tool' };

      const nameEl = $('mcp-active-tool-name');
      const descEl = $('mcp-active-tool-desc');
      const paramsEl = $('mcp-params-input');

      if (nameEl) nameEl.innerText = tool.name;
      if (descEl) descEl.innerText = tool.description || 'No description';

      let sampleParams = {};
      if (tool.parameters) {
        for (const [key, type] of Object.entries(tool.parameters)) {
          if (key === 'path') sampleParams[key] = 'README.md';
          else if (key === 'message' || key === 'comment') sampleParams[key] = 'Commit message';
          else if (key === 'limit') sampleParams[key] = 10;
          else if (key === 'name') sampleParams[key] = 'Home';
          else if (key === 'backend') sampleParams[key] = 'indexeddb';
          else sampleParams[key] = 'value';
        }
      }
      if (paramsEl) paramsEl.value = JSON.stringify(sampleParams, null, 2);
    },

    // --- Storage Diagnostics & Snapshot Import/Export ---
    bindStorageDiagnostics() {
      const exportBtn = $('btn-export-repo');
      const runSqlBtn = $('btn-run-sql');
      const sqlInput = $('sql-query-input');
      const sqlResult = $('sql-query-output');

      if (exportBtn) {
        exportBtn.addEventListener('click', async () => {
          const mgr = window.FossilStorageManager;
          const exp = await mgr.exportRepo();
          let blob;
          if (exp.type === 'binary') {
            blob = new Blob([exp.data], { type: exp.mimeType });
          } else if (exp.type === 'json') {
            blob = new Blob([JSON.stringify(exp.data, null, 2)], { type: exp.mimeType });
          } else {
            blob = new Blob([exp.data], { type: exp.mimeType });
          }
          const url = URL.createObjectURL(blob);
          const a = document.createElement('a');
          a.href = url;
          a.download = exp.filename;
          a.click();
          URL.revokeObjectURL(url);
          showToast(`Repository exported as ${exp.filename}`);
        });
      }

      // Repository Import Handling with Smart Conflict Modal
      const importBtn = $('btn-import-repo');
      const fileInput = $('file-import-input');
      const importModal = $('modal-import-confirm');
      const importConfirmBtn = $('btn-import-confirm-execute');
      const importCancelBtn = $('btn-import-cancel');
      const importAbortBtn = $('btn-import-abort');

      let pendingImportData = null;
      let pendingImportFile = null;

      const closeImportModal = () => {
        if (importModal) importModal.classList.add('hidden');
        pendingImportData = null;
        pendingImportFile = null;
      };

      const executeImport = async (chosenMode) => {
        if (!pendingImportData || !pendingImportFile) return;
        const spinner = $('loading-indicator');
        if (spinner) spinner.classList.remove('hidden');
        try {
          const t0 = performance.now();
          const mgr = window.FossilStorageManager;
          const res = await mgr.importRepo(pendingImportData, pendingImportFile.name, chosenMode);
          const t1 = performance.now();
          const elapsed = (t1 - t0).toFixed(1);
          closeImportModal();
          await this.refreshAll();
          showToast(`Successfully imported ${pendingImportFile.name} in ${chosenMode} mode (${elapsed}ms)!`);
        } catch (err) {
          alert('Import failed: ' + err.message);
        } finally {
          if (spinner) spinner.classList.add('hidden');
        }
      };

      if (importBtn && fileInput) {
        importBtn.addEventListener('click', () => {
          fileInput.value = '';
          fileInput.click();
        });
      }

      if (fileInput) {
        fileInput.addEventListener('change', async (e) => {
          const file = e.target.files && e.target.files[0];
          if (!file) return;

          const reader = new FileReader();
          const isBinary = file.name.endsWith('.fossil');

          reader.onload = async (ev) => {
            pendingImportFile = file;
            pendingImportData = isBinary ? new Uint8Array(ev.target.result) : ev.target.result;

            const mgr = window.FossilStorageManager;
            const hasData = await mgr.hasExistingData();

            if (hasData && importModal) {
              const nameLabel = $('import-filename-label');
              const metaLabel = $('import-meta-label');
              if (nameLabel) nameLabel.innerText = `${file.name} (${(file.size / 1024).toFixed(1)} KB)`;
              if (metaLabel) metaLabel.innerText = isBinary ? 'Binary SQLite (.fossil) repository database' : (file.name.endsWith('.cdb') ? 'Pure-Nim Constant DB (.cdb)' : 'Fossil-Nim JSON Repository Bundle');
              importModal.classList.remove('hidden');
            } else {
              await executeImport('replace');
            }
          };

          if (isBinary) {
            reader.readAsArrayBuffer(file);
          } else {
            reader.readAsText(file);
          }
        });
      }

      if (importCancelBtn) importCancelBtn.addEventListener('click', closeImportModal);
      if (importAbortBtn) importAbortBtn.addEventListener('click', closeImportModal);

      if (importConfirmBtn) {
        importConfirmBtn.addEventListener('click', async () => {
          const modeRadio = document.querySelector('input[name="import-mode-choice"]:checked');
          const chosenMode = modeRadio ? modeRadio.value : 'merge';
          await executeImport(chosenMode);
        });
      }

      if (runSqlBtn && sqlInput && sqlResult) {
        runSqlBtn.addEventListener('click', async () => {
          const q = sqlInput.value.trim();
          if (!q) return;
          const res = await window.fossilMcp.callTool('sql_query', { query: q });
          if (res.error) {
            sqlResult.innerHTML = `<div class="error">${escapeHtml(res.error)}</div>`;
          } else {
            const rows = res.rows || [];
            if (rows.length === 0) {
              sqlResult.innerHTML = '<div class="empty">Query executed successfully (0 rows returned).</div>';
              return;
            }
            const keys = Object.keys(rows[0]);
            let table = '<table class="table" style="width:100%; border-collapse:collapse; margin-top:0.5rem;"><thead><tr style="border-bottom:2px solid var(--color-border);">';
            for (const k of keys) table += `<th style="padding:0.5rem; text-align:left;">${escapeHtml(k)}</th>`;
            table += '</tr></thead><tbody>';
            for (const r of rows) {
              table += '<tr style="border-bottom:1px solid var(--color-border);">';
              for (const k of keys) table += `<td style="padding:0.5rem;">${escapeHtml(String(r[k]))}</td>`;
              table += '</tr>';
            }
            table += '</tbody></table>';
            sqlResult.innerHTML = table;
          }
        });
      }
    }
  };

  // Auto-init on DOMContentLoaded
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => window.FossilBrowserUI.init());
  } else {
    window.FossilBrowserUI.init();
  }
})();
