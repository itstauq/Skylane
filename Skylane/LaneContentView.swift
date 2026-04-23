import AppKit
import AVFoundation
import SwiftUI

struct LaneContentView: View {
    var vm: LaneViewModel
    @State private var accentColor = Preferences.accentColor

    private var currentWidth: CGFloat {
        vm.isExpanded ? vm.expandedWidth : vm.laneWidth - 2
    }

    private var currentHeight: CGFloat {
        vm.isExpanded ? vm.expandedHeight : vm.laneHeight
    }

    private var headerLaneWidth: CGFloat {
        max(0, (vm.expandedWidth - vm.laneWidth) / 2)
    }

    private let headerRowHeight: CGFloat = 44

    var body: some View {
        VStack(spacing: 0) {
            if vm.isExpanded {
                expandedContent
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeIn(duration: 0.2).delay(0.15)),
                        removal: .opacity.animation(.linear(duration: 0))
                    ))
            }
        }
        .frame(width: currentWidth, height: currentHeight)
        .background(
            LaneShape(
                topCornerRadius: 0,
                bottomCornerRadius: vm.isExpanded ? 20 : (vm.isElevated ? 12 : 8)
            )
            .fill(.black)
        )
        .shadow(
            color: .white.opacity(vm.isElevated ? 0.5 : 0),
            radius: vm.isElevated ? 8 : 0
        )
        .scaleEffect(
            vm.isExpanded ? 1.0 : (vm.isElevated ? 1.075 : 1.0),
            anchor: .top
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: vm.viewManager.layoutSnapshot()) {
            vm.syncWidgetRuntimeLayouts()
        }
        .onReceive(NotificationCenter.default.publisher(for: .accentColorPreferenceDidChange)) { _ in
            accentColor = Preferences.accentColor
        }
    }

    private var expandedContent: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                ZStack(alignment: .leading) {
                    Color.clear

                    ZStack(alignment: .leading) {
                        ViewSwitcher(viewManager: vm.viewManager, vm: vm, accentTint: accentColor.color)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                    .frame(width: max(0, headerLaneWidth - 24), height: max(0, headerRowHeight - 8), alignment: .leading)
                    .clipped()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .frame(width: headerLaneWidth, height: headerRowHeight)
                .clipped()

                Rectangle()
                    .fill(.clear)
                    .frame(width: vm.laneWidth, height: headerRowHeight)

                ZStack(alignment: .trailing) {
                    Color.clear

                    HStack(spacing: 6) {
                        if vm.isEditingLayout {
                            HeaderAccessoryButton(
                                activeSymbol: "xmark",
                                tint: Color(red: 0.98, green: 0.39, blue: 0.43),
                                isActive: true
                            ) {
                                vm.revertEditMode()
                            }
                        }

                        HeaderAccessoryButton(
                            activeSymbol: vm.isEditingLayout ? "checkmark" : "pencil",
                            inactiveLabel: "Edit",
                            tint: accentColor.color,
                            isActive: vm.isEditingLayout
                        ) {
                            if vm.isEditingLayout {
                                vm.saveEditMode()
                            } else {
                                vm.toggleEditMode()
                            }
                        }

                        HeaderAccessoryButton(
                            activeSymbol: "pin.fill",
                            inactiveSymbol: "pin",
                            tint: accentColor.color,
                            isActive: vm.isViewPinned,
                            inactiveRotation: .degrees(45)
                        ) {
                            vm.togglePinnedView()
                        }

                        HeaderAccessoryButton(activeSymbol: "gearshape.fill") {
                            if !vm.isViewPinned {
                                vm.collapse()
                            }
                            AppSettingsWindow.open()
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .frame(width: headerLaneWidth, height: headerRowHeight)
                .clipped()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            WidgetLayoutRow(vm: vm, accentTint: accentColor.color)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, headerRowHeight + 12)
                .padding(.horizontal, 18)
                .padding(.bottom, 18)

            // Rename overlay — covers entire expanded area
            if vm.isRenamingView {
                RenameViewDialog(vm: vm)
            }

            if vm.isShowingEditConfirmation {
                EditModeConfirmationDialog(vm: vm)
            }
        }
    }
}

private struct WidgetLayoutRow: View {
    var vm: LaneViewModel
    var accentTint: Color

    @State private var heldWidgetID: UUID?
    @State private var heldWidgetTranslation: CGFloat = 0

    private let slotSpacing: CGFloat = 12
    private let reorderThresholdFactor: CGFloat = 0.2

    var body: some View {
        GeometryReader { geometry in
            let totalGapWidth = slotSpacing * CGFloat(max(ViewLayout.columnCount - 1, 0))
            let slotWidth = max(0, (geometry.size.width - totalGapWidth) / CGFloat(ViewLayout.columnCount))
            let validatedLayout = vm.viewManager.selectedValidatedLayout
            let usedColumns = validatedLayout?.layout.widgets.reduce(0) { max($0, $1.startColumn + $1.span) } ?? 0
            let remainingColumns = max(0, ViewLayout.columnCount - usedColumns)

            if validatedLayout == nil {
                Color.clear
                    .onAppear {
                        assertionFailure("Invalid selected layout encountered during render")
                    }
            }

            ZStack(alignment: .topLeading) {
                if let validatedLayout, validatedLayout.layout.widgets.isEmpty {
                    EmptyWidgetState(vm: vm, isEditing: vm.isEditingLayout)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if vm.isEditingLayout,
                   remainingColumns > 0,
                   let validatedLayout,
                   !validatedLayout.layout.widgets.isEmpty {
                    EmptySlotMenu(vm: vm, column: usedColumns)
                        .frame(
                            width: trailingAreaWidth(remainingColumns: remainingColumns, slotWidth: slotWidth),
                            height: geometry.size.height,
                            alignment: .topLeading
                        )
                        .offset(
                            x: CGFloat(usedColumns) * (slotWidth + slotSpacing),
                            y: 0
                        )
                }

                if let validatedLayout {
                    ForEach(validatedLayout.layout.widgets) { widget in
                        let isHeld = heldWidgetID == widget.id
                        let definition = vm.viewManager.definition(for: widget)

                        WidgetCard(
                            widget: widget,
                            vm: vm,
                            accentTint: accentTint,
                            isEditing: vm.isEditingLayout,
                            isHeld: isHeld,
                            minSpan: definition?.minSpan ?? 3,
                            maxSpan: definition?.maxSpan ?? ViewLayout.columnCount,
                            canSetSpan: { span in
                                vm.viewManager.canSetSpan(span, for: widget.id)
                            },
                            onSetSpan: { span in
                                vm.viewManager.setSpan(span, for: widget.id)
                            },
                            onRemove: {
                                vm.viewManager.removeWidget(widget.id)
                            },
                            onHandleDragChanged: { translation in
                                heldWidgetID = widget.id
                                heldWidgetTranslation = translation
                            },
                            onHandleDragEnded: { translation in
                                defer {
                                    heldWidgetID = nil
                                    heldWidgetTranslation = 0
                                }

                                let direction: MoveDirection = translation > 0 ? .right : .left
                                let threshold = moveThreshold(for: widget, direction: direction, slotWidth: slotWidth)
                                guard abs(translation) > threshold else { return }
                                vm.viewManager.swapWidget(widget.id, direction: direction)
                            }
                        )
                        .frame(
                            width: widgetWidth(for: widget, slotWidth: slotWidth),
                            height: geometry.size.height,
                            alignment: .topLeading
                        )
                        .clipped()
                        .offset(
                            x: widgetXOffset(for: widget, slotWidth: slotWidth),
                            y: 0
                        )
                        .offset(
                            x: isHeld
                                ? clampedWidgetDragOffset(heldWidgetTranslation, widget: widget, slotWidth: slotWidth)
                                : previewOffset(for: widget, slotWidth: slotWidth)
                        )
                        .shadow(color: .black.opacity(isHeld ? 0.26 : 0.12), radius: isHeld ? 18 : 10, y: isHeld ? 8 : 6)
                        .animation(.interpolatingSpring(duration: 0.22, bounce: 0.18), value: validatedLayout.layout.widgets)
                    }
                }
            }
        }
    }

    private func widgetWidth(for widget: WidgetInstance, slotWidth: CGFloat) -> CGFloat {
        (slotWidth * CGFloat(widget.span)) + (slotSpacing * CGFloat(max(widget.span - 1, 0)))
    }

    private func widgetXOffset(for widget: WidgetInstance, slotWidth: CGFloat) -> CGFloat {
        CGFloat(widget.startColumn) * (slotWidth + slotSpacing)
    }

    private func trailingAreaWidth(remainingColumns: Int, slotWidth: CGFloat) -> CGFloat {
        guard remainingColumns > 0 else { return 0 }
        return (slotWidth * CGFloat(remainingColumns)) + (slotSpacing * CGFloat(max(remainingColumns - 1, 0)))
    }

    private func clampedWidgetDragOffset(_ translation: CGFloat, widget: WidgetInstance, slotWidth: CGFloat) -> CGFloat {
        let direction: MoveDirection = translation > 0 ? .right : .left
        let threshold = moveThreshold(for: widget, direction: direction, slotWidth: slotWidth)
        return max(-threshold, min(translation * 0.35, threshold))
    }

    private func moveThreshold(for widget: WidgetInstance, direction: MoveDirection, slotWidth: CGFloat) -> CGFloat {
        neighborCenterDistance(for: widget, direction: direction, slotWidth: slotWidth) * reorderThresholdFactor
    }

    private func previewOffset(for widget: WidgetInstance, slotWidth: CGFloat) -> CGFloat {
        guard let heldWidgetID,
              let widgets = vm.viewManager.selectedValidatedLayout?.layout.widgets.sorted(by: { $0.startColumn < $1.startColumn }),
              let heldWidget = widgets.first(where: { $0.id == heldWidgetID }),
              heldWidget.id != widget.id,
              heldWidgetTranslation != 0 else { return 0 }

        let direction: MoveDirection = heldWidgetTranslation > 0 ? .right : .left
        let threshold = max(moveThreshold(for: heldWidget, direction: direction, slotWidth: slotWidth), 1)
        guard abs(heldWidgetTranslation) > threshold,
              let heldIndex = widgets.firstIndex(where: { $0.id == heldWidgetID }) else { return 0 }

        let neighborIndex = direction == .right ? heldIndex + 1 : heldIndex - 1
        guard widgets.indices.contains(neighborIndex),
              widgets[neighborIndex].id == widget.id else { return 0 }

        let progress = min((abs(heldWidgetTranslation) - threshold) / threshold, 1)
        let easedProgress = progress * progress * (3 - (2 * progress))
        let previewDistance = min(22, (widgetWidth(for: widget, slotWidth: slotWidth) * 0.18) + 6)

        return direction == .right
            ? -(previewDistance * easedProgress)
            : (previewDistance * easedProgress)
    }

    private func neighborCenterDistance(for widget: WidgetInstance, direction: MoveDirection, slotWidth: CGFloat) -> CGFloat {
        guard let widgets = vm.viewManager.selectedValidatedLayout?.layout.widgets.sorted(by: { $0.startColumn < $1.startColumn }),
              let index = widgets.firstIndex(where: { $0.id == widget.id }) else {
            return max(24, widgetWidth(for: widget, slotWidth: slotWidth) * 0.5)
        }

        let neighborIndex = direction == .left ? index - 1 : index + 1
        guard widgets.indices.contains(neighborIndex) else {
            return max(24, widgetWidth(for: widget, slotWidth: slotWidth) * 0.5)
        }

        let neighbor = widgets[neighborIndex]
        let currentWidth = widgetWidth(for: widget, slotWidth: slotWidth)
        let neighborWidth = widgetWidth(for: neighbor, slotWidth: slotWidth)

        return max(24, ((currentWidth + neighborWidth) / 2) + (slotSpacing / 2))
    }
}

private struct EmptySlotMenu: View {
    var vm: LaneViewModel
    var column: Int

    var body: some View {
            Menu {
                ForEach(vm.viewManager.widgetDefinitions) { definition in
                    Button {
                    vm.viewManager.addWidget(definition, at: column)
                } label: {
                    Label(definition.title, systemImage: definition.icon)
                }
            }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.54))
                Text("Add")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.42))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct EmptyWidgetState: View {
    var vm: LaneViewModel
    var isEditing: Bool

    var body: some View {
        let content = VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.04))
                .frame(width: 54, height: 54)
                .overlay {
                    Image(systemName: isEditing ? "plus.square.on.square" : "square.grid.3x3.middle.filled")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }

            Text(isEditing ? "Add your first widget" : "This view is empty")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))

            Text(isEditing ? "Click anywhere to add your first widget." : "Tap Edit to start adding widgets here.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.42))
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        if isEditing {
            Menu {
                ForEach(vm.viewManager.widgetDefinitions) { definition in
                    Button {
                        vm.viewManager.addWidget(definition, at: 0)
                    } label: {
                        Label(definition.title, systemImage: definition.icon)
                    }
                }
            } label: {
                content
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
        } else {
            content
                .overlay(alignment: .topTrailing) {
                    EmptyViewEditHint()
                        .offset(x: -74, y: -14)
                        .allowsHitTesting(false)
                }
        }
    }
}

