import fs from "node:fs";
import Module from "node:module";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { spawn } from "node:child_process";
import { parse } from "acorn";
import esbuild from "esbuild";
import { ALLOWED_BUILTIN_SPECIFIERS } from "./security-policy.mjs";

const command = process.argv[2];
const packageDir = process.cwd();
const canonicalWidgetsRoot = path.join(
  os.homedir(),
  "Library",
  "Application Support",
  "Skylane",
  "Widgets",
);
const BUILTIN_ROOTS = new Set(
  Module.builtinModules
    .map((specifier) => normalizeBuiltinRoot(specifier))
    .filter(Boolean)
);
const ALLOWED_BUILTIN_SPECIFIER_SET = new Set(ALLOWED_BUILTIN_SPECIFIERS);

function packageRootFromMeta(metaURL) {
  return path.resolve(path.dirname(new URL(metaURL).pathname), "..", "..");
}

function normalizeBuiltinRoot(request) {
  if (typeof request !== "string" || request.length === 0) {
    return null;
  }

  const withoutPrefix = request.startsWith("node:") ? request.slice(5) : request;
  return withoutPrefix.split("/")[0] || null;
}

function normalizeBuiltinRequest(request) {
  if (typeof request !== "string" || request.length === 0) {
    return null;
  }

  const withoutPrefix = request.startsWith("node:") ? request.slice(5) : request;
  const root = normalizeBuiltinRoot(request);
  if (!root) {
    return null;
  }

  if (request.startsWith("node:") || BUILTIN_ROOTS.has(withoutPrefix) || BUILTIN_ROOTS.has(root)) {
    return {
      specifier: withoutPrefix,
      root,
    };
  }

  return null;
}

function developmentWidgetsRoot() {
  const workspaceRoot = packageRootFromMeta(import.meta.url);
  return path.join(workspaceRoot, "widgets");
}

function skylaneLogPath() {
  return path.join(
    os.homedir(),
    "Library",
    "Application Support",
    "Skylane",
    "skylane.log",
  );
}

function readManifest(targetPackageDir) {
  const manifestPath = path.join(targetPackageDir, "package.json");
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  const skylaneManifest = manifest.skylane ?? {};

  if (!skylaneManifest.id || !skylaneManifest.title) {
    throw new Error(`Invalid skylane manifest in ${manifestPath}: missing id/title`);
  }

  if (
    !Number.isInteger(skylaneManifest.minSpan) ||
    !Number.isInteger(skylaneManifest.maxSpan) ||
    skylaneManifest.minSpan <= 0 ||
    skylaneManifest.maxSpan < skylaneManifest.minSpan
  ) {
    throw new Error(`Invalid span range in ${manifestPath}`);
  }

  validatePreferences(skylaneManifest.preferences ?? [], manifestPath);

  const entryFile = path.join(targetPackageDir, skylaneManifest.entry ?? "src/index.tsx");
  if (!fs.existsSync(entryFile)) {
    throw new Error(`Missing widget entry file at ${entryFile}`);
  }

  return { manifest, manifestPath, entryFile };
}

const SUPPORTED_PREFERENCE_TYPES = new Set([
  "textfield",
  "password",
  "checkbox",
  "dropdown",
  "camera",
]);

