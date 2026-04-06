# @notchapp/api

React component API for building NotchApp widgets.

Install with:

```bash
npm install @notchapp/api
```

The default authoring model is component-first. Reach for `Card`, `Field`, `List`, `EmptyState`, `Toolbar`, and `DropdownMenu` before you drop to raw primitives like `RoundedRect` or `Circle`.

## Quick Start

```tsx
import {
  Button,
  Card,
  CardContent,
  CardDescription,
  CardTitle,
  DropdownMenu,
  DropdownMenuItem,
  DropdownMenuTriggerButton,
  Field,
  Input,
  Overlay,
  Section,
  usePreference,
  useLocalStorage,
} from "@notchapp/api";

export default function Widget({ environment }) {
  const [draft, setDraft] = useLocalStorage("draft", "");
  const [mailbox] = usePreference("mailbox");

  return (
    <Section spacing="md">
      <Card>
        <Overlay placement="top-end" inset="sm">
          <DropdownMenu trigger={<DropdownMenuTriggerButton symbol="ellipsis" appearance="overlay" />}>
            <DropdownMenuItem>Edit</DropdownMenuItem>
          </DropdownMenu>
        </Overlay>
        <CardContent>
          <CardTitle>Hello from NotchApp</CardTitle>
          <CardDescription>{`Span ${environment.span} • ${mailbox ?? "Inbox"} • Draft ${draft.length}`}</CardDescription>
        </CardContent>
      </Card>

      <Field>
        <Input
          value={draft}
          placeholder="Capture a note"
          onValueChange={setDraft}
        />
      </Field>

      <Button title="Clear" variant="secondary" onClick={() => setDraft("")} />
    </Section>
  );
}
```

## Primary UI Components

- `Card`, `CardHeader`, `CardTitle`, `CardDescription`, `CardContent`, `CardFooter`
- `Section`, `SectionHeader`, `SectionTitle`, `SectionDescription`
- `List`, `ListItem`, `ListItemTitle`, `ListItemDescription`, `ListItemAction`
- `Overlay`, `Field`, `Label`, `Description`, `EmptyState`, `Badge`, `Toolbar`, `ToolbarButton`
- `DropdownMenu`, `DropdownMenuTriggerButton`, `DropdownMenuItem`, `DropdownMenuCheckboxItem`, `DropdownMenuLoadingItem`, `DropdownMenuErrorItem`, `DropdownMenuSeparator`

## Primitives And Hooks

- `Stack`, `Inline`, `Spacer`
- `Text`, `Icon`, `Image`
- `Button`, `Row`, `IconButton`, `Checkbox`, `Input`
- `ScrollView`, `Divider`, `Circle`, `RoundedRect`, `Camera`, `Menu`
- `LocalStorage`
- `useLocalStorage`, `usePreference`, `useCameras`, `useTheme`, `usePromise`, `useFetch`
- `openURL`

## Theme, Preferences, And Host Data

Widgets choose a manifest `theme`, and standard components resolve their styling from that theme automatically.

Use `useTheme()` only when you need advanced customization or bespoke composition. Most widgets should not need manual color assignments for standard controls or surfaces.

Use `Overlay` as a direct child of `Card`, `Camera`, `Section`, or other container components when you need layered affordances such as settings buttons or status badges.

`Card`, `CardHeader`, `CardContent`, `CardFooter`, `Section`, `Field`, `List`, and `Toolbar` accept semantic `inset` tokens such as `none`, `sm`, and `lg` so normal widgets rarely need raw padding objects.

For the common menu case, prefer `DropdownMenu trigger={<DropdownMenuTriggerButton ... />}>...</DropdownMenu>`. The explicit `DropdownMenuTrigger` / `DropdownMenuContent` compounds remain available for advanced composition.

React-style callback aliases are preferred:

- `Button`, `Row`, `IconButton`, `ListItem`, and menu items support `onClick`
- `Checkbox` and `DropdownMenuCheckboxItem` support `onCheckedChange`
- `Input` supports `onValueChange` and `onSubmitValue`

Use the host data APIs in three patterns:

- `usePreference("name")` for manifest-backed configuration values
- `useCameras()` for host-backed resources with selection state
- `usePromise()` only for advanced custom async flows

`useCameras()` follows the shared resource shape: `items`, `value`, `setValue`, `isLoading`, `isPending`, `error`, `refresh`.

```tsx
import { Text, useCameras, usePreference } from "@notchapp/api";

export default function Widget() {
  const [mailbox] = usePreference("mailbox");
  const cameras = useCameras();

  return (
    <Text variant="body">
      {mailbox ?? "Inbox"} • {cameras.value ?? "No Camera"}
    </Text>
  );
}
```

## Learn By Example

- [list-form](../../examples/list-form)
- [media-player](../../examples/media-player)
- [settings-menu](../../examples/settings-menu)
- [widget-development.md](../../docs/widget-development.md)
- [widget-ui.md](../../docs/widget-ui.md)

## Image Notes

Local widget images live under your package `assets/` directory and can be referenced with paths like `src="assets/cover.png"`.

`Image` supports both local package assets and remote image URLs. `contentMode="fill"` is the default, and `contentMode="fit"` keeps the full image visible inside its frame.

Remote image notes:

- widgets use `https://` URLs only
- remote images are fetched by the host, not inside the widget runtime
- custom headers, cookies, and auth are not supported yet
