// component.js - Modular component system, vanilla JS, no frameworks

class Component {
  constructor(name, props = {}) {
    this.name = name;
    this.props = props;
    this.state = 'idle';
    this.error = '';
    this.element = null;
  }
  
  init() {
    this.state = 'idle';
    this.bindEvents();
  }
  
  bindEvents() {}
  
  render() {
    return `<div class="component component-${this.name}">Component ${this.name} not implemented</div>`;
  }
  
  mount(target) {
    if (typeof target === 'string') target = document.querySelector(target);
    if (!target) return;
    this.element = target;
    target.innerHTML = this.render();
    this.state = 'ready';
    this.afterRender();
  }
  
  afterRender() {}
  
  update(props) {
    this.props = {...this.props, ...props};
    this.state = 'loading';
    if (this.element) {
      this.element.innerHTML = this.render();
      this.afterRender();
    }
  }
  
  setError(err) {
    this.error = err;
    this.state = 'error';
    if (this.element) {
      this.element.innerHTML = `<div class="error">Error: ${err}</div>`;
    }
  }
  
  destroy() {
    this.state = 'idle';
    if (this.element) this.element.innerHTML = '';
  }
  
  async fetchData(url) {
    this.state = 'loading';
    try {
      const res = await window.api.get(url);
      this.state = 'ready';
      return res.data;
    } catch (e) {
      this.setError(e.message);
      throw e;
    }
  }
}

window.Component = Component;
window.components = {};

function registerComponent(name, factory) {
  window.components[name] = factory;
}

function createComponent(name, props = {}) {
  const factory = window.components[name];
  if (factory) return factory(props);
  console.warn(`Component not found: ${name}`);
  return new Component(name, props);
}

window.registerComponent = registerComponent;
window.createComponent = createComponent;

class ListComponent extends Component {
  constructor(name, props = {}) {
    super(name, props);
    this.items = props.items || [];
    this.limit = props.limit || 20;
    this.offset = props.offset || 0;
  }
  
  renderList(items, itemRenderer) {
    if (!items || items.length === 0) {
      return `<div class="empty">No items<br><small>Try adjusting filters</small></div>`;
    }
    return `<div class="list">${items.map(itemRenderer).join('')}</div>`;
  }
}

window.ListComponent = ListComponent;

console.log('🧩 component.js loaded - modular component system');
