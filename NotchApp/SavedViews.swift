import Foundation
import SwiftUI

struct SavedView: Identifiable, Codable, Equatable {
    static let homeID = UUID(uuidString: "52A637D9-6F60-4CC5-9F86-23F2C50555D1")!
    static let focusID = UUID(uuidString: "A01A0F0C-C616-4339-AF1B-5B35AD3C54C9")!
    static let planID = UUID(uuidString: "EE8FB2C5-4E2A-47C1-BFA9-E03F52AA8849")!

    var id: UUID
    var name: String
    var icon: String

    init(id: UUID = UUID(), name: String, icon: String) {
        self.id = id
        self.name = name
        self.icon = icon
    }

    static let defaultViews: [SavedView] = [
        SavedView(id: homeID, name: "Home", icon: "house.fill"),
        SavedView(id: focusID, name: "Focus", icon: "timer"),
        SavedView(id: planID, name: "Plan", icon: "calendar"),
    ]
}

enum WidgetKind: String, CaseIterable, Codable, Identifiable {
    case inbox
    case pomodoro
    case calendar
    case cameraPreview
    case ambientSounds
    case music
    case notes
    case linear
    case gmail

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inbox: "Capture"
        case .pomodoro: "Pomodoro"
        case .calendar: "Calendar"
        case .cameraPreview: "Camera Preview"
        case .ambientSounds: "Ambient Sounds"
        case .music: "Music"
        case .notes: "Notes"
        case .linear: "Linear"
        case .gmail: "Gmail"
        }
    }

    var icon: String {
        switch self {
        case .inbox: "square.and.pencil"
        case .pomodoro: "timer"
        case .calendar: "calendar"
        case .cameraPreview: "camera.fill"
        case .ambientSounds: "speaker.wave.2.fill"
        case .music: "music.note"
        case .notes: "note.text"
        case .linear: "point.3.connected.trianglepath.dotted"
        case .gmail: "envelope.fill"
        }
    }

    var caption: String {
        switch self {
        case .inbox: "Quick capture"
        case .pomodoro: "Focus timer"
        case .calendar: "Today's Schedule"
        case .cameraPreview: "Mirror preview"
        case .ambientSounds: "Focus atmosphere"
        case .music: "Now playing"
        case .notes: "Scratchpad"
        case .linear: "Assigned issues"
        case .gmail: "Unread triage"
        }
    }

    var tint: Color {
        switch self {
        case .inbox: Color(red: 0.98, green: 0.46, blue: 0.48)
        case .pomodoro: Color(red: 0.99, green: 0.68, blue: 0.35)
        case .calendar: Color(red: 0.39, green: 0.68, blue: 0.98)
        case .cameraPreview: Color(red: 0.56, green: 0.68, blue: 0.96)
        case .ambientSounds: Color(red: 0.46, green: 0.82, blue: 0.72)
        case .music: Color(red: 0.69, green: 0.54, blue: 0.98)
        case .notes: Color(red: 0.54, green: 0.76, blue: 0.98)
        case .linear: Color(red: 0.72, green: 0.58, blue: 0.98)
        case .gmail: Color(red: 0.96, green: 0.46, blue: 0.48)
        }
    }

    var supportedSpans: [Int] {
        switch self {
        case .inbox: [3, 5, 6]
        case .pomodoro: [3, 4, 6, 9]
        case .calendar: [3, 6]
        case .cameraPreview: [3, 4, 6, 9]
        case .ambientSounds: [3, 4, 6]
        case .music: [3]
        case .notes: [3, 4, 6]
        case .linear: [3, 6]
        case .gmail: [3, 6]
        }
    }

    var defaultSpan: Int {
        supportedSpans.first ?? 1
    }
}

struct WidgetInstance: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: WidgetKind
    var startColumn: Int
    var span: Int

    init(id: UUID = UUID(), kind: WidgetKind, startColumn: Int, span: Int) {
        self.id = id
        self.kind = kind
        self.startColumn = startColumn
        self.span = span
    }
}

