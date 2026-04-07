const React = require("react");
const { useLocalStorage } = require("./hooks/useLocalStorage");
const { usePromise } = require("./hooks/usePromise");
const { useFetch } = require("./hooks/useFetch");
const { useTheme } = require("./hooks/useTheme");
const { usePreference } = require("./hooks/usePreference");
const { useCameras } = require("./hooks/useCameras");
const { useMedia } = require("./hooks/useMedia");
const { openURL } = require("./functions/openURL");
const { LocalStorage } = require("./runtime");

const OVERLAY_SLOT_TYPE = "__notch_overlay";
const LEADING_ACCESSORY_SLOT_TYPE = "__notch_leadingAccessory";
const TRAILING_ACCESSORY_SLOT_TYPE = "__notch_trailingAccessory";
const MENU_LABEL_SLOT_TYPE = "__notch_menuLabel";

function slot(type, props, children, key) {
  return React.createElement(
    type,
    key == null ? props : { ...(props ?? {}), key },
    children
  );
}

function normalizeOverlayChildren(overlay) {
  if (overlay == null || overlay === false) {
    return [];
  }

  if (Array.isArray(overlay)) {
    return overlay.flatMap(normalizeOverlayChildren);
  }

  if (React.isValidElement(overlay)) {
    return [slot(OVERLAY_SLOT_TYPE, { alignment: "center" }, overlay, overlay.key)];
  }

  if (typeof overlay === "object") {
    const node = overlay.element ?? overlay.node;
    if (node != null) {
      return [
        slot(
          OVERLAY_SLOT_TYPE,
          {
            alignment: overlayAlignment(overlay.placement ?? overlay.position ?? overlay.alignment),
            inset: overlay.inset,
            offset: overlay.offset,
          },
          node,
          overlay.key ?? node.key
        ),
      ];
    }
  }

  return [];
}

function normalizeAccessoryChild(type, accessory) {
  if (accessory == null || accessory === false) {
    return [];
  }

  return [slot(type, null, accessory)];
}

function normalizeMenuLabel(label) {
  if (label == null || label === false) {
    return [];
  }

  return [slot(MENU_LABEL_SLOT_TYPE, null, label)];
}

function createHostElement(type, rawProps = {}) {
  const {
    children,
    overlay,
    leadingAccessory,
    trailingAccessory,
    ...props
  } = rawProps;
  const hostChildren = [];

  if (children !== undefined) {
    hostChildren.push(children);
  }

  hostChildren.push(...normalizeOverlayChildren(overlay));
  hostChildren.push(...normalizeAccessoryChild(LEADING_ACCESSORY_SLOT_TYPE, leadingAccessory));
  hostChildren.push(...normalizeAccessoryChild(TRAILING_ACCESSORY_SLOT_TYPE, trailingAccessory));

  return React.createElement(type, props, ...hostChildren);
}

function resolveSpacing(theme, value, fallback) {
  if (typeof value === "number") {
    return value;
  }

  switch (value) {
    case "xs":
      return theme.spacing.xs;
    case "sm":
      return theme.spacing.sm;
    case "md":
      return theme.spacing.md;
    case "lg":
      return theme.spacing.lg;
    case "xl":
      return theme.spacing.xl;
    default:
      return fallback;
  }
}

function resolveInset(theme, value, fallback) {
  if (typeof value === "number") {
    return value;
  }

  switch (value) {
    case "none":
      return 0;
    case "xs":
      return theme.spacing.xs;
    case "sm":
      return theme.spacing.sm;
    case "md":
      return theme.spacing.md;
    case "lg":
      return theme.spacing.lg;
    case "xl":
      return theme.spacing.xl;
    default:
      return fallback;
  }
}

function resolveInsetPadding(theme, inset, fallback) {
  if (inset === undefined) {
    return fallback;
  }

  return resolveInset(theme, inset, 0);
}