private struct EmptyViewEditHint: View {
    var body: some View {
        Image("TwistedArrow")
            .resizable()
            .interpolation(.high)
            .opacity(0.85)
            .frame(width: 200, height: 190)
    }
}

private struct WidgetCard: View {
    var widget: WidgetInstance
    var vm: LaneViewModel
    var accentTint: Color
    var isEditing: Bool
    var isHeld: Bool
    var minSpan: Int
    var maxSpan: Int
    var canSetSpan: (Int) -> Bool
    var onSetSpan: (Int) -> Void
    var onRemove: () -> Void
    var onHandleDragChanged: (CGFloat) -> Void
    var onHandleDragEnded: (CGFloat) -> Void

    var body: some View {
        let definition = vm.viewManager.definition(for: widget) ?? .missing(id: widget.widgetID)
        let tint = definition.tint
        let cardShape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.18))
                    .frame(width: 28, height: 28)
                    .overlay {
                        Image(systemName: definition.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(tint)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(definition.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(definition.caption)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)
            }

            widgetPreview(for: definition, tint: tint)
        }
        .blur(radius: isEditing ? 1.4 : 0)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            cardShape
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(isHeld ? 0.16 : 0.1),
                            tint.opacity(0.14)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .clipShape(cardShape)
        .overlay(
            cardShape
                .strokeBorder(.white.opacity(isEditing ? 0.26 : 0.08), lineWidth: isEditing ? 1.6 : 1)
        )
        .overlay {
            if isEditing {
                cardShape
                    .fill(accentTint.opacity(0.18))
                    .contentShape(cardShape)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                onHandleDragChanged(value.translation.width)
                            }
                            .onEnded { value in
                                onHandleDragEnded(value.translation.width)
                            }
                    )
            }
        }
        .overlay(alignment: .center) {
            if isEditing {
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.96))
                    .padding(10)
                    .background(.black.opacity(0.42), in: Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(.white.opacity(0.22), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.28), radius: 8, y: 4)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topLeading) {
            if isEditing {
                HStack(spacing: 6) {
                    editControlButton(
                        systemName: "minus",
                        tint: .white,
                        isEnabled: canShrink,
                        action: shrink
                    )

                    editControlButton(
                        systemName: "plus",
                        tint: .white,
                        isEnabled: canGrow,
                        action: grow
                    )

                }
                .padding(6)
                .background(.black.opacity(0.42), in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(.white.opacity(0.22), lineWidth: 1)
                )
                .padding(10)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isEditing {
                editControlButton(
                    systemName: "trash",
                    tint: Color(red: 0.98, green: 0.39, blue: 0.43),
                    isEnabled: true,
                    action: onRemove
                )
                .padding(6)
                .background(.black.opacity(0.42), in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(.white.opacity(0.22), lineWidth: 1)
                )
                .padding(10)
            }
        }
    }

    private var smallerSpan: Int? {
        let candidate = widget.span - 1
        guard candidate >= minSpan else { return nil }
        return candidate
    }

    private var largerSpan: Int? {
        let candidate = widget.span + 1
        guard candidate <= maxSpan else { return nil }
        return candidate
    }

    private var canShrink: Bool {
        guard let smallerSpan else { return false }
        return canSetSpan(smallerSpan)
    }

    private var canGrow: Bool {
        guard let largerSpan else { return false }
        return canSetSpan(largerSpan)
    }

    private func shrink() {
        guard let smallerSpan, canSetSpan(smallerSpan) else { return }
        onSetSpan(smallerSpan)
    }

    private func grow() {
        guard let largerSpan, canSetSpan(largerSpan) else { return }
        onSetSpan(largerSpan)
    }

    private func editControlButton(
        systemName: String,
        tint: Color,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint.opacity(isEnabled ? 0.96 : 0.58))
                .frame(width: 26, height: 26)
                .background(.black.opacity(isEnabled ? 0.42 : 0.34), in: Circle())
                .overlay(
                    Circle()
                        .strokeBorder(.white.opacity(isEnabled ? 0.22 : 0.16), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    @ViewBuilder
    private func widgetPreview(for definition: WidgetDefinition, tint: Color) -> some View {
        RuntimeWidgetSurface(widget: widget, definition: definition, vm: vm, tint: tint)
    }
}

private struct RuntimeWidgetSurface: View {
    var widget: WidgetInstance
    var definition: WidgetDefinition
    var vm: LaneViewModel
    var tint: Color
    @State private var preferenceRevision = 0

    private var missingRequiredPreferences: [String] {
        vm.widgetRuntime.missingRequiredPreferenceNames(for: definition, instanceID: widget.id)
    }

    private var resolvedTheme: WidgetResolvedTheme {
        definition.resolvedTheme
    }

    var body: some View {
        Group {
            if !missingRequiredPreferences.isEmpty {
                configurationRequiredSurface
            } else if let error = vm.widgetRuntime.error(for: widget.id) {
                runtimeErrorSurface(message: error)
            } else if let tree = vm.widgetRuntime.renderTree(for: widget.id) {
                RuntimeV2NodeView(
                    node: tree,
                    vm: vm,
                    instanceID: widget.id,
                    theme: resolvedTheme,
                    assetRootURL: definition.assetRootURL,
                    path: []
                )
            } else {
                runtimeLoadingSurface
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: "\(widget.id.uuidString)-\(widget.span)-\(vm.isEditingLayout)-\(vm.viewManager.selectedViewID.uuidString)-\(preferenceRevision)") {
            if !missingRequiredPreferences.isEmpty {
                if vm.widgetRuntime.isMounted(instanceID: widget.id) {
                    vm.widgetRuntime.unmount(instanceID: widget.id)
                }
            } else if vm.widgetRuntime.isMounted(instanceID: widget.id) {
                vm.widgetRuntime.update(
                    instanceID: widget.id,
                    viewID: vm.viewManager.selectedViewID,
                    span: widget.span,
                    isEditing: vm.isEditingLayout
                )
            } else {
                vm.widgetRuntime.mount(
                    widget: definition,
                    instanceID: widget.id,
                    viewID: vm.viewManager.selectedViewID,
                    span: widget.span,
                    isEditing: vm.isEditingLayout
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .widgetPreferencesDidChange)) { notification in
            guard let payload = notification.object as? WidgetPreferencesDidChangePayload,
                  payload.instanceID == widget.id else { return }
            preferenceRevision += 1
        }
    }

    private var runtimeLoadingSurface: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.08))
                .frame(height: 42)

            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(tint.opacity(0.7))
                .frame(width: 80, height: 10)

            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(.white.opacity(0.08))
                .frame(width: 118, height: 8)
        }
    }

    private func runtimeErrorSurface(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.98, green: 0.39, blue: 0.43).opacity(0.14))
                .frame(height: 40)
                .overlay(alignment: .leading) {
                    Label(runtimeErrorTitle, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(red: 0.98, green: 0.58, blue: 0.63))
                        .padding(.horizontal, 12)
                }

            Text(runtimeErrorMessage(detail: message))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var configurationRequiredSurface: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 1.0, green: 0.78, blue: 0.3).opacity(0.14))
                .frame(height: 40)
                .overlay(alignment: .leading) {
                    Label("Configuration Required", systemImage: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(red: 1.0, green: 0.86, blue: 0.55))
                        .padding(.horizontal, 12)
                }

            Text(configurationRequiredMessage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                if !vm.isViewPinned {
                    vm.collapse()
                }
                AppSettingsWindow.open(tab: .widgets, widgetInstanceID: widget.id)
            } label: {
                Text("Open Widget Settings")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.14))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var configurationRequiredMessage: String {
        let missing = missingRequiredPreferences.joined(separator: ", ")
        return "Complete the required preferences for this widget before it can render. Missing: \(missing)"
    }

    private var runtimeErrorTitle: String {
        #if DEBUG
        "Runtime Error"
        #else
        "Widget Unavailable"
        #endif
    }

    private func runtimeErrorMessage(detail: String) -> String {
        #if DEBUG
        detail
        #else
        "This widget is currently unavailable. It may have been removed, disabled, or failed to load."
        #endif
    }
}

private enum RuntimeV2LayoutMode {
    case normal
    case intrinsicMeasurement
}

private struct RuntimeV2LayoutModeKey: EnvironmentKey {
    static let defaultValue: RuntimeV2LayoutMode = .normal
}

private extension EnvironmentValues {
    var runtimeV2LayoutMode: RuntimeV2LayoutMode {
        get { self[RuntimeV2LayoutModeKey.self] }
        set { self[RuntimeV2LayoutModeKey.self] = newValue }
    }
}

private struct RuntimeV2MarqueeNodeView<Content: View>: NSViewRepresentable {
    var active: Bool
    var delay: Double
    var speed: Double
    var gap: CGFloat
    var fadeEdges: Bool
    @ViewBuilder var content: () -> Content
    
    func makeNSView(context: Context) -> RuntimeV2MarqueeNSView {
        let view = RuntimeV2MarqueeNSView()
        view.configure(
            active: active,
            delay: delay,
            speed: speed,
            gap: gap,
            fadeEdges: fadeEdges,
            displayContent: AnyView(content()),
            intrinsicContent: AnyView(
                content()
                    .environment(\.runtimeV2LayoutMode, .intrinsicMeasurement)
                    .fixedSize(horizontal: true, vertical: false)
            )
        )
        return view
    }

    func updateNSView(_ nsView: RuntimeV2MarqueeNSView, context: Context) {
        nsView.configure(
            active: active,
            delay: delay,
            speed: speed,
            gap: gap,
            fadeEdges: fadeEdges,
            displayContent: AnyView(content()),
            intrinsicContent: AnyView(
                content()
                    .environment(\.runtimeV2LayoutMode, .intrinsicMeasurement)
                    .fixedSize(horizontal: true, vertical: false)
            )
        )
    }
}

private struct RuntimeV2MarqueeAnimationState: Equatable {
    var isActive: Bool
    var containerWidth: CGFloat
    var contentWidth: CGFloat
    var delay: Double
    var speed: Double
    var gap: CGFloat
    var fadeEdges: Bool
}

private final class RuntimeV2MarqueeNSView: NSView {
    private let displayHosting = NSHostingView(rootView: AnyView(EmptyView()))
    private let trackView = NSView()
    private let firstHosting = NSHostingView(rootView: AnyView(EmptyView()))
    private let secondHosting = NSHostingView(rootView: AnyView(EmptyView()))
    private let measureHosting = NSHostingView(rootView: AnyView(EmptyView()))
    private let fadeMaskLayer = CAGradientLayer()