function validatePreferences(preferences, manifestPath) {
  if (!Array.isArray(preferences)) {
    throw new Error(`Invalid preferences in ${manifestPath}: preferences must be an array`);
  }

  const seen = new Set();
  for (const preference of preferences) {
    if (!preference || typeof preference !== "object" || Array.isArray(preference)) {
      throw new Error(`Invalid preferences in ${manifestPath}: each preference must be an object`);
    }

    if (!preference.name || !preference.title || !preference.type) {
      throw new Error(`Invalid preferences in ${manifestPath}: each preference must include name/title/type`);
    }

    if (seen.has(preference.name)) {
      throw new Error(`Invalid preferences in ${manifestPath}: duplicate preference name '${preference.name}'`);
    }
    seen.add(preference.name);

    if (!SUPPORTED_PREFERENCE_TYPES.has(preference.type)) {
      throw new Error(`Invalid preferences in ${manifestPath}: unsupported preference type '${preference.type}'`);
    }

    switch (preference.type) {
      case "textfield":
      case "password":
        if (Object.hasOwn(preference, "default") && typeof preference.default !== "string") {
          throw new Error(`Invalid preferences in ${manifestPath}: '${preference.name}' must use a string default`);
        }
        break;
      case "checkbox":
        if (Object.hasOwn(preference, "default") && typeof preference.default !== "boolean") {
          throw new Error(`Invalid preferences in ${manifestPath}: '${preference.name}' must use a boolean default`);
        }
        break;
      case "dropdown":
        if (!Array.isArray(preference.data) || preference.data.length === 0) {
          throw new Error(`Invalid preferences in ${manifestPath}: dropdown '${preference.name}' must include data`);
        }
        if (preference.data.some((item) => !item?.title || !Object.hasOwn(item, "value"))) {
          throw new Error(`Invalid preferences in ${manifestPath}: dropdown '${preference.name}' entries must include title/value`);
        }
        if (Object.hasOwn(preference, "default")
          && !preference.data.some((item) => JSON.stringify(item.value) === JSON.stringify(preference.default))) {
          throw new Error(`Invalid preferences in ${manifestPath}: dropdown '${preference.name}' default must appear in data`);
        }
        break;
      case "camera":
        if (Object.hasOwn(preference, "default") && typeof preference.default !== "string") {
          throw new Error(`Invalid preferences in ${manifestPath}: camera '${preference.name}' must use a string default`);
        }
        break;
      default:
        break;
    }
  }
}

function ensureCanonicalSymlink(targetPackageDir, manifest) {
  fs.mkdirSync(canonicalWidgetsRoot, { recursive: true });

  const widgetID = manifest.skylane.id;
  const linkPath = path.join(canonicalWidgetsRoot, widgetID);
  const sourcePath = fs.realpathSync.native(targetPackageDir);
  const linkStats = safeLstat(linkPath);

  if (linkStats) {
    if (!linkStats.isSymbolicLink()) {
      throw new Error(`Cannot replace non-symlink widget install at ${linkPath}`);
    }

    const existingTarget = safeRealpath(linkPath);
    if (existingTarget == null) {
      fs.rmSync(linkPath, { recursive: true, force: true });
      fs.symlinkSync(sourcePath, linkPath, "dir");
      return linkPath;
    }

    if (existingTarget === sourcePath) {
      return linkPath;
    }

    if (!shouldReplaceSymlink(existingTarget)) {
      throw new Error(`Refusing to replace unmanaged widget install at ${linkPath}`);
    }

    fs.rmSync(linkPath, { recursive: true, force: true });
  }

  fs.symlinkSync(sourcePath, linkPath, "dir");
  return linkPath;
}

function safeLstat(targetPath) {
  try {
    return fs.lstatSync(targetPath);
  } catch (error) {
    if (error?.code === "ENOENT") {
      return null;
    }
    throw error;
  }
}

function safeRealpath(targetPath) {
  try {
    return fs.realpathSync.native(targetPath);
  } catch (error) {
    if (error?.code === "ENOENT") {
      return null;
    }
    throw error;
  }
}

function shouldReplaceSymlink(targetPath) {
  return (
    targetPath.startsWith(developmentWidgetsRoot()) ||
    targetPath.includes("/Contents/Resources/WidgetRuntime/widgets/")
  );
}

