import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { spawn } from "node:child_process";
import { pathToFileURL } from "node:url";
import chokidar from "chokidar";
import esbuild from "esbuild";

const rootDir = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..");
const developmentWidgetsRoot = path.join(rootDir, "widgets");
const canonicalWidgetsRoot = path.join(os.homedir(), "Library", "Application Support", "NotchApp", "Widgets");
const command = process.argv[2];
const packageDir = process.cwd();

function readManifest(packageDir) {
  const manifestPath = path.join(packageDir, "package.json");
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  const notch = manifest.notch ?? {};

  if (!notch.id || !notch.title) {
    throw new Error(`Invalid notch manifest in ${manifestPath}: missing id/title`);
  }

  if (!Number.isInteger(notch.minSpan) || !Number.isInteger(notch.maxSpan) || notch.minSpan <= 0 || notch.maxSpan < notch.minSpan) {
    throw new Error(`Invalid span range in ${manifestPath}`);
  }

  const entryFile = path.join(packageDir, notch.entry ?? "src/index.tsx");
  if (!fs.existsSync(entryFile)) {
    throw new Error(`Missing widget entry file at ${entryFile}`);
  }

  return { manifest, manifestPath, entryFile };
}

function ensureCanonicalSymlink(packageDir, manifest) {
  fs.mkdirSync(canonicalWidgetsRoot, { recursive: true });

  const widgetID = manifest.notch.id;
  const linkPath = path.join(canonicalWidgetsRoot, widgetID);
  const sourcePath = fs.realpathSync.native(packageDir);
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
  return targetPath.startsWith(developmentWidgetsRoot) || targetPath.includes("/Contents/Resources/WidgetRuntime/widgets/");
}

function notifyApp(event, widgetID, info = "") {
  return new Promise((resolve) => {
    const query = new URLSearchParams({ cwd: process.cwd() });
    if (info) {
      query.set("info", info);
    }

    const url = `notch://cli/${encodeURIComponent(widgetID)}/${event}?${query.toString()}`;
    const child = spawn("open", [url], {
      detached: true,
      stdio: "ignore",
    });
    child.unref();
    resolve();
  });
}

async function buildWidget(packageDir, options = {}) {
  const { manifest, entryFile } = readManifest(packageDir);
  const { registerCanonicalInstall = false } = options;
  if (registerCanonicalInstall) {
    ensureCanonicalSymlink(packageDir, manifest);
  }
  const notch = manifest.notch;
  const outputDir = path.join(packageDir, ".notch", "build");
  const outfile = path.join(outputDir, "index.cjs");
  fs.mkdirSync(outputDir, { recursive: true });

  await esbuild.build({
    entryPoints: [entryFile],
    outfile,
    bundle: true,
    platform: "node",
    format: "cjs",
    target: "node22",
    jsx: "automatic",
    jsxImportSource: "@notch/api",
    sourcemap: "inline",
    logLevel: "silent",
  });

  console.log(`Built ${notch.id} -> ${outfile}`);
  return manifest;
}

async function lintWidget(packageDir) {
  readManifest(packageDir);
  console.log(`Validated ${packageDir}`);
}

async function developWidget(packageDir) {
  const initial = readManifest(packageDir);
  ensureCanonicalSymlink(packageDir, initial.manifest);
  await notifyApp("start", initial.manifest.notch.id);

  let watcher;
  let buildInFlight = false;
  let buildQueued = false;
  let debounceTimer;

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
      const manifest = await buildWidget(packageDir, { registerCanonicalInstall: true });
      await notifyApp("build-success", manifest.notch.id);
    } catch (error) {
      const manifest = safeReadManifest(packageDir);
      const widgetID = manifest?.notch.id ?? path.basename(packageDir);
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
    watcher?.close().catch(() => {});
      await notifyApp("stop", initial.manifest.notch.id);
      process.exit(0);
    })();
  };

  for (const signal of ["SIGINT", "SIGTERM", "SIGQUIT", "SIGHUP"]) {
    process.once(signal, stop);
  }

  await runBuild();

  watcher = chokidar.watch(["package.json", "src", "assets"], {
    cwd: packageDir,
    persistent: true,
    atomic: true,
    ignoreInitial: true,
    ignored: [
      "**/.notch/**",
      "**/node_modules/**",
      "**/.git/**",
    ],
  });
  watcher.on("all", () => {
    scheduleBuild();
  });
}

function safeReadManifest(packageDir) {
  try {
    return readManifest(packageDir).manifest;
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
  case "helper":
    await import(pathToFileURL(path.join(rootDir, "scripts", "widget-helper.mjs")).href);
    break;
  default:
    console.error("Usage: notch <build|develop|dev|lint|helper>");
    process.exit(1);
}
