# @notchapp/api

Component API for building NotchApp widgets.

Install with:

```bash
npm install @notchapp/api
```

Use it in a widget:

```tsx
import { Button, Stack, Text } from "@notchapp/api";

export const initialState = {
  count: 0,
};

export const actions = {
  increment(state) {
    return {
      ...state,
      count: (state?.count ?? 0) + 1,
    };
  },
};

export default function Widget({ environment, state }) {
  return (
    <Stack spacing={10}>
      <Text>Hello from NotchApp</Text>
      <Text tone="secondary">{`Span ${environment.span} • Count ${state.count}`}</Text>
      <Button title="Increment" action="increment" />
    </Stack>
  );
}
```

Current exports:

- `Stack`
- `Inline`
- `Row`
- `Text`
- `Icon`
- `IconButton`
- `Checkbox`
- `Input`
- `Button`

The SDK source and examples live in the main repository:

<https://github.com/itstauq/NotchApp>
