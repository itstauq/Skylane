#!/usr/bin/env node

const path = require("node:path");
const { pathToFileURL } = require("node:url");

const cliURL = pathToFileURL(
  path.resolve(__dirname, "../../../scripts/notch-widget-cli.mjs")
);

import(cliURL.href);
