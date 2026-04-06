import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import readline from "node:readline";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const testDir = path.dirname(fileURLToPath(import.meta.url));
const runtimeRoot = path.resolve(testDir, "..");
const runtimeEntryPath = path.join(runtimeRoot, "runtime-v2.mjs");

function createTempDir(t, prefix) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), prefix));
  t.after(() => {
    fs.rmSync(dir, { recursive: true, force: true });
  });
  return dir;
}

function createRuntimeHarness(t) {
  const child = spawn(process.execPath, [runtimeEntryPath], {
    cwd: runtimeRoot,
    stdio: ["pipe", "pipe", "pipe"],
  });

  const messages = [];
  const waiters = [];
  let closed = false;

  const settleWaiters = (message) => {
    for (let index = waiters.length - 1; index >= 0; index -= 1) {
      const waiter = waiters[index];
      if (!waiter.predicate(message)) {
        continue;
      }

      waiters.splice(index, 1);
      clearTimeout(waiter.timeout);
      waiter.resolve(message);
    }
  };

  const failWaiters = (error) => {
    while (waiters.length > 0) {
      const waiter = waiters.pop();
      clearTimeout(waiter.timeout);
      waiter.reject(error);
    }
  };

  readline.createInterface({
    input: child.stdout,
    crlfDelay: Infinity,
  }).on("line", (line) => {
    const message = JSON.parse(line);
    messages.push(message);
    if (message.method === "rpc" && message.params?.method === "localStorage.allItems") {
      child.stdin.write(`${JSON.stringify({
        jsonrpc: "2.0",
        id: message.id,
        result: { value: {} },
      })}\n`);
    }
    settleWaiters(message);
  });

  let stderr = "";
  child.stderr.on("data", (chunk) => {
    stderr += chunk;
  });

  child.on("error", (error) => {
    failWaiters(error);
  });

  child.on("close", (code, signal) => {
    closed = true;
    if (code === 0 || signal === "SIGTERM") {
      failWaiters(new Error("runtime-v2 exited before the expected message arrived."));
      return;
    }

    failWaiters(new Error(stderr || `runtime-v2 exited with code ${code} and signal ${signal}.`));
  });

  t.after(async () => {
    if (closed) {
      return;
    }

    child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", method: "shutdown" })}\n`);
    child.stdin.end();
    await new Promise((resolve) => {
      child.once("close", () => resolve());
    });
  });

  return {
    send(message) {
      child.stdin.write(`${JSON.stringify(message)}\n`);
    },
    waitFor(predicate, description, timeoutMs = 5000) {
      const existing = messages.find(predicate);
      if (existing) {
        return Promise.resolve(existing);
      }

      return new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
          const index = waiters.findIndex((waiter) => waiter.resolve === resolve);
          if (index >= 0) {
            waiters.splice(index, 1);
          }
          reject(new Error(`Timed out waiting for ${description}.`));
        }, timeoutMs);

        waiters.push({
          predicate,
          resolve,
          reject,
          timeout,
        });
      });
    },
  };
}