function resolveFrame(frame, defaults = {}) {
  return { ...defaults, ...(frame ?? {}) };
}

function overlayAlignment(value) {
  switch (value) {
    case "top-start":
    case "topLeading":
      return "topLeading";
    case "top":
      return "top";
    case "top-end":
    case "topTrailing":
      return "topTrailing";
    case "start":
    case "leading":
      return "leading";
    case "end":
    case "trailing":
      return "trailing";
    case "bottom-start":
    case "bottomLeading":
      return "bottomLeading";
    case "bottom":
      return "bottom";
    case "bottom-end":
    case "bottomTrailing":
      return "bottomTrailing";
    default:
      return "center";
  }
}

function contentAlignment(value, fallback = "leading") {
  return typeof value === "string" ? value : fallback;
}

function resolvePressHandler(props = {}) {
  return typeof props.onClick === "function" ? props.onClick : props.onPress;
}

function resolveToggleHandler(props = {}) {
  if (typeof props.onCheckedChange === "function") {
    return () => props.onCheckedChange(!(props.checked === true));
  }

  if (typeof props.onChange === "function") {
    return () => props.onChange(!(props.checked === true));
  }

  return resolvePressHandler(props);
}

function resolveInputChangeHandler(props = {}) {
  if (typeof props.onValueChange === "function") {
    return (payload) => props.onValueChange(payload?.value ?? "");
  }

  return props.onChange;
}

function resolveInputSubmitHandler(props = {}) {
  if (typeof props.onSubmitValue === "function") {
    return (payload) => props.onSubmitValue(payload?.value ?? "");
  }

  return props.onSubmit;
}

function normalizeButtonVariant(variant) {
  switch (variant) {
    case "default":
    case "primary":
      return "primary";
    case "outline":
    case "secondary":
      return "secondary";
    case "ghost":
      return "ghost";
    case "destructive":
      return "destructive";
    default:
      return variant;
  }
}

function normalizeRowVariant(variant) {
  switch (variant) {
    case "default":
    case "secondary":
      return "secondary";
    case "accent":
      return "accent";
    case "ghost":
      return "ghost";
    default:
      return variant;
  }
}

function normalizeIconButtonVariant(variant) {
  switch (variant) {
    case "default":
    case "primary":
      return "primary";
    case "secondary":
      return "secondary";
    case "subtle":
      return "subtle";
    case "ghost":
      return "ghost";
    case "destructive":
      return "destructive";
    default:
      return variant;
  }
}

function splitOverlayChildren(children) {
  const contentChildren = [];
  const overlayChildren = [];

  for (const child of React.Children.toArray(children)) {
    if (React.isValidElement(child) && child.type === Overlay) {
      overlayChildren.push(child);
      continue;
    }

    contentChildren.push(child);
  }

  return {
    contentChildren,
    overlayChildren,
  };
}

function Stack(props = {}) {
  return createHostElement("Stack", props);
}

function Inline(props = {}) {
  return createHostElement("Inline", props);
}

function Spacer(props = {}) {
  return createHostElement("Spacer", props);
}

function Overlay(props = {}) {
  const theme = useTheme();
  const {
    children,
    placement = "center",
    position,
    inset = "none",
    offset,
  } = props;

  return slot(OVERLAY_SLOT_TYPE, {
    alignment: overlayAlignment(placement ?? position),
    inset: resolveInset(theme, inset, 0),
    offset,
  }, children);
}

function Text(props = {}) {
  const { role, variant, ...rest } = props;
  return createHostElement("Text", {
    ...rest,
    variant: typeof variant === "string" ? variant : role,
  });
}

function Icon(props = {}) {
  return createHostElement("Icon", props);
}

function Image(props = {}) {
  return createHostElement("Image", props);
}

