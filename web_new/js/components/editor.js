// editor.js - WYSIWYG Markdown editor with toolbar, live preview, vanilla JS

class MarkdownEditor {
  constructor(textareaId, previewId, options = {}) {
    this.textarea = document.getElementById(textareaId);
    this.preview = document.getElementById(previewId);
    this.options = options;
    this.init();
  }

  init() {
    if (!this.textarea) return;
    // Add toolbar if not exists
    const toolbarId = this.textarea.id + '-toolbar';
    let toolbar = document.getElementById(toolbarId);
    if (!toolbar) {
      toolbar = document.createElement('div');
      toolbar.id = toolbarId;
      toolbar.className = 'editor-toolbar';
      toolbar.innerHTML = `
        <button type="button" data-md="**" data-desc="Bold" title="Bold (Ctrl+B)"><b>B</b></button>
        <button type="button" data-md="*" data-desc="Italic" title="Italic (Ctrl+I)"><i>I</i></button>
        <button type="button" data-md="\`" data-desc="Code" title="Inline code"><code>&lt;/&gt;</code></button>
        <button type="button" data-md="[" data-md-end="](url)" data-desc="Link" title="Link">🔗</button>
        <button type="button" data-md="\\n- " data-desc="List" title="List">• List</button>
        <button type="button" data-md="\\n> " data-desc="Quote" title="Quote">❝ Quote</button>
        <button type="button" data-md="\\n### " data-desc="Heading" title="Heading">H</button>
        <button type="button" data-md="\\n\`\`\`\\n" data-md-end="\\n\`\`\`\\n" data-desc="Code block" title="Code block">CB</button>
        <button type="button" data-md="\\n| col | col |\\n| --- | --- |\\n| " data-desc="Table" title="Table">⊞ Table</button>
        <button type="button" data-md="![alt](" data-md-end=")" data-desc="Image" title="Image">🖼️ Img</button>
        <button type="button" data-md="\\n---\\n" data-desc="HR" title="Horizontal rule">― HR</button>
        <button type="button" onclick="window.editorPreview && window.editorPreview('${this.textarea.id}', '${this.preview.id}')" title="Preview">👁️ Preview</button>
      `;
      this.textarea.parentNode.insertBefore(toolbar, this.textarea);
      toolbar.addEventListener('click', (e) => {
        if (e.target.tagName === 'BUTTON' && e.target.hasAttribute('data-md')) {
          const start = e.target.getAttribute('data-md');
          const end = e.target.getAttribute('data-md-end') || start;
          const desc = e.target.getAttribute('data-desc') || 'text';
          this.insert(start, end, desc);
        }
      });
    }

    // Live preview on input with debounce
    this.textarea.addEventListener('input', () => {
      clearTimeout(this._previewTimeout);
      this._previewTimeout = setTimeout(() => this.updatePreview(), 500);
    });

    // Keyboard shortcuts
    this.textarea.addEventListener('keydown', (e) => {
      if (e.ctrlKey || e.metaKey) {
        if (e.key === 'b') { e.preventDefault(); this.insert('**','**','bold'); }
        if (e.key === 'i') { e.preventDefault(); this.insert('*','*','italic'); }
        if (e.key === 'k') { e.preventDefault(); this.insert('[','](url)','link'); }
        if (e.key === 'e') { e.preventDefault(); this.insert('`','`','code'); }
      }
      if (e.key === 'Tab') {
        e.preventDefault();
        this.insert('  ', '', '');
      }
    });

    // Initial preview
    setTimeout(() => this.updatePreview(), 100);
  }

  insert(before, after, placeholder) {
    const ta = this.textarea;
    const start = ta.selectionStart;
    const end = ta.selectionEnd;
    const selected = ta.value.substring(start, end) || placeholder;
    // Handle \n escapes
    const b = before.replace(/\\n/g, '\n');
    const a = after.replace(/\\n/g, '\n');
    ta.value = ta.value.substring(0, start) + b + selected + a + ta.value.substring(end);
    ta.focus();
    ta.setSelectionRange(start + b.length, start + b.length + selected.length);
    this.updatePreview();
  }

  async updatePreview() {
    if (!this.preview) return;
    const text = this.textarea.value;
    if (!text) {
      this.preview.innerHTML = '<i class="text-muted">Preview empty</i>';
      return;
    }
    try {
      const res = await api.markdown(text);
      this.preview.innerHTML = res.data.html || res.data || '<i>no preview</i>';
      if (window.xhttp) window.xhttp.process(this.preview);
    } catch (e) {
      // Fallback simple markdown
      this.preview.innerHTML = this.simpleMarkdown(text);
    }
  }

  simpleMarkdown(text) {
    return text
      .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
      .replace(/\*\*(.*?)\*\*/g,'<b>$1</b>')
      .replace(/\*(.*?)\*/g,'<i>$1</i>')
      .replace(/`(.*?)`/g,'<code>$1</code>')
      .replace(/\n/g,'<br>');
  }

  getValue() { return this.textarea ? this.textarea.value : ''; }
  setValue(v) { if (this.textarea) { this.textarea.value = v; this.updatePreview(); } }
}

window.MarkdownEditor = MarkdownEditor;
window.editorPreview = async (textareaId, previewId) => {
  const ta = document.getElementById(textareaId);
  const preview = document.getElementById(previewId);
  if (!ta || !preview) return;
  const editor = new MarkdownEditor(textareaId, previewId);
  await editor.updatePreview();
};

console.log('📝 editor.js loaded - WYSIWYG markdown editor');
