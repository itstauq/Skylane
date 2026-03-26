import readline from "node:readline";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const widgets = new Map();
const widgetStates = new Map();

function send(payload) {
  process.stdout.write(`${JSON.stringify(payload)}\n`);
}

function widgetLogger(widgetID) {
  const emit = (level) => (...parts) => {
    send({
      type: "log",
      widgetID,
      level,
      message: parts.map((part) => typeof part === "string" ? part : JSON.stringify(part)).join(" "),
    });
  };

  return {
    log: emit("log"),
    info: emit("info"),
    warn: emit("warn"),
    error: emit("error"),
  };
}

function clearWidget(widgetID, bundlePath) {
  widgetStates.delete(widgetID);
  if (bundlePath) {
    try {
      delete require.cache[require.resolve(bundlePath)];
    } catch {
      // ignore
    }
  }
  widgets.delete(widgetID);
}

function loadWidget(widgetID, bundlePath) {
  clearWidget(widgetID, bundlePath);
  const mod = require(bundlePath);
  widgets.set(widgetID, { bundlePath, mod });
}

function ensureWidget(widgetID) {
  const widget = widgets.get(widgetID);
  if (!widget) {
    throw new Error(`Widget ${widgetID} is not loaded.`);
  }
  return widget;
}

function stateFor(widgetID, instanceID, mod) {
  let instances = widgetStates.get(widgetID);
  if (!instances) {
    instances = new Map();
    widgetStates.set(widgetID, instances);
  }

  if (!instances.has(instanceID)) {
    instances.set(instanceID, structuredClone(mod.initialState ?? {}));
  }

  return instances.get(instanceID);
}

function render(widgetID, instanceID, environment) {
  const { mod } = ensureWidget(widgetID);
  const state = stateFor(widgetID, instanceID, mod);
  const logger = widgetLogger(widgetID);
  const tree = mod.default({
    environment,
    state,
    logger,
  });

  return tree;
}

function invokeAction(widgetID, instanceID, actionID, environment, payload) {
  const { mod } = ensureWidget(widgetID);
  const logger = widgetLogger(widgetID);
  const state = stateFor(widgetID, instanceID, mod);
  const action = mod.actions?.[actionID];

  if (!action) {
    throw new Error(`Unknown action '${actionID}' for widget ${widgetID}.`);
  }

  const nextState = action(state, { environment, logger, payload });
  if (nextState !== undefined) {
    widgetStates.get(widgetID).set(instanceID, nextState);
  }
}

const rl = readline.createInterface({
  input: process.stdin,
  crlfDelay: Infinity,
});

for await (const line of rl) {
  if (!line.trim()) continue;

  let message;
  try {
    message = JSON.parse(line);
  } catch (error) {
    send({ type: "error", message: `Invalid JSON: ${error.message}` });
    continue;
  }

  try {
    switch (message.type) {
      case "load":
        loadWidget(message.widgetID, message.bundlePath);
        send({ requestID: message.requestID, type: "ack", widgetID: message.widgetID });
        break;
      case "reload":
        loadWidget(message.widgetID, message.bundlePath);
        send({ requestID: message.requestID, type: "ack", widgetID: message.widgetID });
        break;
      case "render": {
        const tree = render(message.widgetID, message.instanceID, message.environment);
        send({ requestID: message.requestID, type: "render", widgetID: message.widgetID, tree });
        break;
      }
      case "action":
        invokeAction(message.widgetID, message.instanceID, message.actionID, message.environment, message.payload);
        send({ requestID: message.requestID, type: "ack", widgetID: message.widgetID });
        break;
      default:
        throw new Error(`Unsupported message type '${message.type}'.`);
    }
  } catch (error) {
    send({
      requestID: message.requestID,
      type: "error",
      widgetID: message.widgetID,
      message: error instanceof Error ? error.message : String(error),
    });
  }
}
