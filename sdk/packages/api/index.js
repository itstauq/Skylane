const React = require("react");
const { useLocalStorage } = require("./hooks/useLocalStorage");
const { LocalStorage } = require("./runtime");

function Stack(props = {}) {
  return React.createElement("Stack", props, props.children);
}

function Text(props = {}) {
  return React.createElement("Text", props, props.children);
}

function Button(props = {}) {
  return React.createElement("Button", props, props.children);
}

module.exports = {
  Stack,
  Text,
  Button,
  LocalStorage,
  useLocalStorage,
};