function collectWatchedFiles(targetPath) {
  if (!fs.existsSync(targetPath)) {
    return [];
  }

  const stats = fs.statSync(targetPath);
  if (stats.isFile()) {
    return [targetPath];
  }

  if (!stats.isDirectory()) {
    return [];
  }

  const files = [];
  for (const entry of fs.readdirSync(targetPath, { withFileTypes: true })) {
    if (entry.name === ".git" || entry.name === "node_modules" || entry.name === ".skylane") {
      continue;
    }

    const entryPath = path.join(targetPath, entry.name);
    if (entry.isDirectory()) {
      files.push(...collectWatchedFiles(entryPath));
    } else if (entry.isFile()) {
      files.push(entryPath);
    }
  }

  return files;
}

function snapshotWatchedFiles(watchRoots) {
  const snapshot = new Map();

  for (const watchRoot of watchRoots) {
    for (const filePath of collectWatchedFiles(watchRoot)) {
      const stats = fs.statSync(filePath);
      snapshot.set(filePath, `${stats.size}:${stats.mtimeMs}`);
    }
  }

  return snapshot;
}

function snapshotsDiffer(previousSnapshot, nextSnapshot) {
  if (previousSnapshot.size !== nextSnapshot.size) {
    return true;
  }

  for (const [filePath, signature] of nextSnapshot) {
    if (previousSnapshot.get(filePath) !== signature) {
      return true;
    }
  }

  return false;
}

const skylaneExecutableSuffix = `${path.sep}Contents${path.sep}MacOS${path.sep}Skylane`;

function devEventURL(event, widgetID, info = "") {
  const query = new URLSearchParams({ cwd: process.cwd() });
  if (info) {
    query.set("info", info);
  }

  return `skylane://cli/${encodeURIComponent(widgetID)}/${event}?${query.toString()}`;
}

function parseRunningSkylaneBundlePaths(psOutput) {
  const bundlePaths = new Set();

  for (const rawLine of psOutput.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (line.length === 0) {
      continue;
    }

    const executableIndex = line.indexOf(skylaneExecutableSuffix);
    if (executableIndex < 0) {
      continue;
    }

    const bundlePath = line.slice(0, executableIndex);
    if (!bundlePath.endsWith(".app")) {
      continue;
    }

    bundlePaths.add(bundlePath);
  }

  return [...bundlePaths];
}

function runCommand(command, args, options = {}) {
  return new Promise((resolve) => {
    let child;
    try {
      child = spawn(command, args, {
        stdio: ["ignore", "pipe", "pipe"],
        ...options,
      });
    } catch (error) {
      resolve({
        code: null,
        stdout: "",
        stderr: "",
        error,
      });
      return;
    }

    let stdout = "";
    let stderr = "";

    child.stdout?.on("data", (chunk) => {
      stdout += chunk;
    });
    child.stderr?.on("data", (chunk) => {
      stderr += chunk;
    });
    child.on("error", (error) => {
      resolve({
        code: null,
        stdout,
        stderr,
        error,
      });
    });
    child.on("close", (code) => {
      resolve({
        code,
        stdout,
        stderr,
        error: null,
      });
    });
  });
}

async function runningSkylaneBundlePaths() {
  const testPsOutputPath = process.env.SKYLANE_TEST_PS_OUTPUT_PATH;
  if (testPsOutputPath) {
    try {
      const output = fs.readFileSync(testPsOutputPath, "utf8");
      return {
        bundlePaths: parseRunningSkylaneBundlePaths(output),
        warning: null,
      };
    } catch (error) {
      const warning = error instanceof Error ? error.message : String(error);
      return {
        bundlePaths: [],
        warning,
      };
    }
  }

  const result = await runCommand("ps", ["-axo", "command="]);
  if (result.error || result.code !== 0) {
    const warning = result.error?.message ?? (result.stderr.trim() || "Failed to inspect running processes.");
    return {
      bundlePaths: [],
      warning,
    };
  }

  return {
    bundlePaths: parseRunningSkylaneBundlePaths(result.stdout),
    warning: null,
  };
}

