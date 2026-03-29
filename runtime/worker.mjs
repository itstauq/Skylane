import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import { parentPort, workerData } from "node:worker_threads";

import { clear as clearCallbacks, invoke as invokeCallback } from "./callback-registry.mjs";
import { createRenderer } from "./reconciler.mjs";
import { createStorage } from "./storage.mjs";

if (!parentPort) {
  throw new Error("runtime/worker.mjs must run inside a worker thread.");
}

const {
  widgetId = "unknown-widget",
  instanceId,
  bundlePath = "",
  props = {},
  sessionId,
} = workerData ?? {};

const runtimeDir = path.dirname(fileURLToPath(import.meta.url));
const bundledApiDir = path.join(runtimeDir, "api");
const devApiDir = path.resolve(runtimeDir, "..", "sdk", "packages", "api");
const apiDir = fs.existsSync(path.join(bundledApiDir, "index.js")) ? bundledApiDir : devApiDir;

const require = createRequire(import.meta.url);
const Module = require("node:module");
const originalResolveFilename = Module._resolveFilename;
const runtimeModuleMap = new Map([
  ["react-shim", path.join(runtimeDir, "react-shim.cjs")],
  ["react", path.join(runtimeDir, "react-shim.cjs")],
  ["react/jsx-runtime", path.join(runtimeDir, "node_modules", "react", "jsx-runtime.js")],
  ["@notchapp/api", path.join(apiDir, "index.js")],
  ["@notchapp/api/jsx-runtime", path.join(apiDir, "jsx-runtime.js")],
]);

Module._resolveFilename = function resolveRuntimeModule(request, parent, isMain, options) {
  if (runtimeModuleMap.has(request)) {
    return runtimeModuleMap.get(request);
  }

  return originalResolveFilename.call(this, request, parent, isMain, options);
};

const React = require("react");
const renderer = createRenderer();
let currentProps = props ?? {};
let nextRpcRequestId = 0;
const pendingRpcRequests = new Map();
let storage = createStorage({ callRpc: () => Promise.resolve(null) });

function send(method, params) {
  parentPort.postMessage({
    jsonrpc: "2.0",
    method,
    params,
  });
}

function sendRequest(method, params) {
  const requestId = String(++nextRpcRequestId);

  parentPort.postMessage({
    jsonrpc: "2.0",
    id: requestId,
    method,
    params,
  });

  return new Promise((resolve, reject) => {
    pendingRpcRequests.set(requestId, { resolve, reject });
  });
}

function stringifyLogPart(part) {
  if (typeof part === "string") {
    return part;
  }

  try {
    return JSON.stringify(part);
  } catch {
    return String(part);
  }
}

function createLogger() {
  const emit = (level) => (...parts) => {
    send("log", {
      level,
      message: parts.map(stringifyLogPart).join(" "),
    });
  };

  return {
    log: emit("log"),
    info: emit("info"),
    warn: emit("warn"),
    error: emit("error"),
  };
}

function buildWidgetProps(widgetModule) {
  return {
    ...currentProps,
    state: structuredClone(widgetModule.initialState ?? {}),
    logger: createLogger(),
  };
}

function reportError(error) {
  const payload = error instanceof Error
    ? { message: error.message, stack: error.stack }
    : { message: String(error) };

  send("error", {
    instanceId,
    sessionId,
    error: payload,
  });
}

process.on("uncaughtException", (error) => {
  reportError(error);
  process.exit(1);
});

process.on("unhandledRejection", (error) => {
  reportError(error instanceof Error ? error : new Error(String(error)));
  process.exit(1);
});

function callRpc(method, params = {}) {
  return sendRequest("rpc", { method, params });
}

renderer.onCommit((payload) => {
  send("render", {
    instanceId,
    sessionId,
    ...payload,
  });
});

function handleMessage(message) {
  if (message?.jsonrpc !== "2.0") {
    return;
  }

  const responseId = typeof message.id === "string"
    ? message.id
    : typeof message.id === "number"
      ? String(message.id)
      : "";
  if (responseId && (Object.hasOwn(message, "result") || Object.hasOwn(message, "error"))) {
    const pending = pendingRpcRequests.get(responseId);
    if (!pending) {
      return;
    }

    pendingRpcRequests.delete(responseId);
    if (message.error) {
      const error = new Error(message.error.message ?? "Runtime RPC failed.");
      error.rpcCode = message.error.code;
      error.data = message.error.data;
      pending.reject(error);
      return;
    }

    pending.resolve(message.result ?? null);
    return;
  }

  if (typeof message.method !== "string") {
    return;
  }

  if (message.method === "callback") {
    const callbackId = typeof message.params?.callbackId === "string"
      ? message.params.callbackId
      : "";
    if (!callbackId) {
      return;
    }

    const result = invokeCallback(callbackId, message.params?.payload ?? {});
    if (result && typeof result.then === "function") {
      result.catch((error) => {
        reportError(error instanceof Error ? error : new Error(String(error)));
        process.exit(1);
      });
    }
    return;
  }

  if (message.method === "requestFullTree") {
    renderer.emitFullTree();
    return;
  }

  if (message.method === "shutdown") {
    for (const pending of pendingRpcRequests.values()) {
      pending.reject(new Error("Widget worker shut down before RPC completed."));
    }
    pendingRpcRequests.clear();
    clearCallbacks();
    process.exit(0);
  }
}

parentPort.on("message", handleMessage);

async function bootstrap() {
  const storageSnapshot = await callRpc("localStorage.allItems", {});
  storage = createStorage({
    initialValues: storageSnapshot,
    callRpc,
  });

  globalThis.__NOTCH_RUNTIME__ = {
    localStorage: storage,
    getCurrentProps: () => currentProps,
    callRpc,
  };

  const widgetModule = require(bundlePath);
  const WidgetComponent = typeof widgetModule?.default === "function"
    ? widgetModule.default
    : typeof widgetModule === "function"
      ? widgetModule
      : null;

  if (!WidgetComponent) {
    throw new Error(`Widget bundle at ${bundlePath} must export a default component function.`);
  }

  renderer.render(
    React.createElement(WidgetComponent, buildWidgetProps(widgetModule))
  );
}

await bootstrap();
