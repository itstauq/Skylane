import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const sdkRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const apiEntryPath = path.join(sdkRoot, "packages", "api", "index.js");

function loadAPI() {
  const source = fs.readFileSync(apiEntryPath, "utf8");
  const module = { exports: {} };
  const fakeReact = {
    Fragment: Symbol.for("react.fragment"),
    Children: {
      toArray(value) {
        if (value == null) {
          return [];
        }

        return Array.isArray(value) ? value.flat() : [value];
      },
    },
    createElement(type, props, ...children) {
      const { key, ...restProps } = props ?? {};
      return {
        key: key ?? null,
        type,
        props: {
          ...restProps,
          children: children.length <= 1 ? children[0] : children,
        },
      };
    },
    isValidElement(value) {
      return Boolean(value && typeof value === "object" && "type" in value && "props" in value);
    },
  };

  const sandbox = {
    module,
    exports: module.exports,
    require(specifier) {
      switch (specifier) {
        case "react":
          return fakeReact;
        case "./hooks/useLocalStorage":
          return { useLocalStorage() {} };
        case "./hooks/usePromise":
          return { usePromise() {} };
        case "./hooks/useFetch":
          return { useFetch() {} };
        case "./hooks/useTheme":
          return {
            useTheme() {
              return {
                spacing: { xs: 4, sm: 8, md: 12, lg: 16, xl: 20 },
                radius: { sm: 8, md: 12, lg: 16 },
                colors: {
                  surfacePrimary: "#111111",
                  surfaceSecondary: "#222222",
                  surfaceAccent: "#333333",
                  borderPrimary: "#444444",
                  borderSecondary: "#555555",
                  borderAccent: "#666666",
                  textPrimary: "#ffffff",
                  textSecondary: "#cccccc",
                  textTertiary: "#999999",
                  textOnAccent: "#ffffff",
                  iconPrimary: "#ffffff",
                  iconSecondary: "#cccccc",
                  iconOnAccent: "#ffffff",
                },
              };
            },
          };
        case "./hooks/usePreference":
          return { usePreference() { return [undefined, () => {}]; } };
        case "./hooks/useCameras":
          return {
            useCameras() {
              return {
                items: [],
                value: undefined,
                setValue() {},
                isLoading: false,
                isPending: false,
                error: undefined,
                refresh() {},
              };
            },
          };
        case "./hooks/useMedia":
          return {
            useMedia() {
              return {
                source: null,
                playbackState: "stopped",
                item: null,
                timeline: null,
                artwork: null,
                availableActions: [],
                isLoading: false,
                isPending: false,
                error: undefined,
                refresh() {},
                play() {},
                pause() {},
                togglePlayPause() {},
                nextTrack() {},
                previousTrack() {},
                openSourceApp() {},
              };
            },
          };
        case "./functions/openURL":
          return { openURL() {} };
        case "./runtime":
          return {
            LocalStorage: {},
            getCurrentProps() { return { preferences: { mailbox: "inbox" } }; },
            callRpc() {},
          };
        default:
          throw new Error(`Unexpected dependency: ${specifier}`);
      }
    },
  };

  vm.runInNewContext(source, sandbox, { filename: apiEntryPath });
  return module.exports;
}

test("@notchapp/api exports the extended non-image component surface", () => {
  const api = loadAPI();

  for (const name of [
    "Stack",
    "Inline",
    "Spacer",
    "Overlay",
    "Text",
    "Icon",
    "Image",
    "Button",
    "Row",
    "IconButton",
    "Checkbox",
    "Input",
    "ScrollView",
    "Marquee",
    "Divider",
    "Circle",
    "RoundedRect",
    "usePreference",
    "useCameras",
    "useMedia",
    "DropdownMenuLoadingItem",
    "DropdownMenuErrorItem",
  ]) {
    assert.equal(typeof api[name], "function", `${name} should be exported`);
  }
});

test("@notchapp/api no longer exports the old imperative camera and preference helpers", () => {
  const api = loadAPI();
  assert.equal(api.getPreferenceValues, undefined);
  assert.equal(api.setPreferenceValue, undefined);
  assert.equal(api.listCameras, undefined);
  assert.equal(api.selectCamera, undefined);
  assert.equal(api.getTheme, undefined);
});

test("component wrappers emit host elements with the expected props", () => {
  const api = loadAPI();

  const row = api.Row({
    onPress: () => {},
    children: [
      api.Icon({ symbol: "sparkles" }),
      api.Text({ children: "Capture" }),
    ],
  });
  const input = api.Input({
    value: "Draft",
    placeholder: "Type",
    onChange: () => {},
    onSubmit: () => {},
    trailingAccessory: api.Icon({ symbol: "mic" }),
  });
  const roundedRect = api.RoundedRect({
    fill: "#111111",
    overlay: api.IconButton({ key: "overlay-plus", symbol: "plus", onPress: () => {} }),
  });
  const marquee = api.Marquee({
    active: false,
    speed: 24,
    children: api.Text({ children: "Now Playing" }),
  });
  const cardClick = () => {};
  const card = api.Card({
    onClick: cardClick,
    children: api.Text({ children: "Now Playing" }),
  });
  const image = api.Image({
    src: "assets/cover.png",
    opacity: 0.8,
    contentMode: "fit",
  });
  const remoteImage = api.Image({
    src: "https://example.com/cover.png",
    contentMode: "fit",
  });
  const inputChildren = Array.isArray(input.props.children) ? input.props.children : [input.props.children];
  const roundedRectChildren = Array.isArray(roundedRect.props.children)
    ? roundedRect.props.children
    : [roundedRect.props.children];

  assert.equal(row.type, "Row");
  assert.equal(input.type, "Input");
  assert.equal(roundedRect.type, "RoundedRect");
  assert.equal(marquee.type, "Marquee");
  assert.equal(card.type, api.RoundedRect);
  assert.equal(image.type, "Image");

  assert.equal(input.props.value, "Draft");
  assert.equal(input.props.placeholder, "Type");
  assert.equal(image.props.src, "assets/cover.png");
  assert.equal(image.props.opacity, 0.8);
  assert.equal(image.props.contentMode, "fit");
  assert.equal(remoteImage.props.src, "https://example.com/cover.png");
  assert.equal(remoteImage.props.contentMode, "fit");
  assert.equal(Array.isArray(row.props.children), true);
  assert.equal(inputChildren[0].type, "__notch_trailingAccessory");
  assert.equal(inputChildren[0].props.children.type, "Icon");
  assert.equal(roundedRectChildren[0].type, "__notch_overlay");
  assert.equal(roundedRectChildren[0].key, "overlay-plus");
  assert.equal(roundedRectChildren[0].props.children.type, "IconButton");
  assert.equal(marquee.props.active, false);
  assert.equal(marquee.props.delay, 1.2);
  assert.equal(marquee.props.speed, 24);
  assert.equal(marquee.props.gap, 28);
  assert.equal(marquee.props.fadeEdges, true);
  assert.equal(card.props.onPress, cardClick);
});
