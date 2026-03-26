# notchapp

CLI for developing and building NotchApp widgets.

## Install

```bash
npm install --save-dev notchapp
npm install @notchapp/api
```

## Usage

Inside a widget package:

```bash
npx notchapp dev
```

This starts the hot-reload workflow:

- builds the widget into `.notch/build/index.cjs`
- registers the local widget with NotchApp for development
- rebuilds when `package.json`, `src/`, or `assets/` change
- tells NotchApp to reload the widget after each successful build

Other commands:

```bash
npx notchapp build
npx notchapp lint
```

## Widget Shape

A widget package needs:

- `package.json`
- `src/index.tsx`
- a `notch` manifest in `package.json`

Example:

```json
{
  "name": "@acme/notchapp-widget-hello",
  "private": true,
  "scripts": {
    "dev": "notchapp dev",
    "build": "notchapp build",
    "lint": "notchapp lint"
  },
  "devDependencies": {
    "notchapp": "^0.1.0"
  },
  "dependencies": {
    "@notchapp/api": "^0.1.0"
  },
  "notch": {
    "id": "com.acme.hello",
    "title": "Hello",
    "icon": "sparkles",
    "minSpan": 3,
    "maxSpan": 6,
    "entry": "src/index.tsx"
  }
}
```

NotchApp itself currently runs on macOS. The SDK source and examples live in the main repository:

<https://github.com/itstauq/NotchApp>