    private var isActive = true
    private var animationDelay: Double = 1.2
    private var animationSpeed: Double = 30
    private var itemGap: CGFloat = 28
    private var edgeFadeEnabled = true
    private var measuredContentSize: CGSize = .zero
    private var startWorkItem: DispatchWorkItem?
    private var lastAnimationState: RuntimeV2MarqueeAnimationState?
    private var isAnimationScheduled = false

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true

        fadeMaskLayer.startPoint = CGPoint(x: 0, y: 0.5)
        fadeMaskLayer.endPoint = CGPoint(x: 1, y: 0.5)
        fadeMaskLayer.colors = [
            NSColor.clear.cgColor,
            NSColor.black.cgColor,
            NSColor.black.cgColor,
            NSColor.clear.cgColor
        ]
        fadeMaskLayer.locations = [0, 0.08, 0.92, 1]

        trackView.wantsLayer = true
        trackView.layer?.masksToBounds = false

        addSubview(displayHosting)
        addSubview(trackView)
        trackView.addSubview(firstHosting)
        trackView.addSubview(secondHosting)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        startWorkItem?.cancel()
    }

    override func layout() {
        super.layout()
        updateMeasuredContentSize()
        layoutSubviews()
        updateMask()
        updateAnimationIfNeeded()
    }

    func configure(
        active: Bool,
        delay: Double,
        speed: Double,
        gap: CGFloat,
        fadeEdges: Bool,
        displayContent: AnyView,
        intrinsicContent: AnyView
    ) {
        self.isActive = active
        self.animationDelay = delay
        self.animationSpeed = speed
        self.itemGap = gap
        self.edgeFadeEnabled = fadeEdges

        displayHosting.rootView = displayContent
        firstHosting.rootView = intrinsicContent
        secondHosting.rootView = intrinsicContent
        measureHosting.rootView = intrinsicContent

        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    private func updateMeasuredContentSize() {
        measureHosting.layoutSubtreeIfNeeded()
        let nextSize = measureHosting.fittingSize
        guard nextSize.width > 0 || nextSize.height > 0 else { return }
        measuredContentSize = CGSize(
            width: max(0, CGFloat(Int(nextSize.width.rounded(.towardZero)))),
            height: max(0, CGFloat(Int(nextSize.height.rounded(.towardZero))))
        )
    }

    private func layoutSubviews() {
        displayHosting.frame = bounds
        trackView.frame = bounds

        let contentHeight = min(measuredContentSize.height, bounds.height)
        let yOffset = max(0, (bounds.height - contentHeight) / 2)
        let contentFrame = CGRect(
            x: 0,
            y: yOffset,
            width: measuredContentSize.width,
            height: contentHeight
        )

        firstHosting.frame = contentFrame
        secondHosting.frame = contentFrame.offsetBy(dx: measuredContentSize.width + itemGap, dy: 0)

        let shouldAnimate = currentShouldAnimate
        displayHosting.isHidden = shouldAnimate
        trackView.isHidden = !shouldAnimate
    }

    private var currentContainerWidth: CGFloat {
        max(0, CGFloat(Int(bounds.width.rounded(.towardZero))))
    }

    private var currentShouldAnimate: Bool {
        isActive && currentContainerWidth > 0 && measuredContentSize.width > currentContainerWidth + 4
    }

    private var travelDistance: CGFloat {
        measuredContentSize.width + itemGap
    }

    private var animationDuration: Double {
        max(Double(travelDistance) / max(animationSpeed, 1), 2.4)
    }

    private var animationState: RuntimeV2MarqueeAnimationState {
        RuntimeV2MarqueeAnimationState(
            isActive: isActive,
            containerWidth: currentContainerWidth,
            contentWidth: measuredContentSize.width,
            delay: animationDelay,
            speed: animationSpeed,
            gap: itemGap,
            fadeEdges: edgeFadeEnabled
        )
    }

    private func updateAnimationIfNeeded() {
        let nextState = animationState
        guard nextState != lastAnimationState else { return }
        lastAnimationState = nextState

        stopAnimation()
        guard currentShouldAnimate else { return }
        scheduleAnimationStart()
    }

    private func scheduleAnimationStart() {
        startWorkItem?.cancel()
        isAnimationScheduled = true

        let workItem = DispatchWorkItem { [weak self] in
            self?.startAnimation()
        }
        startWorkItem = workItem

        let delay = max(animationDelay, 0)
        if delay <= 0 {
            DispatchQueue.main.async(execute: workItem)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    private func startAnimation() {
        guard currentShouldAnimate else { return }

        startWorkItem = nil
        isAnimationScheduled = false
        trackView.layer?.removeAnimation(forKey: "marqueeScroll")
        trackView.layer?.setAffineTransform(.identity)

        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = 0
        animation.toValue = -travelDistance
        animation.duration = animationDuration
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.isRemovedOnCompletion = true
        trackView.layer?.add(animation, forKey: "marqueeScroll")
    }

    private func stopAnimation() {
        startWorkItem?.cancel()
        startWorkItem = nil
        isAnimationScheduled = false
        trackView.layer?.removeAnimation(forKey: "marqueeScroll")
        trackView.layer?.setAffineTransform(.identity)
    }

    private func updateMask() {
        guard let layer else { return }
        if edgeFadeEnabled && currentShouldAnimate {
            fadeMaskLayer.frame = bounds
            layer.mask = fadeMaskLayer
        } else {
            layer.mask = nil
        }
    }
}

private struct RuntimeV2NodeView: View {
    var node: RenderNodeV2
    var vm: LaneViewModel
    var instanceID: UUID
    var theme: WidgetResolvedTheme
    var assetRootURL: URL
    var path: [Int]
    @Environment(\.runtimeV2LayoutMode) private var layoutMode

    var body: some View {
        styled(baseView)
    }

    private var baseView: AnyView {
        switch node.type {
        case "Stack":
            return AnyView(
                VStack(
                    alignment: RuntimeV2StyleResolver.horizontalAlignment(node.string("alignment")),
                    spacing: CGFloat(node.number("spacing") ?? 8)
                ) {
                    childViews
                }
            )
        case "Inline":
            return AnyView(
                HStack(
                    alignment: RuntimeV2StyleResolver.verticalAlignment(node.string("alignment")),
                    spacing: CGFloat(node.number("spacing") ?? 8)
                ) {
                    childViews
                }
            )
        case "ScrollView":
            return scrollView
        case "Divider":
            return AnyView(
                Rectangle()
                    .fill(RuntimeV2StyleResolver.color(hex: node.string("color")) ?? Color.white.opacity(0.08))
                    .frame(height: 1)
            )
        case "Marquee":
            return AnyView(
                RuntimeV2MarqueeNodeView(
                    active: node.bool("active") ?? true,
                    delay: node.number("delay") ?? 1.2,
                    speed: node.number("speed") ?? 30,
                    gap: CGFloat(node.number("gap") ?? 28),
                    fadeEdges: node.bool("fadeEdges") ?? true
                ) {
                    marqueeContent
                }
            )
        case "Text", "__text":
            let text = Text(node.string("text") ?? "")
                .font(textFont)
                .foregroundStyle(textColor)
                .multilineTextAlignment(RuntimeV2StyleResolver.textAlignment(node.string("alignment")))
                .lineLimit(node.decoded("lineLimit", as: Int.self) ?? node.decoded("lineClamp", as: Int.self))
                .minimumScaleFactor(CGFloat(node.number("minimumScaleFactor") ?? 1))
                .truncationMode(.tail)
                .strikethrough(node.bool("strikethrough") ?? false, color: .white.opacity(0.28))

            if layoutMode == .intrinsicMeasurement {
                return AnyView(text.fixedSize(horizontal: true, vertical: false))
            }

            if node.value("frame") != nil {
                return AnyView(text)
            }

            return AnyView(
                text.frame(maxWidth: .infinity, alignment: RuntimeV2StyleResolver.textFrameAlignment(node.string("alignment")))
            )
        case "Icon":
            return AnyView(
                Image(systemName: node.string("symbol") ?? "questionmark")
                    .font(
                        .system(
                            size: CGFloat(node.number("size") ?? 12),
                            weight: RuntimeV2StyleResolver.fontWeight(node.string("weight"), default: .semibold)
                        )
                    )
                    .foregroundStyle(iconColor)
            )
        case "Image":
            return AnyView(
                RuntimeV2ImageNodeView(
                    node: node,
                    instanceID: instanceID,
                    assetRootURL: assetRootURL
                )
            )
        case "Camera":
            return AnyView(
                RuntimeV2CameraNodeView(node: node)
            )
        case "Menu":
            return AnyView(
                RuntimeV2MenuNodeView(
                    node: node,
                    vm: vm,
                    instanceID: instanceID,
                    theme: theme,
                    assetRootURL: assetRootURL,
                    path: path
                )
            )
        case "Button":
            let variant = node.string("variant") ?? "primary"
            let buttonWidth = node.number("width").map { CGFloat($0) }
            let metrics = buttonMetrics
            let cornerRadius = CGFloat(
                node.number("cornerRadius")
                    ?? ((node.string("shape") ?? "default") == "pill" ? (metrics.height / 2) : 10)
            )
            return AnyView(
                Button {
                    guard let callbackID = node.string("onPress") else { return }
                    vm.widgetRuntime.triggerCallback(callbackID: callbackID, for: instanceID)
                } label: {
                    Text(node.string("title") ?? "Action")
                        .font(
                            .system(
                                size: metrics.fontSize,
                                weight: RuntimeV2StyleResolver.fontWeight(node.string("weight"), default: .semibold)
                            )
                        )
                        .foregroundStyle(buttonForegroundColor(variant: variant))
                        .frame(maxWidth: buttonWidth == nil ? .infinity : nil)
                        .frame(width: buttonWidth, height: metrics.height)
                        .background(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(buttonBackgroundColor(variant: variant))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(buttonBorderColor(variant: variant), lineWidth: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(node.string("onPress") == nil)
            )
        case "Row":
            let variant = node.string("variant") ?? "secondary"
            return AnyView(
                Button {
                    guard let callbackID = node.string("onPress") else { return }
                    vm.widgetRuntime.triggerCallback(callbackID: callbackID, for: instanceID)
                } label: {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(rowBackgroundColor(variant: variant))
                        .frame(maxWidth: .infinity)
                        .frame(height: CGFloat(theme.controls.rowHeight))
                        .overlay {
                            if node.children.count == 1 {
                                RuntimeV2NodeView(
                                    node: node.children[0],
                                    vm: vm,
                                    instanceID: instanceID,
                                    theme: theme,
                                    assetRootURL: assetRootURL,
                                    path: path + [0]
                                )
                                    .padding(.horizontal, 10)
                            } else {
                                HStack(spacing: 8) {
                                    childViews
                                }
                                .padding(.horizontal, 10)
                            }
                        }
                }
                .buttonStyle(.plain)
                .disabled(node.string("onPress") == nil)
            )
        case "IconButton":
            let variant = node.string("variant") ?? "ghost"
            let buttonWidth = CGFloat(node.number("width") ?? iconButtonMetrics.frameSize)
            let buttonHeight = CGFloat(node.number("height") ?? iconButtonMetrics.frameSize)
            let iconSize = CGFloat(node.number("iconSize") ?? iconButtonMetrics.fontSize)
            let cornerRadius = CGFloat(
                node.number("cornerRadius")
                    ?? ((node.string("shape") ?? "default") == "pill"
                        ? min(buttonWidth, buttonHeight) / 2
                        : min(buttonWidth, buttonHeight) / 2)
            )
            return AnyView(
                Button {
                    guard let callbackID = node.string("onPress"), !(node.bool("disabled") ?? false) else { return }
                    vm.widgetRuntime.triggerCallback(callbackID: callbackID, for: instanceID)
                } label: {
                    ZStack {
                        if variant != "ghost" {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(iconButtonBackgroundColor(variant: variant))
                                .overlay {
                                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                        .strokeBorder(iconButtonBorderColor(variant: variant), lineWidth: 1)
                                }
                        }

                        Image(systemName: node.string("symbol") ?? "questionmark")
                            .font(
                                .system(
                                    size: iconSize,
                                    weight: RuntimeV2StyleResolver.fontWeight(node.string("weight"), default: .semibold)
                                )
                            )
                            .foregroundStyle(iconColor(variant: variant))
                    }
                    .frame(width: buttonWidth, height: buttonHeight)
                    .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(node.bool("disabled") ?? false)
            )
        case "Checkbox":
            return AnyView(
                Button {
                    guard let callbackID = node.string("onPress"), !(node.bool("disabled") ?? false) else { return }
                    vm.widgetRuntime.triggerCallback(callbackID: callbackID, for: instanceID)
                } label: {
                    Circle()
                        .fill((node.bool("checked") ?? false) ? color(theme.colors.primary) : Color.clear)
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    (node.bool("checked") ?? false) ? color(theme.colors.ring) : color(theme.colors.border),
                                    lineWidth: 1.2
                                )
                        }
                        .frame(width: CGFloat(theme.controls.checkboxSize), height: CGFloat(theme.controls.checkboxSize))
                        .overlay {
                            if node.bool("checked") ?? false {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(color(theme.colors.primaryForeground))
                            }
                        }
                }
                .buttonStyle(.plain)
                .disabled(node.bool("disabled") ?? false)
            )
        case "Input":
            return AnyView(
                RuntimeV2InputNodeView(
                    node: node,
                    vm: vm,
                    instanceID: instanceID,
                    theme: theme,
                    assetRootURL: assetRootURL,
                    path: path
                )
            )
        case "Circle":
            return circleView
        case "RoundedRect":
            return roundedRectView
        case "ProgressBar":
            return progressBarView
        case "Slider":
            return AnyView(
                RuntimeV2SliderNodeView(
                    node: node,
                    vm: vm,
                    instanceID: instanceID,
                    theme: theme
                )
            )
        case "Spacer":
            return AnyView(Spacer(minLength: CGFloat(node.number("minLength") ?? 0)))
        default:
            return AnyView(EmptyView())
        }
    }

    @ViewBuilder
    private var childViews: some View {
        ForEach(indexedChildren) { child in
            RuntimeV2NodeView(
                node: child.node,
                vm: vm,
                instanceID: instanceID,
                theme: theme,
                assetRootURL: assetRootURL,
                path: path + [child.index]
            )
        }
    }

    @ViewBuilder
    private var marqueeContent: some View {
        if indexedChildren.count == 1, let child = indexedChildren.first {
            RuntimeV2NodeView(
                node: child.node,
                vm: vm,
                instanceID: instanceID,
                theme: theme,
                assetRootURL: assetRootURL,
                path: path + [child.index]
            )
        } else {
            HStack(
                alignment: RuntimeV2StyleResolver.verticalAlignment(node.string("alignment")),
                spacing: CGFloat(node.number("spacing") ?? 0)
            ) {
                childViews
            }
        }
    }

    private var indexedChildren: [RuntimeV2IndexedChild] {
        node.children.enumerated().map { index, child in
            RuntimeV2IndexedChild(
                id: child.id ?? child.key ?? "v2-index-\(index)",
                index: index,
                node: child
            )
        }
    }

    private var scrollView: AnyView {
        let isHorizontal = node.string("direction") == "horizontal"
        let spacing = CGFloat(node.number("spacing") ?? 8)
        let showsIndicators = node.bool("showsIndicators") ?? false
        let fadeEdges = node.string("fadeEdges") ?? "bottom"

        if isHorizontal {
            return AnyView(
                ScrollView(.horizontal, showsIndicators: showsIndicators) {
                    HStack(
                        alignment: RuntimeV2StyleResolver.verticalAlignment(node.string("alignment")),
                        spacing: spacing
                    ) {
                        childViews
                    }
                }
            )
        }

        let view = AnyView(
            ScrollView(.vertical, showsIndicators: showsIndicators) {
                VStack(
                    alignment: RuntimeV2StyleResolver.horizontalAlignment(node.string("alignment")),
                    spacing: spacing
                ) {
                    childViews
                }
            }
        )

        guard fadeEdges != "none" else {
            return view
        }

        return AnyView(view.mask(scrollFadeMask(for: fadeEdges)))
    }

    private var circleView: AnyView {
        let size = CGFloat(node.number("size") ?? 24)
        let width = CGFloat(node.number("width") ?? node.number("size") ?? 24)
        let height = CGFloat(node.number("height") ?? node.number("size") ?? 24)
        let fillColor = RuntimeV2StyleResolver.color(hex: node.string("fill")) ?? Color.clear
        let strokeColor = RuntimeV2StyleResolver.color(hex: node.string("strokeColor"))
        let strokeWidth = CGFloat(node.number("strokeWidth") ?? 0)

        var view = AnyView(
            Circle()
                .fill(fillColor)
                .frame(
                    width: node.number("size") != nil ? size : width,
                    height: node.number("size") != nil ? size : height
                )
        )

        if let strokeColor, strokeWidth > 0 {
            view = AnyView(
                view.overlay {
                    Circle()
                        .strokeBorder(strokeColor, lineWidth: strokeWidth)
                }
            )
        }

        if !node.children.isEmpty {
            view = AnyView(
                view.overlay {
                    ZStack {
                        childViews
                    }
                }
            )
        }

        return view
    }

    private var roundedRectView: AnyView {
        let width = node.number("width").map { CGFloat($0) }
        let height = node.number("height").map { CGFloat($0) }
        let cornerRadius = CGFloat(node.number("cornerRadius") ?? 12)
        let fillColor = RuntimeV2StyleResolver.color(hex: node.string("fill")) ?? Color.clear
        let strokeColor = RuntimeV2StyleResolver.color(hex: node.string("strokeColor"))
        let strokeWidth = CGFloat(node.number("strokeWidth") ?? 0)

        var view = AnyView(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fillColor)
                .frame(width: width, height: height)
        )

        if let strokeColor, strokeWidth > 0 {
            view = AnyView(
                view.overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(strokeColor, lineWidth: strokeWidth)
                }
            )
        }

        if !node.children.isEmpty {
            view = AnyView(
                view.overlay {
                    ZStack {
                        childViews
                    }
                }
            )
        }

        return view
    }

    private var progressBarView: AnyView {
        let rawValue = CGFloat(node.number("value") ?? 0)
        let value = max(0, min(1, rawValue))
        let height = CGFloat(node.number("height") ?? 8)
        let cornerRadius = CGFloat(node.number("cornerRadius") ?? (height / 2))
        let tintColor = RuntimeV2StyleResolver.color(hex: node.string("tint")) ?? color(theme.colors.primary)
        let trackColor = RuntimeV2StyleResolver.color(hex: node.string("track")) ?? color(theme.colors.secondary)

        return AnyView(
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(trackColor)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(tintColor)
                        .frame(width: max(height, proxy.size.width * value))
                }
            }
            .frame(height: height)
        )
    }

    private func styled(_ content: AnyView) -> AnyView {
        var view = content

        if let padding = RuntimeV2StyleResolver.padding(from: node.value("padding")) {
            view = AnyView(view.padding(padding.edgeInsets))
        }

        if let frame = RuntimeV2StyleResolver.frame(from: node.value("frame")) {
            view = applyFrame(frame, to: view)
        }

        if node.type == "Image" {
            view = AnyView(view.clipped())
        }

        if let backgroundColor = RuntimeV2StyleResolver.color(hex: node.string("background")) {
            view = AnyView(view.background(backgroundColor))
        }

        if let clipShape = RuntimeV2StyleResolver.clipShape(from: node.value("clipShape")) {
            view = clipped(view, using: clipShape)
        }

        if let opacity = node.number("opacity") {
            view = AnyView(view.opacity(opacity))
        }

        if let pointerEvents = node.string("pointerEvents") {
            view = AnyView(view.allowsHitTesting(pointerEvents != "none"))
        } else if let allowsHitTesting = node.bool("allowsHitTesting") {
            view = AnyView(view.allowsHitTesting(allowsHitTesting))
        }

        if let overlays = node.decoded("overlay", as: [RuntimeV2OverlayPayload].self), !overlays.isEmpty {
            for overlay in overlays {
                let overlayContent = RuntimeV2NodeView(
                    node: overlay.node,
                    vm: vm,
                    instanceID: instanceID,
                    theme: theme,
                    assetRootURL: assetRootURL,
                    path: path
                )
                let inset = CGFloat(overlay.inset ?? 0)
                let offsetX = CGFloat(overlay.offset?.x ?? 0)
                let offsetY = CGFloat(overlay.offset?.y ?? 0)
                view = AnyView(
                    view.overlay(alignment: RuntimeV2StyleResolver.alignment(overlay.alignment)) {
                        overlayContent
                            .padding(inset)
                            .offset(x: offsetX, y: offsetY)
                    }
                )
            }
        }

        if !isControlNode, let callbackID = node.string("onPress") {
            view = pressable(view, callbackID: callbackID)
        }

        return view
    }

    private func applyFrame(_ frame: RuntimeV2FramePayload, to content: AnyView) -> AnyView {
        let alignment = RuntimeV2StyleResolver.alignment(frame.alignment)
        let width = frame.width.map { CGFloat($0) }
        let height = frame.height.map { CGFloat($0) }
        let maxWidth = frame.maxWidth?.cgFloatValue
        let maxHeight = frame.maxHeight?.cgFloatValue

        let fixed = AnyView(
            content.frame(
                width: width,
                height: height,
                alignment: alignment
            )
        )

        return AnyView(
            fixed.frame(
                maxWidth: maxWidth,
                maxHeight: maxHeight,
                alignment: alignment
            )
        )
    }

    private func pressable(_ content: AnyView, callbackID: String) -> AnyView {
        if let clipShape = RuntimeV2StyleResolver.clipShape(from: node.value("clipShape")) {
            switch clipShape.type {
            case "circle":
                return AnyView(
                    content
                        .contentShape(Circle())
                        .onTapGesture {
                            vm.widgetRuntime.triggerCallback(callbackID: callbackID, for: instanceID)
                        }
                )
            case "roundedRect":
                return AnyView(
                    content
                        .contentShape(
                            RoundedRectangle(
                                cornerRadius: CGFloat(clipShape.cornerRadius ?? 12),
                                style: .continuous
                            )
                        )
                        .onTapGesture {
                            vm.widgetRuntime.triggerCallback(callbackID: callbackID, for: instanceID)
                        }
                )
            default:
                break
            }
        }

        if node.type == "Circle" {
            return AnyView(
                content
                    .contentShape(Circle())
                    .onTapGesture {
                        vm.widgetRuntime.triggerCallback(callbackID: callbackID, for: instanceID)
                    }
            )
        }

        if node.type == "RoundedRect" {
            return AnyView(
                content
                    .contentShape(
                        RoundedRectangle(
                            cornerRadius: CGFloat(node.number("cornerRadius") ?? 12),
                            style: .continuous
                        )
                    )
                    .onTapGesture {
                        vm.widgetRuntime.triggerCallback(callbackID: callbackID, for: instanceID)
                    }
            )
        }

        return AnyView(
            content
                .contentShape(Rectangle())
                .onTapGesture {
                    vm.widgetRuntime.triggerCallback(callbackID: callbackID, for: instanceID)
                }
        )
    }

    private func clipped(_ content: AnyView, using clipShape: RuntimeV2ClipShapePayload) -> AnyView {
        switch clipShape.type {
        case "circle":
            return AnyView(content.clipShape(Circle()))
        case "roundedRect":
            return AnyView(
                content.clipShape(
                    RoundedRectangle(
                        cornerRadius: CGFloat(clipShape.cornerRadius ?? 12),
                        style: .continuous
                    )
                )
            )
        default:
            return content
        }
    }

    private var textColor: Color {
        if let explicit = RuntimeV2StyleResolver.color(hex: node.string("color")) {
            return explicit
        }

        if node.string("tone") == "accent" {
            return color(theme.colors.primary)
        }
        if node.string("tone") == "destructive" {
            return color(theme.colors.destructive)
        }
        if node.string("tone") == "warning" {
            return color(theme.colors.warning)
        }
        if node.string("tone") == "success" {
            return color(theme.colors.success)
        }
        if node.string("tone") == "onAccent" {
            return color(theme.colors.primaryForeground)
        }
        let textVariant = node.string("variant") ?? node.string("role")

        if textVariant == "placeholder" {
            return color(theme.colors.mutedForeground).opacity(0.84)
        }

        switch node.string("tone") {
        case "primary":
            return color(theme.colors.foreground)
        case "tertiary":
            return color(theme.colors.mutedForeground).opacity(0.76)
        case "secondary":
            return color(theme.colors.mutedForeground)
        default:
            return color(theme.colors.mutedForeground)
        }
    }

    private var iconColor: Color {
        if let explicit = RuntimeV2StyleResolver.color(hex: node.string("color")) {
            return explicit
        }

        switch node.string("tone") {
        case "accent":
            return color(theme.colors.primary)
        case "destructive":
            return color(theme.colors.destructive)
        case "warning":
            return color(theme.colors.warning)
        case "success":
            return color(theme.colors.success)
        case "onAccent":
            return color(theme.colors.primaryForeground)
        default:
            break
        }

        switch node.string("tone") {
        case "primary":
            return color(theme.colors.foreground)
        case "tertiary":
            return color(theme.colors.mutedForeground).opacity(0.76)
        default:
            return color(theme.colors.mutedForeground)
        }
    }

    private var iconButtonMetrics: (fontSize: CGFloat, frameSize: CGFloat) {
        switch node.string("size") {
        case "sm":
            return (10, 20)
        case "md":
            return (11, 28)
        case "lg":
            return (12, 32)
        case "xl":
            return (14, 36)
        case "large":
            return (12, CGFloat(theme.controls.iconButtonLargeSize))
        default:
            return (10, CGFloat(theme.controls.iconButtonSize))
        }
    }

    private var buttonMetrics: (fontSize: CGFloat, height: CGFloat) {
        let defaultFontSize = CGFloat(theme.typography.buttonLabel.size)
        let defaultHeight = CGFloat(theme.controls.buttonHeight)

        let sizedDefaults: (fontSize: CGFloat, height: CGFloat)
        switch node.string("size") {
        case "sm":
            sizedDefaults = (10, 24)
        case "lg":
            sizedDefaults = (12, 34)
        case "xl":
            sizedDefaults = (13, 38)
        default:
            sizedDefaults = (defaultFontSize, defaultHeight)
        }

        return (
            CGFloat(node.number("fontSize") ?? Double(sizedDefaults.fontSize)),
            CGFloat(node.number("height") ?? Double(sizedDefaults.height))
        )
    }

    private enum ThemeTextRole {
        case title
        case subtitle
        case body
        case caption
        case label
        case placeholder
        case buttonLabel
    }

    private func themedFont(for role: ThemeTextRole) -> Font {
        let style: WidgetThemeTypographyStyle
        switch role {
        case .title:
            style = theme.typography.title
        case .subtitle:
            style = theme.typography.subtitle
        case .body:
            style = theme.typography.body
        case .caption:
            style = theme.typography.caption
        case .label:
            style = theme.typography.label
        case .placeholder:
            style = theme.typography.placeholder
        case .buttonLabel:
            style = theme.typography.buttonLabel
        }

        return .system(
            size: CGFloat(style.size),
            weight: RuntimeV2StyleResolver.fontWeight(style.weight, default: .medium)
        )
    }

    private var textFont: Font {
        if node.number("size") != nil || node.string("weight") != nil || node.string("design") != nil {
            return .system(
                size: CGFloat(node.number("size") ?? theme.typography.body.size),
                weight: RuntimeV2StyleResolver.fontWeight(node.string("weight"), default: .medium),
                design: RuntimeV2StyleResolver.fontDesign(node.string("design"))
            )
        }

        switch node.string("variant") ?? node.string("role") {
        case "title":
            return themedFont(for: .title)
        case "subtitle":
            return themedFont(for: .subtitle)
        case "caption":
            return themedFont(for: .caption)
        case "label":
            return themedFont(for: .label)
        case "placeholder":
            return themedFont(for: .placeholder)
        default:
            return themedFont(for: .body)
        }
    }

    private func color(_ hex: String) -> Color {
        RuntimeV2StyleResolver.color(hex: hex) ?? .white
    }

    private func buttonBackgroundColor(variant: String) -> Color {
        switch variant {
        case "secondary":
            return color(theme.colors.secondary)
        case "outline":
            return Color.clear
        case "ghost":
            return Color.clear
        case "destructive":
            return color(theme.colors.destructive)
        default:
            return color(theme.colors.primary)
        }
    }

    private func buttonBorderColor(variant: String) -> Color {
        switch variant {
        case "secondary":
            return color(theme.colors.border)
        case "outline":
            return color(theme.colors.border)
        case "ghost", "destructive":
            return Color.clear
        default:
            return Color.clear
        }
    }

    private func buttonForegroundColor(variant: String) -> Color {
        switch variant {
        case "primary":
            return color(theme.colors.primaryForeground)
        case "destructive":
            return color(theme.colors.destructiveForeground)
        case "secondary":
            return color(theme.colors.secondaryForeground)
        case "outline", "ghost":
            return color(theme.colors.foreground)
        default:
            return color(theme.colors.foreground)
        }
    }

    private func rowBackgroundColor(variant: String) -> Color {
        switch variant {
        case "accent":
            return color(theme.colors.accent)
        case "ghost":
            return Color.clear
        default:
            return color(theme.colors.secondary)
        }
    }

    private func iconColor(variant: String) -> Color {
        switch variant {
        case "primary":
            return color(theme.colors.primaryForeground)
        case "destructive":
            return color(theme.colors.destructiveForeground)
        case "secondary":
            return color(theme.colors.secondaryForeground)
        case "subtle":
            return color(theme.colors.accentForeground)
        default:
            return iconColor
        }
    }

    private func iconButtonBackgroundColor(variant: String) -> Color {
        switch variant {
        case "primary":
            return color(theme.colors.primary)
        case "secondary":
            return color(theme.colors.secondary)
        case "subtle":
            return color(theme.colors.accent)
        case "destructive":
            return color(theme.colors.destructive)
        default:
            return Color.clear
        }
    }

    private func iconButtonBorderColor(variant: String) -> Color {
        switch variant {
        case "secondary":
            return color(theme.colors.border)
        case "subtle":
            return color(theme.colors.ring)
        case "primary", "destructive":
            return Color.clear
        default:
            return Color.clear
        }
    }

    private var isControlNode: Bool {
        switch node.type {
        case "Button", "Row", "Checkbox", "IconButton", "Input":
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private func scrollFadeMask(for fadeEdges: String) -> some View {
        switch fadeEdges {
        case "top":
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.18),
                    .init(color: .black, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case "both":
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.18),
                    .init(color: .black, location: 0.82),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        default:
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.82),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

struct WidgetCameraDeviceOption: Codable, Equatable {
    var id: String
    var name: String
    var selected: Bool
}

@MainActor
final class WidgetCameraPermissionController: ObservableObject {
    static let shared = WidgetCameraPermissionController()

    enum State: Equatable {
        case idle
        case needsPermission
        case requesting
        case ready
        case denied
        case unavailable(String)
    }

    @Published private(set) var state: State = .idle
    private var suspendedPanelsPendingRestore: [SuspendedLanePanelState]?
    private var appDidBecomeActiveObserver: NSObjectProtocol?

    func ensureStarted() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            state = .ready
        case .notDetermined:
            if state == .idle {
                state = .needsPermission
            }
        case .denied, .restricted:
            state = .denied
        @unknown default:
            state = .unavailable("Camera unavailable.")
        }
    }

    func requestPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            state = .ready
        case .notDetermined:
            guard state != .requesting else { return }
            state = .requesting
            let suspendedPanels = suspendLanePanels()
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    defer { self.restoreLanePanels(suspendedPanels) }
                    if granted {
                        self.state = .ready
                    } else {
                        self.state = .denied
                    }
                }
            }
        case .denied, .restricted:
            state = .denied
            let suspendedPanels = suspendLanePanels()
            rememberPanelsForRestore(suspendedPanels)
            if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                NSWorkspace.shared.open(settingsURL)
            }
        @unknown default:
            state = .unavailable("Camera unavailable.")
        }
    }

    func setUnavailable(_ message: String) {
        state = .unavailable(message)
    }
}

