# NotchApp

NotchApp is a productivity app that turns your MacBook notch into an always-available widget hub.

https://github.com/user-attachments/assets/8f011a49-6c6f-4cc4-b100-5430d12cd2ae

## Features

- expand the notch into a larger interactive surface
- create multiple views and organize widgets across them
- choose from a carefully crafted set of built-in widgets (coming soon)
- build your own using a Raycast-inspired extensions API

## Planned Widgets

These are some of the built-in widgets currently planned for v1.

- **Home:** Quick Capture, Camera Preview, Music
- **Focus:** Pomodoro, Notes, Ambient Sounds
- **Plan:** Linear, Calendar, Gmail

![mock-widgets](https://github.com/user-attachments/assets/43825158-46d0-4da9-ab8f-b1b5ab1bd501)

## Requirements

- macOS 14+
- Xcode 15+
- [just](https://github.com/casey/just) (`brew install just`)

## Run

```bash
just dev
```

This command builds the app in Debug and launches `NotchApp`.

You can also open [NotchApp.xcodeproj](NotchApp.xcodeproj) in Xcode and run the `NotchApp` scheme directly.

## Project Structure

- [NotchApp/NotchAppApp.swift](NotchApp/NotchAppApp.swift): app entry point and notch/window lifecycle
- [NotchApp/NotchContentView.swift](NotchApp/NotchContentView.swift): expanded notch UI
- [NotchApp/ViewSwitcher.swift](NotchApp/ViewSwitcher.swift): tab strip, selection, and reordering
- [NotchApp/SavedViews.swift](NotchApp/SavedViews.swift): saved view model and ordering logic
- [NotchApp/NotchPanel.swift](NotchApp/NotchPanel.swift): panel behavior
- [NotchApp/NotchViewModel.swift](NotchApp/NotchViewModel.swift): hover, expansion, and pinned state

## License

Apache 2.0. See [LICENSE](LICENSE).
