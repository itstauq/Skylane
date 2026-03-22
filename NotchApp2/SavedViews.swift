import SwiftUI

struct SavedView: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var icon: String // SF Symbol name

    init(name: String, icon: String) {
        self.id = UUID()
        self.name = name
        self.icon = icon
    }

    static let defaultViews: [SavedView] = [
        SavedView(name: "Home", icon: "house.fill"),
        SavedView(name: "Focus", icon: "timer"),
        SavedView(name: "Plan", icon: "calendar"),
    ]
}

@MainActor
@Observable
final class ViewManager {
    var views: [SavedView] = SavedView.defaultViews
    var selectedViewID: UUID

    init() {
        selectedViewID = SavedView.defaultViews[0].id
    }

    var selectedView: SavedView? {
        views.first { $0.id == selectedViewID }
    }

    func select(_ view: SavedView) {
        selectedViewID = view.id
    }

    func addView(name: String, icon: String = "square.grid.2x2.fill") {
        let view = SavedView(name: name, icon: icon)
        views.append(view)
        selectedViewID = view.id
    }

    func removeView(_ view: SavedView) {
        guard views.count > 1 else { return }
        views.removeAll { $0.id == view.id }
        if selectedViewID == view.id {
            selectedViewID = views[0].id
        }
    }

    func renameView(_ view: SavedView, to name: String) {
        if let i = views.firstIndex(where: { $0.id == view.id }) {
            views[i].name = name
        }
    }

    func setIcon(_ view: SavedView, to icon: String) {
        if let i = views.firstIndex(where: { $0.id == view.id }) {
            views[i].icon = icon
        }
    }

    func canMoveViewLeft(_ view: SavedView) -> Bool {
        guard let index = views.firstIndex(where: { $0.id == view.id }) else { return false }
        return index > 0
    }

    func canMoveViewRight(_ view: SavedView) -> Bool {
        guard let index = views.firstIndex(where: { $0.id == view.id }) else { return false }
        return index < views.index(before: views.endIndex)
    }

    func moveViewLeft(_ view: SavedView) {
        move(view, by: -1)
    }

    func moveViewRight(_ view: SavedView) {
        move(view, by: 1)
    }

    func moveView(id: UUID, to destinationIndex: Int) {
        guard let currentIndex = views.firstIndex(where: { $0.id == id }) else { return }

        let boundedDestination = min(max(destinationIndex, 0), views.count)
        let adjustedDestination = currentIndex < boundedDestination ? boundedDestination - 1 : boundedDestination

        guard currentIndex != adjustedDestination else { return }

        let movedView = views.remove(at: currentIndex)
        views.insert(movedView, at: adjustedDestination)
    }

    private func move(_ view: SavedView, by offset: Int) {
        guard let currentIndex = views.firstIndex(where: { $0.id == view.id }) else { return }
        let destinationIndex = currentIndex + offset
        guard views.indices.contains(destinationIndex) else { return }
        views.swapAt(currentIndex, destinationIndex)
    }

    static let availableIcons = [
        "house.fill", "chart.bar.fill", "square.grid.2x2.fill",
        "star.fill", "bookmark.fill", "folder.fill",
        "tray.fill", "clock.fill", "calendar",
        "checkmark.circle.fill", "bell.fill", "gear",
        "person.fill", "heart.fill", "bolt.fill",
        "music.note", "gamecontroller.fill", "paintbrush.fill",
        "terminal.fill", "doc.text.fill", "globe",
    ]
}