function Camera(props = {}) {
  const theme = useTheme();

  return createHostElement("Camera", {
    ...props,
    frame: resolveFrame(props.frame, { maxWidth: Infinity, maxHeight: Infinity }),
    clipShape: props.clipShape ?? { type: "roundedRect", cornerRadius: theme.radius.lg },
    background: props.background ?? theme.colors.surfaceCanvas,
  });
}

function Menu(props = {}) {
  const { children, label, ...rest } = props;
  const hostChildren = [];

  if (children !== undefined) {
    hostChildren.push(children);
  }

  hostChildren.push(...normalizeMenuLabel(label));

  return React.createElement("Menu", rest, ...hostChildren);
}

function Button(props = {}) {
  const { variant, onClick, ...rest } = props;
  return createHostElement("Button", {
    ...rest,
    onPress: resolvePressHandler(props),
    variant: normalizeButtonVariant(variant ?? "default"),
  });
}

function Row(props = {}) {
  const { variant, onClick, ...rest } = props;
  return createHostElement("Row", {
    ...rest,
    onPress: resolvePressHandler(props),
    variant: normalizeRowVariant(variant ?? "default"),
  });
}

function IconButton(props = {}) {
  const { variant, onClick, ...rest } = props;
  return createHostElement("IconButton", {
    ...rest,
    onPress: resolvePressHandler(props),
    variant: normalizeIconButtonVariant(variant ?? "ghost"),
  });
}

function Checkbox(props = {}) {
  const {
    onClick,
    onPress,
    onChange,
    onCheckedChange,
    ...rest
  } = props;

  return createHostElement("Checkbox", {
    ...rest,
    onPress: resolveToggleHandler(props),
  });
}

function Input(props = {}) {
  const {
    onValueChange,
    onSubmitValue,
    ...rest
  } = props;

  return createHostElement("Input", {
    ...rest,
    onChange: resolveInputChangeHandler(props),
    onSubmit: resolveInputSubmitHandler(props),
  });
}

function ScrollView(props = {}) {
  return createHostElement("ScrollView", props);
}

function Marquee(props = {}) {
  const {
    active = true,
    delay = 1.2,
    speed = 30,
    gap = 28,
    fadeEdges = true,
    ...rest
  } = props;

  return createHostElement("Marquee", {
    ...rest,
    active,
    delay,
    speed,
    gap,
    fadeEdges,
    frame: resolveFrame(rest.frame, { maxWidth: Infinity }),
  });
}

function Divider(props = {}) {
  return createHostElement("Divider", props);
}

function Circle(props = {}) {
  return createHostElement("Circle", props);
}

function RoundedRect(props = {}) {
  return createHostElement("RoundedRect", props);
}

function cardSurfaceStyles(theme, variant) {
  switch (variant) {
    case "accent":
      return {
        fill: theme.colors.surfaceAccent,
        strokeColor: theme.colors.borderAccent,
      };
    case "secondary":
      return {
        fill: theme.colors.surfaceSecondary,
        strokeColor: theme.colors.borderSecondary,
      };
    case "ghost":
      return {
        fill: "#00000000",
        strokeColor: theme.colors.borderSecondary,
      };
    default:
      return {
        fill: theme.colors.surfacePrimary,
        strokeColor: theme.colors.borderPrimary,
      };
  }
}

function badgeStyles(theme, variant) {
  switch (variant) {
    case "secondary":
      return {
        fill: theme.colors.surfaceSecondary,
        strokeColor: theme.colors.borderSecondary,
        textTone: "secondary",
        iconColor: theme.colors.iconSecondary,
      };
    case "outline":
      return {
        fill: "#00000000",
        strokeColor: theme.colors.borderPrimary,
        textTone: "secondary",
        iconColor: theme.colors.iconSecondary,
      };
    default:
      return {
        fill: theme.colors.surfaceAccent,
        strokeColor: theme.colors.borderAccent,
        textTone: "onAccent",
        iconColor: theme.colors.iconOnAccent,
      };
  }
}

