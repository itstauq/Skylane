import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const testDir = path.dirname(fileURLToPath(import.meta.url));
const sdkRoot = path.resolve(testDir, "..");
const repoRoot = path.resolve(sdkRoot, "..");
const cliPath = path.join(repoRoot, "sdk", "packages", "notchapp", "cli.mjs");

function createTempDir(t, prefix) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), prefix));
  t.after(() => {
    fs.rmSync(dir, { recursive: true, force: true });
  });
  return dir;
}

function writeWidgetFixture(widgetDir, source) {
  fs.mkdirSync(path.join(widgetDir, "src"), { recursive: true });
  fs.writeFileSync(
    path.join(widgetDir, "package.json"),
    JSON.stringify({
      name: "tmp-widget",
      private: true,
      notch: {
        id: "tmp.widget",
        title: "Tmp Widget",
        minSpan: 1,
        maxSpan: 1,
        entry: "src/index.js",
      },
    }, null, 2)
  );
  fs.writeFileSync(path.join(widgetDir, "src", "index.js"), source);
}

function runProcess(command, args, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      ...options,
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (chunk) => {
      stdout += chunk;
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk;
    });
    child.on("error", reject);
    child.on("close", (code, signal) => {
      resolve({ code, signal, stdout, stderr });
    });
  });
}

function runCli(args, options = {}) {
  return runProcess(process.execPath, [cliPath, ...args], options);
}

function writeExecutable(filePath, contents) {
  fs.writeFileSync(filePath, contents, { mode: 0o755 });
}

function createFakeSystemCommands(t, options = {}) {
  const {
    psOutput = "",
    psExitCode = "0",
    failingOpenApps = [],
  } = options;
  const binDir = createTempDir(t, "notch-cli-bin-");
  const openLogPath = path.join(binDir, "open-log.jsonl");
  const psOutputPath = path.join(binDir, "ps-output.txt");
  const failureSet = new Set(failingOpenApps);

  fs.writeFileSync(psOutputPath, psOutput);

  writeExecutable(path.join(binDir, "ps"), `#!${process.execPath}
const fs = require("node:fs");
const outputPath = process.env.NOTCHAPP_TEST_PS_OUTPUT_PATH;
if (outputPath && fs.existsSync(outputPath)) {
  process.stdout.write(fs.readFileSync(outputPath, "utf8"));
}
process.exit(Number(process.env.NOTCHAPP_TEST_PS_EXIT_CODE ?? "0"));
`);

  writeExecutable(path.join(binDir, "open"), `#!${process.execPath}
const fs = require("node:fs");
const args = process.argv.slice(2);
const logPath = process.env.NOTCHAPP_TEST_OPEN_LOG_PATH;
fs.appendFileSync(logPath, JSON.stringify(args) + "\\n");
const failingApps = new Set(JSON.parse(process.env.NOTCHAPP_TEST_FAILING_OPEN_APPS ?? "[]"));
const bundlePath = args[0] === "-a" ? args[1] : "";
if (bundlePath && failingApps.has(bundlePath)) {
  process.stderr.write("failed to open " + bundlePath + "\\n");
  process.exit(1);
}
process.exit(0);
`);

  return {
    binDir,
    env: {
      NOTCHAPP_TEST_PS_OUTPUT_PATH: psOutputPath,
      NOTCHAPP_TEST_PS_EXIT_CODE: psExitCode,
      NOTCHAPP_TEST_OPEN_LOG_PATH: openLogPath,
      NOTCHAPP_TEST_FAILING_OPEN_APPS: JSON.stringify([...failureSet]),
    },
    openLogPath,
  };
}

function readOpenLog(logPath) {
  if (!fs.existsSync(logPath)) {
    return [];
  }

  return fs.readFileSync(logPath, "utf8")
    .trim()
    .split("\n")
    .filter(Boolean)
    .map((line) => JSON.parse(line));
}

function waitFor(predicate, timeoutMs = 5000, intervalMs = 50) {
  const startedAt = Date.now();

  return new Promise((resolve, reject) => {
    const poll = () => {
      if (predicate()) {
        resolve();
        return;
      }

      if (Date.now() - startedAt >= timeoutMs) {
        reject(new Error(`Timed out after ${timeoutMs}ms waiting for condition`));
        return;
      }

      setTimeout(poll, intervalMs);
    };

    poll();
  });
}

