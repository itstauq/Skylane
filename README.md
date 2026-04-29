# Skylane

Skylane is a productivity app that turns your MacBook cutout into an always-available widget hub.

https://github.com/user-attachments/assets/7ad6477e-7c51-41ae-8b2b-f1d7d288fdd9

## Features

- expand the compact surface into a larger interactive workspace
- create multiple views and organize widgets across them
- choose from a carefully crafted set of built-in widgets
- build your own using a Raycast-inspired extensions API

## Built-in Widgets

These ship with Skylane.

- **Home:** Quick Capture, Camera Preview, Music
- **Focus:** Pomodoro, Goal, Ambient Sounds
- **Plan:** Linear, Calendar, Email

## Requirements

- macOS 14+
- Xcode 15+
- [just](https://github.com/casey/just) (`brew install just`)

## Run

```bash
just dev
```

This command builds the app in Debug and launches `Skylane`.

You can also open [Skylane.xcodeproj](Skylane.xcodeproj) in Xcode and run the `Skylane` scheme directly.

## Project Structure

- [Skylane/SkylaneApp.swift](Skylane/SkylaneApp.swift): app entry point and lane/window lifecycle
- [Skylane/LaneContentView.swift](Skylane/LaneContentView.swift): expanded lane UI
- [Skylane/ViewSwitcher.swift](Skylane/ViewSwitcher.swift): tab strip, selection, and reordering
- [Skylane/SavedViews.swift](Skylane/SavedViews.swift): saved view model and ordering logic
- [Skylane/LanePanel.swift](Skylane/LanePanel.swift): panel behavior
- [Skylane/LaneViewModel.swift](Skylane/LaneViewModel.swift): hover, expansion, and pinned state

## License

Apache 2.0. See [LICENSE](LICENSE).