test("runtime-v2 forwards updateProps to mounted workers and rerenders with the new environment", async (t) => {
  const dir = createTempDir(t, "notch-runtime-v2-update-props-");
  const bundlePath = path.join(dir, "bundle.cjs");

  fs.writeFileSync(
    bundlePath,
    [
      'const React = require("react");',
      "module.exports.default = function Widget(props) {",
      '  return React.createElement("Text", null, String(props.environment.span));',
      "};",
      "",
    ].join("\n")
  );

  const runtime = createRuntimeHarness(t);
  const instanceId = "instance-1";
  const baseEnvironment = {
    widgetId: "test.widget",
    instanceId,
    viewId: "view-1",
    hostColumnCount: 4,
    isEditing: false,
    isDevelopment: false,
  };

  runtime.send({
    jsonrpc: "2.0",
    id: "mount-1",
    method: "mount",
    params: {
      widgetId: "test.widget",
      instanceId,
      bundlePath,
      props: {
        environment: {
          ...baseEnvironment,
          span: 1,
        },
      },
    },
  });

  const mountResponse = await runtime.waitFor(
    (message) => message.id === "mount-1",
    "the mount response"
  );
  const sessionId = mountResponse.result?.sessionId;
  assert.equal(typeof sessionId, "string");

  const initialRender = await runtime.waitFor(
    (message) => message.method === "render"
      && message.params?.sessionId === sessionId
      && message.params?.kind === "full",
    "the initial full render"
  );
  assert.equal(initialRender.params.data?.props?.text, "1");

  runtime.send({
    jsonrpc: "2.0",
    method: "updateProps",
    params: {
      instanceId,
      sessionId,
      props: {
        environment: {
          ...baseEnvironment,
          span: 3,
        },
      },
    },
  });

  runtime.send({
    jsonrpc: "2.0",
    method: "requestFullTree",
    params: {
      instanceId,
      sessionId,
    },
  });

  const updatedRender = await runtime.waitFor(
    (message) => message.method === "render"
      && message.params?.sessionId === sessionId
      && message.params?.kind === "full"
      && message.params?.data?.props?.text === "3",
    "the updated full render"
  );
  assert.equal(updatedRender.params.data.props.text, "3");
});

test("runtime-v2 exposes resolved preferences through usePreference and resyncs on prop updates", async (t) => {
  const dir = createTempDir(t, "notch-runtime-v2-preferences-");
  const bundlePath = path.join(dir, "bundle.cjs");

  fs.writeFileSync(
    bundlePath,
    [
      'const React = require("react");',
      'const { usePreference } = require("@notchapp/api");',
      "module.exports.default = function Widget() {",
      '  const [mailbox] = usePreference("mailbox");',
      '  return React.createElement("Text", null, String(mailbox ?? "missing"));',
      "};",
      "",
    ].join("\n")
  );

  const runtime = createRuntimeHarness(t);
  const instanceId = "instance-preferences-1";

  runtime.send({
    jsonrpc: "2.0",
    id: "mount-preferences-1",
    method: "mount",
    params: {
      widgetId: "test.widget",
      instanceId,
      bundlePath,
      props: {
        environment: {
          widgetId: "test.widget",
          instanceId,
          viewId: "view-1",
          span: 1,
          hostColumnCount: 4,
          isEditing: false,
          isDevelopment: false,
        },
        preferences: {
          mailbox: "inbox",
        },
      },
    },
  });

  const mountResponse = await runtime.waitFor(
    (message) => message.id === "mount-preferences-1",
    "the preferences mount response"
  );
  const sessionId = mountResponse.result?.sessionId;
  assert.equal(typeof sessionId, "string");

  const render = await runtime.waitFor(
    (message) => message.method === "render"
      && message.params?.sessionId === sessionId
      && message.params?.kind === "full",
    "the preferences render"
  );

  assert.equal(render.params.data?.props?.text, "inbox");

  runtime.send({
    jsonrpc: "2.0",
    method: "updateProps",
    params: {
      instanceId,
      sessionId,
      props: {
        environment: {
          widgetId: "test.widget",
          instanceId,
          viewId: "view-1",
          span: 1,
          hostColumnCount: 4,
          isEditing: false,
          isDevelopment: false,
        },
        preferences: {
          mailbox: "archive",
        },
      },
    },
  });

  runtime.send({
    jsonrpc: "2.0",
    method: "requestFullTree",
    params: {
      instanceId,
      sessionId,
    },
  });

  const updatedRender = await runtime.waitFor(
    (message) => message.method === "render"
      && message.params?.sessionId === sessionId
      && message.params?.kind === "full"
      && message.params?.data?.props?.text === "archive",
    "the updated preferences render"
  );

  assert.equal(updatedRender.params.data?.props?.text, "archive");
});

