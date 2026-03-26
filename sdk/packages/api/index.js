function flattenChildren(input) {
  if (input == null || input === false) return [];
  if (Array.isArray(input)) return input.flatMap(flattenChildren);
  return [input];
}

function extractText(input) {
  return flattenChildren(input)
    .map((item) => {
      if (typeof item === "string" || typeof item === "number") return String(item);
      if (item && typeof item.text === "string") return item.text;
      return "";
    })
    .join("");
}

function wrapNode(input) {
  if (input == null || input === false) return null;
  const flattened = flattenChildren(input);
  if (flattened.length === 0) return null;
  return { node: flattened[0] };
}

function Stack(props = {}) {
  return {
    id: props.id ?? undefined,
    type: "Stack",
    direction: props.direction ?? "vertical",
    spacing: props.spacing ?? 8,
    children: flattenChildren(props.children),
  };
}

function Inline(props = {}) {
  return {
    id: props.id ?? undefined,
    type: "Inline",
    spacing: props.spacing ?? 8,
    children: flattenChildren(props.children),
  };
}

function Row(props = {}) {
  return {
    id: props.id ?? undefined,
    type: "Row",
    action: props.action ?? null,
    payload: props.payload ?? null,
    children: flattenChildren(props.children),
  };
}

function Text(props = {}) {
  return {
    id: props.id ?? undefined,
    type: "Text",
    text: props.text ?? extractText(props.children),
    role: props.role ?? undefined,
    tone: props.tone ?? undefined,
    lineClamp: props.lineClamp ?? undefined,
    strikethrough: props.strikethrough ?? undefined,
    children: [],
  };
}

function Icon(props = {}) {
  return {
    id: props.id ?? undefined,
    type: "Icon",
    symbol: props.symbol ?? props.icon ?? props.name ?? undefined,
    tone: props.tone ?? undefined,
    children: [],
  };
}

function IconButton(props = {}) {
  return {
    id: props.id ?? undefined,
    type: "IconButton",
    symbol: props.symbol ?? props.icon ?? props.name ?? undefined,
    action: props.action ?? null,
    payload: props.payload ?? null,
    tone: props.tone ?? undefined,
    disabled: props.disabled ?? false,
    children: [],
  };
}

function Checkbox(props = {}) {
  return {
    id: props.id ?? undefined,
    type: "Checkbox",
    checked: props.checked ?? false,
    action: props.action ?? null,
    payload: props.payload ?? null,
    children: [],
  };
}

function Input(props = {}) {
  return {
    id: props.id ?? undefined,
    type: "Input",
    value: props.value ?? "",
    placeholder: props.placeholder ?? "",
    changeAction: props.changeAction ?? null,
    submitAction: props.submitAction ?? null,
    leadingAccessory: wrapNode(props.leadingAccessory),
    trailingAccessory: wrapNode(props.trailingAccessory),
    children: [],
  };
}

function Button(props = {}) {
  return {
    id: props.id ?? undefined,
    type: "Button",
    title: props.title ?? extractText(props.children),
    action: props.action ?? null,
    payload: props.payload ?? null,
    children: [],
  };
}

module.exports = {
  Stack,
  Inline,
  Row,
  Text,
  Icon,
  IconButton,
  Checkbox,
  Input,
  Button,
  __internal: {
    flattenChildren,
    extractText,
  },
};