test("CLI build copies local assets into .notch/build/assets", async (t) => {
  const widgetDir = createTempDir(t, "notch-cli-assets-copy-");
  const assetPath = path.join(widgetDir, "assets", "covers", "hero.txt");
  writeWidgetFixture(widgetDir, `
    export default function Widget() {
      return null;
    }
  `);

  fs.mkdirSync(path.dirname(assetPath), { recursive: true });
  fs.writeFileSync(assetPath, "cover-art");

  const result = await runCli(["build"], { cwd: widgetDir });

  assert.equal(result.code, 0, result.stderr || result.stdout);
  assert.equal(
    fs.readFileSync(path.join(widgetDir, ".notch", "build", "assets", "covers", "hero.txt"), "utf8"),
    "cover-art"
  );
});

test("CLI build removes stale copied assets when the source assets directory disappears", async (t) => {
  const widgetDir = createTempDir(t, "notch-cli-assets-prune-");
  const sourceAssetsDir = path.join(widgetDir, "assets");
  const builtAssetPath = path.join(widgetDir, ".notch", "build", "assets", "icon.txt");
  writeWidgetFixture(widgetDir, `
    export default function Widget() {
      return null;
    }
  `);

  fs.mkdirSync(sourceAssetsDir, { recursive: true });
  fs.writeFileSync(path.join(sourceAssetsDir, "icon.txt"), "present");

  let result = await runCli(["build"], { cwd: widgetDir });
  assert.equal(result.code, 0, result.stderr || result.stdout);
  assert.equal(fs.existsSync(builtAssetPath), true);

  fs.rmSync(sourceAssetsDir, { recursive: true, force: true });

  result = await runCli(["build"], { cwd: widgetDir });
  assert.equal(result.code, 0, result.stderr || result.stdout);
  assert.equal(fs.existsSync(builtAssetPath), false);
});

test("CLI build preserves the last good bundle when asset copying fails", async (t) => {
  const widgetDir = createTempDir(t, "notch-cli-assets-staging-");
  const sourceAssetsDir = path.join(widgetDir, "assets");
  const builtBundlePath = path.join(widgetDir, ".notch", "build", "index.cjs");
  const builtAssetPath = path.join(widgetDir, ".notch", "build", "assets", "icon.txt");
  const unreadableAssetPath = path.join(sourceAssetsDir, "broken.txt");

  writeWidgetFixture(widgetDir, `
    export default function Widget() {
      return "version-one";
    }
  `);

  fs.mkdirSync(sourceAssetsDir, { recursive: true });
  fs.writeFileSync(path.join(sourceAssetsDir, "icon.txt"), "present");

  let result = await runCli(["build"], { cwd: widgetDir });
  assert.equal(result.code, 0, result.stderr || result.stdout);
  assert.match(fs.readFileSync(builtBundlePath, "utf8"), /version-one/);
  assert.equal(fs.readFileSync(builtAssetPath, "utf8"), "present");

  fs.writeFileSync(path.join(widgetDir, "src", "index.js"), `
    export default function Widget() {
      return "version-two";
    }
  `);
  fs.rmSync(sourceAssetsDir, { recursive: true, force: true });
  fs.mkdirSync(sourceAssetsDir, { recursive: true });
  fs.writeFileSync(unreadableAssetPath, "broken");
  fs.chmodSync(unreadableAssetPath, 0o000);
  t.after(() => {
    if (fs.existsSync(unreadableAssetPath)) {
      fs.chmodSync(unreadableAssetPath, 0o644);
    }
  });

  result = await runCli(["build"], { cwd: widgetDir });
  assert.notEqual(result.code, 0);
  assert.match(result.stderr || result.stdout, /EACCES|Permission denied|broken\.txt/);
  assert.match(fs.readFileSync(builtBundlePath, "utf8"), /version-one/);
  assert.equal(fs.readFileSync(builtAssetPath, "utf8"), "present");
});