function Card(props = {}) {
  const theme = useTheme();
  const {
    children,
    variant = "default",
    size = "md",
    frame,
    cornerRadius,
    fill,
    strokeColor,
    strokeWidth,
    onClick,
    ...rest
  } = props;
  const styles = cardSurfaceStyles(theme, variant);
  const { contentChildren, overlayChildren } = splitOverlayChildren(children);
  const sizeFrame = size === "sm"
    ? { height: 94 }
    : size === "lg"
      ? { height: 110 }
      : null;

  return React.createElement(
    RoundedRect,
    {
      ...rest,
      onPress: resolvePressHandler(props),
      frame: resolveFrame(frame, { maxWidth: Infinity, ...(sizeFrame ?? {}) }),
      cornerRadius: cornerRadius ?? theme.radius.md,
      fill: fill ?? styles.fill,
      strokeColor: strokeColor ?? styles.strokeColor,
      strokeWidth:
        strokeWidth
        ?? ((strokeColor ?? styles.strokeColor) == null ? 0 : 1),
    },
    React.createElement(
      Stack,
      {
        spacing: 0,
        alignment: "leading",
        frame: resolveFrame(null, { maxWidth: Infinity, maxHeight: Infinity }),
      },
      contentChildren
    ),
    ...overlayChildren
  );
}

function CardHeader(props = {}) {
  const theme = useTheme();
  const { children, spacing, padding, inset, alignment, ...rest } = props;

  return React.createElement(Stack, {
    ...rest,
    spacing: resolveSpacing(theme, spacing, theme.spacing.xs),
    alignment: contentAlignment(alignment),
    padding: padding ?? resolveInsetPadding(theme, inset, {
      top: theme.spacing.lg,
      leading: theme.spacing.lg,
      trailing: theme.spacing.lg,
      bottom: theme.spacing.sm,
    }),
    frame: resolveFrame(rest.frame, { maxWidth: Infinity }),
    children,
  });
}

function CardTitle(props = {}) {
  const { children, variant, tone, ...rest } = props;
  return React.createElement(Text, {
    ...rest,
    variant: variant ?? "title",
    tone: tone ?? "primary",
    children,
  });
}

function CardDescription(props = {}) {
  const { children, variant, tone, ...rest } = props;
  return React.createElement(Text, {
    ...rest,
    variant: variant ?? "body",
    tone: tone ?? "secondary",
    children,
  });
}

function CardContent(props = {}) {
  const theme = useTheme();
  const { children, spacing, padding, inset, alignment, ...rest } = props;

  return React.createElement(Stack, {
    ...rest,
    spacing: resolveSpacing(theme, spacing, theme.spacing.sm),
    alignment: contentAlignment(alignment),
    padding: padding ?? resolveInsetPadding(theme, inset, {
      top: theme.spacing.lg,
      leading: theme.spacing.lg,
      trailing: theme.spacing.lg,
      bottom: theme.spacing.lg,
    }),
    frame: resolveFrame(rest.frame, { maxWidth: Infinity, maxHeight: Infinity }),
    children,
  });
}

function CardFooter(props = {}) {
  const theme = useTheme();
  const { children, spacing, padding, inset, alignment, ...rest } = props;

  return React.createElement(Inline, {
    ...rest,
    spacing: resolveSpacing(theme, spacing, theme.spacing.sm),
    alignment: typeof alignment === "string" ? alignment : "center",
    padding: padding ?? resolveInsetPadding(theme, inset, {
      top: theme.spacing.sm,
      leading: theme.spacing.lg,
      trailing: theme.spacing.lg,
      bottom: theme.spacing.lg,
    }),
    frame: resolveFrame(rest.frame, { maxWidth: Infinity }),
    children,
  });
}

function Section(props = {}) {
  const theme = useTheme();
  const { children, spacing, padding, inset, alignment, ...rest } = props;

  return React.createElement(Stack, {
    ...rest,
    spacing: resolveSpacing(theme, spacing, theme.spacing.md),
    alignment: contentAlignment(alignment),
    padding: padding ?? resolveInsetPadding(theme, inset, undefined),
    frame: resolveFrame(rest.frame, { maxWidth: Infinity }),
    children,
  });
}