struct ViewLayout: Codable, Equatable {
    static let columnCount = 12

    var widgets: [WidgetInstance] = []
}

struct ValidatedViewLayout {
    var layout: ViewLayout
    var occupancy: [UUID?]
}

@MainActor
@Observable
final class ViewManager {
    var views: [SavedView]
    var selectedViewID: UUID
    private var layoutsByViewID: [UUID: ViewLayout]

    init() {
        views = SavedView.defaultViews
        selectedViewID = SavedView.defaultViews[0].id
        layoutsByViewID = Dictionary(
            uniqueKeysWithValues: SavedView.defaultViews.map { ($0.id, Self.defaultLayout(for: $0)) }
        )
    }

    var selectedView: SavedView? {
        views.first { $0.id == selectedViewID }
    }

    var selectedLayout: ViewLayout {
        guard let view = selectedView else { return ViewLayout() }
        return layout(for: view)
    }

    var selectedValidatedLayout: ValidatedViewLayout? {
        guard let view = selectedView else { return nil }
        return validatedLayout(for: view)
    }

    func layout(for view: SavedView) -> ViewLayout {
        layoutsByViewID[view.id] ?? Self.defaultLayout(for: view)
    }

    func validatedLayout(for view: SavedView) -> ValidatedViewLayout? {
        let layout = layout(for: view)
        return Self.validate(layout: layout)
    }

    func layoutSnapshot() -> [UUID: ViewLayout] {
        layoutsByViewID
    }

    func restoreLayouts(from snapshot: [UUID: ViewLayout]) {
        layoutsByViewID = snapshot
    }

    func select(_ view: SavedView) {
        selectedViewID = view.id
    }

    func addView(name: String, icon: String = "square.grid.2x2.fill") {
        let view = SavedView(name: name, icon: icon)
        views.append(view)
        layoutsByViewID[view.id] = ViewLayout()
        selectedViewID = view.id
    }