@MainActor
final class WidgetCameraSessionController: ObservableObject {
    @Published private(set) var sessionErrorMessage: String?
    let session = AVCaptureSession()

    private let preferredDeviceID: String?
    private let sessionQueue = DispatchQueue(label: "com.skylaneapp.camera")
    private var didConfigureSession = false
    private var isStarting = false
    private var currentDeviceID: String?
    private var visiblePreviewIDs: Set<UUID> = []

    init(preferredDeviceID: String?) {
        self.preferredDeviceID = preferredDeviceID
    }

    func previewDidAppear(_ id: UUID) {
        visiblePreviewIDs.insert(id)
        ensureStarted()
    }

    func previewDidDisappear(_ id: UUID) {
        visiblePreviewIDs.remove(id)
        stopSessionIfUnused()
    }

    func ensureStarted() {
        guard !visiblePreviewIDs.isEmpty else { return }
        guard WidgetCameraPermissionController.shared.state == .ready else { return }
        guard !isStarting else { return }
        isStarting = true

        sessionQueue.async {
            defer {
                Task { @MainActor in
                    self.isStarting = false
                }
            }

            do {
                try self.configureSessionIfNeeded()
                try self.switchToPreferredDeviceIfNeeded()
                if !self.session.isRunning {
                    self.session.startRunning()
                }
                Task { @MainActor in
                    self.sessionErrorMessage = nil
                }
            } catch {
                Task { @MainActor in
                    self.sessionErrorMessage = error.localizedDescription
                }
            }
        }
    }