async function notifyApp(event, widgetID, info = "") {
  const url = devEventURL(event, widgetID, info);
  const { bundlePaths, warning } = await runningSkylaneBundlePaths();

  if (warning) {
    console.warn(`Warning: could not inspect running Skylane processes: ${warning}`);
  }

  if (bundlePaths.length === 0) {
    console.warn("Warning: no running Skylane installations found; no app was notified.");
    return {
      notifiedCount: 0,
      failedBundlePaths: [],
    };
  }

  const failedBundlePaths = [];
  let notifiedCount = 0;

  for (const bundlePath of bundlePaths) {
    const result = await openSkylaneBundle(bundlePath, url);
    if (result.error || result.code !== 0) {
      failedBundlePaths.push(bundlePath);
      const details = result.error?.message ?? (result.stderr.trim() || `exit code ${result.code}`);
      console.warn(`Warning: failed to notify ${bundlePath}: ${details}`);
      continue;
    }

    notifiedCount += 1;
  }

  if (notifiedCount > 0) {
    console.log(`Notified ${notifiedCount} running Skylane installation(s).`);
  } else {
    console.warn("Warning: found running Skylane installations, but none accepted the widget update notification.");
  }

  return {
    notifiedCount,
    failedBundlePaths,
  };
}

function createWidgetLogTail(widgetID) {
  const logPath = skylaneLogPath();
  const prefix = `Widget ${widgetID} [`;
  let offset = 0;

  function primeOffset() {
    try {
      offset = fs.statSync(logPath).size;
    } catch {
      offset = 0;
    }
  }

  function printNewLines() {
    let stat;
    try {
      stat = fs.statSync(logPath);
    } catch {
      return;
    }

    if (stat.size < offset) {
      offset = 0;
    }
    if (stat.size === offset) {
      return;
    }

    const fd = fs.openSync(logPath, "r");
    try {
      const length = stat.size - offset;
      const buffer = Buffer.alloc(length);
      fs.readSync(fd, buffer, 0, length, offset);
      offset = stat.size;

      for (const line of buffer.toString("utf8").split(/\r?\n/)) {
        if (line.includes(prefix)) {
          console.log(line);
        }
      }
    } finally {
      fs.closeSync(fd);
    }
  }

  primeOffset();
  const timer = setInterval(printNewLines, 500);

  return () => {
    clearInterval(timer);
  };
}

async function openSkylaneBundle(bundlePath, url) {
  const testOpenLogPath = process.env.SKYLANE_TEST_OPEN_LOG_PATH;
  if (testOpenLogPath) {
    try {
      fs.appendFileSync(testOpenLogPath, JSON.stringify(["-a", bundlePath, url]) + "\n");
      const failingApps = new Set(JSON.parse(process.env.SKYLANE_TEST_FAILING_OPEN_APPS ?? "[]"));
      if (failingApps.has(bundlePath)) {
        return {
          code: 1,
          stdout: "",
          stderr: `failed to open ${bundlePath}\n`,
          error: null,
        };
      }

      return {
        code: 0,
        stdout: "",
        stderr: "",
        error: null,
      };
    } catch (error) {
      return {
        code: null,
        stdout: "",
        stderr: "",
        error,
      };
    }
  }

  return runCommand("open", ["-a", bundlePath, url]);
}

function failOnDynamicImport(outfile) {
  const emitted = fs.readFileSync(outfile, "utf8");
  const sourceMapIndex = emitted.lastIndexOf("\n//# sourceMappingURL=");
  const executableSource = sourceMapIndex >= 0 ? emitted.slice(0, sourceMapIndex) : emitted;
  const program = parse(executableSource, {
    ecmaVersion: "latest",
    sourceType: "script",
  });

  if (containsDynamicImport(program)) {
    throw new Error(
      `Dynamic import is unsupported in the widget runtime. ${outfile} still contains import(...).`
    );
  }
}

