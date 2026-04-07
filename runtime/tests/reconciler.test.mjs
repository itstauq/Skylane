import assert from "node:assert/strict";
import { test } from "node:test";
import Module, { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { invoke as invokeCallback } from "../callback-registry.mjs";
import { createHostEventBus } from "../host-events.mjs";
import { createRenderer } from "../reconciler.mjs";

const testDir = path.dirname(fileURLToPath(import.meta.url));
const runtimeNodeModules = path.resolve(testDir, "..", "node_modules");
process.env.NODE_PATH = [process.env.NODE_PATH, runtimeNodeModules]
  .filter(Boolean)
  .join(path.delimiter);
Module._initPaths();

const require = createRequire(import.meta.url);
const React = require("react");
const api = require("../../sdk/packages/api");
const OVERLAY_SLOT_TYPE = "__notch_overlay";
const LEADING_ACCESSORY_SLOT_TYPE = "__notch_leadingAccessory";
const TRAILING_ACCESSORY_SLOT_TYPE = "__notch_trailingAccessory";
const MENU_LABEL_SLOT_TYPE = "__notch_menuLabel";

const mockTheme = {
  colors: {
    accent: "#B08AFA",
    accentForeground: "#000000BF",
    surfaceCanvas: "#17191E",
    surfacePrimary: "#FFFFFF10",
    surfaceSecondary: "#FFFFFF0D",
    surfaceTertiary: "#FFFFFF08",
    surfaceAccent: "#B08AFA2E",
    surfaceAccentEmphasis: "#B08AFA42",
    surfaceOverlay: "#00000047",
    borderPrimary: "#FFFFFF1F",
    borderSecondary: "#FFFFFF12",
    borderAccent: "#B08AFA52",
    textPrimary: "#FFFFFFE0",
    textSecondary: "#FFFFFFB8",
    textTertiary: "#FFFFFF6B",
    textPlaceholder: "#FFFFFF7A",
    textOnAccent: "#000000BF",
    iconPrimary: "#FFFFFFD6",
    iconSecondary: "#FFFFFFB8",
    iconTertiary: "#FFFFFF70",
    iconOnAccent: "#000000BF",
    success: "#33D175",
    warning: "#FCAD59",
    destructive: "#FA6478",
  },
  typography: {
    title: { size: 12, weight: "semibold" },
    subtitle: { size: 11, weight: "semibold" },
    body: { size: 11, weight: "medium" },
    caption: { size: 10, weight: "semibold" },
    label: { size: 11, weight: "semibold" },
    placeholder: { size: 11, weight: "medium" },
    buttonLabel: { size: 11, weight: "semibold" },
  },
  spacing: { xs: 4, sm: 8, md: 10, lg: 12, xl: 16 },
  radius: { sm: 10, md: 12, lg: 16, xl: 18, full: 999 },
  controls: {
    buttonHeight: 28,
    rowHeight: 34,
    inputHeight: 40,
    iconButtonSize: 16,
    iconButtonLargeSize: 20,
    checkboxSize: 14,
  },
};

let currentProps = {
  theme: mockTheme,
  preferences: {},
};
let rpcHandler = () => Promise.resolve(null);
const hostEvents = createHostEventBus();

function subscribeMockHostEvent(name, listener) {
  return hostEvents.subscribe(name, listener);
}

function emitMockHostEvent(name, payload) {
  hostEvents.dispatch(name, payload);
}

function resetMockRuntime() {
  currentProps = {
    theme: mockTheme,
    preferences: {},
  };
  rpcHandler = () => Promise.resolve(null);
  hostEvents.clear();
}

globalThis.__NOTCH_RUNTIME__ = {
  localStorage: {
    getItem() {
      return null;
    },
    setItem() {},
    removeItem() {},
    allItems() {
      return {};
    },
  },
  getCurrentProps() {
    return currentProps;
  },
  callRpc(method, params) {
    return rpcHandler(method, params);
  },
  subscribeHostEvent(name, listener) {
    return subscribeMockHostEvent(name, listener);
  },
};

function renderTree(element) {
  const renderer = createRenderer();
  let commit = null;
  renderer.onCommit((payload) => {
    commit = payload;
  });
  renderer.render(element);
  assert.ok(commit);
  return commit.data;
}

function overlaySlot(child, alignment = "center", key) {
  return React.createElement(OVERLAY_SLOT_TYPE, key == null ? { alignment } : { alignment, key }, child);
}

function leadingAccessorySlot(child) {
  return React.createElement(LEADING_ACCESSORY_SLOT_TYPE, null, child);
}

function trailingAccessorySlot(child) {
  return React.createElement(TRAILING_ACCESSORY_SLOT_TYPE, null, child);
}

function menuLabelSlot(child) {
  return React.createElement(MENU_LABEL_SLOT_TYPE, null, child);
}

async function flushEffects() {
  await new Promise((resolve) => setImmediate(resolve));
}

test("reconciler serializes the new component wrappers into v2 host nodes", () => {
  const tree = renderTree(
    React.createElement(
      "Stack",
      { spacing: 12, alignment: "center" },
        React.createElement(
          "Inline",
          { spacing: 6, alignment: "top" },
          React.createElement("Icon", { symbol: "star.fill", size: 16 }),
          React.createElement("Image", { src: "assets/cover.png" }),
          React.createElement("Text", { tone: "secondary", lineClamp: 1 }, "Hello"),
          React.createElement("Spacer", { minLength: 4 })
        ),
      React.createElement(
        "ScrollView",
      { spacing: 8, fadeEdges: "both" },
        React.createElement("Divider", { color: "#FF0000AA" }),
        React.createElement("Circle", { size: 12, fill: "#FFFFFF" }),
        React.createElement("RoundedRect", { width: 20, height: 10, cornerRadius: 4, fill: "#111111" }),
        React.createElement("Camera", { cornerRadius: 16 })
      ),
      React.createElement(
        "Marquee",
        { active: true, speed: 30 },
        React.createElement("Text", { tone: "primary", lineClamp: 1 }, "Now Playing")
      ),
      React.createElement("Row", null, React.createElement("Text", null, "Row")),
      React.createElement("IconButton", { symbol: "trash", size: "large" }),
      React.createElement("Checkbox", { checked: true }),
      React.createElement("Input", { value: "Draft", placeholder: "Type here" })
    )
  );

  assert.equal(tree.type, "Stack");
  assert.equal(tree.children[0].type, "Inline");
  assert.equal(tree.children[0].children[0].type, "Icon");
  assert.equal(tree.children[0].children[1].type, "Image");
  assert.equal(tree.children[0].children[1].props.src, "assets/cover.png");
  assert.equal(tree.children[0].children[2].type, "Text");
  assert.equal(tree.children[0].children[3].type, "Spacer");

  assert.equal(tree.children[1].type, "ScrollView");
  assert.equal(tree.children[1].children[0].type, "Divider");
  assert.equal(tree.children[1].children[1].type, "Circle");
  assert.equal(tree.children[1].children[2].type, "RoundedRect");
  assert.equal(tree.children[1].children[3].type, "Camera");

  assert.equal(tree.children[2].type, "Marquee");
  assert.equal(tree.children[2].children[0].type, "Text");
  assert.equal(tree.children[3].type, "Row");
  assert.equal(tree.children[4].type, "IconButton");
  assert.equal(tree.children[5].type, "Checkbox");
  assert.equal(tree.children[6].type, "Input");
});

test("reconciler serializes shadcn-inspired product components into host primitives", () => {
  const tree = renderTree(
    React.createElement(
      api.Section,
      { spacing: "md" },
      React.createElement(
        api.Card,
        { variant: "accent" },
        React.createElement(
          api.CardContent,
          null,
          React.createElement(api.CardTitle, null, "After Hours"),
          React.createElement(api.CardDescription, null, "Now playing")
        )
      ),
      React.createElement(
        api.List,
        { spacing: "sm" },
        React.createElement(
          api.ListItem,
          {
            onPress: () => {},
            leadingAccessory: React.createElement(api.Checkbox, { checked: true }),
          },
          React.createElement(api.ListItemTitle, null, "Ship the new API"),
          React.createElement(
            api.ListItemAction,
            null,
            React.createElement(api.IconButton, {
              symbol: "trash",
              variant: "secondary",
              size: "md",
            })
          )
        )
      )
    )
  );

  assert.equal(tree.type, "Stack");
  assert.equal(tree.children[0].type, "RoundedRect");
  assert.equal(tree.children[0].props.fill, mockTheme.colors.surfaceAccent);
  assert.equal(tree.children[0].children[0].type, "Stack");
  assert.equal(tree.children[0].children[0].children[0].type, "Stack");
  assert.equal(tree.children[0].children[0].children[0].children[0].type, "Text");
  assert.equal(tree.children[0].children[0].children[0].children[0].props.variant, "title");

  assert.equal(tree.children[1].type, "Stack");
  assert.equal(tree.children[1].children[0].type, "Row");
  assert.equal(tree.children[1].children[0].children[0].type, "Inline");
  assert.equal(tree.children[1].children[0].children[0].children[0].type, "Checkbox");
  assert.equal(tree.children[1].children[0].children[0].children.at(-1).type, "IconButton");
  assert.equal(tree.children[1].children[0].children[0].children.at(-1).props.variant, "secondary");
  assert.equal(tree.children[1].children[0].children[0].children.at(-1).props.size, "md");
});

test("reconciler serializes dropdown menu happy-path props and helper items into Menu nodes", () => {
  const tree = renderTree(
    React.createElement(
      api.DropdownMenu,
      {
        trigger: React.createElement(api.ToolbarButton, {
          symbol: "gearshape.fill",
          variant: "secondary",
          size: "sm",
        }),
      },
      React.createElement(api.DropdownMenuCheckboxItem, { checked: true }, "Mirror Preview"),
      React.createElement(api.DropdownMenuSeparator),
      React.createElement(api.DropdownMenuLoadingItem, null, "Loading…"),
      React.createElement(api.DropdownMenuSeparator),
      React.createElement(api.DropdownMenuErrorItem, null, "Unable to load")
    )
  );

  assert.equal(tree.type, "Menu");
  assert.equal(tree.props.label.type, "IconButton");
  assert.equal(tree.props.label.props.variant, "secondary");
  assert.equal(tree.props.label.props.size, "sm");
  assert.equal(tree.children[0].type, "Button");
  assert.equal(tree.children[0].props.checked, true);
  assert.equal(tree.children[1].type, "Divider");
  assert.equal(tree.children[2].type, "Button");
  assert.equal(tree.children[2].props.disabled, true);
  assert.equal(tree.children[3].type, "Divider");
  assert.equal(tree.children[4].type, "Button");
  assert.equal(tree.children[4].props.disabled, true);
});

test("sdk react-style callback aliases serialize to host callbacks", () => {
  let clicked = 0;
  let toggled = null;
  let changed = null;
  let submitted = null;

  const tree = renderTree(
    React.createElement(
      "Stack",
      null,
      React.createElement(api.Button, { onClick: () => { clicked += 1; } }, "Save"),
      React.createElement(api.Checkbox, {
        checked: true,
        onCheckedChange: (nextValue) => {
          toggled = nextValue;
        },
      }),
      React.createElement(api.Input, {
        value: "",
        onValueChange: (value) => {
          changed = value;
        },
        onSubmitValue: (value) => {
          submitted = value;
        },
      })
    )
  );

  invokeCallback(tree.children[0].props.onPress);
  invokeCallback(tree.children[1].props.onPress);
  invokeCallback(tree.children[2].props.onChange, { value: "hello" });
  invokeCallback(tree.children[2].props.onSubmit, { value: "done" });

  assert.equal(clicked, 1);
  assert.equal(toggled, false);
  assert.equal(changed, "hello");
  assert.equal(submitted, "done");
});

test("dropdown menu trigger button provides an overlay-ready trigger", () => {
  const tree = renderTree(
    React.createElement(
      api.DropdownMenu,
      {
        trigger: React.createElement(api.DropdownMenuTriggerButton, {
          symbol: "gearshape.fill",
          appearance: "overlay",
        }),
      },
      React.createElement(api.DropdownMenuItem, null, "Open")
    )
  );

  assert.equal(tree.type, "Menu");
  assert.equal(tree.props.label.type, "RoundedRect");
  assert.equal(tree.props.label.children[0].type, "Icon");
  assert.equal(tree.props.label.children[0].props.symbol, "gearshape.fill");
});

test("overlay serializes semantic position, inset, and offset through product components", () => {
  resetMockRuntime();

  const tree = renderTree(
    React.createElement(
      api.Card,
      null,
      React.createElement(
        api.Overlay,
        {
          placement: "top-end",
          inset: "sm",
          offset: { x: 2, y: 3 },
        },
        React.createElement(api.Icon, { symbol: "gearshape.fill" })
      ),
      React.createElement(
        api.CardContent,
        null,
        React.createElement(api.CardTitle, null, "Camera Preview")
      )
    )
  );

  assert.equal(tree.type, "RoundedRect");
  assert.equal(tree.props.overlay[0].alignment, "topTrailing");
  assert.equal(tree.props.overlay[0].inset, mockTheme.spacing.sm);
  assert.deepEqual(tree.props.overlay[0].offset, { x: 2, y: 3 });
  assert.equal(tree.props.overlay[0].node.type, "Icon");
});

test("text uses variant instead of role in the public api", () => {
  const tree = renderTree(
    React.createElement(api.Text, { variant: "subtitle", tone: "secondary" }, "Hello")
  );

  assert.equal(tree.type, "Text");
  assert.equal(tree.props.variant, "subtitle");
  assert.equal(tree.props.role, undefined);
});

test("reconciler normalizes overlay and accessory nodes and keeps callback props", () => {
  let overlayPayload = null;
  let accessoryPayload = null;
  let submitPayload = null;

  const tree = renderTree(
    React.createElement(
      "Stack",
      null,
      React.createElement(
        "RoundedRect",
        { fill: "#101010" },
        overlaySlot(
          React.createElement("IconButton", {
            symbol: "plus",
            onPress: (payload) => {
              overlayPayload = payload;
            },
          }),
          "topTrailing"
        )
      ),
      React.createElement(
        "Input",
        {
          value: "Draft",
          placeholder: "Capture",
          onChange: (payload) => {
            accessoryPayload = payload;
          },
          onSubmit: (payload) => {
            submitPayload = payload;
          },
        },
        leadingAccessorySlot(
          React.createElement("IconButton", {
            symbol: "sparkles",
            onPress: (payload) => {
              accessoryPayload = payload;
            },
          })
        ),
        trailingAccessorySlot(React.createElement("Icon", { symbol: "mic" }))
      )
    )
  );

  const roundedRect = tree.children[0];
  const input = tree.children[1];

  assert.equal(roundedRect.props.overlay[0].alignment, "topTrailing");
  assert.equal(roundedRect.props.overlay[0].node.type, "IconButton");
  assert.match(roundedRect.props.overlay[0].node.props.onPress, /^cb_/);

  assert.equal(input.props.leadingAccessory.type, "IconButton");
  assert.equal(input.props.trailingAccessory.type, "Icon");
  assert.match(input.props.leadingAccessory.props.onPress, /^cb_/);
  assert.match(input.props.onChange, /^cb_/);
  assert.match(input.props.onSubmit, /^cb_/);

  invokeCallback(roundedRect.props.overlay[0].node.props.onPress, { source: "overlay" });
  invokeCallback(input.props.leadingAccessory.props.onPress, { source: "leading" });
  invokeCallback(input.props.onSubmit, { value: "Submitted" });

  assert.deepEqual(overlayPayload, { source: "overlay" });
  assert.deepEqual(accessoryPayload, { source: "leading" });
  assert.deepEqual(submitPayload, { value: "Submitted" });
});

test("reconciler renders nested overlay and accessory components through React", () => {
  function HookAccessory(props) {
    const [symbol] = React.useState(props.symbol);
    return React.createElement("IconButton", { symbol, onPress: props.onPress });
  }

  class ClassAccessory extends React.Component {
    render() {
      return React.createElement("Icon", { symbol: this.props.symbol });
    }
  }

  const tree = renderTree(
    React.createElement(
      "Stack",
      null,
      React.createElement(
        "RoundedRect",
        null,
        overlaySlot(React.createElement(HookAccessory, { symbol: "plus" }))
      ),
      React.createElement(
        "Input",
        { value: "Draft" },
        leadingAccessorySlot(React.createElement(HookAccessory, { symbol: "sparkles" })),
        trailingAccessorySlot(React.createElement(ClassAccessory, { symbol: "mic" }))
      )
    )
  );

  assert.equal(tree.children[0].props.overlay[0].node.type, "IconButton");
  assert.equal(tree.children[0].props.overlay[0].node.props.symbol, "plus");
  assert.equal(tree.children[1].props.leadingAccessory.type, "IconButton");
  assert.equal(tree.children[1].props.leadingAccessory.props.symbol, "sparkles");
  assert.equal(tree.children[1].props.trailingAccessory.type, "Icon");
  assert.equal(tree.children[1].props.trailingAccessory.props.symbol, "mic");
});

test("reconciler serializes frame infinity sentinels and flattens fragment overlays", () => {
  const tree = renderTree(
    React.createElement(
      "RoundedRect",
      { frame: { maxWidth: Infinity, maxHeight: Infinity } },
      overlaySlot(
        React.createElement(
          React.Fragment,
          null,
          React.createElement("IconButton", { symbol: "plus" }),
          React.createElement("Icon", { symbol: "mic" })
        )
      )
    )
  );

  assert.equal(tree.props.frame.maxWidth, "infinity");
  assert.equal(tree.props.frame.maxHeight, "infinity");
  assert.equal(tree.props.overlay.length, 2);
  assert.equal(tree.props.overlay[0].node.type, "IconButton");
  assert.equal(tree.props.overlay[1].node.type, "Icon");
});

test("reconciler preserves menu labels and callback props", () => {
  let menuPayload = null;

  const tree = renderTree(
    React.createElement(
      "Menu",
      null,
      menuLabelSlot(React.createElement("IconButton", { symbol: "gearshape.fill" })),
      React.createElement("Button", {
        title: "Mirror Preview",
        onPress: (payload) => {
          menuPayload = payload;
        },
      })
    )
  );

  assert.equal(tree.type, "Menu");
  assert.equal(tree.props.label.type, "IconButton");
  assert.equal(tree.children[0].type, "Button");
  assert.match(tree.children[0].props.onPress, /^cb_/);

  invokeCallback(tree.children[0].props.onPress, { source: "menu" });
  assert.deepEqual(menuPayload, { source: "menu" });
});

test("text nodes preserve overlay slot children while keeping flattened text content", () => {
  const tree = renderTree(
    React.createElement(
      "Text",
      null,
      "Hello",
      overlaySlot(React.createElement("Icon", { symbol: "plus" }), "trailing")
    )
  );

  assert.equal(tree.type, "Text");
  assert.equal(tree.props.text, "Hello");
  assert.equal(tree.children.length, 0);
  assert.equal(tree.props.overlay.length, 1);
  assert.equal(tree.props.overlay[0].alignment, "trailing");
  assert.equal(tree.props.overlay[0].node.type, "Icon");
});

test("usePreference supports updater setters and resyncs when host props change", async () => {
  resetMockRuntime();
  currentProps = {
    theme: mockTheme,
    preferences: {
      mailbox: "inbox",
    },
  };

  const rpcCalls = [];
  rpcHandler = (method, params) => {
    rpcCalls.push({ method, params });
    return Promise.resolve(null);
  };

  const renderer = createRenderer();
  const commits = [];
  renderer.onCommit((payload) => {
    commits.push(payload);
  });

  function PreferenceWidget() {
    const [mailbox, setMailbox] = api.usePreference("mailbox");
    return React.createElement(
      "Stack",
      null,
      React.createElement("Text", null, String(mailbox ?? "missing")),
      React.createElement("Button", {
        title: "Update",
        onPress: () => {
          setMailbox((value) => `${value ?? ""}!`);
        },
      })
    );
  }

  renderer.render(React.createElement(PreferenceWidget));
  let tree = commits.at(-1).data;
  assert.equal(tree.children[0].props.text, "inbox");

  invokeCallback(tree.children[1].props.onPress);
  await flushEffects();
  renderer.emitFullTree();

  tree = commits.at(-1).data;
  assert.equal(tree.children[0].props.text, "inbox!");
  assert.deepEqual(rpcCalls, [
    {
      method: "preferences.setValue",
      params: {
        name: "mailbox",
        value: "inbox!",
      },
    },
  ]);

  currentProps = {
    ...currentProps,
    preferences: {
      mailbox: "archive",
    },
  };
  renderer.render(React.createElement(PreferenceWidget));
  await flushEffects();
  renderer.emitFullTree();

  tree = commits.at(-1).data;
  assert.equal(tree.children[0].props.text, "archive");
});

test("useCameras loads devices, supports optimistic selection, and refreshes", async () => {
  resetMockRuntime();
  currentProps = {
    theme: mockTheme,
    preferences: {
      cameraDeviceId: "cam-1",
    },
  };

  let refreshVersion = 0;
  const rpcCalls = [];
  rpcHandler = async (method, params) => {
    rpcCalls.push({ method, params });

    if (method === "camera.listDevices") {
      if (refreshVersion === 0) {
        return [
          { id: "cam-1", name: "Front Camera", selected: true },
          { id: "cam-2", name: "Desk Camera", selected: false },
        ];
      }

      return [
        { id: "cam-1", name: "Front Camera", selected: false },
        { id: "cam-2", name: "Studio Camera", selected: true },
      ];
    }

    if (method === "camera.selectDevice") {
      return null;
    }

    throw new Error(`Unexpected RPC: ${method}`);
  };

  const renderer = createRenderer();
  const commits = [];
  renderer.onCommit((payload) => {
    commits.push(payload);
  });

  function CamerasWidget() {
    const cameras = api.useCameras();
    return React.createElement(
      "Stack",
      null,
      React.createElement("Text", null, String(cameras.value ?? "missing")),
      React.createElement("Text", null, String(cameras.items.length)),
      React.createElement("Text", null, cameras.items[1]?.name ?? "missing"),
      React.createElement("Button", {
        title: "Select",
        onPress: () => {
          cameras.setValue("cam-2");
        },
      }),
      React.createElement("Button", {
        title: "Refresh",
        onPress: () => {
          cameras.refresh();
        },
      })
    );
  }

  renderer.render(React.createElement(CamerasWidget));
  await flushEffects();
  await flushEffects();
  renderer.emitFullTree();

  let tree = commits.at(-1).data;
  assert.equal(tree.children[0].props.text, "cam-1");
  assert.equal(tree.children[1].props.text, "2");
  assert.equal(tree.children[2].props.text, "Desk Camera");

  invokeCallback(tree.children[3].props.onPress);
  await flushEffects();
  renderer.emitFullTree();

  tree = commits.at(-1).data;
  assert.equal(tree.children[0].props.text, "cam-2");

  currentProps = {
    ...currentProps,
    preferences: {
      cameraDeviceId: "cam-2",
    },
  };
  renderer.render(React.createElement(CamerasWidget));
  await flushEffects();
  renderer.emitFullTree();

  tree = commits.at(-1).data;
  assert.equal(tree.children[0].props.text, "cam-2");

  refreshVersion = 1;
  invokeCallback(tree.children[4].props.onPress);
  await flushEffects();
  await flushEffects();
  renderer.emitFullTree();

  tree = commits.at(-1).data;
  assert.equal(tree.children[2].props.text, "Studio Camera");
  assert.equal(rpcCalls.filter((call) => call.method === "camera.listDevices").length, 2);
  assert.equal(rpcCalls.filter((call) => call.method === "camera.selectDevice").length, 1);
});

test("useCameras rolls back optimistic selection when selection fails", async () => {
  resetMockRuntime();
  currentProps = {
    theme: mockTheme,
    preferences: {
      cameraDeviceId: "cam-1",
    },
  };

  rpcHandler = async (method) => {
    if (method === "camera.listDevices") {
      return [
        { id: "cam-1", name: "Front Camera", selected: true },
        { id: "cam-2", name: "Desk Camera", selected: false },
      ];
    }

    if (method === "camera.selectDevice") {
      throw new Error("Unable to switch camera.");
    }

    throw new Error(`Unexpected RPC: ${method}`);
  };

  const renderer = createRenderer();
  const commits = [];
  renderer.onCommit((payload) => {
    commits.push(payload);
  });

  function CamerasWidget() {
    const cameras = api.useCameras();
    return React.createElement(
      "Stack",
      null,
      React.createElement("Text", null, String(cameras.value ?? "missing")),
      React.createElement("Button", {
        title: "Select",
        onPress: () => {
          cameras.setValue("cam-2");
        },
      }),
      cameras.error
        ? React.createElement("Text", null, cameras.error.message)
        : null
    );
  }

  renderer.render(React.createElement(CamerasWidget));
  await flushEffects();
  await flushEffects();
  renderer.emitFullTree();

  let tree = commits.at(-1).data;
  assert.equal(tree.children[0].props.text, "cam-1");

  invokeCallback(tree.children[1].props.onPress);
  await flushEffects();
  await flushEffects();
  renderer.emitFullTree();

  tree = commits.at(-1).data;
  assert.equal(tree.children[0].props.text, "cam-1");
  assert.equal(tree.children[2].props.text, "Unable to switch camera.");
});

test("useMedia keeps current state after transport actions until the host pushes an update", async () => {
  resetMockRuntime();

  const pausedState = {
    source: {
      id: "com.apple.Music",
      name: "Music",
      bundleIdentifier: "com.apple.Music",
      kind: "application",
    },
    playbackState: "paused",
    item: {
      id: "track-1",
      title: "After Hours",
      artist: "The Weeknd",
      album: "After Hours",
    },
    timeline: {
      positionSeconds: 12,
      durationSeconds: 240,
    },
    artwork: null,
    availableActions: [
      "play",
      "togglePlayPause",
      "nextTrack",
      "previousTrack",
      "openSourceApp",
    ],
  };
  const playingState = {
    ...pausedState,
    playbackState: "playing",
    availableActions: [
      "pause",
      "togglePlayPause",
      "nextTrack",
      "previousTrack",
      "openSourceApp",
    ],
  };
  const rpcCalls = [];
  rpcHandler = async (method) => {
    rpcCalls.push(method);

    if (method === "media.getState") {
      return pausedState;
    }

    if (method === "media.play") {
      return null;
    }

    if (method === "media.openSourceApp") {
      return null;
    }

    throw new Error(`Unexpected RPC: ${method}`);
  };

  const renderer = createRenderer();
  const commits = [];
  renderer.onCommit((payload) => {
    commits.push(payload);
  });

  function MediaWidget() {
    const media = api.useMedia();
    return React.createElement(
      "Stack",
      null,
      React.createElement("Text", null, media.item?.title ?? "Nothing Playing"),
      React.createElement("Text", null, media.playbackState),
      React.createElement("Text", null, media.availableActions.join(",")),
      React.createElement("Button", {
        title: "Play",
        onPress: () => {
          media.play();
        },
      }),
      React.createElement("Button", {
        title: "Open",
        onPress: () => {
          media.openSourceApp();
        },
      })
    );
  }

  renderer.render(React.createElement(MediaWidget));
  await flushEffects();
  await flushEffects();
  renderer.emitFullTree();

  let tree = commits.at(-1).data;
  assert.equal(tree.children[0].props.text, "After Hours");
  assert.equal(tree.children[1].props.text, "paused");
  assert.match(tree.children[2].props.text, /openSourceApp/);

  invokeCallback(tree.children[3].props.onPress);
  await flushEffects();
  await flushEffects();
  renderer.emitFullTree();

  tree = commits.at(-1).data;
  assert.equal(tree.children[1].props.text, "paused");
  assert.match(tree.children[2].props.text, /play/);

  emitMockHostEvent("media.state", playingState);
  await flushEffects();
  renderer.emitFullTree();

  tree = commits.at(-1).data;
  assert.equal(tree.children[1].props.text, "playing");
  assert.match(tree.children[2].props.text, /pause/);

  invokeCallback(tree.children[4].props.onPress);
  await flushEffects();
  await flushEffects();
  renderer.emitFullTree();

  tree = commits.at(-1).data;
  assert.equal(tree.children[0].props.text, "After Hours");
  assert.equal(tree.children[1].props.text, "playing");
  assert.deepEqual(rpcCalls, ["media.getState", "media.play", "media.openSourceApp"]);
});

test("useMedia does not poll automatically after the initial getState", async () => {
  resetMockRuntime();

  let getStateCallCount = 0;
  rpcHandler = async (method) => {
    if (method !== "media.getState") {
      throw new Error(`Unexpected RPC: ${method}`);
    }

    getStateCallCount += 1;
    return {
      source: null,
      playbackState: "stopped",
      item: {
        title: getStateCallCount === 1 ? "First" : "Second",
      },
      timeline: null,
      artwork: null,
      availableActions: [],
    };
  };

  const renderer = createRenderer();
  const commits = [];
  renderer.onCommit((payload) => {
    commits.push(payload);
  });

  function MediaWidget() {
    const media = api.useMedia();
    return React.createElement("Text", null, media.item?.title ?? "Nothing Playing");
  }

  renderer.render(React.createElement(MediaWidget));
  await flushEffects();
  await flushEffects();
  renderer.emitFullTree();

  let tree = commits.at(-1).data;
  assert.equal(tree.props.text, "First");

  await new Promise((resolve) => setTimeout(resolve, 60));
  await flushEffects();
  await flushEffects();
  renderer.emitFullTree();

  tree = commits.at(-1).data;
  assert.equal(tree.props.text, "First");
  assert.equal(getStateCallCount, 1);

  renderer.render(React.createElement("Text", null, "done"));
  await flushEffects();
});

test("useMedia applies pushed host media state updates without waiting for polling", async () => {
  resetMockRuntime();

  const pausedState = {
    source: {
      id: "com.apple.Music",
      name: "Music",
      bundleIdentifier: "com.apple.Music",
      kind: "application",
    },
    playbackState: "paused",
    item: {
      id: "track-1",
      title: "After Hours",
      artist: "The Weeknd",
      album: "After Hours",
    },
    timeline: null,
    artwork: null,
    availableActions: ["play", "togglePlayPause"],
  };
  const playingState = {
    ...pausedState,
    playbackState: "playing",
    item: {
      ...pausedState.item,
      id: "track-2",
      title: "Blinding Lights",
    },
    availableActions: ["pause", "togglePlayPause", "nextTrack", "previousTrack"],
  };
  const rpcCalls = [];
  rpcHandler = async (method) => {
    rpcCalls.push(method);
    if (method === "media.getState") {
      return pausedState;
    }

    throw new Error(`Unexpected RPC: ${method}`);
  };

  const renderer = createRenderer();
  const commits = [];
  renderer.onCommit((payload) => {
    commits.push(payload);
  });

  function MediaWidget() {
    const media = api.useMedia();
    return React.createElement(
      "Stack",
      null,
      React.createElement("Text", null, media.item?.title ?? "Nothing Playing"),
      React.createElement("Text", null, media.playbackState)
    );
  }

  renderer.render(React.createElement(MediaWidget));
  await flushEffects();
  await flushEffects();
  renderer.emitFullTree();

  let tree = commits.at(-1).data;
  assert.equal(tree.children[0].props.text, "After Hours");
  assert.equal(tree.children[1].props.text, "paused");
  assert.deepEqual(rpcCalls, ["media.getState"]);

  emitMockHostEvent("media.state", playingState);
  await flushEffects();
  renderer.emitFullTree();

  tree = commits.at(-1).data;
  assert.equal(tree.children[0].props.text, "Blinding Lights");
  assert.equal(tree.children[1].props.text, "playing");
  assert.deepEqual(rpcCalls, ["media.getState"]);
});

test("reconciler preserves stable node ids across keyed reorders", () => {
  const renderer = createRenderer();
  const commits = [];
  renderer.onCommit((payload) => {
    commits.push(payload);
  });

  renderer.render(
    React.createElement(
      "Stack",
      null,
      React.createElement("Row", { key: "alpha" }, React.createElement("Text", null, "Alpha")),
      React.createElement("Row", { key: "beta" }, React.createElement("Text", null, "Beta"))
    )
  );

  const initialTree = commits.at(-1).data;
  const alphaId = initialTree.children[0].id;
  const betaId = initialTree.children[1].id;

  renderer.render(
    React.createElement(
      "Stack",
      null,
      React.createElement("Row", { key: "beta" }, React.createElement("Text", null, "Beta")),
      React.createElement("Row", { key: "alpha" }, React.createElement("Text", null, "Alpha"))
    )
  );
  renderer.emitFullTree();

  const reorderedTree = commits.at(-1).data;
  assert.equal(reorderedTree.children[0].id, betaId);
  assert.equal(reorderedTree.children[1].id, alphaId);
});

test("keyed overlay items preserve node identity across reorder", () => {
  const renderer = createRenderer();
  const commits = [];
  renderer.onCommit((payload) => {
    commits.push(payload);
  });

  function App(props) {
    return React.createElement(
      "RoundedRect",
      null,
      ...props.items.map((item) =>
        overlaySlot(
          React.createElement("IconButton", { symbol: item.symbol }),
          "center",
          item.key
        )
      )
    );
  }

  renderer.render(
    React.createElement(App, {
      items: [
        { key: "alpha", symbol: "a.circle" },
        { key: "beta", symbol: "b.circle" },
      ],
    })
  );

  const initialTree = commits.at(-1).data;
  const firstOverlayId = initialTree.props.overlay[0].node.id;
  const secondOverlayId = initialTree.props.overlay[1].node.id;

  renderer.render(
    React.createElement(App, {
      items: [
        { key: "beta", symbol: "b.circle" },
        { key: "alpha", symbol: "a.circle" },
      ],
    })
  );
  renderer.emitFullTree();

  const reorderedTree = commits.at(-1).data;
  assert.equal(reorderedTree.props.overlay[0].node.id, secondOverlayId);
  assert.equal(reorderedTree.props.overlay[1].node.id, firstOverlayId);
});

test("overlay state persists across renders without remounting a nested root", async () => {
  const renderer = createRenderer();
  const commits = [];
  renderer.onCommit((payload) => {
    commits.push(payload);
  });

  function StatefulOverlay() {
    const [count, setCount] = React.useState(0);
    return React.createElement("IconButton", {
      symbol: String(count),
      onPress: () => {
        setCount((value) => value + 1);
      },
    });
  }

  function App(props) {
    return React.createElement(
      "RoundedRect",
      { fill: props.fill },
      overlaySlot(React.createElement(StatefulOverlay))
    );
  }

  renderer.render(React.createElement(App, { fill: "#111111" }));
  let tree = commits.at(-1).data;
  const originalOverlayId = tree.props.overlay[0].node.id;
  const increment = tree.props.overlay[0].node.props.onPress;

  invokeCallback(increment);
  await flushEffects();
  renderer.emitFullTree();

  tree = commits.at(-1).data;
  assert.equal(tree.props.overlay[0].node.id, originalOverlayId);
  assert.equal(tree.props.overlay[0].node.props.symbol, "1");

  renderer.render(React.createElement(App, { fill: "#222222" }));
  renderer.emitFullTree();
  tree = commits.at(-1).data;
  assert.equal(tree.props.overlay[0].node.id, originalOverlayId);
  assert.equal(tree.props.overlay[0].node.props.symbol, "1");
});

test("accessory state persists across renders without remounting a nested root", async () => {
  const renderer = createRenderer();
  const commits = [];
  renderer.onCommit((payload) => {
    commits.push(payload);
  });

  function StatefulAccessory() {
    const [symbol, setSymbol] = React.useState("mic");
    return React.createElement("IconButton", {
      symbol,
      onPress: () => {
        setSymbol("mic.fill");
      },
    });
  }

  function App(props) {
    return React.createElement(
      "Input",
      { value: props.value },
      trailingAccessorySlot(React.createElement(StatefulAccessory))
    );
  }

  renderer.render(React.createElement(App, { value: "one" }));
  let tree = commits.at(-1).data;
  const originalAccessoryId = tree.props.trailingAccessory.id;
  const updateAccessory = tree.props.trailingAccessory.props.onPress;

  invokeCallback(updateAccessory);
  await flushEffects();
  renderer.emitFullTree();

  tree = commits.at(-1).data;
  assert.equal(tree.props.trailingAccessory.id, originalAccessoryId);
  assert.equal(tree.props.trailingAccessory.props.symbol, "mic.fill");

  renderer.render(React.createElement(App, { value: "two" }));
  renderer.emitFullTree();
  tree = commits.at(-1).data;
  assert.equal(tree.props.trailingAccessory.id, originalAccessoryId);
  assert.equal(tree.props.trailingAccessory.props.symbol, "mic.fill");
});

test("overlay effects clean up on rerender and unmount", async () => {
  const events = [];
  const renderer = createRenderer();

  function EffectOverlay(props) {
    React.useEffect(() => {
      events.push(`mount:${props.label}`);
      return () => {
        events.push(`cleanup:${props.label}`);
      };
    }, [props.label]);

    return React.createElement("Icon", { symbol: props.label });
  }

  function App(props) {
    return React.createElement(
      "RoundedRect",
      null,
      overlaySlot(React.createElement(EffectOverlay, { label: props.label }))
    );
  }

  renderer.render(React.createElement(App, { label: "one" }));
  await flushEffects();
  renderer.render(React.createElement(App, { label: "two" }));
  await flushEffects();
  renderer.unmount();
  await flushEffects();

  assert.deepEqual(events, [
    "mount:one",
    "cleanup:one",
    "mount:two",
    "cleanup:two",
  ]);
});