function SectionHeader(props = {}) {
  const theme = useTheme();
  const { children, spacing, alignment, ...rest } = props;

  return React.createElement(Stack, {
    ...rest,
    spacing: resolveSpacing(theme, spacing, theme.spacing.xs),
    alignment: contentAlignment(alignment),
    children,
  });
}

function SectionTitle(props = {}) {
  const { children, variant, tone, ...rest } = props;
  return React.createElement(Text, {
    ...rest,
    variant: variant ?? "subtitle",
    tone: tone ?? "primary",
    children,
  });
}

function SectionDescription(props = {}) {
  const { children, variant, tone, ...rest } = props;
  return React.createElement(Text, {
    ...rest,
    variant: variant ?? "caption",
    tone: tone ?? "secondary",
    children,
  });
}

function List(props = {}) {
  const theme = useTheme();
  const { children, spacing, scrollable = false, padding, inset, alignment, ...rest } = props;
  const Component = scrollable ? ScrollView : Stack;

  return React.createElement(Component, {
    ...rest,
    spacing: resolveSpacing(theme, spacing, theme.spacing.sm),
    alignment: contentAlignment(alignment),
    padding: padding ?? resolveInsetPadding(theme, inset, undefined),
    children,
  });
}

function ListItemTitle(props = {}) {
  const { children, variant, tone, ...rest } = props;
  return React.createElement(Text, {
    ...rest,
    variant: variant ?? "body",
    tone: tone ?? "primary",
    lineClamp: rest.lineClamp ?? 1,
    children,
  });
}

function ListItemDescription(props = {}) {
  const { children, variant, tone, ...rest } = props;
  return React.createElement(Text, {
    ...rest,
    variant: variant ?? "caption",
    tone: tone ?? "secondary",
    children,
  });
}

function ListItemAction(props = {}) {
  return React.createElement(React.Fragment, null, props.children);
}

function ListItem(props = {}) {
  const theme = useTheme();
  const {
    children,
    leadingAccessory,
    trailingAccessory,
    onPress,
    onClick,
    variant = "default",
    spacing,
    alignment,
    ...rest
  } = props;
  const titleChildren = [];
  const descriptionChildren = [];
  const actionChildren = [];
  const bodyChildren = [];

  for (const child of React.Children.toArray(children)) {
    if (!React.isValidElement(child)) {
      bodyChildren.push(child);
      continue;
    }

    if (child.type === ListItemTitle) {
      titleChildren.push(child);
      continue;
    }

    if (child.type === ListItemDescription) {
      descriptionChildren.push(child);
      continue;
    }

    if (child.type === ListItemAction) {
      actionChildren.push(...React.Children.toArray(child.props.children));
      continue;
    }

    bodyChildren.push(child);
  }

  const hasDescription = descriptionChildren.length > 0;
  const hasTrailingContent = trailingAccessory != null || actionChildren.length > 0;

  return React.createElement(
    Row,
    {
      ...rest,
      onPress: resolvePressHandler(props),
      variant,
    },
    React.createElement(
      Inline,
      {
        spacing: resolveSpacing(theme, spacing, theme.spacing.sm),
        alignment: alignment ?? (hasDescription ? "top" : "center"),
      },
      leadingAccessory,
      React.createElement(
        Stack,
        {
          spacing: hasDescription ? theme.spacing.xs : 0,
          alignment: "leading",
          frame: { maxWidth: Infinity },
        },
        ...titleChildren,
        ...descriptionChildren,
        ...bodyChildren
      ),
      hasTrailingContent ? React.createElement(Spacer) : null,
      ...actionChildren,
      trailingAccessory
    )
  );
}

