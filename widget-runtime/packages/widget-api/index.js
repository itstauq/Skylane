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

function Stack(props = {}) {
  return {
    id: props.id ?? undefined,
    type: "Stack",
    direction: props.direction ?? "vertical",
    spacing: props.spacing ?? 8,
    children: flattenChildren(props.children),
  };
}

function Text(props = {}) {
  return {
    id: props.id ?? undefined,
    type: "Text",
    text: props.text ?? extractText(props.children),
    children: [],
  };
}

function Button(props = {}) {
  return {
    id: props.id ?? undefined,
    type: "Button",
    title: props.title ?? extractText(props.children),
    action: props.action ?? null,
    children: [],
  };
}

module.exports = {
  Stack,
  Text,
  Button,
  __internal: {
    flattenChildren,
    extractText,
  },
};