    func refreshPreferredDeviceIfNeeded() {
        guard !visiblePreviewIDs.isEmpty else { return }
        guard WidgetCameraPermissionController.shared.state == .ready else { return }

        sessionQueue.async {
            do {
                try self.configureSessionIfNeeded()
                try self.switchToPreferredDeviceIfNeeded()
                if !self.session.isRunning {
                    self.session.startRunning()
                }
                Task { @MainActor in
                    self.sessionErrorMessage = nil
                }
            } catch {
                Task { @MainActor in
                    self.sessionErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func stopSessionIfUnused() {
        guard visiblePreviewIDs.isEmpty else { return }
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    private func configureSessionIfNeeded() throws {
        guard !didConfigureSession else { return }

        session.beginConfiguration()
        defer {
            session.commitConfiguration()
        }

        session.sessionPreset = .high

        let devices = WidgetCameraRegistry.discoverDevices()
        let device =
            devices.first(where: { $0.uniqueID == preferredDeviceID })
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video)

        guard let device else {
            throw NSError(
                domain: "SkylaneCamera",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No camera is available on this Mac."]
            )
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw NSError(
                domain: "SkylaneCamera",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Unable to access the camera input."]
            )
        }

        session.addInput(input)
        currentDeviceID = device.uniqueID
        didConfigureSession = true
    }

    private func switchToPreferredDeviceIfNeeded() throws {
        guard let preferredDeviceID, currentDeviceID != preferredDeviceID else { return }

        let devices = WidgetCameraRegistry.discoverDevices()
        guard let device = devices.first(where: { $0.uniqueID == preferredDeviceID }) else {
            return
        }

        let input = try AVCaptureDeviceInput(device: device)

        session.beginConfiguration()
        defer {
            session.commitConfiguration()
        }

        for existingInput in session.inputs {
            session.removeInput(existingInput)
        }

        guard session.canAddInput(input) else {
            throw NSError(
                domain: "SkylaneCamera",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Unable to switch to the selected camera."]
            )
        }

        session.addInput(input)
        currentDeviceID = device.uniqueID
    }
}

@MainActor
final class WidgetCameraRegistry {
    static let shared = WidgetCameraRegistry()

    private var controllers: [String: WidgetCameraSessionController] = [:]
    private let defaultKey = "__default__"

    func controller(for preferredDeviceID: String?) -> WidgetCameraSessionController {
        let devices = Self.discoverDevices()
        let key = Self.effectiveSelectedDeviceID(
            preferredDeviceID: preferredDeviceID,
            from: devices
        ) ?? defaultKey
        if let existing = controllers[key] {
            return existing
        }

        let controller = WidgetCameraSessionController(preferredDeviceID: key == defaultKey ? nil : key)
        controllers[key] = controller
        return controller
    }

    func availableDevices(selectedDeviceID: String?) -> [WidgetCameraDeviceOption] {
        let devices = Self.discoverDevices()
        let effectiveSelectedDeviceID = Self.effectiveSelectedDeviceID(
            preferredDeviceID: selectedDeviceID,
            from: devices
        )

        if selectedDeviceID?.isEmpty == false {
            controller(for: selectedDeviceID).refreshPreferredDeviceIfNeeded()
        }

        if devices.isEmpty, let fallback = AVCaptureDevice.default(for: .video) {
            return [
                WidgetCameraDeviceOption(
                    id: fallback.uniqueID,
                    name: fallback.localizedName,
                    selected: effectiveSelectedDeviceID == fallback.uniqueID
                )
            ]
        }

        return devices.map { device in
            WidgetCameraDeviceOption(
                id: device.uniqueID,
                name: device.localizedName,
                selected: effectiveSelectedDeviceID == device.uniqueID
            )
        }
    }

    static func discoverDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    static func effectiveSelectedDeviceID(
        preferredDeviceID: String?,
        from devices: [AVCaptureDevice]
    ) -> String? {
        if let preferredDeviceID,
           devices.contains(where: { $0.uniqueID == preferredDeviceID }) {
            return preferredDeviceID
        }

        if let defaultFrontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
            return defaultFrontCamera.uniqueID
        }

        if let firstDevice = devices.first {
            return firstDevice.uniqueID
        }

        return AVCaptureDevice.default(for: .video)?.uniqueID
    }
}

private struct RuntimeV2MenuNodeView: View {
    var node: RenderNodeV2
    var vm: LaneViewModel
    var instanceID: UUID
    var theme: WidgetResolvedTheme
    var assetRootURL: URL
    var path: [Int]

    var body: some View {
        Menu {
            ForEach(Array(node.children.enumerated()), id: \.offset) { child in
                RuntimeV2MenuItemView(
                    node: child.element,
                    vm: vm,
                    instanceID: instanceID
                )
            }
        } label: {
            if let label = node.decoded("label", as: RenderNodeV2.self) {
                RuntimeV2NodeView(
                    node: label,
                    vm: vm,
                    instanceID: instanceID,
                    theme: theme,
                    assetRootURL: assetRootURL,
                    path: path + [-1]
                )
            } else {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}

private struct RuntimeV2MenuItemView: View {
    var node: RenderNodeV2
    var vm: LaneViewModel
    var instanceID: UUID

    var body: some View {
        switch node.type {
        case "Divider":
            Divider()
        case "Button":
            if node.value("checked") != nil {
                Toggle(isOn: checkedBinding) {
                    Text(node.string("title") ?? "Action")
                }
                .disabled(node.bool("disabled") ?? false)
            } else {
                Button(node.string("title") ?? "Action") {
                    guard let callbackID = node.string("onPress") else { return }
                    vm.widgetRuntime.triggerCallback(callbackID: callbackID, for: instanceID)
                }
                .disabled((node.bool("disabled") ?? false) || node.string("onPress") == nil)
            }
        default:
            if let title = node.string("title"), !title.isEmpty {
                Text(title)
            } else if let text = node.string("text"), !text.isEmpty {
                Text(text)
            } else {
                EmptyView()
            }
        }
    }

    private var checkedBinding: Binding<Bool> {
        Binding(
            get: {
                node.bool("checked") ?? false
            },
            set: { _ in
                guard let callbackID = node.string("onPress"), !(node.bool("disabled") ?? false) else { return }
                vm.widgetRuntime.triggerCallback(callbackID: callbackID, for: instanceID)
            }
        )
    }
}

private struct RuntimeV2CameraNodeView: View {
    var node: RenderNodeV2
    @StateObject private var permissionController = WidgetCameraPermissionController.shared
    @State private var previewID = UUID()
    @State private var sessionRevision = 0

    private var isMirrored: Bool {
        node.bool("mirrored") ?? false
    }

    private var preferredDeviceID: String? {
        node.string("deviceId")
    }

    private var controller: WidgetCameraSessionController {
        WidgetCameraRegistry.shared.controller(for: preferredDeviceID)
    }

    var body: some View {
        Group {
            switch permissionController.state {
            case .ready:
                if controller.sessionErrorMessage != nil {
                    fallback(symbol: "camera.metering.unknown", title: "Camera Unavailable")
                } else {
                    RuntimeV2CameraSessionView(session: controller.session, mirrored: isMirrored)
                }
            case .needsPermission:
                permissionPrompt
            case .denied:
                permissionPrompt(title: "Camera Access Needed", buttonLabel: "Open Settings")
            case .unavailable:
                fallback(symbol: "camera.metering.unknown", title: "Camera Unavailable")
            case .requesting:
                fallback(symbol: "camera.fill", title: "Requesting Camera Access")
            case .idle:
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            permissionController.ensureStarted()
            controller.previewDidAppear(previewID)
        }
        .onDisappear {
            controller.previewDidDisappear(previewID)
        }
        .onChange(of: permissionController.state) { _, newState in
            if newState == .ready {
                controller.ensureStarted()
            }
        }
        .onChange(of: preferredDeviceID) { oldValue, newValue in
            guard oldValue != newValue else { return }
            WidgetCameraRegistry.shared.controller(for: oldValue).previewDidDisappear(previewID)
            let nextController = WidgetCameraRegistry.shared.controller(for: newValue)
            nextController.previewDidAppear(previewID)
        }
        .onReceive(controller.objectWillChange) { _ in
            sessionRevision &+= 1
        }
    }

    private var permissionPrompt: some View {
        permissionPrompt(title: "Camera Access", buttonLabel: "Enable")
    }

    private func permissionPrompt(title: String, buttonLabel: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "camera.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))

            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))

            Button {
                permissionController.requestPermission()
            } label: {
                Text(buttonLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .frame(minWidth: 96)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.14))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fallback(symbol: String, title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))

            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
}

private struct SuspendedLanePanelState {
    weak var panel: LanePanel?
    let alphaValue: CGFloat
    let wasVisible: Bool
}

@MainActor
private extension WidgetCameraPermissionController {
    func suspendLanePanels() -> [SuspendedLanePanelState] {
        let suspended = LanePanel.allPanels.map { panel in
            SuspendedLanePanelState(panel: panel, alphaValue: panel.alphaValue, wasVisible: panel.isVisible)
        }

        for panel in LanePanel.allPanels {
            panel.orderOut(nil)
        }

        NSApp.activate(ignoringOtherApps: true)
        return suspended
    }

    func restoreLanePanels(_ suspended: [SuspendedLanePanelState]) {
        for snapshot in suspended {
            guard let panel = snapshot.panel else { continue }
            panel.alphaValue = snapshot.alphaValue
            if snapshot.wasVisible {
                panel.orderFrontRegardless()
            }
        }
    }

    func rememberPanelsForRestore(_ suspended: [SuspendedLanePanelState]) {
        suspendedPanelsPendingRestore = suspended

        if let appDidBecomeActiveObserver {
            NotificationCenter.default.removeObserver(appDidBecomeActiveObserver)
        }

        appDidBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            guard let self, let suspended = self.suspendedPanelsPendingRestore else { return }
            self.restoreLanePanels(suspended)
            self.suspendedPanelsPendingRestore = nil
            if let observer = self.appDidBecomeActiveObserver {
                NotificationCenter.default.removeObserver(observer)
                self.appDidBecomeActiveObserver = nil
            }
        }
    }
}

private struct RuntimeV2CameraSessionView: NSViewRepresentable {
    var session: AVCaptureSession
    var mirrored: Bool

    func makeNSView(context: Context) -> RuntimeV2CameraNSView {
        let view = RuntimeV2CameraNSView()
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.setSession(session)
        view.setMirrored(mirrored)
        return view
    }

    func updateNSView(_ nsView: RuntimeV2CameraNSView, context: Context) {
        if nsView.previewLayer.session !== session {
            nsView.setSession(session)
        }
        nsView.setMirrored(mirrored)
    }
}

private final class RuntimeV2CameraNSView: NSView {
    private var desiredMirrored: Bool = false
    private var sessionObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let sessionObserver {
            NotificationCenter.default.removeObserver(sessionObserver)
        }
    }

    override func makeBackingLayer() -> CALayer {
        AVCaptureVideoPreviewLayer()
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    func setSession(_ session: AVCaptureSession) {
        if let sessionObserver {
            NotificationCenter.default.removeObserver(sessionObserver)
            self.sessionObserver = nil
        }

        previewLayer.session = session

        sessionObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionDidStartRunning,
            object: session,
            queue: .main
        ) { [weak self] _ in
            self?.applyMirrored()
        }
    }

    func setMirrored(_ mirrored: Bool) {
        desiredMirrored = mirrored
        applyMirrored()
    }

    private func applyMirrored() {
        guard let connection = previewLayer.connection else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        if connection.isVideoMirroringSupported {
            connection.isVideoMirrored = desiredMirrored
        }
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
        previewLayer.videoGravity = .resizeAspectFill
        applyMirrored()
    }
}

private struct RuntimeV2IndexedChild: Identifiable {
    var id: String
    var index: Int
    var node: RenderNodeV2
}

private struct RuntimeV2ImageSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

@MainActor
private final class RuntimeV2ImageLoader: ObservableObject {
    @Published private(set) var image: NSImage?

    func load(
        instanceID: UUID,
        sourceURL: URL?,
        targetSize: CGSize?,
        contentMode: String?,
        scale: CGFloat
    ) async {
        guard let sourceURL,
              let targetSize,
              targetSize.width > 0,
              targetSize.height > 0 else {
            image = nil
            return
        }

        if let cached = WidgetImagePipeline.cachedImage(
            for: instanceID,
            at: sourceURL,
            targetSize: targetSize,
            scale: scale,
            contentMode: contentMode
        ) {
            image = cached
            return
        }

        image = nil

        let nextImage = await WidgetImagePipeline.image(
            for: instanceID,
            at: sourceURL,
            targetSize: targetSize,
            scale: scale,
            contentMode: contentMode
        )

        guard !Task.isCancelled else { return }
        image = nextImage
    }
}

private struct RuntimeV2ImageNodeView: View {
    var node: RenderNodeV2
    var instanceID: UUID
    var assetRootURL: URL

    @Environment(\.displayScale) private var displayScale
    @StateObject private var loader = RuntimeV2ImageLoader()
    @State private var measuredSize: CGSize = .zero

    private var screenScale: CGFloat {
        max(displayScale, 1)
    }

    private var resolvedAssetURL: URL? {
        guard let resolved = WidgetAssetResolver.assetURL(for: node.string("src"), under: assetRootURL),
              FileManager.default.fileExists(atPath: resolved.path) else {
            return nil
        }

        return resolved
    }

    private var resolvedHostAssetURL: URL? {
        guard let source = node.string("src")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !source.isEmpty,
              let url = URL(string: source),
              WidgetImagePipeline.isHostAssetURL(url) else {
            return nil
        }

        return url
    }

    private var resolvedRemoteURL: URL? {
        guard let source = node.string("src")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !source.isEmpty,
              let url = URL(string: source),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        return url
    }

    private var resolvedSourceURL: URL? {
        resolvedHostAssetURL ?? resolvedRemoteURL ?? resolvedAssetURL
    }

    private var explicitFrameSize: CGSize? {
        guard let frame = RuntimeV2StyleResolver.frame(from: node.value("frame")) else {
            return nil
        }

        let width = max(0, CGFloat(frame.width ?? 0))
        let height = max(0, CGFloat(frame.height ?? 0))
        guard width > 0 || height > 0 else {
            return nil
        }

        return CGSize(width: width, height: height)
    }

    private var intrinsicImageSize: CGSize? {
        guard let resolvedSourceURL else { return nil }
        return WidgetImagePipeline.intrinsicSize(at: resolvedSourceURL)
    }

    private var resolvedLayoutSize: CGSize? {
        RuntimeV2ImageLayoutResolver.layoutSize(
            explicitFrameSize: explicitFrameSize,
            measuredSize: measuredSize,
            intrinsicSize: intrinsicImageSize
        )
    }

    private var targetSize: CGSize? {
        RuntimeV2ImageLayoutResolver.requestSize(
            explicitFrameSize: explicitFrameSize,
            measuredSize: measuredSize,
            intrinsicSize: intrinsicImageSize
        )
    }

    private var idealWidth: CGFloat? {
        let explicitWidth = explicitFrameSize?.width ?? 0
        guard explicitWidth <= 0 else { return nil }
        return resolvedLayoutSize?.width
    }

    private var idealHeight: CGFloat? {
        let explicitHeight = explicitFrameSize?.height ?? 0
        guard explicitHeight <= 0 else { return nil }
        return resolvedLayoutSize?.height
    }

    private var aspectRatio: CGFloat? {
        if let intrinsicImageSize,
           intrinsicImageSize.width > 0,
           intrinsicImageSize.height > 0 {
            return intrinsicImageSize.width / intrinsicImageSize.height
        }

        if let imageSize = loader.image?.size,
           imageSize.width > 0,
           imageSize.height > 0 {
            return imageSize.width / imageSize.height
        }

        return nil
    }

    private var loadKey: String {
        let width = Int((targetSize?.width ?? 0).rounded(.up))
        let height = Int((targetSize?.height ?? 0).rounded(.up))
        let scale = Int((screenScale * 100).rounded())
        let sourceIdentifier = resolvedSourceURL?.absoluteString ?? "missing"
        return "\(instanceID.uuidString)#\(sourceIdentifier)#\(width)x\(height)#\(scale)#\(node.string("contentMode") ?? "fill")"
    }

    var body: some View {
        Group {
            if let image = loader.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(
                        aspectRatio,
                        contentMode: RuntimeV2StyleResolver.imageContentMode(node.string("contentMode"))
                    )
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.06))
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.32))
                    }
                    .aspectRatio(
                        aspectRatio,
                        contentMode: RuntimeV2StyleResolver.imageContentMode(node.string("contentMode"))
                    )
            }
        }
        .frame(idealWidth: idealWidth, idealHeight: idealHeight)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: RuntimeV2ImageSizePreferenceKey.self,
                    value: proxy.size
                )
            }
        )
        .onPreferenceChange(RuntimeV2ImageSizePreferenceKey.self) { size in
            let width = max(0, CGFloat(Int(size.width.rounded(.up))))
            let height = max(0, CGFloat(Int(size.height.rounded(.up))))
            measuredSize = CGSize(width: width, height: height)
        }
        .task(id: loadKey) {
            await loader.load(
                instanceID: instanceID,
                sourceURL: resolvedSourceURL,
                targetSize: targetSize,
                contentMode: node.string("contentMode"),
                scale: screenScale
            )
        }
    }
}