function Field(props = {}) {
  const theme = useTheme();
  const { children, spacing, padding, inset, alignment, ...rest } = props;

  return React.createElement(Stack, {
    ...rest,
    spacing: resolveSpacing(theme, spacing, theme.spacing.xs),
    alignment: contentAlignment(alignment),
    padding: padding ?? resolveInsetPadding(theme, inset, undefined),
    children,
  });
}

function Label(props = {}) {
  const { children, variant, tone, ...rest } = props;
  return React.createElement(Text, {
    ...rest,
    variant: variant ?? "label",
    tone: tone ?? "primary",
    children,
  });
}

function Description(props = {}) {
  const { children, variant, tone, ...rest } = props;
  return React.createElement(Text, {
    ...rest,
    variant: variant ?? "caption",
    tone: tone ?? "secondary",
    children,
  });
}

function Badge(props = {}) {
  const theme = useTheme();
  const {
    children,
    symbol,
    variant = "default",
    size = "md",
    ...rest
  } = props;
  const styles = badgeStyles(theme, variant);
  const horizontalPadding = size === "lg" ? theme.spacing.sm : theme.spacing.xs;
  const verticalPadding = size === "lg" ? theme.spacing.xs : 6;

  return React.createElement(
    RoundedRect,
    {
      ...rest,
      cornerRadius: theme.radius.full,
      fill: styles.fill,
      strokeColor: styles.strokeColor,
      strokeWidth: 1,
    },
    React.createElement(
      Inline,
      {
        spacing: theme.spacing.xs,
        alignment: "center",
        padding: {
          vertical: verticalPadding,
          horizontal: horizontalPadding,
        },
      },
      symbol
        ? React.createElement(Icon, {
            symbol,
            size: size === "lg" ? 12 : 10,
            weight: "semibold",
            color: styles.iconColor,
          })
        : null,
      children == null
        ? null
        : React.createElement(Text, {
            variant: size === "lg" ? "label" : "caption",
            tone: styles.textTone,
            children,
          })
    )
  );
}

function EmptyState(props = {}) {
  const theme = useTheme();
  const {
    symbol = "sparkles",
    title,
    description,
    action,
    children,
    variant = "secondary",
    ...rest
  } = props;

  return React.createElement(
    Stack,
    {
      ...rest,
      spacing: theme.spacing.sm,
      alignment: "center",
      frame: resolveFrame(rest.frame, { maxWidth: Infinity }),
    },
    symbol
      ? React.createElement(Icon, {
          symbol,
          size: 14,
          weight: "semibold",
          color: variant === "default" ? theme.colors.accent : theme.colors.iconTertiary,
        })
      : null,
    title
      ? React.createElement(Text, {
          variant: "subtitle",
          tone: "primary",
          alignment: "center",
          children: title,
        })
      : null,
    description
      ? React.createElement(Text, {
          variant: "caption",
          tone: "tertiary",
          alignment: "center",
          children: description,
        })
      : null,
    children,
    action
  );
}

function Toolbar(props = {}) {
  const theme = useTheme();
  const { children, spacing, padding, inset, alignment, ...rest } = props;

  return React.createElement(Inline, {
    ...rest,
    spacing: resolveSpacing(theme, spacing, theme.spacing.sm),
    alignment: alignment ?? "center",
    padding: padding ?? resolveInsetPadding(theme, inset, undefined),
    frame: resolveFrame(rest.frame, { maxWidth: Infinity }),
    children,
  });
}

function ToolbarButton(props = {}) {
  const {
    symbol,
    children,
    title,
    variant = "secondary",
    size = "md",
    ...rest
  } = props;

  if (symbol) {
    return React.createElement(IconButton, {
      ...rest,
      symbol,
      variant,
      size,
    });
  }

  return React.createElement(Button, {
    ...rest,
    title,
    variant,
    children,
  });
}

function DropdownMenuTrigger(props = {}) {
  return React.createElement(React.Fragment, null, props.children);
}

