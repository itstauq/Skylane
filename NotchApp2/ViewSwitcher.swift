import SwiftUI

struct ViewSwitcher: View {
    var viewManager: ViewManager
    var vm: NotchViewModel
    private let maxVisibleViews = 3

    private var visibleViews: [SavedView] {
        let allViews = viewManager.views
        let maxVisible = min(maxVisibleViews, allViews.count)

        guard maxVisible > 0 else { return [] }

        var viewsToShow = Array(allViews.prefix(maxVisible))

        if let selectedView = viewManager.selectedView,
           !viewsToShow.contains(where: { $0.id == selectedView.id }) {
            viewsToShow[maxVisible - 1] = selectedView
        }

        return viewsToShow
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(visibleViews) { view in
                Button {
                    viewManager.select(view)
                } label: {
                    HStack {
                        Image(systemName: view.icon)
                            .font(.system(size: 10, weight: .semibold))
                        Text(view.name)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(view.id == viewManager.selectedViewID ? .white.opacity(0.12) : .clear)
                    )
                    .foregroundStyle(view.id == viewManager.selectedViewID ? .white : .white.opacity(0.65))
                }
                .buttonStyle(.plain)
            }

            Menu {
                ForEach(viewManager.views) { view in
                    Button {
                        viewManager.select(view)
                    } label: {
                        HStack {
                            Image(systemName: view.icon)
                            Text(view.name)
                            if view.id == viewManager.selectedViewID {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }

                Divider()

                Button {
                    viewManager.addView(name: "New View")
                } label: {
                    Label("Add View", systemImage: "plus")
                }

                if let view = viewManager.selectedView {
                    Button {
                        vm.renameViewName = view.name
                        vm.isRenamingView = true
                    } label: {
                        Label("Rename View", systemImage: "pencil")
                    }

                    Menu {
                        ForEach(ViewManager.availableIcons, id: \.self) { icon in
                            Button {
                                viewManager.setIcon(view, to: icon)
                            } label: {
                                HStack {
                                    Image(systemName: icon)
                                    Text(icon.replacingOccurrences(of: ".fill", with: "").replacingOccurrences(of: ".", with: " ").capitalized)
                                    if icon == view.icon {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Icon", systemImage: "paintpalette")
                    }

                    if viewManager.views.count > 1 {
                        Button(role: .destructive) {
                            viewManager.removeView(view)
                        } label: {
                            Label("Delete \"\(view.name)\"", systemImage: "trash")
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.58))
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(.white.opacity(0.08), in: Capsule())
        .foregroundStyle(.white)
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
            vm.isViewMenuOpen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
            vm.isViewMenuOpen = false
        }
    }
}
