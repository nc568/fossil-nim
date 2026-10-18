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
      "tab.timeline": "Таймлайн",
      "tab.files": "Файлы и редактор",
      "tab.diff": "Myers Diff",
      "tab.wiki": "Wiki и документация",
      "tab.tickets": "Тикеты",
      "tab.mcp": "ИИ-агент MCP (89)",
      "tab.storage": "Мульти-БД диагностика",
      "tab.about": "О проекте",
      "sidebar.workspace": "Рабочая область",
      "sidebar.info": "Информация",
      "sidebar.collapse": "Свернуть панель",
      "sidebar.expand": "Развернуть панель",
      "about.title": "О проекте Fossil-Nim",
      "about.desc": "Архитектура, динамические переменные среды и спецификации",
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
      "tab.timeline": "Timeline",
      "tab.files": "Files & Editor",
      "tab.diff": "Myers Diff",
      "tab.wiki": "Wiki & Docs",
      "tab.tickets": "Tickets",
      "tab.mcp": "AI Agent MCP (89)",
      "tab.storage": "Multi-DB Diagnostics",
      "tab.about": "About Project",
      "sidebar.workspace": "Workspace",
      "sidebar.info": "Information",
      "sidebar.collapse": "Collapse sidebar",
      "sidebar.expand": "Expand sidebar",
      "about.title": "About Fossil-Nim",
      "about.desc": "Architecture, dynamic environment variables and specifications",
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
        let translation = this.t(key, el.innerText);
        if (el.classList.contains('sidebar-text') && el.previousElementSibling && el.previousElementSibling.classList.contains('sidebar-icon')) {
          translation = translation.replace(/^[\p{Extended_Pictographic}\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}\s]+/u, '').trim();
        }
        el.innerText = translation;
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
    mcpCategoryFilter: 'all',
    wikiEditMode: false,
    fileOriginalContent: '',
    ticketFilter: 'all',
    ticketPriorityFilter: 'all',
    calendarMonth: new Date().getMonth(),
    calendarYear: new Date().getFullYear(),
    calendarDate: new Date()
  };

  // Helper functions
  function $(id) {
    return document.getElementById(id);
  }

  function escapeHtml(str) {
    if (str === null || str === undefined) return '';
    return String(str)
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

  function computeMyersDiff(textA, textB, fileName) {
    const a = textA || '';
    const b = textB || '';
    const fn = fileName || 'diff';
    if (window.FossilCore) {
      if (typeof window.FossilCore.myersDiff === 'function') {
        try { return window.FossilCore.myersDiff(a, b, fn); } catch (e) { console.warn("Myers diff error:", e); }
      }
      if (typeof window.FossilCore.diffUnified === 'function') {
        try { return window.FossilCore.diffUnified(a, b, fn); } catch (e) { console.warn("diffUnified error:", e); }
      }
    }
    const aLines = a.split('\n');
    const bLines = b.split('\n');
    const out = ['--- a/' + fn, '+++ b/' + fn, '@@ -1,' + aLines.length + ' +1,' + bLines.length + ' @@'];
    const max = Math.max(aLines.length, bLines.length);
    for (let i = 0; i < max; i++) {
      if (aLines[i] === bLines[i]) {
        out.push(' ' + (aLines[i] !== undefined ? aLines[i] : ''));
      } else {
        if (aLines[i] !== undefined) out.push('-' + aLines[i]);
        if (bLines[i] !== undefined) out.push('+' + bLines[i]);
      }
    }
    return out.join('\n');
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

      this.bindSidebar();
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
      this.bindCalendarActions();
      this.bindPullRequestActions();
      this.bindMcpActions();
      this.bindStorageDiagnostics();

      // Initial Render & Dynamic Variables
      this.updateDynamicStatus();
      await this.refreshAll();
      this.updateDynamicStatus();
      window.FossilI18n.applyAll();
      console.log('✅ Fossil-Nim Professional Browser Edition Ready!');
    },

    detectRuntime() {
      const isBrowser = typeof window !== 'undefined';
      const hasWasm = typeof WebAssembly === 'object' && typeof WebAssembly.validate === 'function';
      const hasIDB = typeof indexedDB !== 'undefined';
      const isNimJs = !!(window.FossilCore && window.FossilCore.diffUnified);
      const version = (window.FossilCore && window.FossilCore.version) || '2.26.0';

      return {
        isBrowser,
        hasWasm,
        hasIDB,
        isNimJs,
        version,
        engineName: 'Nim 2.0 (JS/WASM transpile)',
        runtimeType: 'Browser JS / WASM'
      };
    },

    updateDynamicStatus() {
      const runtime = this.detectRuntime();
      const versionEl = $('dyn-version-label');
      const runtimeEl = $('dyn-runtime-label');
      const verStr = String(runtime.version || '2.26.0').replace(/^v+/, 'v');
      if (versionEl) versionEl.innerText = verStr;
      if (runtimeEl) runtimeEl.innerText = runtime.runtimeType;

      const mgr = window.FossilStorageManager;
      const activeBackend = mgr ? mgr.backendType : (state.activeBackend || 'indexeddb');
      state.activeBackend = activeBackend;

      const backendNames = {
        indexeddb: 'IndexedDB (Native)',
        sqlite_wasm: 'SQLite WASM (.fossil)',
        cdb: 'Pure-Nim CDB (RAM)'
      };
      const backendLabel = backendNames[activeBackend] || activeBackend;

      const backendEl = $('dyn-backend-label');
      if (backendEl) backendEl.innerText = backendLabel;

      const activeNameEl = $('active-backend-name');
      if (activeNameEl) activeNameEl.innerText = backendLabel;

      const aboutDbBadge = $('about-db-badge');
      if (aboutDbBadge) aboutDbBadge.innerText = `Active DB: ${backendLabel}`;

      const toolCount = (window.fossilMcp && Array.isArray(window.fossilMcp.tools)) ? window.fossilMcp.tools.length : 89;

      const dynMcpCount = $('dyn-mcp-count');
      if (dynMcpCount) dynMcpCount.innerText = toolCount;

      const sidebarMcpBadge = $('sidebar-mcp-badge');
      if (sidebarMcpBadge) sidebarMcpBadge.innerText = toolCount;

      const aboutMcpCount = $('about-mcp-count');
      if (aboutMcpCount) aboutMcpCount.innerText = toolCount;

      const aboutDynMcpTotal = $('about-dyn-mcp-total');
      if (aboutDynMcpTotal) aboutDynMcpTotal.innerText = `${toolCount} Tools (Registered)`;

      const aboutDynVersion = $('about-dyn-version');
      if (aboutDynVersion) aboutDynVersion.innerText = `Fossil-Nim ${verStr}`;

      const aboutDynTarget = $('about-dyn-target');
      if (aboutDynTarget) aboutDynTarget.innerText = runtime.engineName;

      const aboutDynDb = $('about-dyn-db');
      if (aboutDynDb) aboutDynDb.innerText = backendLabel;

      const aboutDynWasm = $('about-dyn-wasm');
      if (aboutDynWasm) aboutDynWasm.innerText = runtime.hasWasm ? 'Supported (WebAssembly Ready)' : 'Not Available';

      const aboutDynUa = $('about-dyn-ua');
      if (aboutDynUa && typeof navigator !== 'undefined') {
        aboutDynUa.innerText = navigator.userAgent;
      }
    },

    bindSidebar() {
      const app = $('app');
      const collapseBtn = $('btn-sidebar-collapse');
      const toggleBtn = $('btn-sidebar-toggle');
      const backdrop = $('sidebar-backdrop');

      const isCollapsed = localStorage.getItem('fossil_sidebar_collapsed') === 'true';
      if (isCollapsed && app) {
        app.classList.add('sidebar-collapsed');
      }

      const toggleCollapse = () => {
        if (!app) return;
        if (window.innerWidth <= 900) {
          app.classList.toggle('sidebar-open');
        } else {
          const next = !app.classList.contains('sidebar-collapsed');
          app.classList.toggle('sidebar-collapsed', next);
          localStorage.setItem('fossil_sidebar_collapsed', String(next));
        }
      };

      if (collapseBtn) collapseBtn.addEventListener('click', toggleCollapse);
      if (toggleBtn) toggleBtn.addEventListener('click', toggleCollapse);

      if (backdrop) backdrop.addEventListener('click', () => {
        if (app) app.classList.remove('sidebar-open');
      });
    },

    bindTabs() {
      const tabButtons = document.querySelectorAll('.tab-btn[data-tab], .sidebar-link[data-tab]');
      tabButtons.forEach(btn => {
        btn.addEventListener('click', () => {
          const targetTab = btn.getAttribute('data-tab');
          this.switchTab(targetTab);
        });
      });
    },

    switchTab(tabName) {
      state.currentTab = tabName;
      document.querySelectorAll('.tab-btn, .sidebar-link').forEach(b => {
        b.classList.toggle('active', b.getAttribute('data-tab') === tabName);
      });
      document.querySelectorAll('.tab-content').forEach(c => {
        c.classList.toggle('active', c.id === 'tab-' + tabName);
      });
      const app = $('app');
      if (app && app.classList.contains('sidebar-open')) {
        app.classList.remove('sidebar-open');
      }
      if (tabName === 'timeline') this.refreshTimeline();
      else if (tabName === 'files') this.refreshFiles();
      else if (tabName === 'wiki') this.refreshWiki();
      else if (tabName === 'tickets') this.refreshTickets();
      else if (tabName === 'calendar') this.refreshCalendar();
      else if (tabName === 'about') this.updateDynamicStatus();
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
          this.updateDynamicStatus();
          await this.refreshAll();
          this.updateDynamicStatus();
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
        menuBtn.addEventListener('click', (e) => {
          e.stopPropagation();
          navActions.classList.toggle('open');
        });
        document.addEventListener('click', (e) => {
          if (!navActions.contains(e.target) && e.target !== menuBtn) {
            navActions.classList.remove('open');
          }
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
        this.refreshTickets(),
        this.refreshCalendar(),
        this.refreshMcpList()
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
          const diffOutput = computeMyersDiff(state.fileOriginalContent, current, state.activeFile);
          const diffPreview = $('editor-diff-preview');
          if (diffPreview) {
            diffPreview.innerHTML = `
              <div style="margin-bottom:0.5rem; font-weight:600; font-size:0.85rem; color:var(--color-text-secondary); display:flex; justify-content:space-between; align-items:center;">
                <span>⚡ Myers Unified Diff Preview (${escapeHtml(state.activeFile)}):</span>
                <button id="btn-close-diff-preview" class="btn btn-secondary btn-sm" style="padding:0.15rem 0.5rem; font-size:0.75rem;">✕ Закрыть Diff</button>
              </div>
              ${formatDiffHtml(diffOutput)}
            `;
            diffPreview.classList.remove('hidden');
            const closeBtn = $('btn-close-diff-preview');
            if (closeBtn) closeBtn.onclick = () => diffPreview.classList.add('hidden');
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
          const diffOutput = computeMyersDiff(inputA.value, inputB.value, 'sample.nim');
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

    // --- Tickets Overhaul & Actions ---
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
          const deadline = $('ticket-deadline') ? $('ticket-deadline').value : '';
          const desc = $('ticket-desc').value.trim();
          if (!title) return;

          const res = await window.fossilMcp.callTool('ticket_create', { title, priority, deadline, desc });
          if (res.success) {
            $('ticket-title').value = '';
            $('ticket-desc').value = '';
            if ($('ticket-deadline')) $('ticket-deadline').value = '';
            modal.classList.add('hidden');
            await this.refreshTickets();
            await this.refreshCalendar();
            showToast('Тикет успешно создан!');
          }
        });
      }

      // Filter bar buttons
      document.querySelectorAll('.ticket-filter-btn').forEach(btn => {
        btn.addEventListener('click', () => {
          document.querySelectorAll('.ticket-filter-btn').forEach(b => b.classList.remove('active'));
          btn.classList.add('active');
          state.ticketFilter = btn.getAttribute('data-filter') || 'all';
          this.refreshTickets();
        });
      });

      // Priority filter dropdown
      const prioritySelect = $('select-ticket-priority-filter');
      if (prioritySelect) {
        prioritySelect.addEventListener('change', (e) => {
          state.ticketPriorityFilter = e.target.value;
          this.refreshTickets();
        });
      }

      // Edit Modal Actions
      const editModal = $('modal-ticket-edit');
      const editCloseBtn = $('btn-modal-ticket-edit-close');
      const editCancelBtn = $('btn-modal-ticket-edit-cancel');
      const editForm = $('form-ticket-edit');
      const deleteBtn = $('btn-ticket-delete-action');

      if (editCloseBtn && editModal) editCloseBtn.addEventListener('click', () => editModal.classList.add('hidden'));
      if (editCancelBtn && editModal) editCancelBtn.addEventListener('click', () => editModal.classList.add('hidden'));

      if (editForm) {
        editForm.addEventListener('submit', async (e) => {
          e.preventDefault();
          const id = $('ticket-edit-id').value;
          const title = $('ticket-edit-title').value.trim();
          const priority = $('ticket-edit-priority').value;
          const status = $('ticket-edit-status').value;
          const deadline = $('ticket-edit-deadline').value;
          const desc = $('ticket-edit-desc').value.trim();

          const res = await window.fossilMcp.callTool('ticket_update', { id, title, priority, status, deadline, desc });
          if (res.success) {
            editModal.classList.add('hidden');
            await this.refreshTickets();
            await this.refreshCalendar();
            showToast('Изменения сохранены!');
          }
        });
      }

      if (deleteBtn) {
        deleteBtn.addEventListener('click', async () => {
          const id = $('ticket-edit-id').value;
          if (confirm(`Вы уверены, что хотите удалить тикет #${id}?`)) {
            await window.fossilMcp.callTool('ticket_delete', { id });
            if (editModal) editModal.classList.add('hidden');
            await this.refreshTickets();
            await this.refreshCalendar();
            showToast('Тикет удален!');
          }
        });
      }

      // Link PR button inside Edit Modal
      const linkPrBtn = $('btn-ticket-link-new-pr');
      if (linkPrBtn) {
        linkPrBtn.addEventListener('click', () => {
          const id = $('ticket-edit-id').value;
          if (editModal) editModal.classList.add('hidden');
          this.openPrModal(id);
        });
      }

      // History Modal Close Actions
      const histModal = $('modal-ticket-history');
      const histCloseBtn = $('btn-modal-ticket-history-close');
      const histOkBtn = $('btn-modal-ticket-history-ok');
      if (histCloseBtn && histModal) histCloseBtn.addEventListener('click', () => histModal.classList.add('hidden'));
      if (histOkBtn && histModal) histOkBtn.addEventListener('click', () => histModal.classList.add('hidden'));
    },

    async openTicketEditModal(id) {
      const modal = $('modal-ticket-edit');
      if (!modal) return;
      const res = await window.fossilMcp.callTool('ticket_get', { id });
      const t = res.ticket;
      if (!t) return;

      $('ticket-edit-id').value = t.id;
      const idBadge = $('ticket-edit-id-badge');
      if (idBadge) idBadge.innerText = t.id;
      $('ticket-edit-title').value = t.title || '';
      $('ticket-edit-priority').value = t.priority || 'Medium';
      $('ticket-edit-status').value = t.status || 'Open';
      $('ticket-edit-desc').value = t.desc || '';

      const deadlineInput = $('ticket-edit-deadline');
      if (deadlineInput) {
        if (t.deadline && Number(t.deadline) > 0) {
          const d = new Date(Number(t.deadline));
          const yyyy = d.getFullYear();
          const mm = String(d.getMonth() + 1).padStart(2, '0');
          const dd = String(d.getDate()).padStart(2, '0');
          deadlineInput.value = `${yyyy}-${mm}-${dd}`;
        } else {
          deadlineInput.value = '';
        }
      }

      // Render Linked PRs
      const prsContainer = $('ticket-edit-linked-prs');
      if (prsContainer) {
        const prListRes = await window.fossilMcp.callTool('pr_list', { ticketId: t.id });
        const prs = prListRes.pullRequests || [];
        if (prs.length === 0) {
          prsContainer.innerHTML = '<span style="font-size:0.82rem; color:var(--color-text-muted);">Нет привязанных Pull Requests.</span>';
        } else {
          let prHtml = '';
          for (const pr of prs) {
            const isMerged = (pr.status || '').toLowerCase() === 'merged';
            prHtml += `
              <div style="display:flex; justify-content:space-between; align-items:center; padding:0.4rem 0.6rem; background:var(--color-bg); border:1px solid var(--color-border); border-radius:4px; font-size:0.82rem;">
                <div style="display:flex; gap:0.4rem; align-items:center;">
                  <span class="badge ${isMerged ? 'badge-primary' : 'badge-success'}">${escapeHtml(pr.id)}</span>
                  <b>${escapeHtml(pr.title)}</b>
                  <span style="color:var(--color-text-muted); font-family:var(--font-mono); font-size:0.75rem;">(${escapeHtml(pr.sourceBranch)} ➔ ${escapeHtml(pr.targetBranch)})</span>
                </div>
                ${!isMerged ? `<button type="button" class="btn btn-primary btn-sm btn-merge-pr" data-pr="${escapeHtml(pr.id)}" style="font-size:0.75rem; padding:0.15rem 0.45rem;">🔀 Merge</button>` : '<span class="badge badge-secondary">Merged ✓</span>'}
              </div>
            `;
          }
          prsContainer.innerHTML = prHtml;
          prsContainer.querySelectorAll('.btn-merge-pr').forEach(btn => {
            btn.addEventListener('click', async () => {
              const prId = btn.getAttribute('data-pr');
              await window.fossilMcp.callTool('pr_merge', { id: prId });
              showToast(`Pull Request ${prId} смерджен в ветку trunk!`);
              this.openTicketEditModal(t.id);
              await this.refreshTickets();
              await this.refreshCalendar();
            });
          });
        }
      }

      modal.classList.remove('hidden');
    },

    async openTicketHistoryModal(id) {
      const modal = $('modal-ticket-history');
      if (!modal) return;
      const res = await window.fossilMcp.callTool('ticket_get', { id });
      const t = res.ticket;
      if (!t) return;

      const badge = $('ticket-history-id-badge');
      if (badge) badge.innerText = t.id;
      const titleRow = $('ticket-history-title-row');
      if (titleRow) titleRow.innerText = t.title;

      const list = $('ticket-history-list');
      if (list) {
        const history = t.history || [];
        if (history.length === 0) {
          list.innerHTML = '<div style="color:var(--color-text-muted); font-size:0.85rem;">Нет записей в истории изменений.</div>';
        } else {
          let html = '';
          for (const item of history) {
            const timeStr = item.timestamp ? new Date(item.timestamp).toLocaleString() : '';
            html += `
              <div class="history-item">
                <div class="history-dot"></div>
                <div class="history-time">${escapeHtml(timeStr)} • <b>${escapeHtml(item.user || 'system')}</b></div>
                <div class="history-action">${escapeHtml(item.action || 'update')}</div>
                <div class="history-detail">${escapeHtml(item.detail || '')}</div>
              </div>
            `;
          }
          list.innerHTML = html;
        }
      }
      modal.classList.remove('hidden');
    },

    async refreshTickets() {
      const list = $('tickets-list');
      if (!list) return;

      const allRes = await window.fossilMcp.callTool('ticket_list', { status: 'all' });
      const allTickets = allRes.tickets || [];

      // Update counters
      const cntAll = $('tkt-cnt-all');
      const cntOpen = $('tkt-cnt-open');
      const cntClosed = $('tkt-cnt-closed');
      const openCount = allTickets.filter(t => (t.status || 'Open').toLowerCase() !== 'closed').length;
      const closedCount = allTickets.filter(t => (t.status || 'Open').toLowerCase() === 'closed').length;
      if (cntAll) cntAll.innerText = allTickets.length;
      if (cntOpen) cntOpen.innerText = openCount;
      if (cntClosed) cntClosed.innerText = closedCount;

      // Filter tickets
      let filtered = allTickets;
      if (state.ticketFilter === 'open') {
        filtered = filtered.filter(t => (t.status || 'Open').toLowerCase() !== 'closed');
      } else if (state.ticketFilter === 'closed') {
        filtered = filtered.filter(t => (t.status || 'Open').toLowerCase() === 'closed');
      }

      if (state.ticketPriorityFilter && state.ticketPriorityFilter !== 'all') {
        filtered = filtered.filter(t => (t.priority || '').toLowerCase() === state.ticketPriorityFilter.toLowerCase());
      }

      if (filtered.length === 0) {
        list.innerHTML = `<div class="empty">${window.FossilI18n.t('tickets.empty', 'No tickets found matching the selected filter.')}</div>`;
        return;
      }

      const now = Date.now();
      let html = '<div style="display:flex; flex-direction:column; gap:0.75rem;">';

      for (const t of filtered) {
        const priority = t.priority || 'Medium';
        const priorityClass = `priority-${priority.toLowerCase()}`;
        const isClosed = (t.status || 'Open').toLowerCase() === 'closed';

        // Deadline computation
        let deadlineHtml = '';
        if (t.deadline && Number(t.deadline) > 0) {
          const d = new Date(Number(t.deadline));
          const diffDays = Math.ceil((Number(t.deadline) - now) / (24 * 60 * 60 * 1000));
          if (diffDays < 0 && !isClosed) {
            deadlineHtml = `<span class="badge-overdue">⚠️ Просрочено на ${Math.abs(diffDays)} дн. (${d.toLocaleDateString()})</span>`;
          } else {
            deadlineHtml = `<span class="badge badge-secondary" style="font-size:0.75rem;">📅 Дедлайн: ${d.toLocaleDateString()} (${diffDays >= 0 ? 'осталось ' + diffDays + ' дн.' : 'завершено'})</span>`;
          }
        } else {
          deadlineHtml = `<span class="badge badge-secondary" style="opacity:0.7; font-size:0.75rem;">📋 В бэклоге (без дедлайна)</span>`;
        }

        // Linked PRs badges
        let prsHtml = '';
        if (t.linkedPrs && t.linkedPrs.length > 0) {
          prsHtml = t.linkedPrs.map(prId => `<span class="pr-badge" data-pr="${escapeHtml(prId)}">🔀 ${escapeHtml(prId)}</span>`).join(' ');
        }

        html += `
          <div class="ticket-card ${priorityClass}" data-id="${escapeHtml(t.id)}">
            <div style="display:flex; justify-content:space-between; align-items:flex-start; margin-bottom:0.4rem; flex-wrap:wrap; gap:0.5rem;">
              <div style="display:flex; gap:0.5rem; align-items:center; flex-wrap:wrap;">
                <span class="badge ${priorityClass}">${escapeHtml(priority)}</span>
                <b style="font-size:1.02rem; color:var(--color-text);">${escapeHtml(t.title)}</b>
                <span style="font-size:0.78rem; font-family:var(--font-mono); color:var(--color-text-muted);">#${escapeHtml(t.id)}</span>
              </div>
              <div style="display:flex; gap:0.4rem; align-items:center; flex-wrap:wrap;">
                ${deadlineHtml}
                <span class="badge ${isClosed ? 'badge-secondary' : 'badge-primary'}">${escapeHtml(t.status || 'Open')}</span>
              </div>
            </div>

            <p style="margin:0 0 0.5rem 0; font-size:0.88rem; color:var(--color-text-secondary); line-height:1.5;">
              ${escapeHtml(t.desc || 'Описание отсутствует')}
            </p>

            ${prsHtml ? `<div style="margin-bottom:0.5rem; display:flex; gap:0.35rem; align-items:center; flex-wrap:wrap;"><span style="font-size:0.78rem; color:var(--color-text-muted);">Pull Requests:</span> ${prsHtml}</div>` : ''}

            <div class="ticket-actions-row">
              <button class="btn btn-secondary btn-sm btn-ticket-action" data-action="edit" data-id="${escapeHtml(t.id)}">✏️ Редактировать</button>
              ${!isClosed ?
                `<button class="btn btn-secondary btn-sm btn-ticket-action" data-action="close" data-id="${escapeHtml(t.id)}">✓ Завершить</button>` :
                `<button class="btn btn-secondary btn-sm btn-ticket-action" data-action="reopen" data-id="${escapeHtml(t.id)}">🔄 Открыть снова</button>`
              }
              <button class="btn btn-secondary btn-sm btn-ticket-action" data-action="history" data-id="${escapeHtml(t.id)}">📜 История (${(t.history || []).length})</button>
              <button class="btn btn-secondary btn-sm btn-ticket-action" data-action="pr" data-id="${escapeHtml(t.id)}">🔀 Pull Request</button>
              <button class="btn btn-secondary btn-sm btn-ticket-action" data-action="delete" data-id="${escapeHtml(t.id)}" style="margin-left:auto; color:var(--color-danger);">🗑️ Удалить</button>
            </div>
          </div>
        `;
      }
      html += '</div>';
      list.innerHTML = html;

      // Event delegation for actions
      list.querySelectorAll('.btn-ticket-action').forEach(btn => {
        btn.addEventListener('click', async (e) => {
          e.stopPropagation();
          const action = btn.getAttribute('data-action');
          const id = btn.getAttribute('data-id');

          if (action === 'edit') {
            this.openTicketEditModal(id);
          } else if (action === 'close') {
            await window.fossilMcp.callTool('ticket_close', { id });
            showToast(`Тикет #${id} закрыт!`);
            await this.refreshTickets();
            await this.refreshCalendar();
          } else if (action === 'reopen') {
            await window.fossilMcp.callTool('ticket_reopen', { id });
            showToast(`Тикет #${id} открыт снова!`);
            await this.refreshTickets();
            await this.refreshCalendar();
          } else if (action === 'history') {
            this.openTicketHistoryModal(id);
          } else if (action === 'pr') {
            this.openPrModal(id);
          } else if (action === 'delete') {
            if (confirm(`Удалить тикет #${id}?`)) {
              await window.fossilMcp.callTool('ticket_delete', { id });
              showToast(`Тикет #${id} удален!`);
              await this.refreshTickets();
              await this.refreshCalendar();
            }
          }
        });
      });
    },

    // --- Timeline Calendar & Roadmap Actions ---
    // --- Linear Timeline Calendar & Roadmap Gantt Actions ---
    bindCalendarActions() {
      const prevBtn = $('btn-calendar-prev');
      const nextBtn = $('btn-calendar-next');
      const todayBtn = $('btn-calendar-today');
      const addBtn = $('btn-calendar-add-ticket');
      const toggleBacklogBtn = $('btn-toggle-backlog');
      const filterStatus = $('cal-filter-status');
      const filterPriority = $('cal-filter-priority');
      const scaleMonth = $('scale-month');
      const scale2Weeks = $('scale-2weeks');
      const scaleAll = $('scale-all');

      if (!state.calendarScale) state.calendarScale = 'month';

      if (prevBtn) {
        prevBtn.addEventListener('click', () => {
          if (state.calendarScale === '2weeks') {
            const curDate = state.calendarDate || new Date();
            state.calendarDate = new Date(curDate.getTime() - 14 * 24 * 60 * 60 * 1000);
            state.calendarMonth = state.calendarDate.getMonth();
            state.calendarYear = state.calendarDate.getFullYear();
          } else {
            state.calendarMonth--;
            if (state.calendarMonth < 0) {
              state.calendarMonth = 11;
              state.calendarYear--;
            }
          }
          this.refreshCalendar();
        });
      }

      if (nextBtn) {
        nextBtn.addEventListener('click', () => {
          if (state.calendarScale === '2weeks') {
            const curDate = state.calendarDate || new Date();
            state.calendarDate = new Date(curDate.getTime() + 14 * 24 * 60 * 60 * 1000);
            state.calendarMonth = state.calendarDate.getMonth();
            state.calendarYear = state.calendarDate.getFullYear();
          } else {
            state.calendarMonth++;
            if (state.calendarMonth > 11) {
              state.calendarMonth = 0;
              state.calendarYear++;
            }
          }
          this.refreshCalendar();
        });
      }

      if (todayBtn) {
        todayBtn.addEventListener('click', () => {
          const now = new Date();
          state.calendarMonth = now.getMonth();
          state.calendarYear = now.getFullYear();
          state.calendarDate = now;
          this.refreshCalendar();
        });
      }

      if (addBtn) {
        addBtn.addEventListener('click', () => {
          const modal = $('modal-ticket');
          if (modal) {
            const todayStr = new Date().toISOString().split('T')[0];
            if ($('ticket-deadline')) $('ticket-deadline').value = todayStr;
            modal.classList.remove('hidden');
          }
        });
      }

      if (toggleBacklogBtn) {
        toggleBacklogBtn.addEventListener('click', () => {
          const layout = $('calendar-layout');
          if (layout) {
            layout.classList.toggle('backlog-collapsed');
            const isCollapsed = layout.classList.contains('backlog-collapsed');
            toggleBacklogBtn.classList.toggle('btn-primary', isCollapsed);
            toggleBacklogBtn.classList.toggle('btn-secondary', !isCollapsed);
          }
        });
      }

      if (filterStatus) {
        filterStatus.addEventListener('change', () => this.refreshCalendar());
      }
      if (filterPriority) {
        filterPriority.addEventListener('change', () => this.refreshCalendar());
      }

      // Scale selectors
      const setScale = (scale) => {
        state.calendarScale = scale;
        [scaleMonth, scale2Weeks, scaleAll].forEach(b => {
          if (b) {
            b.classList.remove('active', 'btn-primary');
            b.classList.add('btn-secondary');
          }
        });
        const activeBtn = scale === 'month' ? scaleMonth : (scale === '2weeks' ? scale2Weeks : scaleAll);
        if (activeBtn) {
          activeBtn.classList.add('active', 'btn-primary');
          activeBtn.classList.remove('btn-secondary');
        }
        this.refreshCalendar();
      };

      if (scaleMonth) scaleMonth.addEventListener('click', () => setScale('month'));
      if (scale2Weeks) scale2Weeks.addEventListener('click', () => setScale('2weeks'));
      if (scaleAll) scaleAll.addEventListener('click', () => setScale('all'));

      // Ensure Tooltip DOM element exists
      if (!document.getElementById('timeline-tooltip')) {
        const tt = document.createElement('div');
        tt.id = 'timeline-tooltip';
        tt.className = 'timeline-tooltip';
        document.body.appendChild(tt);
      }
    },

    async refreshCalendar() {
      const monthLabel = $('calendar-month-label');
      const datesHeader = $('timeline-dates-header');
      const tasksList = $('timeline-tasks-list');
      const bodyGrid = $('timeline-body-grid');
      const legacyGrid = $('calendar-days-grid');

      const monthNamesRu = ['Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь', 'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'];
      const monthNamesEn = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
      const curLang = (window.FossilI18n && window.FossilI18n.currentLang) || 'ru';
      const mName = curLang === 'ru' ? monthNamesRu[state.calendarMonth] : monthNamesEn[state.calendarMonth];

      if (monthLabel) {
        if (state.calendarScale === '2weeks') {
          monthLabel.innerText = `14 дней (${mName} ${state.calendarYear})`;
        } else if (state.calendarScale === 'all') {
          monthLabel.innerText = `Вся дорожная карта (${state.calendarYear})`;
        } else {
          monthLabel.innerText = `${mName} ${state.calendarYear}`;
        }
      }

      // Fetch all tickets from MCP
      const allRes = await window.fossilMcp.callTool('ticket_list', { status: 'all' });
      const tickets = allRes.tickets || [];
      const now = new Date();
      const nowTs = now.getTime();
      const ONE_DAY = 24 * 60 * 60 * 1000;

      // Filter tickets with and without deadlines
      const scheduled = tickets.filter(t => t.deadline && Number(t.deadline) > 0);
      const backlog = tickets.filter(t => !t.deadline || Number(t.deadline) === 0);

      // Overdue tickets
      const overdue = scheduled.filter(t => Number(t.deadline) < nowTs && (t.status || 'Open').toLowerCase() !== 'closed');
      const closed = scheduled.filter(t => (t.status || 'Open').toLowerCase() === 'closed');

      // Update counters & badges
      const totalScheduledEl = $('cal-total-scheduled');
      const totalClosedEl = $('cal-total-closed');
      const totalOverdueEl = $('cal-total-overdue');
      const backlogCountEl = $('cal-backlog-count');
      const btnBacklogCountEl = $('btn-backlog-count');
      const upcomingCountEl = $('cal-upcoming-count');
      const sidebarCalBadge = $('sidebar-calendar-badge');

      if (totalScheduledEl) totalScheduledEl.innerText = `${scheduled.length} с дедлайном`;
      if (totalClosedEl) totalClosedEl.innerText = `${closed.length} завершено`;
      if (totalOverdueEl) {
        if (overdue.length > 0) {
          totalOverdueEl.style.display = 'inline-block';
          totalOverdueEl.innerText = `⚠️ ${overdue.length} просрочено`;
        } else {
          totalOverdueEl.style.display = 'none';
        }
      }
      if (backlogCountEl) backlogCountEl.innerText = backlog.length;
      if (btnBacklogCountEl) btnBacklogCountEl.innerText = backlog.length;
      if (upcomingCountEl) upcomingCountEl.innerText = scheduled.length;
      if (sidebarCalBadge) {
        if (overdue.length > 0) {
          sidebarCalBadge.style.display = 'inline-block';
          sidebarCalBadge.innerText = overdue.length;
        } else {
          sidebarCalBadge.style.display = 'none';
        }
      }

      // Render Backlog side panel
      const backlogList = $('calendar-backlog-list');
      if (backlogList) {
        if (backlog.length === 0) {
          backlogList.innerHTML = '<div style="font-size:0.8rem; color:var(--color-text-muted); padding:0.5rem 0;">Все задачи имеют назначенные дедлайны!</div>';
        } else {
          let bHtml = '';
          for (const t of backlog) {
            const pClass = `priority-${(t.priority || 'Medium').toLowerCase()}`;
            bHtml += `
              <div class="ticket-card ${pClass}" style="padding:0.6rem 0.75rem; cursor:pointer;" data-id="${escapeHtml(t.id)}">
                <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:0.2rem;">
                  <span class="badge ${pClass}" style="font-size:0.7rem; padding:0.1rem 0.35rem;">${escapeHtml(t.priority || 'Medium')}</span>
                  <span style="font-size:0.72rem; color:var(--color-text-muted);">#${escapeHtml(t.id)}</span>
                </div>
                <div style="font-weight:600; font-size:0.84rem; white-space:nowrap; overflow:hidden; text-overflow:ellipsis;">${escapeHtml(t.title)}</div>
                <div style="display:flex; justify-content:space-between; align-items:center; margin-top:0.35rem; font-size:0.72rem;">
                  <span style="color:var(--color-text-secondary);">${escapeHtml(t.status || 'Open')}</span>
                  <span style="color:var(--color-primary); font-weight:600;">+ Назначить дедлайн</span>
                </div>
              </div>
            `;
          }
          backlogList.innerHTML = bHtml;
          backlogList.querySelectorAll('.ticket-card').forEach(el => {
            el.addEventListener('click', () => this.openTicketEditModal(el.getAttribute('data-id')));
          });
        }
      }

      // Filter scheduled tickets by UI controls
      const statusFilter = $('cal-filter-status') ? $('cal-filter-status').value : 'all';
      const priorityFilter = $('cal-filter-priority') ? $('cal-filter-priority').value : 'all';

      let displayedScheduled = scheduled.filter(t => {
        if (statusFilter === 'open' && (t.status || 'Open').toLowerCase() === 'closed') return false;
        if (statusFilter === 'closed' && (t.status || 'Open').toLowerCase() !== 'closed') return false;
        if (priorityFilter !== 'all' && (t.priority || 'Medium').toLowerCase() !== priorityFilter.toLowerCase()) return false;
        return true;
      });

      // Sort: Critical & Overdue first, then by deadline
      displayedScheduled.sort((a, b) => {
        const aDead = Number(a.deadline);
        const bDead = Number(b.deadline);
        const aOver = aDead < nowTs && (a.status||'Open').toLowerCase() !== 'closed';
        const bOver = bDead < nowTs && (b.status||'Open').toLowerCase() !== 'closed';
        if (aOver && !bOver) return -1;
        if (!aOver && bOver) return 1;
        return aDead - bDead;
      });

      // Compute Timeline Visible Window (Start Date, End Date, Total Days)
      const year = state.calendarYear;
      const month = state.calendarMonth;
      let startDate, endDate, totalDays, cellWidth = 42;

      if (state.calendarScale === '2weeks') {
        cellWidth = 56;
        const curDate = state.calendarDate || now;
        startDate = new Date(curDate.getFullYear(), curDate.getMonth(), curDate.getDate() - 4, 0, 0, 0);
        endDate = new Date(startDate.getTime() + 14 * ONE_DAY);
        totalDays = 14;
      } else if (state.calendarScale === 'all') {
        cellWidth = 36;
        let minTs = nowTs - 3 * ONE_DAY;
        let maxTs = nowTs + 7 * ONE_DAY;
        for (const t of scheduled) {
          const cStart = Number(t.created) || (Number(t.deadline) - 4 * ONE_DAY);
          const cEnd = Number(t.deadline);
          if (cStart < minTs) minTs = cStart;
          if (cEnd > maxTs) maxTs = cEnd;
        }
        startDate = new Date(minTs);
        startDate.setHours(0, 0, 0, 0);
        endDate = new Date(maxTs);
        endDate.setHours(23, 59, 59, 999);
        totalDays = Math.max(14, Math.ceil((endDate.getTime() - startDate.getTime()) / ONE_DAY));
      } else {
        // Month view (default)
        cellWidth = 42;
        startDate = new Date(year, month, 1, 0, 0, 0);
        const daysInMonth = new Date(year, month + 1, 0).getDate();
        endDate = new Date(year, month, daysInMonth, 23, 59, 59);
        totalDays = daysInMonth;
      }

      const totalCanvasWidth = totalDays * cellWidth;
      const weekdaysRu = ['Вс', 'Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб'];
      const weekdaysEn = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
      const wNames = curLang === 'ru' ? weekdaysRu : weekdaysEn;

      // 1. Build Dates Header Strip
      if (datesHeader) {
        let hHtml = '';
        for (let i = 0; i < totalDays; i++) {
          const cDate = new Date(startDate.getTime() + i * ONE_DAY);
          const dNum = cDate.getDate();
          const dWeek = cDate.getDay();
          const isWeekend = dWeek === 0 || dWeek === 6;
          const isToday = cDate.getFullYear() === now.getFullYear() &&
                          cDate.getMonth() === now.getMonth() &&
                          cDate.getDate() === now.getDate();

          hHtml += `
            <div class="timeline-date-cell ${isWeekend ? 'weekend' : ''} ${isToday ? 'today-cell' : ''}"
                 style="width:${cellWidth}px;"
                 title="${cDate.toLocaleDateString()}">
              <span class="timeline-date-daynum">${dNum}</span>
              <span class="timeline-date-dayname">${wNames[dWeek]}</span>
            </div>
          `;
        }
        datesHeader.innerHTML = hHtml;
        datesHeader.style.width = `${totalCanvasWidth}px`;
      }

      // 2. Build Tasks Column (Left) and Gantt Rows (Right)
      if (tasksList && bodyGrid) {
        if (displayedScheduled.length === 0) {
          tasksList.innerHTML = `
            <div style="padding:2rem 1rem; color:var(--color-text-muted); font-size:0.82rem; text-align:center;">
              Нет запланированных задач по выбранным фильтрам.
            </div>
          `;
          bodyGrid.innerHTML = `
            <div style="padding:2.5rem 1.5rem; color:var(--color-text-muted); font-size:0.85rem; width:${totalCanvasWidth}px;">
              💡 Назначьте дедлайн задаче из бэклога или нажмите <b>«+ Создать тикет с дедлайном»</b>.
            </div>
          `;
        } else {
          let leftHtml = '';
          let rightRowsHtml = '';

          // Background vertical grid lines
          let gridLinesHtml = `<div class="timeline-grid-lines" style="width:${totalCanvasWidth}px;">`;
          for (let i = 0; i < totalDays; i++) {
            const cDate = new Date(startDate.getTime() + i * ONE_DAY);
            const dWeek = cDate.getDay();
            const isWeekend = dWeek === 0 || dWeek === 6;
            const isToday = cDate.getFullYear() === now.getFullYear() &&
                            cDate.getMonth() === now.getMonth() &&
                            cDate.getDate() === now.getDate();

            gridLinesHtml += `
              <div class="timeline-grid-line ${isWeekend ? 'weekend' : ''} ${isToday ? 'today-line' : ''}"
                   style="width:${cellWidth}px;"></div>
            `;
          }
          gridLinesHtml += `</div>`;

          for (const t of displayedScheduled) {
            const priorityLower = (t.priority || 'Medium').toLowerCase();
            const pClass = `priority-${priorityLower}`;
            const isClosed = (t.status || 'Open').toLowerCase() === 'closed';
            const deadlineTs = Number(t.deadline);
            const createdTs = Number(t.created) || (deadlineTs - 4 * ONE_DAY);
            const isOverdue = deadlineTs < nowTs && !isClosed;
            const diffDays = Math.ceil((deadlineTs - nowTs) / ONE_DAY);
            const totalSpanDays = Math.max(1, Math.round((deadlineTs - createdTs) / ONE_DAY));

            const dStart = new Date(createdTs);
            const dEnd = new Date(deadlineTs);
            const startStr = `${dStart.getDate()}.${String(dStart.getMonth() + 1).padStart(2, '0')}`;
            const endStr = `${dEnd.getDate()}.${String(dEnd.getMonth() + 1).padStart(2, '0')}`;

            // Left Task Item
            leftHtml += `
              <div class="timeline-task-item ${pClass}" data-id="${escapeHtml(t.id)}" title="${escapeHtml(t.title)} (${escapeHtml(t.priority || 'Medium')})">
                <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:2px;">
                  <span style="font-weight:700; font-size:0.75rem; color:var(--color-primary);">#${escapeHtml(t.id)}</span>
                  <span class="badge ${pClass}" style="font-size:0.65rem; padding:0.05rem 0.35rem;">${escapeHtml(t.priority || 'Medium')}</span>
                </div>
                <div style="font-weight:600; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; font-size:0.82rem;">
                  ${isClosed ? '✓ ' : (isOverdue ? '⚠️ ' : '')}${escapeHtml(t.title)}
                </div>
                <div style="display:flex; justify-content:space-between; align-items:center; font-size:0.68rem; color:var(--color-text-muted); margin-top:2px;">
                  <span>${startStr} → ${endStr}</span>
                  <span style="color:${isClosed ? 'var(--color-success)' : (isOverdue ? 'var(--color-danger)' : 'var(--color-text-secondary)')}; font-weight:700;">
                    ${isClosed ? 'Готово' : (isOverdue ? 'Просрочено' : diffDays + ' дн.')}
                  </span>
                </div>
              </div>
            `;

            // Right Gantt Bar Position
            const startDayOffset = (createdTs - startDate.getTime()) / ONE_DAY;
            const endDayOffset = (deadlineTs - startDate.getTime()) / ONE_DAY + 1; // Include deadline day

            const visStart = Math.max(0, startDayOffset);
            const visEnd = Math.min(totalDays, endDayOffset);
            const safeVisEnd = visEnd <= visStart ? visStart + 0.9 : visEnd;

            const leftPx = visStart * cellWidth;
            const widthPx = Math.max((safeVisEnd - visStart) * cellWidth, 34);

            const hasLeftContinuation = startDayOffset < 0;
            const hasRightContinuation = endDayOffset > totalDays;

            rightRowsHtml += `
              <div class="timeline-row" style="width:${totalCanvasWidth}px;" data-id="${escapeHtml(t.id)}">
                <div class="timeline-bar ${pClass} ${isClosed ? 'status-closed' : ''} ${isOverdue ? 'is-overdue' : ''}"
                     style="left:${leftPx}px; width:${widthPx}px;"
                     data-id="${escapeHtml(t.id)}"
                     data-title="${escapeHtml(t.title)}"
                     data-priority="${escapeHtml(t.priority || 'Medium')}"
                     data-status="${escapeHtml(t.status || 'Open')}"
                     data-reporter="${escapeHtml(t.reporter || 'user')}"
                     data-start="${startStr}"
                     data-end="${endStr}"
                     data-span="${totalSpanDays}"
                     data-diff="${diffDays}"
                     data-overdue="${isOverdue ? 'true' : 'false'}"
                     data-closed="${isClosed ? 'true' : 'false'}">
                  <span class="timeline-bar-title">
                    ${hasLeftContinuation ? '◄ ' : ''}${escapeHtml(t.title)} (${totalSpanDays} дн.)${hasRightContinuation ? ' ►' : ''}
                  </span>
                  <span class="timeline-deadline-pin" title="Дедлайн: ${endStr}">
                    ${isClosed ? '✓' : (isOverdue ? '!' : '●')}
                  </span>
                </div>
              </div>
            `;
          }

          tasksList.innerHTML = leftHtml;
          bodyGrid.innerHTML = gridLinesHtml + rightRowsHtml;
          bodyGrid.style.width = `${totalCanvasWidth}px`;

          // Setup rich hover tooltips and clicks
          const tooltip = $('timeline-tooltip');
          bodyGrid.querySelectorAll('.timeline-bar').forEach(bar => {
            bar.addEventListener('mouseenter', (e) => {
              if (!tooltip) return;
              const title = bar.getAttribute('data-title');
              const id = bar.getAttribute('data-id');
              const priority = bar.getAttribute('data-priority');
              const status = bar.getAttribute('data-status');
              const reporter = bar.getAttribute('data-reporter');
              const start = bar.getAttribute('data-start');
              const end = bar.getAttribute('data-end');
              const span = bar.getAttribute('data-span');
              const diff = Number(bar.getAttribute('data-diff'));
              const isOverdue = bar.getAttribute('data-overdue') === 'true';
              const isClosed = bar.getAttribute('data-closed') === 'true';

              let statusText = isClosed ? '<span style="color:var(--color-success); font-weight:700;">✓ Завершено</span>' :
                               (isOverdue ? `<span style="color:var(--color-danger); font-weight:700;">⚠️ Просрочено на ${Math.abs(diff)} дн.</span>` :
                               `<span style="color:var(--color-primary); font-weight:700;">В работе (осталось ${diff} дн.)</span>`);

              tooltip.innerHTML = `
                <div style="font-weight:700; font-size:0.86rem; margin-bottom:0.35rem; color:var(--color-text);">
                  #${escapeHtml(id)}: ${escapeHtml(title)}
                </div>
                <div style="display:flex; gap:0.4rem; margin-bottom:0.4rem;">
                  <span class="badge priority-${priority.toLowerCase()}">${escapeHtml(priority)}</span>
                  <span class="badge badge-secondary">${escapeHtml(status)}</span>
                </div>
                <div style="font-size:0.75rem; color:var(--color-text-secondary); line-height:1.4;">
                  <div>📅 <b>Сроки:</b> ${start} → ${end} (${span} дн.)</div>
                  <div>⏳ <b>Статус:</b> ${statusText}</div>
                  <div>👤 <b>Автор:</b> ${escapeHtml(reporter)}</div>
                </div>
                <div style="font-size:0.68rem; color:var(--color-text-muted); margin-top:0.4rem; border-top:1px solid var(--color-border); padding-top:0.3rem;">
                  Нажмите на полосу, чтобы открыть или изменить тикет
                </div>
              `;
              tooltip.style.display = 'block';
            });

            bar.addEventListener('mousemove', (e) => {
              if (!tooltip) return;
              let x = e.clientX + 14;
              let y = e.clientY + 14;
              if (x + 320 > window.innerWidth) {
                x = Math.max(10, e.clientX - 330);
              }
              if (y + 180 > window.innerHeight) {
                y = Math.max(10, e.clientY - 160);
              }
              tooltip.style.left = x + 'px';
              tooltip.style.top = y + 'px';
            });

            bar.addEventListener('mouseleave', () => {
              if (tooltip) tooltip.style.display = 'none';
            });

            bar.addEventListener('click', (e) => {
              e.stopPropagation();
              if (tooltip) tooltip.style.display = 'none';
              this.openTicketEditModal(bar.getAttribute('data-id'));
            });
          });

          // Click on left item opens edit modal as well
          tasksList.querySelectorAll('.timeline-task-item').forEach(el => {
            el.addEventListener('click', () => {
              this.openTicketEditModal(el.getAttribute('data-id'));
            });
          });
        }
      }

      // Auto-scroll timeline to 'Today' if today is visible
      const chartArea = $('timeline-chart-area');
      const isCurrentMonth = (now.getFullYear() === state.calendarYear && now.getMonth() === state.calendarMonth);
      if (chartArea && isCurrentMonth && state.calendarScale === 'month') {
        const todayOffset = (now.getDate() - 3) * cellWidth;
        chartArea.scrollLeft = Math.max(0, todayOffset);
      }

      // Legacy grid compatibility
      if (legacyGrid) legacyGrid.innerHTML = '';
    },

    // --- Pull Request Actions ---
    bindPullRequestActions() {
      const openPrBtn = $('btn-open-pr-modal');
      const prModal = $('modal-pr');
      const closeBtn = $('btn-modal-pr-close');
      const form = $('form-pr');

      if (openPrBtn && prModal) {
        openPrBtn.addEventListener('click', () => this.openPrModal());
      }
      if (closeBtn && prModal) {
        closeBtn.addEventListener('click', () => prModal.classList.add('hidden'));
      }
      if (form) {
        form.addEventListener('submit', async (e) => {
          e.preventDefault();
          const title = $('pr-title').value.trim();
          const sourceBranch = $('pr-source-branch').value.trim();
          const targetBranch = $('pr-target-branch').value.trim() || 'trunk';
          const ticketId = $('pr-target-ticket-select').value;
          const description = $('pr-description').value.trim();
          if (!title || !sourceBranch) return;

          const res = await window.fossilMcp.callTool('pr_create', {
            title,
            sourceBranch,
            targetBranch,
            description,
            ticketId
          });

          if (res.success) {
            $('pr-title').value = '';
            $('pr-description').value = '';
            prModal.classList.add('hidden');
            await this.refreshTickets();
            await this.refreshCalendar();
            await this.refreshTimeline();
            showToast(`Pull Request ${res.pullRequest.id} успешно создан!`);
          }
        });
      }
    },

    async openPrModal(targetTicketId = '') {
      const modal = $('modal-pr');
      if (!modal) return;

      const select = $('pr-target-ticket-select');
      if (select) {
        const tktRes = await window.fossilMcp.callTool('ticket_list', { status: 'all' });
        const tickets = tktRes.tickets || [];
        let optHtml = '<option value="">-- Без привязки к тикету --</option>';
        for (const t of tickets) {
          const isSelected = t.id === targetTicketId ? 'selected' : '';
          optHtml += `<option value="${escapeHtml(t.id)}" ${isSelected}>#${escapeHtml(t.id)}: ${escapeHtml(t.title)} (${escapeHtml(t.priority || 'Medium')})</option>`;
        }
        select.innerHTML = optHtml;
      }

      modal.classList.remove('hidden');
    },

    // --- Rich MCP Tools Console ---
    bindMcpActions() {
      const runBtn = $('btn-mcp-invoke');
      const copyPromptBtn = $('btn-copy-mcp-prompt');
      const loadSampleBtn = $('btn-mcp-load-sample');

      this.renderMcpCategoryFilterBar();
      this.refreshMcpList();
      this.selectMcpTool(state.activeMcpTool);

      if (loadSampleBtn) {
        loadSampleBtn.addEventListener('click', () => {
          const tool = window.fossilMcp.getToolInfo(state.activeMcpTool);
          const paramsEl = $('mcp-params-input');
          if (paramsEl) {
            paramsEl.value = JSON.stringify(tool.sampleParams || {}, null, 2);
          }
        });
      }

      if (runBtn) {
        runBtn.addEventListener('click', async () => {
          const outputEl = $('mcp-output-json');
          const statusPill = $('mcp-status-pill');
          const latencyPill = $('mcp-latency-pill');
          if (!outputEl) return;

          outputEl.innerText = '// Executing MCP tool in active storage backend...';
          const toolName = state.activeMcpTool;
          let params = {};
          try {
            params = JSON.parse($('mcp-params-input').value || '{}');
          } catch (e) {
            outputEl.innerText = 'JSON Parse Error: ' + e.message;
            if (statusPill) {
              statusPill.className = 'badge badge-danger';
              statusPill.innerText = '400 Bad JSON';
            }
            return;
          }

          const t0 = performance.now();
          const res = await window.fossilMcp.callTool(toolName, params);
          const elapsed = (performance.now() - t0).toFixed(1);

          if (latencyPill) {
            latencyPill.style.display = 'inline-block';
            latencyPill.innerText = `⏱️ ${elapsed}ms`;
          }

          if (res.error) {
            if (statusPill) {
              statusPill.className = 'badge badge-danger';
              statusPill.innerText = 'Error';
            }
          } else {
            if (statusPill) {
              statusPill.className = 'badge badge-success';
              statusPill.innerText = '200 OK';
            }
          }

          outputEl.innerText = JSON.stringify(res, null, 2);

          // Auto-refresh tabs if tool modified state
          if (toolName.startsWith('ticket_')) {
            this.refreshTickets();
            this.refreshCalendar();
          } else if (toolName.startsWith('pr_')) {
            this.refreshTickets();
            this.refreshCalendar();
          } else if (toolName.startsWith('vcs_file_')) {
            this.refreshFiles();
          } else if (toolName.startsWith('vcs_commit')) {
            this.refreshTimeline();
          }
        });
      }

      if (copyPromptBtn) {
        copyPromptBtn.addEventListener('click', () => {
          const promptText = `You are connected to Fossil-Nim In-Browser Distributed VCS via Model Context Protocol.\nAvailable MCP Tools: 89.\nActive Storage Backend: ${window.FossilStorageManager.backendType}.\nSupported Endpoints: window.fossilMcp.callTool(name, params).\nCategories: VCS Core, File System, Wiki & Docs, Issues & Tickets, Roadmap & Calendar, Pull Requests, Multi-DB Storage.`;
          navigator.clipboard.writeText(promptText).then(() => {
            showToast('Системный промпт ИИ скопирован в буфер!');
          });
        });
      }
    },

    renderMcpCategoryFilterBar() {
      const bar = $('mcp-category-filter-bar');
      if (!bar) return;

      const cats = [
        { id: 'all', name: 'Все (89)' },
        { id: 'vcs', name: '🌿 VCS Core' },
        { id: 'files', name: '📁 Files' },
        { id: 'wiki', name: '📖 Wiki' },
        { id: 'tickets', name: '🎫 Tickets' },
        { id: 'calendar', name: '📅 Calendar' },
        { id: 'prs', name: '🔀 Pull Requests' },
        { id: 'storage', name: '💾 Storage' },
        { id: 'search', name: '🔍 Diagnostics' }
      ];

      let html = '';
      for (const c of cats) {
        const isActive = c.id === state.mcpCategoryFilter;
        html += `<button class="btn btn-secondary btn-sm mcp-cat-btn ${isActive ? 'btn-primary' : ''}" data-cat="${c.id}" style="font-size:0.78rem; padding:0.25rem 0.65rem;">${escapeHtml(c.name)}</button>`;
      }
      bar.innerHTML = html;

      bar.querySelectorAll('.mcp-cat-btn').forEach(btn => {
        btn.addEventListener('click', () => {
          state.mcpCategoryFilter = btn.getAttribute('data-cat') || 'all';
          this.renderMcpCategoryFilterBar();
          this.refreshMcpList();
        });
      });
    },

    refreshMcpList() {
      const list = $('mcp-tools-list');
      const countEl = $('mcp-filtered-count');
      if (!list) return;

      const allTools = window.fossilMcp.listTools().tools;
      let filtered = allTools;
      if (state.mcpCategoryFilter && state.mcpCategoryFilter !== 'all') {
        filtered = filtered.filter(t => t.category === state.mcpCategoryFilter);
      }

      if (countEl) countEl.innerText = filtered.length;

      let html = '';
      for (const tool of filtered) {
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
    },

    selectMcpTool(toolName) {
      state.activeMcpTool = toolName;
      document.querySelectorAll('.mcp-tool-item').forEach(el => {
        el.classList.toggle('active', el.getAttribute('data-tool') === toolName);
      });

      const tool = window.fossilMcp.getToolInfo(toolName);
      const nameEl = $('mcp-active-tool-name');
      const catBadge = $('mcp-active-tool-cat-badge');
      const descEl = $('mcp-active-tool-desc');
      const paramsTableContainer = $('mcp-params-table-container');
      const paramsInput = $('mcp-params-input');

      if (nameEl) nameEl.innerText = tool.name;

      if (catBadge) {
        const catInfo = window.MCP_CATEGORIES && window.MCP_CATEGORIES[tool.category];
        catBadge.innerText = catInfo ? catInfo.name : (tool.category || 'MCP');
        catBadge.className = `badge ${catInfo ? catInfo.badgeClass : 'badge-primary'}`;
      }

      if (descEl) {
        descEl.innerText = tool.description || 'Описание инструмента.';
      }

      // Render Parameters Schema Table
      if (paramsTableContainer) {
        const params = tool.parameters || {};
        const paramKeys = Object.keys(params);
        if (paramKeys.length === 0) {
          paramsTableContainer.innerHTML = '<span style="font-size:0.82rem; color:var(--color-text-muted); font-style:italic;">Инструмент не требует параметров (вызывается без аргументов {}).</span>';
        } else {
          let tableHtml = `
            <table class="mcp-params-table">
              <thead>
                <tr>
                  <th>Параметр</th>
                  <th>Тип</th>
                  <th>Статус</th>
                  <th>Описание</th>
                  <th>По умолчанию</th>
                </tr>
              </thead>
              <tbody>
          `;
          for (const [key, spec] of Object.entries(params)) {
            const isReq = spec.required;
            tableHtml += `
              <tr>
                <td><code>${escapeHtml(key)}</code></td>
                <td><span style="color:var(--color-text-secondary);">${escapeHtml(spec.type || 'string')}</span></td>
                <td>${isReq ? '<span class="badge badge-danger" style="font-size:0.7rem; padding:0.1rem 0.35rem;">Обязательный</span>' : '<span class="badge badge-secondary" style="font-size:0.7rem; padding:0.1rem 0.35rem;">Опционально</span>'}</td>
                <td>${escapeHtml(spec.description || '')}</td>
                <td><span style="color:var(--color-text-muted);">${escapeHtml(spec.default !== undefined ? String(spec.default) : '-')}</span></td>
              </tr>
            `;
          }
          tableHtml += '</tbody></table>';
          paramsTableContainer.innerHTML = tableHtml;
        }
      }

      if (paramsInput) {
        paramsInput.value = JSON.stringify(tool.sampleParams || {}, null, 2);
      }
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