function DropdownMenuTriggerButton(props = {}) {
  const theme = useTheme();
  const {
    symbol = "ellipsis",
    appearance = "toolbar",
    size = "sm",
    variant = "secondary",
    ...rest
  } = props;

  if (appearance === "overlay") {
    return React.createElement(
      RoundedRect,
      {
        ...rest,
        cornerRadius: theme.radius.sm,
        fill: theme.colors.surfaceOverlay,
        width: 28,
        height: 24,
      },
      React.createElement(Icon, {
        symbol,
        size: 10,
        weight: "bold",
        color: theme.colors.iconPrimary,
      })
    );
  }

  return React.createElement(ToolbarButton, {
    ...rest,
    symbol,
    size,
    variant,
  });
}

function DropdownMenuContent(props = {}) {
  return React.createElement(React.Fragment, null, props.children);
}

function DropdownMenu(props = {}) {
  const { children, label, trigger: triggerProp, ...rest } = props;
  let trigger = triggerProp ?? label ?? null;
  const items = [];

  for (const child of React.Children.toArray(children)) {
    if (React.isValidElement(child) && child.type === DropdownMenuTrigger) {
      trigger = child.props.children;
      continue;
    }

    if (React.isValidElement(child) && child.type === DropdownMenuContent) {
      items.push(...React.Children.toArray(child.props.children));
      continue;
    }

    items.push(child);
  }

  return React.createElement(Menu, {
    ...rest,
    label: trigger,
    children: items,
  });
}

function DropdownMenuItem(props = {}) {
  const { children, onClick, ...rest } = props;
  return React.createElement(Button, {
    ...rest,
    variant: "ghost",
    onClick: props.onClick,
    onPress: props.onPress,
    children,
  });
}

function DropdownMenuCheckboxItem(props = {}) {
  const { children, checked, onChange, onCheckedChange, onClick, ...rest } = props;
  return React.createElement(Button, {
    ...rest,
    variant: "ghost",
    checked,
    onPress: resolveToggleHandler(props),
    children,
  });
}

function DropdownMenuLoadingItem(props = {}) {
  const { children = "Loading…", ...rest } = props;
  return React.createElement(DropdownMenuItem, {
    ...rest,
    disabled: true,
    children,
  });
}

function DropdownMenuErrorItem(props = {}) {
  const {
    children,
    error,
    fallback = "Unable to load.",
    ...rest
  } = props;
  const message = children
    ?? (typeof error?.message === "string" && error.message.trim() ? error.message : fallback);

  return React.createElement(DropdownMenuItem, {
    ...rest,
    disabled: true,
    children: message,
  });
}

function DropdownMenuSeparator(props = {}) {
  return React.createElement(Divider, props);
}

module.exports = {
  Stack,
  Inline,
  Spacer,
  Overlay,
  Text,
  Icon,
  Image,
  Camera,
  Menu,
  Button,
  Row,
  IconButton,
  Checkbox,
  Input,
  ScrollView,
  Marquee,
  Divider,
  Circle,
  RoundedRect,
  Card,
  CardHeader,
  CardTitle,
  CardDescription,
  CardContent,
  CardFooter,
  Section,
  SectionHeader,
  SectionTitle,
  SectionDescription,
  List,
  ListItem,
  ListItemTitle,
  ListItemDescription,
  ListItemAction,
  Field,
  Label,
  Description,
  EmptyState,
  Badge,
  Toolbar,
  ToolbarButton,
  DropdownMenu,
  DropdownMenuTrigger,
  DropdownMenuTriggerButton,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuCheckboxItem,
  DropdownMenuLoadingItem,
  DropdownMenuErrorItem,
  DropdownMenuSeparator,
  LocalStorage,
  useLocalStorage,
  usePreference,
  useCameras,
  useMedia,
  usePromise,
  useFetch,
  useTheme,
  openURL,
};