private struct RuntimeV2InputNodeView: View {
    var node: RenderNodeV2
    var vm: LaneViewModel
    var instanceID: UUID
    var theme: WidgetResolvedTheme
    var assetRootURL: URL
    var path: [Int]

    @State private var text = ""

    private var inputFont: NSFont {
        .systemFont(
            ofSize: CGFloat(theme.typography.body.size),
            weight: RuntimeV2StyleResolver.nsFontWeight(theme.typography.body.weight, default: .medium)
        )
    }

    private var inputTextColor: NSColor {
        NSColor(RuntimeV2StyleResolver.color(hex: theme.colors.foreground) ?? .white)
    }

    private var inputInsertionPointColor: NSColor {
        NSColor(RuntimeV2StyleResolver.color(hex: theme.colors.foreground) ?? .white)
    }

    var body: some View {
        HStack(spacing: 4) {
            if let leadingAccessory = node.decoded("leadingAccessory", as: RenderNodeV2.self) {
                RuntimeV2NodeView(
                    node: leadingAccessory,
                    vm: vm,
                    instanceID: instanceID,
                    theme: theme,
                    assetRootURL: assetRootURL,
                    path: path
                )
            }

            RuntimeInputTextField(
                text: $text,
                placeholder: node.string("placeholder") ?? "",
                font: inputFont,
                textColor: inputTextColor,
                insertionPointColor: inputInsertionPointColor,
                onCommit: {
                    guard let callbackID = node.string("onSubmit") else { return }
                    vm.widgetRuntime.triggerCallback(
                        callbackID: callbackID,
                        for: instanceID,
                        payload: .object([
                            "value": .string(text)
                        ])
                    )
                }
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            if let trailingAccessory = node.decoded("trailingAccessory", as: RenderNodeV2.self) {
                Circle()
                    .fill(RuntimeV2StyleResolver.color(hex: theme.colors.muted) ?? .white.opacity(0.08))
                    .frame(width: 24, height: 24)
                    .overlay {
                        RuntimeV2NodeView(
                            node: trailingAccessory,
                            vm: vm,
                            instanceID: instanceID,
                            theme: theme,
                            assetRootURL: assetRootURL,
                            path: path
                        )
                    }
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: CGFloat(theme.controls.inputHeight))
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(RuntimeV2StyleResolver.color(hex: theme.colors.card) ?? .white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(RuntimeV2StyleResolver.color(hex: theme.colors.input) ?? .white.opacity(0.12), lineWidth: 1)
        )
        .onAppear {
            text = node.string("value") ?? ""
        }
        .onChange(of: node.string("value") ?? "") { _, newValue in
            if newValue != text {
                text = newValue
            }
        }
        .onChange(of: text) { oldValue, newValue in
            guard oldValue != newValue,
                  newValue != (node.string("value") ?? ""),
                  let callbackID = node.string("onChange") else { return }

            vm.widgetRuntime.triggerCallback(
                callbackID: callbackID,
                for: instanceID,
                payload: .object([
                    "value": .string(newValue)
                ])
            )
        }
    }
}

private struct RuntimeV2SliderNodeView: View {
    var node: RenderNodeV2
    var vm: LaneViewModel
    var instanceID: UUID
    var theme: WidgetResolvedTheme

    @State private var value: Double = 0

    private var minValue: Double {
        node.number("min") ?? 0
    }

    private var maxValue: Double {
        let candidate = node.number("max") ?? 1
        return candidate > minValue ? candidate : minValue + 1
    }

    private var stepValue: Double? {
        guard let step = node.number("step"), step > 0 else { return nil }
        return step
    }

    private var tintColor: Color {
        RuntimeV2StyleResolver.color(hex: node.string("tint"))
            ?? RuntimeV2StyleResolver.color(hex: theme.colors.primary)
            ?? .white
    }

    private var isDisabled: Bool {
        node.bool("disabled") ?? false
    }

    private func clampedValue(_ rawValue: Double) -> Double {
        min(max(rawValue, minValue), maxValue)
    }

    var body: some View {
        Group {
            if let stepValue {
                Slider(value: binding, in: minValue...maxValue, step: stepValue)
            } else {
                Slider(value: binding, in: minValue...maxValue)
            }
        }
        .tint(tintColor)
        .disabled(isDisabled)
        .frame(height: 20)
        .onAppear {
            value = clampedValue(node.number("value") ?? minValue)
        }
        .onChange(of: node.number("value") ?? minValue) { _, newValue in
            let nextValue = clampedValue(newValue)
            if nextValue != value {
                value = nextValue
            }
        }
    }

    private var binding: Binding<Double> {
        Binding(
            get: { value },
            set: { newValue in
                let nextValue = clampedValue(newValue)
                value = nextValue

                guard let callbackID = node.string("onChange") else { return }
                vm.widgetRuntime.triggerCallback(
                    callbackID: callbackID,
                    for: instanceID,
                    payload: .object([
                        "value": .number(nextValue)
                    ])
                )
            }
        )
    }
}

private struct RuntimeNodeView: View {
    var node: RuntimeRenderNode
    var vm: LaneViewModel
    var instanceID: UUID
    var tint: Color

    var body: some View {
        switch node.type {
        case "Stack":
            stackView
        case "Inline":
            inlineView
        case "Row":
            rowView
        case "Text":
            textView
        case "Button":
            buttonView
        case "Icon":
            iconView
        case "IconButton":
            iconButtonView
        case "Checkbox":
            checkboxView
        case "Input":
            RuntimeInputNodeView(node: node, vm: vm, instanceID: instanceID, tint: tint)
        case "Spacer":
            Spacer(minLength: 0)
        default:
            EmptyView()
        }
    }

    private var textView: some View {
        Text(node.text ?? "")
            .font(textFont(role: node.role))
            .foregroundStyle(textColor(tone: node.tone, role: node.role))
            .multilineTextAlignment(.leading)
            .lineLimit(node.lineClamp)
            .strikethrough(node.strikethrough ?? false, color: .white.opacity(0.28))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var buttonView: some View {
        Button {
            if let action = node.action {
                vm.widgetRuntime.triggerAction(action, payload: node.payload, for: instanceID)
            }
        } label: {
            Text(node.title ?? "Action")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tint.opacity(0.24))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(tint.opacity(0.32), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var iconView: some View {
        Image(systemName: node.symbol ?? "questionmark")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(iconColor(tone: node.tone))
    }

    private var iconButtonView: some View {
        Button {
            guard let action = node.action, !(node.disabled ?? false) else { return }
            vm.widgetRuntime.triggerAction(action, payload: node.payload, for: instanceID)
        } label: {
            Image(systemName: node.symbol ?? "questionmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(iconColor(tone: node.tone))
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
        .disabled(node.disabled ?? false)
    }

    private var checkboxView: some View {
        Button {
            guard let action = node.action else { return }
            vm.widgetRuntime.triggerAction(action, payload: node.payload, for: instanceID)
        } label: {
            Circle()
                .strokeBorder(.white.opacity((node.checked ?? false) ? 0.12 : 0.28), lineWidth: 1.2)
                .frame(width: 14, height: 14)
                .overlay {
                    if node.checked ?? false {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var stackView: some View {
        let spacing = node.spacing.map { CGFloat($0) } ?? 8
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(node.children) { child in
                RuntimeNodeView(node: child, vm: vm, instanceID: instanceID, tint: tint)
            }
        }
    }

    @ViewBuilder
    private var inlineView: some View {
        let spacing = node.spacing.map { CGFloat($0) } ?? 8
        HStack(spacing: spacing) {
            ForEach(node.children) { child in
                if child.type == "Spacer" {
                    Spacer(minLength: 0)
                } else {
                    RuntimeNodeView(node: child, vm: vm, instanceID: instanceID, tint: tint)
                }
            }
        }
    }

    private var rowView: some View {
        Button {
            guard let action = node.action else { return }
            vm.widgetRuntime.triggerAction(action, payload: node.payload, for: instanceID)
        } label: {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.05))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .overlay {
                    if node.children.count == 1 {
                        RuntimeNodeView(node: node.children[0], vm: vm, instanceID: instanceID, tint: tint)
                            .padding(.horizontal, 10)
                    } else {
                        HStack(spacing: 8) {
                            ForEach(node.children) { child in
                                RuntimeNodeView(node: child, vm: vm, instanceID: instanceID, tint: tint)
                            }
                        }
                        .padding(.horizontal, 10)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(node.action == nil)
    }

    private func textFont(role: String?) -> Font {
        switch role {
        case "caption":
            .system(size: 11, weight: .semibold)
        case "placeholder":
            .system(size: 11, weight: .medium)
        default:
            .system(size: 11, weight: .medium)
        }
    }

    private func textColor(tone: String?, role: String?) -> Color {
        if role == "placeholder" {
            return .white.opacity(0.48)
        }

        switch tone {
        case "primary":
            return Color.white.opacity(0.84)
        case "secondary":
            return Color.white.opacity(0.72)
        case "tertiary":
            return Color.white.opacity(0.42)
        default:
            return Color.white.opacity(0.72)
        }
    }

    private func iconColor(tone: String?) -> Color {
        switch tone {
        case "primary":
            return .white.opacity(0.84)
        case "tertiary":
            return .white.opacity(0.26)
        default:
            return .white.opacity(0.42)
        }
    }
}

private struct RuntimeInputNodeView: View {
    var node: RuntimeRenderNode
    var vm: LaneViewModel
    var instanceID: UUID
    var tint: Color

    @State private var text = ""

    var body: some View {
        HStack(spacing: 4) {
            if let leadingAccessory = node.leadingAccessory {
                RuntimeNodeView(node: leadingAccessory.node, vm: vm, instanceID: instanceID, tint: tint)
            }

            RuntimeInputTextField(
                text: $text,
                placeholder: node.placeholder ?? "",
                onCommit: {
                    guard let action = node.submitAction else { return }
                    vm.widgetRuntime.triggerAction(
                        action,
                        payload: RuntimeActionPayload(value: text, id: nil),
                        for: instanceID
                    )
                }
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            if let trailingAccessory = node.trailingAccessory {
                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 24, height: 24)
                    .overlay {
                        RuntimeNodeView(node: trailingAccessory.node, vm: vm, instanceID: instanceID, tint: tint)
                    }
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.07))
        )
        .onAppear {
            text = node.value ?? ""
        }
        .onChange(of: node.value ?? "") { _, newValue in
            if newValue != text {
                text = newValue
            }
        }
        .onChange(of: text) { oldValue, newValue in
            guard oldValue != newValue,
                  newValue != (node.value ?? ""),
                  let action = node.changeAction else { return }

            vm.widgetRuntime.triggerAction(
                action,
                payload: RuntimeActionPayload(value: newValue, id: nil),
                for: instanceID
            )
        }
    }
}

private struct RuntimeInputTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var font: NSFont = .systemFont(ofSize: 11, weight: .medium)
    var textColor: NSColor = .white.withAlphaComponent(0.72)
    var insertionPointColor: NSColor = .white
    var onCommit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommit: onCommit, insertionPointColor: insertionPointColor)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = RuntimeFocusableTextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.stringValue = text
        configureLaneTextField(
            textField,
            placeholder: placeholder,
            font: font,
            textColor: textColor
        )
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.onCommit = onCommit
        context.coordinator.insertionPointColor = insertionPointColor

        if textField.stringValue != text {
            textField.stringValue = text
        }

        if textField.font != font {
            textField.font = font
        }

        if textField.textColor != textColor {
            textField.textColor = textColor
        }
    }

    static func dismantleNSView(_ textField: NSTextField, coordinator: Coordinator) {
        if let panel = textField.window as? LanePanel {
            panel.releaseKeyInput()
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        var onCommit: () -> Void
        var insertionPointColor: NSColor

        init(text: Binding<String>, onCommit: @escaping () -> Void, insertionPointColor: NSColor) {
            _text = text
            self.onCommit = onCommit
            self.insertionPointColor = insertionPointColor
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            text = textField.stringValue
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField,
                  let window = textField.window else { return }

            if let panel = window as? LanePanel {
                panel.activateForKeyInput()
            }

            if let editor = window.fieldEditor(true, for: textField) as? NSTextView {
                editor.insertionPointColor = insertionPointColor
            }
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField,
                  let panel = textField.window as? LanePanel else { return }

            panel.releaseKeyInput()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                onCommit()
                return true
            }

            return false
        }
    }
}

private final class RuntimeFocusableTextField: NSTextField {
    override func mouseDown(with event: NSEvent) {
        if let panel = window as? LanePanel {
            panel.activateForKeyInput()
        }

        super.mouseDown(with: event)
    }
}

private struct HeaderAccessoryButton: View {
    var activeSymbol: String
    var inactiveSymbol: String?
    var activeLabel: String?
    var inactiveLabel: String?
    var tint: Color = .white
    var isActive = false
    var activeRotation: Angle = .zero
    var inactiveRotation: Angle = .zero
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let label = isActive ? activeLabel : inactiveLabel {
                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle((isActive ? tint : .white).opacity(isActive ? 0.95 : 0.72))
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isActive ? tint.opacity(0.18) : .white.opacity(0.06))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(
                                    isActive ? tint.opacity(0.4) : .white.opacity(0.06),
                                    lineWidth: 1
                                )
                        )
                } else {
                    Image(systemName: isActive ? activeSymbol : (inactiveSymbol ?? activeSymbol))
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(isActive ? activeRotation : inactiveRotation)
                        .foregroundStyle((isActive ? tint : .white).opacity(isActive ? 0.95 : 0.72))
                        .frame(width: 26, height: 26)
                        .background(
                            Circle()
                                .fill(isActive ? tint.opacity(0.18) : .white.opacity(0.06))
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    isActive ? tint.opacity(0.4) : .white.opacity(0.06),
                                    lineWidth: 1
                                )
                        )
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct RenameViewDialog: View {
    var vm: LaneViewModel
    @State private var escMonitor: Any?

    private var selectedIcon: String {
        vm.viewManager.selectedView?.icon ?? "pencil"
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.82)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: selectedIcon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: 24, height: 24)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                    RenameTextField(
                        text: Bindable(vm).renameViewName,
                        placeholder: "View name",
                        onCommit: commit,
                        onCancel: cancel,
                        onFrameChange: updateTextFieldFrame
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "return")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.34))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                )

                HStack(spacing: 6) {
                    KeycapLabel("esc")
                    Text("cancel")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))

                    Spacer(minLength: 0)

                    KeycapLabel("return")
                    Text("rename")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(width: 300)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.74))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.24), radius: 16, y: 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Enable keyboard on the panel
            if let panel = LanePanel.contentPanel {
                panel.activateForKeyInput()
                DispatchQueue.main.async {
                    panel.activateForKeyInput()
                }
            }
            escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 { // Escape
                    cancel()
                    return nil
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = escMonitor {
                NSEvent.removeMonitor(monitor)
                escMonitor = nil
            }
            vm.renameViewFieldScreenRect = .zero
            if let panel = LanePanel.contentPanel {
                panel.releaseKeyInput()
            }
        }
    }

    private func commit() {
        let trimmed = vm.renameViewName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, let view = vm.viewManager.selectedView {
            vm.viewManager.renameView(view, to: trimmed)
        }
        vm.isRenamingView = false
    }

    private func cancel() {
        vm.isRenamingView = false
    }

    private func updateTextFieldFrame(_ frame: CGRect) {
        vm.renameViewFieldScreenRect = frame
    }
}

