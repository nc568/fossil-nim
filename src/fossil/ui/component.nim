## Component System - Modular, platform agnostic
## Base for all UI components, works for web, TUI, desktop

import ./core
import std/[json, tables, options]

type
  ComponentState* = enum
    csIdle
    csLoading
    csReady
    csError

  ComponentProps* = object
    id*: string
    data*: JsonNode
    query*: Table[string, string]
    theme*: string
    currentUser*: string

  Component* = ref object of RootObj
    name*: string
    state*: ComponentState
    props*: ComponentProps
    html*: string # For web rendering
    error*: string

method init*(c: Component) {.base.} =
  c.state = csIdle

method render*(c: Component): string {.base.} =
  ## Platform agnostic render - returns HTML for web, text for TUI
  "<div>Component " & c.name & " not implemented</div>"

method update*(c: Component, props: ComponentProps) {.base.} =
  c.props = props
  c.state = csLoading

method destroy*(c: Component) {.base.} =
  c.state = csIdle

method handleEvent*(c: Component, event: string, data: JsonNode): JsonNode {.base.} =
  %* {"ok": false, "error": "event not handled: " & event}

# Component registry - modular architecture
var componentRegistry* = initTable[string, proc(): Component]()

proc registerComponent*(name: string, factory: proc(): Component) =
  componentRegistry[name] = factory

proc createComponent*(name: string): Component =
  if componentRegistry.hasKey(name):
    return componentRegistry[name]()
  else:
    var c = Component(name: name, state: csError, error: "Component not found: " & name)
    return c

# Base components for code reuse
type
  ListComponent* = ref object of Component
    items*: seq[JsonNode]
    limit*: int
    offset*: int

  DetailComponent* = ref object of Component
    itemId*: string

  FormComponent* = ref object of Component
    fields*: Table[string, string]
    submitting*: bool

method renderList*(c: ListComponent): string {.base.} =
  var html = "<div class='component-list'><h2>" & c.name & "</h2><ul>"
  for item in c.items:
    html.add "<li>" & $item & "</li>"
  html.add "</ul></div>"
  html

# For JS generation - generate vanilla JS component base
proc generateJsComponentBase*(): string =
  """
// Component System - Vanilla JS, modular, no frameworks
// Base class for all components, platform agnostic logic in Nim, rendering in JS

class Component {
  constructor(name, props = {}) {
    this.name = name;
    this.props = props;
    this.state = 'idle'; // idle, loading, ready, error
    this.error = '';
    this.element = null;
  }
  
  init() {
    this.state = 'idle';
    this.bindEvents();
  }
  
  bindEvents() {
    // Override in subclasses
  }
  
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
  
  afterRender() {
    // Called after render, for binding
  }
  
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
      this.element.innerHTML = `<div class="error">${err}</div>`;
    }
  }
  
  destroy() {
    this.state = 'idle';
    if (this.element) this.element.innerHTML = '';
  }
  
  // xhttp-like helpers
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

// Component Registry - modular architecture
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

// List Component base
class ListComponent extends Component {
  constructor(name, props = {}) {
    super(name, props);
    this.items = props.items || [];
    this.limit = props.limit || 20;
    this.offset = props.offset || 0;
  }
  
  renderList(items, itemRenderer) {
    if (!items || items.length === 0) {
      return `<div class="empty">No items</div>`;
    }
    return `<div class="list">${items.map(itemRenderer).join('')}</div>`;
  }
}

window.ListComponent = ListComponent;
"""
