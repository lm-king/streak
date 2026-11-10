// 极简 DOM 垫片：覆盖 preview.html 用到的 API + localStorage + 事件派发
var __els = {};
var storage = {};
var localStorage = {
  getItem: function (k) { return k in storage ? storage[k] : null; },
  setItem: function (k, v) { storage[k] = String(v); },
  removeItem: function (k) { delete storage[k]; }
};
function makeEl(tag) {
  var cls = new Set();
  var el = { tagName: tag, children: [], dataset: {}, _html: '', _text: '', offsetWidth: 0, _ev: {} };
  el.style = { setProperty: function (k, v) { this[k] = v; } };
  Object.defineProperty(el, 'className', {
    get: function () { return Array.from(cls).join(' '); },
    set: function (v) { cls.clear(); String(v).split(/\s+/).filter(Boolean).forEach(function (c) { cls.add(c); }); }
  });
  el.classList = {
    add: function () { for (var i = 0; i < arguments.length; i++) cls.add(arguments[i]); },
    remove: function () { for (var i = 0; i < arguments.length; i++) cls.delete(arguments[i]); },
    contains: function (c) { return cls.has(c); },
    toggle: function (c, on) { if (on === undefined) { cls.has(c) ? cls.delete(c) : cls.add(c); } else if (on) cls.add(c); else cls.delete(c); }
  };
  Object.defineProperty(el, 'innerHTML', { get: function () { return el._html; }, set: function (v) { el._html = String(v); if (el._html === '') el.children = []; } });
  Object.defineProperty(el, 'textContent', { get: function () { return el._text; }, set: function (v) { el._text = String(v); } });
  el.appendChild = function (c) { el.children.push(c); return c; };
  el.setAttribute = function () {};
  el.addEventListener = function (t, f) { (el._ev[t] = el._ev[t] || []).push(f); };
  el.click = function () { (el._ev.click || []).forEach(function (f) { f({ target: el, stopPropagation: function () {}, clientX: 0, clientY: 0 }); }); };
  el.focus = function () {}; el.blur = function () {};
  return el;
}
var document = {
  getElementById: function (id) { if (!__els[id]) __els[id] = makeEl('div'); return __els[id]; },
  createElement: function (t) { return makeEl(t); },
  createDocumentFragment: function () { return makeEl('fragment'); }
};
var window = { addEventListener: function () {}, innerWidth: 1440, innerHeight: 960 };
var navigator = {};
function requestAnimationFrame(fn) { setTimeout(fn, 0); }
