// setup.js - Setup/admin component
registerComponent('setup', (props) => {
  const c = new Component('setup', props);
  c.fetch = async () => {
    try {
      const r = await fetch('/setup');
      const html = await r.text();
      const parser = new DOMParser();
      const doc = parser.parseFromString(html, 'text/html');
      return { html: doc.body ? doc.body.innerHTML : html };
    } catch (e) {
      return { html: '<div class="error">Failed to load setup: ' + e.message + '</div>' };
    }
  };
  c.render = () => {
    const data = c.props.data || {};
    return data.html || `
      <div class="card">
        <h1>⚙️ Setup & Administration</h1>
        <div class="loading"><div class="spinner"></div></div>
      </div>
    `;
  };
  c.afterRender = () => {
    const main = document.getElementById('main');
    if (main && window.xhttp) window.xhttp.process(main);
  };
  return c;
});
console.log('📦 setup component loaded');