function containsDynamicImport(node) {
  if (!node || typeof node !== "object") {
    return false;
  }

  if (node.type === "ImportExpression") {
    return true;
  }

  for (const value of Object.values(node)) {
    if (Array.isArray(value)) {
      for (const child of value) {
        if (containsDynamicImport(child)) {
          return true;
        }
      }
      continue;
    }

    if (containsDynamicImport(value)) {
      return true;
    }
  }

  return false;
}

function builtinModulePolicyPlugin() {
  return {
    name: "builtin-module-policy",
    setup(build) {
      build.onResolve({ filter: /.*/ }, async (args) => {
        if (args.pluginData?.skipBuiltinPolicy) {
          return null;
        }

        const builtin = normalizeBuiltinRequest(args.path);
        if (!builtin) {
          return null;
        }

        if (!args.path.startsWith("node:")) {
          const resolved = await build.resolve(args.path, {
            kind: args.kind,
            importer: args.importer,
            namespace: args.namespace,
            resolveDir: args.resolveDir,
            pluginData: { skipBuiltinPolicy: true },
          });

          if (!resolved.errors?.length && resolved.path && !resolved.external) {
            return resolved;
          }
        }

        if (!ALLOWED_BUILTIN_SPECIFIER_SET.has(builtin.specifier)) {
          return {
            errors: [
              {
                text: `Built-in module "${args.path}" is not available in the widget runtime.`,
              },
            ],
          };
        }

        return { path: args.path, external: true };
      });
    },
  };
}

function syncWidgetAssets(targetPackageDir, outputDir) {
  const sourceAssetsDir = path.join(targetPackageDir, "assets");
  const destinationAssetsDir = path.join(outputDir, "assets");

  fs.rmSync(destinationAssetsDir, { recursive: true, force: true });

  if (!fs.existsSync(sourceAssetsDir)) {
    return;
  }

  fs.cpSync(sourceAssetsDir, destinationAssetsDir, {
    recursive: true,
    dereference: true,
  });
}

function replaceBuildOutput(outputDir, stagingOutputDir, backupOutputDir) {
  fs.rmSync(backupOutputDir, { recursive: true, force: true });

  let movedExistingBuild = false;
  if (fs.existsSync(outputDir)) {
    fs.renameSync(outputDir, backupOutputDir);
    movedExistingBuild = true;
  }

  try {
    fs.renameSync(stagingOutputDir, outputDir);
    if (movedExistingBuild) {
      fs.rmSync(backupOutputDir, { recursive: true, force: true });
    }
  } catch (error) {
    if (!fs.existsSync(outputDir) && movedExistingBuild && fs.existsSync(backupOutputDir)) {
      fs.renameSync(backupOutputDir, outputDir);
    }
    throw error;
  }
}

async function buildWidget(targetPackageDir, options = {}) {
  const { manifest, entryFile } = readManifest(targetPackageDir);
  const { registerCanonicalInstall = false } = options;
  if (registerCanonicalInstall) {
    ensureCanonicalSymlink(targetPackageDir, manifest);
  }

  const skylaneManifest = manifest.skylane;
  const outputRoot = path.join(targetPackageDir, ".skylane");
  const outputDir = path.join(outputRoot, "build");
  const outfile = path.join(outputDir, "index.cjs");
  const stagingOutputDir = path.join(outputRoot, `build.${process.pid}.staging`);
  const backupOutputDir = path.join(outputRoot, `build.${process.pid}.backup`);
  const stagingOutfile = path.join(stagingOutputDir, "index.cjs");
  fs.mkdirSync(outputRoot, { recursive: true });
  fs.rmSync(stagingOutputDir, { recursive: true, force: true });
  fs.mkdirSync(stagingOutputDir, { recursive: true });

  try {
    await esbuild.build({
      entryPoints: [entryFile],
      outfile: stagingOutfile,
      bundle: true,
      platform: "browser",
      format: "cjs",
      target: "es2022",
      jsx: "automatic",
      jsxImportSource: "@skylane/api",
      alias: {
        react: "react-shim",
        "react/jsx-runtime": "@skylane/api/jsx-runtime",
      },
      plugins: [builtinModulePolicyPlugin()],
      external: [
        "@skylane/api",
        "@skylane/api/jsx-runtime",
        "react-shim",
      ],
      sourcemap: "inline",
      logLevel: "silent",
    });

    failOnDynamicImport(stagingOutfile);
    syncWidgetAssets(targetPackageDir, stagingOutputDir);
    replaceBuildOutput(outputDir, stagingOutputDir, backupOutputDir);
  } finally {
    fs.rmSync(stagingOutputDir, { recursive: true, force: true });
    fs.rmSync(backupOutputDir, { recursive: true, force: true });
  }

  console.log(`Built ${skylaneManifest.id} -> ${outfile}`);
  return manifest;
}