test("CLI dev rebuilds when assets are added after startup", async (t) => {
  const widgetDir = createTempDir(t, "notch-cli-assets-dev-");
  const fakeHome = createTempDir(t, "notch-cli-home-");
  const builtBundlePath = path.join(widgetDir, ".notch", "build", "index.cjs");
  const builtAssetPath = path.join(widgetDir, ".notch", "build", "assets", "late.txt");

  writeWidgetFixture(widgetDir, `
    export default function Widget() {
      return null;
    }
  `);

  const child = spawn(process.execPath, [cliPath, "dev"], {
    cwd: widgetDir,
    env: { ...process.env, HOME: fakeHome },
    stdio: ["ignore", "pipe", "pipe"],
  });

  let stdout = "";
  let stderr = "";
  child.stdout.on("data", (chunk) => {
    stdout += chunk;
  });
  child.stderr.on("data", (chunk) => {
    stderr += chunk;
  });

  const stopChild = async () => {
    if (child.exitCode != null) {
      return;
    }

    child.kill("SIGTERM");
    await Promise.race([
      new Promise((resolve) => child.once("close", resolve)),
      new Promise((resolve) => setTimeout(resolve, 1000)),
    ]);

    if (child.exitCode == null) {
      child.kill("SIGKILL");
      await new Promise((resolve) => child.once("close", resolve));
    }
  };

  t.after(async () => {
    await stopChild();
  });

  await waitFor(() => fs.existsSync(builtBundlePath), 10000);

  fs.mkdirSync(path.join(widgetDir, "assets"), { recursive: true });
  fs.writeFileSync(path.join(widgetDir, "assets", "late.txt"), "late");

  await waitFor(() => fs.existsSync(builtAssetPath), 10000);
  assert.equal(fs.readFileSync(builtAssetPath, "utf8"), "late");
  assert.match(stdout, /Built tmp\.widget ->/);
});

test("CLI dev notifies each unique running NotchApp bundle path", async (t) => {
  const widgetDir = createTempDir(t, "notch-cli-dev-fanout-");
  const fakeHome = createTempDir(t, "notch-cli-home-");
  const builtBundlePath = path.join(widgetDir, ".notch", "build", "index.cjs");
  const bundleA = "/Applications/NotchApp.app";
  const bundleB = "/Users/test/DerivedData/Build/Products/Debug/NotchApp.app";
  const commands = createFakeSystemCommands(t, {
    psOutput: [
      `${bundleA}/Contents/MacOS/NotchApp`,
      `${bundleA}/Contents/MacOS/NotchApp --launched-by-test`,
      `${bundleB}/Contents/MacOS/NotchApp`,
      "/Applications/Other.app/Contents/MacOS/Other",
    ].join("\n"),
  });

  writeWidgetFixture(widgetDir, `
    export default function Widget() {
      return null;
    }
  `);

  const child = spawn(process.execPath, [cliPath, "dev"], {
    cwd: widgetDir,
    env: {
      ...process.env,
      ...commands.env,
      HOME: fakeHome,
      PATH: `${commands.binDir}:${process.env.PATH ?? ""}`,
    },
    stdio: ["ignore", "pipe", "pipe"],
  });

  let stdout = "";
  let stderr = "";
  child.stdout.on("data", (chunk) => {
    stdout += chunk;
  });
  child.stderr.on("data", (chunk) => {
    stderr += chunk;
  });

  const stopChild = async () => {
    if (child.exitCode != null) {
      return;
    }

    child.kill("SIGTERM");
    await Promise.race([
      new Promise((resolve) => child.once("close", resolve)),
      new Promise((resolve) => setTimeout(resolve, 1000)),
    ]);

    if (child.exitCode == null) {
      child.kill("SIGKILL");
      await new Promise((resolve) => child.once("close", resolve));
    }
  };

  t.after(async () => {
    await stopChild();
  });

  await waitFor(() => fs.existsSync(builtBundlePath), 10000);
  await waitFor(() => {
    const openCalls = readOpenLog(commands.openLogPath);
    return openCalls.filter((args) => args[2]?.includes("/build-success?")).length >= 2;
  }, 10000);

  const openCalls = readOpenLog(commands.openLogPath);
  const buildSuccessCalls = openCalls.filter((args) => args[2]?.includes("/build-success?"));
  assert.equal(buildSuccessCalls.length, 2);
  assert.deepEqual(
    buildSuccessCalls.map((args) => args[1]).sort(),
    [bundleA, bundleB].sort()
  );
  assert.equal(stderr, "", stderr);
  assert.match(stdout, /Notified 2 running NotchApp installation\(s\)\./);
});