struct EditModeConfirmationDialog: View {
    var vm: LaneViewModel
    @State private var escMonitor: Any?

    var body: some View {
        let saveTint = Preferences.accentColor.color

        ZStack {
            Color.black.opacity(0.82)
                .ignoresSafeArea()
                .onTapGesture {
                    cancel()
                }

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Save layout changes?")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))

                    Text("Your edits will be lost if you revert this session.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.52))
                }

                HStack(spacing: 8) {
                    Button(action: discard) {
                        Text("Discard")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(red: 0.98, green: 0.39, blue: 0.43))
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(red: 0.98, green: 0.39, blue: 0.43).opacity(0.12))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color(red: 0.98, green: 0.39, blue: 0.43).opacity(0.3), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Button(action: save) {
                        Text("Save")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(saveTint.opacity(0.2))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(saveTint.opacity(0.34), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 6) {
                    KeycapLabel("esc")
                    Text("keep editing")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))

                    Spacer(minLength: 0)

                    KeycapLabel("return")
                    Text("save")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(width: 320)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.74))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.24), radius: 16, y: 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if let panel = LanePanel.contentPanel {
                panel.activateForKeyInput()
                DispatchQueue.main.async {
                    panel.activateForKeyInput()
                }
            }
            escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 {
                    cancel()
                    return nil
                }
                if event.keyCode == 36 {
                    save()
                    return nil
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = escMonitor {
                NSEvent.removeMonitor(monitor)
                escMonitor = nil
            }
            if let panel = LanePanel.contentPanel {
                panel.releaseKeyInput()
            }
        }
    }

    private func save() {
        vm.saveEditMode()
    }

    private func discard() {
        vm.revertEditMode()
    }

    private func cancel() {
        vm.dismissEditConfirmation()
    }
}