async function lintWidget(targetPackageDir) {
  readManifest(targetPackageDir);
  console.log(`Validated ${targetPackageDir}`);
}

async function developWidget(targetPackageDir) {
  const initial = readManifest(targetPackageDir);
  const stopLogTail = createWidgetLogTail(initial.manifest.skylane.id);
  ensureCanonicalSymlink(targetPackageDir, initial.manifest);
  await notifyApp("start", initial.manifest.skylane.id);
  const watchRoots = ["package.json", "src", "assets"]
    .map((relativePath) => path.join(targetPackageDir, relativePath));

  let buildInFlight = false;
  let buildQueued = false;
  let debounceTimer;
  let pollTimer;
  let lastSnapshot = snapshotWatchedFiles(watchRoots);

  const scheduleBuild = () => {
    clearTimeout(debounceTimer);
    debounceTimer = setTimeout(() => {
      void runBuild();
    }, 150);
  };

  const runBuild = async () => {
    if (buildInFlight) {
      buildQueued = true;
      return;
    }

    buildInFlight = true;
    try {
      const manifest = await buildWidget(targetPackageDir, {
        registerCanonicalInstall: true,
      });
      await notifyApp("build-success", manifest.skylane.id);
    } catch (error) {
      const manifest = safeReadManifest(targetPackageDir);
      const widgetID = manifest?.skylane.id ?? path.basename(targetPackageDir);
      const message = error instanceof Error ? error.message : String(error);
      await notifyApp("build-failure", widgetID, message);
      console.error(message);
    } finally {
      buildInFlight = false;
      if (buildQueued) {
        buildQueued = false;
        scheduleBuild();
      }
    }
  };

  const stop = () => {
    void (async () => {
      clearTimeout(debounceTimer);
      if (pollTimer) {
        clearInterval(pollTimer);
      }
      stopLogTail();
      await notifyApp("stop", initial.manifest.skylane.id);
      process.exit(0);
    })();
  };

  for (const signal of ["SIGINT", "SIGTERM", "SIGQUIT", "SIGHUP"]) {
    process.once(signal, stop);
  }

  await runBuild();

  pollTimer = setInterval(() => {
    const nextSnapshot = snapshotWatchedFiles(watchRoots);
    if (!snapshotsDiffer(lastSnapshot, nextSnapshot)) {
      return;
    }

    lastSnapshot = nextSnapshot;
    scheduleBuild();
  }, 250);
}

function safeReadManifest(targetPackageDir) {
  try {
    return readManifest(targetPackageDir).manifest;
  } catch {
    return null;
  }
}

switch (command) {
  case "build":
    await buildWidget(packageDir);
    break;
  case "lint":
    await lintWidget(packageDir);
    break;
  case "develop":
  case "dev":
    await developWidget(packageDir);
    break;
  default:
    console.error("Usage: skylane <build|develop|dev|lint>");
    process.exit(1);
}