test("CLI dev warns and keeps watching when no NotchApp process is running", async (t) => {
  const widgetDir = createTempDir(t, "notch-cli-dev-no-app-");
  const fakeHome = createTempDir(t, "notch-cli-home-");
  const builtBundlePath = path.join(widgetDir, ".notch", "build", "index.cjs");
  const commands = createFakeSystemCommands(t, {
    psOutput: "",
  });

  writeWidgetFixture(widgetDir, `
    export default function Widget() {
      return null;
    }
  `);

  const child = spawn(process.execPath, [cliPath, "dev"], {
    cwd: widgetDir,
    env: {
      ...process.env,
      ...commands.env,
      HOME: fakeHome,
      PATH: `${commands.binDir}:${process.env.PATH ?? ""}`,
    },
    stdio: ["ignore", "pipe", "pipe"],
  });

  let stdout = "";
  let stderr = "";
  child.stdout.on("data", (chunk) => {
    stdout += chunk;
  });
  child.stderr.on("data", (chunk) => {
    stderr += chunk;
  });

  const stopChild = async () => {
    if (child.exitCode != null) {
      return;
    }

    child.kill("SIGTERM");
    await Promise.race([
      new Promise((resolve) => child.once("close", resolve)),
      new Promise((resolve) => setTimeout(resolve, 1000)),
    ]);

    if (child.exitCode == null) {
      child.kill("SIGKILL");
      await new Promise((resolve) => child.once("close", resolve));
    }
  };

  t.after(async () => {
    await stopChild();
  });

  await waitFor(() => fs.existsSync(builtBundlePath), 10000);
  await waitFor(() => stderr.includes("no running NotchApp installations found"), 10000);

  assert.equal(readOpenLog(commands.openLogPath).length, 0);
  assert.match(stdout, /Built tmp\.widget ->/);
  assert.match(stderr, /Warning: no running NotchApp installations found; no app was notified\./);
});

test("CLI dev continues notifying other bundles when one delivery fails", async (t) => {
  const widgetDir = createTempDir(t, "notch-cli-dev-partial-failure-");
  const fakeHome = createTempDir(t, "notch-cli-home-");
  const builtBundlePath = path.join(widgetDir, ".notch", "build", "index.cjs");
  const goodBundle = "/Applications/NotchApp.app";
  const badBundle = "/Users/test/DerivedData/Build/Products/Debug/NotchApp.app";
  const commands = createFakeSystemCommands(t, {
    psOutput: [
      `${goodBundle}/Contents/MacOS/NotchApp`,
      `${badBundle}/Contents/MacOS/NotchApp`,
    ].join("\n"),
    failingOpenApps: [badBundle],
  });

  writeWidgetFixture(widgetDir, `
    export default function Widget() {
      return null;
    }
  `);

  const child = spawn(process.execPath, [cliPath, "dev"], {
    cwd: widgetDir,
    env: {
      ...process.env,
      ...commands.env,
      HOME: fakeHome,
      PATH: `${commands.binDir}:${process.env.PATH ?? ""}`,
    },
    stdio: ["ignore", "pipe", "pipe"],
  });

  let stdout = "";
  let stderr = "";
  child.stdout.on("data", (chunk) => {
    stdout += chunk;
  });
  child.stderr.on("data", (chunk) => {
    stderr += chunk;
  });

  const stopChild = async () => {
    if (child.exitCode != null) {
      return;
    }

    child.kill("SIGTERM");
    await Promise.race([
      new Promise((resolve) => child.once("close", resolve)),
      new Promise((resolve) => setTimeout(resolve, 1000)),
    ]);

    if (child.exitCode == null) {
      child.kill("SIGKILL");
      await new Promise((resolve) => child.once("close", resolve));
    }
  };

  t.after(async () => {
    await stopChild();
  });

  await waitFor(() => fs.existsSync(builtBundlePath), 10000);
  await waitFor(() => stderr.includes(`failed to notify ${badBundle}`), 10000);

  const openCalls = readOpenLog(commands.openLogPath);
  const buildSuccessCalls = openCalls.filter((args) => args[2]?.includes("/build-success?"));
  assert.equal(buildSuccessCalls.length, 2);
  assert.deepEqual(
    buildSuccessCalls.map((args) => args[1]).sort(),
    [badBundle, goodBundle].sort()
  );
  assert.match(stdout, /Notified 1 running NotchApp installation\(s\)\./);
  assert.match(stderr, new RegExp(`Warning: failed to notify ${badBundle.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}: failed to open`));
});