private struct KeycapLabel: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white.opacity(0.6))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.white.opacity(0.06), lineWidth: 1)
            )
    }
}

private struct RenameTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onCommit: () -> Void
    var onCancel: () -> Void
    var onFrameChange: (CGRect) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommit: onCommit, onCancel: onCancel, onFrameChange: onFrameChange)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.stringValue = text
        configureLaneTextField(
            textField,
            placeholder: placeholder,
            font: .systemFont(ofSize: 12, weight: .medium),
            textColor: .white
        )
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.onCommit = onCommit
        context.coordinator.onCancel = onCancel
        context.coordinator.onFrameChange = onFrameChange

        if textField.stringValue != text {
            textField.stringValue = text
        }

        if let window = textField.window {
            let rectInWindow = textField.convert(textField.bounds, to: nil)
            let rectOnScreen = window.convertToScreen(rectInWindow)
            context.coordinator.onFrameChange(rectOnScreen)
        }

        context.coordinator.focusIfNeeded(textField)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        var onCommit: () -> Void
        var onCancel: () -> Void
        var onFrameChange: (CGRect) -> Void
        var hasFocused = false
        var focusAttempts = 0

        init(
            text: Binding<String>,
            onCommit: @escaping () -> Void,
            onCancel: @escaping () -> Void,
            onFrameChange: @escaping (CGRect) -> Void
        ) {
            _text = text
            self.onCommit = onCommit
            self.onCancel = onCancel
            self.onFrameChange = onFrameChange
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            text = textField.stringValue
        }

        func focusIfNeeded(_ textField: NSTextField) {
            guard !hasFocused, focusAttempts < 8 else { return }

            let attempt = focusAttempts
            focusAttempts += 1

            DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0 : 0.05)) {
                guard !self.hasFocused, let window = textField.window else { return }

                _ = window.makeFirstResponder(nil)
                guard window.makeFirstResponder(textField) else {
                    self.focusIfNeeded(textField)
                    return
                }

                guard let editor = window.fieldEditor(true, for: textField) as? NSTextView else {
                    self.focusIfNeeded(textField)
                    return
                }

                editor.insertionPointColor = .white
                editor.selectedRange = NSRange(location: 0, length: textField.stringValue.count)
                self.hasFocused = true
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                onCommit()
                return true
            }

            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                onCancel()
                return true
            }

            return false
        }
    }
}

private func configureLaneTextField(
    _ textField: NSTextField,
    placeholder: String,
    font: NSFont,
    textColor: NSColor
) {
    textField.placeholderString = placeholder
    textField.isBordered = false
    textField.isBezeled = false
    textField.drawsBackground = false
    textField.focusRingType = .none
    textField.isEditable = true
    textField.isSelectable = true
    textField.isEnabled = true
    textField.font = font
    textField.textColor = textColor
    textField.cell?.usesSingleLineMode = true
    textField.cell?.lineBreakMode = .byTruncatingTail
}

struct LaneBlurView: View {
    var vm: LaneViewModel

    var body: some View {
        EmptyView()
    }
}