test("runtime-v2 exposes resolved theme through useTheme", async (t) => {
  const dir = createTempDir(t, "notch-runtime-v2-theme-");
  const bundlePath = path.join(dir, "bundle.cjs");

  fs.writeFileSync(
    bundlePath,
    [
      'const React = require("react");',
      'const { useTheme } = require("@notchapp/api");',
      "module.exports.default = function Widget() {",
      "  const theme = useTheme();",
      '  return React.createElement("Text", null, String(theme.colors?.accent ?? "missing"));',
      "};",
      "",
    ].join("\n")
  );

  const runtime = createRuntimeHarness(t);
  const instanceId = "instance-theme-1";

  runtime.send({
    jsonrpc: "2.0",
    id: "mount-theme-1",
    method: "mount",
    params: {
      widgetId: "test.widget",
      instanceId,
      bundlePath,
      props: {
        environment: {
          widgetId: "test.widget",
          instanceId,
          viewId: "view-1",
          span: 1,
          hostColumnCount: 4,
          isEditing: false,
          isDevelopment: false,
        },
        preferences: {},
        theme: {
          name: "indigo",
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
        },
      },
    },
  });

  const mountResponse = await runtime.waitFor(
    (message) => message.id === "mount-theme-1",
    "the theme mount response"
  );
  const sessionId = mountResponse.result?.sessionId;
  assert.equal(typeof sessionId, "string");

  const render = await runtime.waitFor(
    (message) => message.method === "render"
      && message.params?.sessionId === sessionId
      && message.params?.kind === "full",
    "the theme render"
  );

  assert.equal(render.params.data?.props?.text, "#B08AFA");
});

test("runtime-v2 renders compound sdk components into the expected host tree", async (t) => {
  const dir = createTempDir(t, "notch-runtime-v2-compound-");
  const bundlePath = path.join(dir, "bundle.cjs");

  fs.writeFileSync(
    bundlePath,
    [
      'const React = require("react");',
      'const { Card, CardContent, CardTitle, ToolbarButton } = require("@notchapp/api");',
      "module.exports.default = function Widget() {",
      "  return React.createElement(",
      "    Card,",
      '    { variant: "accent" },',
      "    React.createElement(",
      "      CardContent,",
      "      null,",
      '      React.createElement(CardTitle, null, "Player"),',
      '      React.createElement(ToolbarButton, { symbol: "play.fill", variant: "default", size: "xl" })',
      "    )",
      "  );",
      "};",
      "",
    ].join("\n")
  );

  const runtime = createRuntimeHarness(t);
  const instanceId = "instance-compound-1";

  runtime.send({
    jsonrpc: "2.0",
    id: "mount-compound-1",
    method: "mount",
    params: {
      widgetId: "test.widget",
      instanceId,
      bundlePath,
      props: {
        environment: {
          widgetId: "test.widget",
          instanceId,
          viewId: "view-1",
          span: 1,
          hostColumnCount: 4,
          isEditing: false,
          isDevelopment: false,
        },
        preferences: {},
        theme: {
          name: "indigo",
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
        },
      },
    },
  });

  const mountResponse = await runtime.waitFor(
    (message) => message.id === "mount-compound-1",
    "the compound mount response"
  );
  const sessionId = mountResponse.result?.sessionId;
  assert.equal(typeof sessionId, "string");

  const render = await runtime.waitFor(
    (message) => message.method === "render"
      && message.params?.sessionId === sessionId
      && message.params?.kind === "full",
    "the compound render"
  );

  assert.equal(render.params.data?.type, "RoundedRect");
  assert.equal(render.params.data?.props?.fill, "#B08AFA2E");
  assert.equal(render.params.data?.children?.[0]?.type, "Stack");
  assert.equal(render.params.data?.children?.[0]?.children?.[0]?.children?.[0]?.props?.variant, "title");
  assert.equal(render.params.data?.children?.[0]?.children?.[0]?.children?.[1]?.type, "IconButton");
  assert.equal(render.params.data?.children?.[0]?.children?.[0]?.children?.[1]?.props?.size, "xl");
});
