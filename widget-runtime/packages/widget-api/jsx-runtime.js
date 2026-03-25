const { __internal } = require("./index.js");

const Fragment = Symbol.for("notch.fragment");

function jsx(type, props, key) {
  if (type === Fragment) {
    return __internal.flattenChildren(props?.children);
  }

  const merged = { ...(props ?? {}) };
  if (key != null && merged.id == null) {
    merged.id = String(key);
  }

  if (typeof type === "function") {
    return type(merged);
  }

  throw new Error(`Unsupported JSX type: ${String(type)}`);
}

const jsxs = jsx;

module.exports = {
  Fragment,
  jsx,
  jsxs,
};
