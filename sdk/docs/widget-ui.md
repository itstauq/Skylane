# Widget UI Guide

Build widgets with the same mental model as modern React UI libraries: compose opinionated components first, then reach for primitives only when you need something bespoke.

## Cards

Use cards for surfaces, grouped actions, and hero content.

```tsx
import {
  Overlay,
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardTitle,
  DropdownMenu,
  DropdownMenuItem,
  DropdownMenuTriggerButton,
} from "@notchapp/api";

export default function Widget() {
  return (
    <Card>
      <Overlay placement="top-end" inset="sm">
        <DropdownMenu trigger={<DropdownMenuTriggerButton symbol="ellipsis" appearance="overlay" />}>
          <DropdownMenuItem>Edit</DropdownMenuItem>
        </DropdownMenu>
      </Overlay>
      <CardContent>
        <CardTitle>Weekly Review</CardTitle>
        <CardDescription>3 notes waiting for triage</CardDescription>
      </CardContent>
      <CardFooter>
        <Button title="Open" />
        <Button title="Dismiss" variant="secondary" />
      </CardFooter>
    </Card>
  );
}
```

Supported variants:

- `default`
- `secondary`
- `accent`
- `ghost`

Card size presets:

- `sm`
- `md` default
- `lg`

`CardHeader`, `CardContent`, and `CardFooter` support semantic `inset` values:

- `none`
- `xs`
- `sm`
- `md`
- `lg`
- `xl`

Overlay placements:

- `top-start`
- `top`
- `top-end`
- `start`
- `center`
- `end`
- `bottom-start`
- `bottom`
- `bottom-end`

## Lists And Fields

Use `List` and `ListItem` for structured rows. Use `Field`, `Label`, and `Description` for input groups.

```tsx
import {
  Checkbox,
  Description,
  Field,
  Input,
  List,
  ListItem,
  ListItemAction,
  ListItemTitle,
} from "@notchapp/api";

export default function Widget() {
  return (
    <>
      <Field>
        <Input placeholder="Capture a task" />
        <Description>Press return to save it.</Description>
      </Field>

      <List scrollable spacing="sm">
        <ListItem
          leadingAccessory={<Checkbox checked />}
          trailingAccessory={<Input value="2m" disabled />}
        >
          <ListItemTitle>Ship camera widget polish</ListItemTitle>
          <ListItemAction />
        </ListItem>
      </List>
    </>
  );
}
```

## Overlays And Menus

Use `Overlay` and `DropdownMenu` for layered settings affordances.

```tsx
import {
  Camera,
  DropdownMenu,
  DropdownMenuCheckboxItem,
  DropdownMenuErrorItem,
  DropdownMenuLoadingItem,
  DropdownMenuSeparator,
  DropdownMenuTriggerButton,
  Overlay,
} from "@notchapp/api";

export default function Widget() {
  return (
    <Camera>
      <Overlay placement="top-end" inset="sm">
        <DropdownMenu
          trigger={<DropdownMenuTriggerButton symbol="gearshape.fill" appearance="overlay" />}
        >
          <DropdownMenuLoadingItem>Loading Cameras…</DropdownMenuLoadingItem>
          <DropdownMenuSeparator />
          <DropdownMenuErrorItem>Unable to load cameras</DropdownMenuErrorItem>
          <DropdownMenuSeparator />
          <DropdownMenuCheckboxItem checked>Mirror Preview</DropdownMenuCheckboxItem>
          <DropdownMenuSeparator />
          <DropdownMenuCheckboxItem>Show Labels</DropdownMenuCheckboxItem>
        </DropdownMenu>
      </Overlay>
    </Camera>
  );
}
```

`Overlay` should be a direct child of the component you want to decorate.

For simple menus, prefer the `trigger` prop on `DropdownMenu`. Reach for `DropdownMenuTrigger` and `DropdownMenuContent` only when you need more custom composition.

## Toolbars

Use `Toolbar` for dense transport controls and grouped actions.

```tsx
import { Toolbar, ToolbarButton } from "@notchapp/api";

export default function Widget() {
  return (
    <Toolbar spacing="lg">
      <ToolbarButton symbol="backward.fill" variant="secondary" size="md" />
      <ToolbarButton symbol="play.fill" variant="default" size="xl" />
      <ToolbarButton symbol="forward.fill" variant="secondary" size="md" />
    </Toolbar>
  );
}
```

## Text And Escape Hatches

Use `Text variant="..."` for semantic typography:

- `title`
- `subtitle`
- `body`
- `caption`
- `label`
- `placeholder`

Use `tone` for semantics, not hierarchy:

- `primary`
- `secondary`
- `tertiary`
- `accent`
- `success`
- `warning`
- `destructive`
- `onAccent`

When you need something more custom, use `useTheme()` and low-level primitives such as `Stack`, `Inline`, `RoundedRect`, `Circle`, and `Icon`. Treat that as the advanced path, not the default path.

Callback conventions:

- prefer `onClick` for pressable actions
- prefer `onCheckedChange` for boolean controls
- prefer `onValueChange` and `onSubmitValue` for text input
