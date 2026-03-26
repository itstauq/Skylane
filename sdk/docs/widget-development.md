# Widget Development

Build widgets for NotchApp with `notchapp` and `@notchapp/api`.

The day-to-day workflow is simple: install the SDK in your widget package, run `npx notchapp dev`, and let NotchApp hot-reload your widget while you edit.

## Install

Create a widget package and install the SDK:

```bash
npm install --save-dev notchapp
npm install @notchapp/api
```

Minimal layout:

```text
my-widget/
  package.json
  src/
    index.tsx
```

Example `package.json`:

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

## Develop

Run this inside your widget directory:

```bash
npx notchapp dev
```

Or:

```bash
npm run dev
```

`notchapp dev` is the main development workflow. It:

- builds your widget into `.notch/build/index.cjs`
- registers the local widget with NotchApp for development
- watches `package.json`, `src/`, and `assets/`
- rebuilds and reloads the widget whenever you save changes
- prints build output in the terminal

That means the normal loop is just:

1. run `npx notchapp dev`
2. edit your widget
3. save
4. see the updated widget in NotchApp

## Build

Create a production build with:

```bash
npx notchapp build
```

## Lint

Validate the widget manifest and entry file with:

```bash
npx notchapp lint
```

## Write a Widget

Each widget needs:

- a `default` export that renders the widget
- a `notch` manifest in `package.json`
- optional `initialState`
- optional `actions`

Example:

```tsx
import { Button, Stack, Text } from "@notchapp/api";

export const initialState = {
  count: 0,
  draft: "",
};

export const actions = {
  increment(state) {
    return {
      ...state,
      count: (state?.count ?? 0) + 1,
    };
  },
  setDraft(state, { payload }) {
    return {
      ...state,
      draft: payload?.value ?? "",
    };
  },
};

export default function Widget({ environment, state, logger }) {
  logger.info(`render span=${environment.span} count=${state.count}`);

  return (
    <Stack spacing={10}>
      <Text>Hello from NotchApp</Text>
      <Text tone="secondary">{`Span ${environment.span} • Count ${state.count}`}</Text>
      <Button title="Increment" action="increment" />
    </Stack>
  );
}
```

`initialState` is the per-widget-instance state that NotchApp keeps while the widget is mounted. That state comes back into your render function as `state`.

The render function receives:

- `environment`
- `state`
- `logger`

`environment.span` is the most useful field in practice. Use it to make your widget width-responsive and adapt to narrow or wide layouts.

Actions receive the current state plus:

- `environment`
- `logger`
- `payload`

Current payload shape:

```ts
type RuntimeActionPayload = {
  value?: string;
  id?: string;
};
```

`Input` sends `{ value }` on change and submit. `Button`, `Row`, `IconButton`, and `Checkbox` can send a custom `payload`.

If an action returns `undefined`, the current state is preserved.

## Manifest

Each widget declares a `notch` block in `package.json`.

Required fields:

- `id`
- `title`
- `icon`
- `minSpan`
- `maxSpan`

Optional fields:

- `description`
- `entry` default: `src/index.tsx`

Current validation rules:

- `id` and `title` must be non-empty
- `minSpan` and `maxSpan` must be integers
- `minSpan` must be greater than `0`
- `maxSpan` must be greater than or equal to `minSpan`
- the entry file must exist
- the host currently supports up to `12` columns

## Components

`@notchapp/api` currently exports:

- `Stack`
- `Inline`
- `Row`
- `Text`
- `Icon`
- `IconButton`
- `Checkbox`
- `Input`
- `Button`

The fastest reference is the starter widget in [sdk/examples/hello](/Users/tauquir/Projects/NotchApp2/sdk/examples/hello).