    func removeView(_ view: SavedView) {
        guard views.count > 1 else { return }
        views.removeAll { $0.id == view.id }
        layoutsByViewID.removeValue(forKey: view.id)
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

    func occupancyForSelectedView() -> [UUID?] {
        selectedValidatedLayout?.occupancy ?? Array(repeating: nil, count: ViewLayout.columnCount)
    }

    func addWidget(_ kind: WidgetKind, at column: Int, in view: SavedView? = nil) {
        let targetView = view ?? selectedView
        guard let targetView else { return }
        var layout = Self.normalizedPackedLayout(for: layout(for: targetView))
        let usedColumns = Self.totalUsedColumns(in: layout)
        guard usedColumns + kind.defaultSpan <= ViewLayout.columnCount else { return }

        let widget = WidgetInstance(kind: kind, startColumn: usedColumns, span: kind.defaultSpan)
        layout.widgets.append(widget)
        setLayout(Self.packedLayout(for: layout.widgets), for: targetView)
    }

    func removeWidget(_ widgetID: UUID, in view: SavedView? = nil) {
        let targetView = view ?? selectedView
        guard let targetView else { return }

        var layout = Self.normalizedPackedLayout(for: layout(for: targetView))
        layout.widgets.removeAll { $0.id == widgetID }
        setLayout(Self.packedLayout(for: layout.widgets), for: targetView)
    }

    func widget(id: UUID, in view: SavedView? = nil) -> WidgetInstance? {
        let targetView = view ?? selectedView
        guard let targetView else { return nil }
        return layout(for: targetView).widgets.first(where: { $0.id == id })
    }

    func availableSpans(for widgetID: UUID, in view: SavedView? = nil) -> [Int] {
        guard let widget = widget(id: widgetID, in: view) else { return [] }
        return widget.kind.supportedSpans
    }

    func canSetSpan(_ span: Int, for widgetID: UUID, in view: SavedView? = nil) -> Bool {
        proposedResize(widgetID: widgetID, to: span, in: view) != nil
    }

    func setSpan(_ span: Int, for widgetID: UUID, in view: SavedView? = nil) {
        guard let targetView = view ?? selectedView,
              let proposed = proposedResize(widgetID: widgetID, to: span, in: targetView) else { return }
        setLayout(proposed.layout, for: targetView)
    }

    func canSwapWidget(_ widgetID: UUID, direction: MoveDirection, in view: SavedView? = nil) -> Bool {
        proposedSwap(widgetID: widgetID, direction: direction, in: view) != nil
    }

    func swapWidget(_ widgetID: UUID, direction: MoveDirection, in view: SavedView? = nil) {
        guard let targetView = view ?? selectedView,
              let proposed = proposedSwap(widgetID: widgetID, direction: direction, in: targetView) else { return }
        setLayout(proposed.layout, for: targetView)
    }

    func isColumnEmpty(_ column: Int, in view: SavedView? = nil) -> Bool {
        let targetView = view ?? selectedView
        guard let targetView, let occupancy = validatedLayout(for: targetView)?.occupancy,
              occupancy.indices.contains(column) else { return false }
        return occupancy[column] == nil
    }

    func widgetStartColumn(for widgetID: UUID, in view: SavedView? = nil) -> Int? {
        widget(id: widgetID, in: view)?.startColumn
    }

    private func proposedResize(widgetID: UUID, to span: Int, in view: SavedView?) -> ValidatedViewLayout? {
        let targetView = view ?? selectedView
        guard let targetView,
              var layout = validatedLayout(for: targetView)?.layout,
              let index = layout.widgets.firstIndex(where: { $0.id == widgetID }) else { return nil }

        layout = Self.normalizedPackedLayout(for: layout)

        let widget = layout.widgets[index]
        guard widget.kind.supportedSpans.contains(span) else { return nil }

        if span == widget.span {
            return Self.validate(layout: Self.packedLayout(for: layout.widgets))
        }

        layout.widgets[index].span = span
        guard Self.totalUsedColumns(in: layout) <= ViewLayout.columnCount else { return nil }
        return Self.validate(layout: Self.packedLayout(for: layout.widgets))
    }

    private func proposedSwap(widgetID: UUID, direction: MoveDirection, in view: SavedView?) -> ValidatedViewLayout? {
        let targetView = view ?? selectedView
        guard let targetView else { return nil }

        let sortedWidgets = Self.normalizedPackedLayout(for: layout(for: targetView)).widgets

        guard let current = sortedWidgets.first(where: { $0.id == widgetID }),
              let neighbor = neighborWidget(for: current, direction: direction, in: sortedWidgets) else { return nil }

        var reorderedWidgets = sortedWidgets
        guard let currentIndex = reorderedWidgets.firstIndex(where: { $0.id == current.id }),
              let neighborIndex = reorderedWidgets.firstIndex(where: { $0.id == neighbor.id }) else { return nil }
        reorderedWidgets.swapAt(currentIndex, neighborIndex)
        return Self.validate(layout: Self.packedLayout(for: reorderedWidgets))
    }

    private func neighborWidget(for widget: WidgetInstance, direction: MoveDirection, in widgets: [WidgetInstance]) -> WidgetInstance? {
        let sorted = widgets.sorted { $0.startColumn < $1.startColumn }
        guard let index = sorted.firstIndex(where: { $0.id == widget.id }) else { return nil }

        switch direction {
        case .left:
            guard index > 0 else { return nil }
            return sorted[index - 1]
        case .right:
            guard index < sorted.index(before: sorted.endIndex) else { return nil }
            return sorted[index + 1]
        }
    }

    private func setLayout(_ layout: ViewLayout, for view: SavedView) {
        guard let validated = Self.validate(layout: layout) else {
            assertionFailure("Attempted to save invalid layout for \(view.name)")
            return
        }

        layoutsByViewID[view.id] = validated.layout
    }

    private func move(_ view: SavedView, by offset: Int) {
        guard let currentIndex = views.firstIndex(where: { $0.id == view.id }) else { return }
        let destinationIndex = currentIndex + offset
        guard views.indices.contains(destinationIndex) else { return }
        views.swapAt(currentIndex, destinationIndex)
    }

    private static func occupant(at column: Int, in layout: ViewLayout) -> UUID? {
        validate(layout: layout)?.occupancy[column]
    }

    private static func totalUsedColumns(in layout: ViewLayout) -> Int {
        layout.widgets.reduce(0) { $0 + $1.span }
    }

    private static func normalizedPackedLayout(for layout: ViewLayout) -> ViewLayout {
        packedLayout(for: layout.widgets.sorted { lhs, rhs in
            if lhs.startColumn == rhs.startColumn {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.startColumn < rhs.startColumn
        })
    }

    private static func packedLayout(for widgets: [WidgetInstance]) -> ViewLayout {
        var packedWidgets: [WidgetInstance] = []
        var nextStart = 0

        for var widget in widgets {
            widget.startColumn = nextStart
            packedWidgets.append(widget)
            nextStart += widget.span
        }

        return ViewLayout(widgets: packedWidgets)
    }

    static func validate(layout: ViewLayout) -> ValidatedViewLayout? {
        var occupancy = Array<UUID?>(repeating: nil, count: ViewLayout.columnCount)

        for widget in layout.widgets {
            guard widget.kind.supportedSpans.contains(widget.span) else { return nil }
            guard widget.startColumn >= 0 else { return nil }
            let endColumn = widget.startColumn + widget.span
            guard endColumn <= ViewLayout.columnCount else { return nil }

            for column in widget.startColumn..<endColumn {
                if occupancy[column] != nil {
                    return nil
                }
                occupancy[column] = widget.id
            }
        }

        return ValidatedViewLayout(layout: layout, occupancy: occupancy)
    }

    static func repairedLayout(for layout: ViewLayout, prioritized: [UUID]) -> ValidatedViewLayout? {
        if let validated = validate(layout: layout) {
            return validated
        }

        var repaired = layout

        for widgetID in prioritized {
            guard let index = repaired.widgets.firstIndex(where: { $0.id == widgetID }) else { continue }
            let supported = repaired.widgets[index].kind.supportedSpans.filter { $0 <= repaired.widgets[index].span }.sorted(by: >)

            for span in supported {
                repaired.widgets[index].span = span
                if let validated = validate(layout: repaired) {
                    return validated
                }
            }
        }

        return nil
    }

    static func shiftRightToResolveOverlaps(in layout: inout ViewLayout) {
        let sortedIDs = layout.widgets
            .sorted { lhs, rhs in
                if lhs.startColumn == rhs.startColumn {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.startColumn < rhs.startColumn
            }
            .map(\.id)

        var nextStart = 0

        for id in sortedIDs {
            guard let index = layout.widgets.firstIndex(where: { $0.id == id }) else { continue }
            layout.widgets[index].startColumn = max(layout.widgets[index].startColumn, nextStart)
            nextStart = layout.widgets[index].startColumn + layout.widgets[index].span
        }
    }

    private static func defaultLayout(for view: SavedView) -> ViewLayout {
        switch view.id {
        case SavedView.homeID:
            return ViewLayout(widgets: [
                WidgetInstance(kind: .inbox, startColumn: 0, span: 5),
                WidgetInstance(kind: .cameraPreview, startColumn: 5, span: 4),
                WidgetInstance(kind: .music, startColumn: 9, span: 3),
            ])
        case SavedView.focusID:
            return ViewLayout(widgets: [
                WidgetInstance(kind: .pomodoro, startColumn: 0, span: 4),
                WidgetInstance(kind: .notes, startColumn: 4, span: 4),
                WidgetInstance(kind: .ambientSounds, startColumn: 8, span: 4),
            ])
        case SavedView.planID:
            return ViewLayout(widgets: [
                WidgetInstance(kind: .linear, startColumn: 0, span: 6),
                WidgetInstance(kind: .calendar, startColumn: 6, span: 3),
                WidgetInstance(kind: .gmail, startColumn: 9, span: 3),
            ])
        default:
            return ViewLayout()
        }
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

enum MoveDirection {
    case left
    case right
}
