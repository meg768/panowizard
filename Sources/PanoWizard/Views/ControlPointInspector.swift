import AppKit
import CoreImage
import ImageIO
import SwiftUI

private extension Notification.Name {
    static let controlPointEditorDelete = Notification.Name(
        "PanoWizard.ControlPointEditor.Delete"
    )
    static let controlPointEditorCancel = Notification.Name(
        "PanoWizard.ControlPointEditor.Cancel"
    )
}

struct ControlPointCommandActions {
    let addPointTitle: String
    let optimizeTitle: String
    let canSuggest: Bool
    let canSuggestProject: Bool
    let canRegenerateProject: Bool
    let canRemoveSelectedPoint: Bool
    let canRemovePairPoints: Bool
    let canRemoveProjectPoints: Bool
    let canOptimize: Bool
    let toggleAddingPoint: () -> Void
    let suggestPairPoints: () -> Void
    let suggestProjectPoints: () -> Void
    let requestRegenerateProjectPoints: () -> Void
    let removeSelectedPoint: () -> Void
    let requestRemovePairPoints: () -> Void
    let requestRemoveProjectPoints: () -> Void
    let optimize: () -> Void
}

private struct ControlPointCommandActionsKey: FocusedValueKey {
    typealias Value = ControlPointCommandActions
}

extension FocusedValues {
    var controlPointCommandActions: ControlPointCommandActions? {
        get { self[ControlPointCommandActionsKey.self] }
        set { self[ControlPointCommandActionsKey.self] = newValue }
    }
}

enum ControlPointCoordinateSpace {
    static func orientedSize(
        rawWidth: Int,
        rawHeight: Int,
        displayedWidth: Int,
        displayedHeight: Int
    ) -> CGSize {
        let rawIsLandscape = rawWidth >= rawHeight
        let displayedIsLandscape = displayedWidth >= displayedHeight
        if rawIsLandscape == displayedIsLandscape {
            return CGSize(width: rawWidth, height: rawHeight)
        }
        return CGSize(width: rawHeight, height: rawWidth)
    }
}

private enum ControlPointMarkerPalette {
    static func color(_ index: Int) -> Color {
        let colors: [Color] = [
            .yellow, .blue, .pink, .gray, .green, .mint,
            .white, .red, .indigo, .brown, .purple, .orange,
            .gray, .cyan
        ]
        return colors[index % colors.count]
    }
}

struct ControlPointEditor: View {
    private enum BulkDeletionRequest {
        case pair
        case project
    }

    let diagnostics: ControlPointDiagnostics
    let selectedPairID: ControlPointPair.ID
    let leftImageIndex: Int
    let rightImageIndex: Int
    let onSelectImages: (Int, Int) -> Void
    let onMovePoint: (DiagnosticControlPoint.ID, Int, CGPoint) -> Void
    let onRemovePoint: (DiagnosticControlPoint.ID) -> Void
    let onAddPoint: (CGPoint, Int) -> DiagnosticControlPoint.ID
    let onPredictPoint: (CGPoint, Int) -> (point: CGPoint, imageIndex: Int)
    let isSuggestingPoints: Bool
    let onSuggestPoints: () -> Void
    let onSuggestProjectPoints: () -> Void
    let onRegenerateProjectPoints: () -> Void
    let onRemoveAllPoints: () -> Void
    let onRemoveAllProjectPoints: () -> Void
    let onOptimize: () -> Void
    let isPoleAlignment: Bool
    @State private var selectedPointID: DiagnosticControlPoint.ID?
    @State private var pointIDToReveal: DiagnosticControlPoint.ID?
    @State private var magnifiedPointID: DiagnosticControlPoint.ID?
    @State private var isAddingPoint = false
    @State private var isCommandPressed = false
    @State private var isShiftPressed = false
    @State private var commandPreviewPoints: [Int: CGPoint] = [:]
    @State private var modifierMonitor: Any?
    @State private var deleteKeyMonitor: Any?
    @State private var pendingSelectionAfterDelete:
        DiagnosticControlPoint.ID?
    @State private var isRegenerateDialogPresented = false
    @State private var bulkDeletionRequest: BulkDeletionRequest?
    @FocusState private var editorHasFocus: Bool

    private var selectedPair: ControlPointPair? {
        guard diagnostics.images.indices.contains(selectedPairID.firstImage),
              diagnostics.images.indices.contains(selectedPairID.secondImage)
        else {
            return nil
        }
        let points = diagnostics.cleanedPoints.filter {
            $0.pair == selectedPairID
        }
        return ControlPointPair(
            firstImage: selectedPairID.firstImage,
            secondImage: selectedPairID.secondImage,
            rawCount: points.count,
            cleanedCount: points.count
        )
    }

    private var displayedPoints: [DiagnosticControlPoint] {
        guard let pair = selectedPair else { return [] }
        return diagnostics.cleanedPoints.filter { $0.pair == pair.id }
    }

    var body: some View {
        if let pair = selectedPair,
           diagnostics.images.indices.contains(pair.firstImage),
           diagnostics.images.indices.contains(pair.secondImage) {
            VStack(spacing: 0) {
                Text(instruction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(.bar)

                HStack(spacing: 1) {
                    controlPointColumn(
                        imageIndex: leftImageIndex,
                        allowsAdding: true
                    )
                    controlPointColumn(
                        imageIndex: rightImageIndex,
                        allowsAdding: false
                    )
                    ControlPointErrorList(
                        points: displayedPoints,
                        selectedPointID: selectedPointID,
                        onSelectPoint: {
                            selectedPointID = $0
                            editorHasFocus = true
                        }
                    )
                    .frame(width: 108)
                }
            }
            .focusable()
            .focusEffectDisabled()
            .focused($editorHasFocus)
            .focusedSceneValue(
                \.controlPointCommandActions,
                commandActions
            )
            .confirmationDialog(
                "Ersätt alla kontrollpunkter?",
                isPresented: $isRegenerateDialogPresented,
                titleVisibility: .visible
            ) {
                Button(
                    "Radera manuella ändringar och generera om",
                    role: .destructive,
                    action: onRegenerateProjectPoints
                )
                Button("Avbryt", role: .cancel) {}
            } message: {
                Text(
                    "Alla befintliga och manuellt redigerade "
                        + "kontrollpunkter ersätts. Detta kan inte "
                        + "ångras efter att projektet har sparats."
                )
            }
            .confirmationDialog(
                bulkDeletionTitle,
                isPresented: Binding(
                    get: { bulkDeletionRequest != nil },
                    set: { presented in
                        if !presented {
                            bulkDeletionRequest = nil
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
                Button(bulkDeletionButtonTitle, role: .destructive) {
                    performBulkDeletion()
                }
                Button("Avbryt", role: .cancel) {
                    bulkDeletionRequest = nil
                }
            } message: {
                Text("Åtgärden kan inte ångras efter att projektet har sparats.")
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .controlPointEditorDelete
                )
            ) { _ in
                removeSelectedPoint()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .controlPointEditorCancel
                )
            ) { _ in
                isAddingPoint = false
                selectedPointID = nil
                magnifiedPointID = nil
                commandPreviewPoints = [:]
            }
            .onKeyPress(.tab) {
                selectAdjacentPoint(backwards: isShiftPressed)
                return .handled
            }
            .onAppear {
                editorHasFocus = true
                modifierMonitor = NSEvent.addLocalMonitorForEvents(
                    matching: .flagsChanged
                ) { event in
                    isCommandPressed = event.modifierFlags.contains(.command)
                    isShiftPressed = event.modifierFlags.contains(.shift)
                    if !isCommandPressed {
                        commandPreviewPoints = [:]
                    }
                    return event
                }
                deleteKeyMonitor = NSEvent.addLocalMonitorForEvents(
                    matching: .keyDown
                ) { event in
                    if event.keyCode == 53 {
                        NotificationCenter.default.post(
                            name: .controlPointEditorCancel,
                            object: nil
                        )
                        return nil
                    }
                    guard event.keyCode == 51 || event.keyCode == 117 else {
                        return event
                    }
                    NotificationCenter.default.post(
                        name: .controlPointEditorDelete,
                        object: nil
                    )
                    return nil
                }
            }
            .onDisappear {
                if let modifierMonitor {
                    NSEvent.removeMonitor(modifierMonitor)
                }
                if let deleteKeyMonitor {
                    NSEvent.removeMonitor(deleteKeyMonitor)
                }
                modifierMonitor = nil
                deleteKeyMonitor = nil
                commandPreviewPoints = [:]
            }
            .onChange(of: selectedPairID) {
                selectedPointID = nil
                pendingSelectionAfterDelete = nil
                magnifiedPointID = nil
                isAddingPoint = false
            }
            .onChange(of: displayedPoints.map(\.id)) {
                guard let pendingSelectionAfterDelete else { return }
                if displayedPoints.contains(where: {
                    $0.id == pendingSelectionAfterDelete
                }) {
                    selectedPointID = pendingSelectionAfterDelete
                } else {
                    selectedPointID = displayedPoints.first?.id
                }
                self.pendingSelectionAfterDelete = nil
                editorHasFocus = true
            }
        } else {
            ContentUnavailableView(
                "Inga kontrollpunkter",
                systemImage: "scope",
                description: Text("Det valda bildparet finns inte längre.")
            )
        }
    }

    private var commandActions: ControlPointCommandActions {
        ControlPointCommandActions(
            addPointTitle: isAddingPoint
                ? "Avbryt ny punkt" : "Lägg till punkt",
            optimizeTitle: isPoleAlignment ? "Anpassa" : "Optimera",
            canSuggest: !isSuggestingPoints,
            canSuggestProject: !isPoleAlignment && !isSuggestingPoints,
            canRegenerateProject: !isPoleAlignment && !isSuggestingPoints,
            canRemoveSelectedPoint: selectedPointID != nil,
            canRemovePairPoints: !displayedPoints.isEmpty,
            canRemoveProjectPoints:
                !isPoleAlignment && !diagnostics.cleanedPoints.isEmpty,
            canOptimize: displayedPoints.count >= 3,
            toggleAddingPoint: toggleAddingPoint,
            suggestPairPoints: onSuggestPoints,
            suggestProjectPoints: onSuggestProjectPoints,
            requestRegenerateProjectPoints: {
                isRegenerateDialogPresented = true
            },
            removeSelectedPoint: removeSelectedPoint,
            requestRemovePairPoints: {
                bulkDeletionRequest = .pair
            },
            requestRemoveProjectPoints: {
                bulkDeletionRequest = .project
            },
            optimize: onOptimize
        )
    }

    private func toggleAddingPoint() {
        isAddingPoint.toggle()
        selectedPointID = nil
    }

    private var bulkDeletionTitle: String {
        switch bulkDeletionRequest {
        case .pair:
            "Radera alla punkter i bildparet?"
        case .project:
            "Radera alla kontrollpunkter i projektet?"
        case nil:
            "Radera kontrollpunkter?"
        }
    }

    private var bulkDeletionButtonTitle: String {
        switch bulkDeletionRequest {
        case .pair:
            "Radera alla mellan bild \(leftImageIndex + 1) och "
                + "\(rightImageIndex + 1)"
        case .project:
            "Radera alla kontrollpunkter"
        case nil:
            "Radera"
        }
    }

    private func performBulkDeletion() {
        switch bulkDeletionRequest {
        case .pair:
            onRemoveAllPoints()
        case .project:
            onRemoveAllProjectPoints()
        case nil:
            break
        }
        bulkDeletionRequest = nil
    }

    private var instruction: String {
        if isCommandPressed {
            return "Klicka för att lägga till punkt och projicerad motpunkt"
        }
        if isAddingPoint {
            return "Klicka i vänster bild · motpunkten placeras automatiskt"
        }
        if magnifiedPointID != nil {
            return "Dra för mikrojustering · båda detaljerna är förstorade"
        }
        if selectedPointID != nil {
            return "Dra punkten i valfri bild för att finjustera"
        }
        return "\(displayedPoints.count) kontrollpunkter · klicka för att markera"
    }

    private func removeSelectedPoint() {
        guard let selectedPointID else { return }
        let selectedIndex = displayedPoints.firstIndex {
            $0.id == selectedPointID
        }
        let nextPointID = selectedIndex.flatMap { index in
            if index + 1 < displayedPoints.count {
                return displayedPoints[index + 1].id
            }
            if index > 0 {
                return displayedPoints[index - 1].id
            }
            return nil
        }
        pendingSelectionAfterDelete = nextPointID
        self.selectedPointID = nextPointID
        onRemovePoint(selectedPointID)
    }

    private func selectAdjacentPoint(backwards: Bool) {
        guard !displayedPoints.isEmpty else {
            selectedPointID = nil
            return
        }
        guard let selectedPointID,
              let index = displayedPoints.firstIndex(where: {
                  $0.id == selectedPointID
              }) else {
            self.selectedPointID = backwards
                ? displayedPoints.last?.id
                : displayedPoints.first?.id
            return
        }
        let offset = backwards ? -1 : 1
        let nextIndex = (
            index + offset + displayedPoints.count
        ) % displayedPoints.count
        self.selectedPointID = displayedPoints[nextIndex].id
    }

    @ViewBuilder
    private func controlPointColumn(
        imageIndex: Int,
        allowsAdding: Bool
    ) -> some View {
        ControlPointImage(
            image: diagnostics.images[imageIndex],
            imageIndex: imageIndex,
            points: displayedPoints,
            selectedPointID: selectedPointID,
            magnifiedPointID: magnifiedPointID,
            pointIDToReveal: pointIDToReveal,
            isAddingPoint: isAddingPoint,
            commandAddsPoint: isCommandPressed,
            commandPreviewPoint: commandPreviewPoints[imageIndex],
            allowsAdding: allowsAdding,
            onSelectPoint: {
                selectedPointID = $0
                editorHasFocus = true
            },
            onMagnifyPoint: { magnifiedPointID = $0 },
            onCommandPreview: { point in
                updateCommandPreview(
                    point,
                    from: imageIndex
                )
            },
            onMovePoint: onMovePoint,
            onAddPoint: { point in
                isAddingPoint = false
                let newPointID = onAddPoint(point, imageIndex)
                selectedPointID = newPointID
                pointIDToReveal = newPointID
                editorHasFocus = true
            }
        )
    }

    private func updateCommandPreview(
        _ point: CGPoint?,
        from imageIndex: Int
    ) {
        guard isCommandPressed, let point else {
            commandPreviewPoints = [:]
            return
        }
        commandPreviewPoints = [imageIndex: point]
    }
}

private struct ControlPointErrorList: View {
    let points: [DiagnosticControlPoint]
    let selectedPointID: DiagnosticControlPoint.ID?
    let onSelectPoint: (DiagnosticControlPoint.ID) -> Void

    private var pointsByDescendingError: [(offset: Int, element: DiagnosticControlPoint)] {
        points.enumerated().sorted { left, right in
            switch (left.element.error, right.element.error) {
            case let (leftError?, rightError?):
                if leftError != rightError {
                    return leftError > rightError
                }
                return left.offset < right.offset
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return left.offset < right.offset
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Num")
                Spacer()
                Text("Fel")
            }
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(.bar)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(pointsByDescendingError, id: \.element.id) {
                            index,
                            point in
                            Button {
                                onSelectPoint(point.id)
                            } label: {
                                HStack {
                                    Text("\(index + 1)")
                                        .font(.caption.bold())
                                        .foregroundStyle(.black)
                                        .frame(width: 25, height: 25)
                                        .background(
                                            markerColor(index),
                                            in: Circle()
                                        )
                                        .overlay {
                                            Circle().stroke(
                                                point.id == selectedPointID
                                                    ? Color.white
                                                    : Color.black,
                                                lineWidth:
                                                    point.id == selectedPointID
                                                        ? 2
                                                        : 1
                                            )
                                        }
                                    Spacer()
                                    if let error = point.error {
                                        Text(
                                            error,
                                            format: .number.precision(
                                                .fractionLength(1)
                                            )
                                        )
                                        .monospacedDigit()
                                    } else {
                                        Text("—")
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .padding(.horizontal, 9)
                                .frame(height: 29)
                                .contentShape(Rectangle())
                                .background(
                                    point.id == selectedPointID
                                        ? Color.accentColor.opacity(0.28)
                                        : Color.clear
                                )
                            }
                            .buttonStyle(.plain)
                            .id(point.id)

                            Divider()
                        }
                    }
                }
                .onChange(of: selectedPointID) {
                    guard let selectedPointID else { return }
                    withAnimation {
                        proxy.scrollTo(selectedPointID, anchor: .center)
                    }
                }
            }
        }
        .background(.background)
    }

    private func markerColor(_ index: Int) -> Color {
        ControlPointMarkerPalette.color(index)
    }

}

private struct ControlPointImage: View {
    let image: SourceImage
    let imageIndex: Int
    let points: [DiagnosticControlPoint]
    let selectedPointID: DiagnosticControlPoint.ID?
    let magnifiedPointID: DiagnosticControlPoint.ID?
    let pointIDToReveal: DiagnosticControlPoint.ID?
    let isAddingPoint: Bool
    let commandAddsPoint: Bool
    let commandPreviewPoint: CGPoint?
    let allowsAdding: Bool
    let onSelectPoint: (DiagnosticControlPoint.ID?) -> Void
    let onMagnifyPoint: (DiagnosticControlPoint.ID?) -> Void
    let onCommandPreview: (CGPoint?) -> Void
    let onMovePoint: (DiagnosticControlPoint.ID, Int, CGPoint) -> Void
    let onAddPoint: (CGPoint) -> Void
    @State private var sourceImage: CGImage?
    @State private var viewport = ControlPointViewportController()
    @State private var draggedPointID: DiagnosticControlPoint.ID?
    @State private var draggedPointStartCoordinate: CGPoint?
    @State private var quarterTurns = 0
    @State private var exifOrientation = CGImagePropertyOrientation.up

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Bild \(imageIndex + 1)")
                    .font(.headline)
                Text(image.filename)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                Spacer()
                ControlPointZoomControls(controller: viewport)

                Button {
                    quarterTurns = (quarterTurns + 1) % 4
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Rotera bilden 90°")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            GeometryReader { geometry in
                if let sourceImage {
                    let displayedSourceImage = rotatedImage(
                        sourceImage,
                        quarterTurns: quarterTurns
                    ) ?? sourceImage
                    // Hugin's control-point coordinates already use the
                    // EXIF-oriented image space. ImageIO applies that same
                    // orientation while decoding the thumbnail, so applying
                    // EXIF once more here would rotate the markers away from
                    // their actual features.
                    let decodedCoordinateSize =
                        ControlPointCoordinateSpace.orientedSize(
                            rawWidth: image.pixelWidth,
                            rawHeight: image.pixelHeight,
                            displayedWidth: sourceImage.width,
                            displayedHeight: sourceImage.height
                        )
                    let controlPointCoordinateSize = decodedCoordinateSize
                    let displayedCoordinateSize = quarterTurns.isMultiple(of: 2)
                        ? controlPointCoordinateSize
                        : CGSize(
                            width: controlPointCoordinateSize.height,
                            height: controlPointCoordinateSize.width
                        )
                    let displayedImageSize = CGSize(
                        width: displayedSourceImage.width,
                        height: displayedSourceImage.height
                    )
                    let fitted = aspectFit(displayedImageSize, in: geometry.size)
                    let fitMagnification = min(
                        fitted.width / max(displayedImageSize.width, 1),
                        fitted.height / max(displayedImageSize.height, 1)
                    )
                    let documentSize = displayedImageSize
                    let origin = CGPoint.zero
                    let markerLocations = points.map { point in
                        ControlPointHitTarget(
                            id: point.id,
                            position: displayedPosition(
                                for: displayCoordinate(
                                    for: coordinates(for: point),
                                    in: controlPointCoordinateSize
                                ),
                                coordinateSize: displayedCoordinateSize,
                                fittedSize: documentSize,
                                origin: origin
                            )
                        )
                    }
                    ControlPointNativeScrollView(
                        controller: viewport,
                        protectedPoints: markerLocations,
                        fitMagnification: fitMagnification,
                        backgroundPanEnabled:
                            !(isAddingPoint && allowsAdding),
                        onCommandClick: { location in
                            onAddPoint(originalCoordinate(
                                for: sourceCoordinate(
                                    for: location,
                                    coordinateSize: displayedCoordinateSize,
                                    fittedSize: documentSize,
                                    origin: origin
                                ),
                                in: controlPointCoordinateSize
                            ))
                        },
                        onPointMouseDown: { pointID in
                            viewport.beginPointMove()
                            onSelectPoint(pointID)
                            onMagnifyPoint(pointID)
                        },
                        onPointDragged: { pointID, location in
                            onMovePoint(
                                pointID,
                                imageIndex,
                                originalCoordinate(
                                    for: sourceCoordinate(
                                        for: location,
                                        coordinateSize: displayedCoordinateSize,
                                        fittedSize: documentSize,
                                        origin: origin
                                    ),
                                    in: controlPointCoordinateSize
                                )
                            )
                        },
                        onPointMouseUp: {
                            viewport.endPointMove()
                            onMagnifyPoint(nil)
                        }
                    ) {
                        ZStack {
                                Image(decorative: displayedSourceImage, scale: 1)
                                    .resizable()
                                    .frame(
                                        width: documentSize.width,
                                        height: documentSize.height
                                    )
                                    .position(
                                        x: documentSize.width / 2,
                                        y: documentSize.height / 2
                                    )

                        ControlPointMarkerLayer(
                            markers: Array(points.enumerated()).map {
                                index, point in
                                ControlPointScreenMarker(
                                    id: point.id,
                                    number: index + 1,
                                    position: displayedPosition(
                                        for: displayCoordinate(
                                            for: coordinates(for: point),
                                            in: controlPointCoordinateSize
                                        ),
                                        coordinateSize: displayedCoordinateSize,
                                        fittedSize: documentSize,
                                        origin: origin
                                    ),
                                    selected: point.id == selectedPointID
                                )
                            },
                            controller: viewport,
                            fitMagnification: fitMagnification,
                            onSelect: { pointID in
                                onSelectPoint(pointID)
                            },
                            onDragChanged: { pointID, translation in
                                if draggedPointID != pointID {
                                    draggedPointID = pointID
                                    draggedPointStartCoordinate = points
                                        .first { $0.id == pointID }
                                        .map {
                                            displayCoordinate(
                                                for: coordinates(for: $0),
                                                in: controlPointCoordinateSize
                                            )
                                        }
                                    onSelectPoint(pointID)
                                    onMagnifyPoint(pointID)
                                }
                                guard let start = draggedPointStartCoordinate
                                else { return }
                                let coordinate = CGPoint(
                                    x: min(max(
                                        start.x + translation.width
                                            / documentSize.width
                                            * displayedCoordinateSize.width,
                                        0
                                    ), displayedCoordinateSize.width),
                                    y: min(max(
                                        start.y + translation.height
                                            / documentSize.height
                                            * displayedCoordinateSize.height,
                                        0
                                    ), displayedCoordinateSize.height)
                                )
                                onMovePoint(
                                    pointID,
                                    imageIndex,
                                    originalCoordinate(
                                        for: coordinate,
                                        in: controlPointCoordinateSize
                                    )
                                )
                            },
                            onDragEnded: {
                                draggedPointID = nil
                                draggedPointStartCoordinate = nil
                                onMagnifyPoint(nil)
                            }
                        )
                        .frame(
                            width: documentSize.width,
                            height: documentSize.height
                        )
                        .allowsHitTesting(false)
                        if let sourcePoint = points.first(where: {
                                $0.id == magnifiedPointID
                            }).map(coordinates(for:)) {
                            let displayPoint = displayCoordinate(
                                for: sourcePoint,
                                in: controlPointCoordinateSize
                            )
                            let position = displayedPosition(
                                for: displayPoint,
                                coordinateSize: displayedCoordinateSize,
                                fittedSize: documentSize,
                                origin: origin
                            )
                            ControlPointLoupe(
                                sourceImage: displayedSourceImage,
                                sourcePoint: displayPoint,
                                coordinateSize: displayedCoordinateSize,
                                viewportMagnification:
                                    viewport.actualMagnification
                            )
                            .scaleEffect(
                                1 / max(
                                    viewport.actualMagnification,
                                    0.001
                                )
                            )
                            .position(loupePosition(
                                near: position,
                                in: viewport.visibleDocumentRect,
                                magnification: viewport.actualMagnification
                            ))
                            .allowsHitTesting(false)
                        }
                            }
                            .frame(
                                width: documentSize.width,
                                height: documentSize.height
                            )
                    }
                    .onChange(of: pointIDToReveal) {
                        guard let pointIDToReveal,
                              let location = markerLocations.first(where: {
                                  $0.id == pointIDToReveal
                              })?.position else { return }
                        Task { @MainActor in
                            await Task.yield()
                            let visible = viewport.visibleDocumentRect
                            guard !visible.contains(location) else { return }
                            let visibleCenter = CGPoint(
                                x: visible.midX,
                                y: visible.midY
                            )
                            let coordinate = originalCoordinate(
                                for: sourceCoordinate(
                                    for: visibleCenter,
                                    coordinateSize: displayedCoordinateSize,
                                    fittedSize: documentSize,
                                    origin: origin
                                ),
                                in: controlPointCoordinateSize
                            )
                            onMovePoint(
                                pointIDToReveal,
                                imageIndex,
                                coordinate
                            )
                        }
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .task(id: image.id) {
            async let loadedImage = ControlPointThumbnailCache.shared.image(
                at: image.url,
                maximumPixelSize: max(image.pixelWidth, image.pixelHeight)
            )
            async let loadedOrientation = ControlPointThumbnailCache.shared
                .orientation(at: image.url)
            let (resolvedImage, resolvedOrientation) = await (
                loadedImage,
                loadedOrientation
            )
            exifOrientation = resolvedOrientation
            quarterTurns = 0
            sourceImage = resolvedImage
        }
        .onChange(of: selectedPointID) {
            if selectedPointID == nil {
                draggedPointID = nil
                draggedPointStartCoordinate = nil
                viewport.endPan()
            }
        }
    }

    private func coordinates(for point: DiagnosticControlPoint) -> CGPoint {
        if point.firstImage == imageIndex {
            return CGPoint(x: point.firstX, y: point.firstY)
        }
        return CGPoint(x: point.secondX, y: point.secondY)
    }

    private func displayCoordinate(
        for point: CGPoint,
        in size: CGSize
    ) -> CGPoint {
        return switch quarterTurns {
        case 1: CGPoint(x: size.height - point.y, y: point.x)
        case 2: CGPoint(x: size.width - point.x, y: size.height - point.y)
        case 3: CGPoint(x: point.y, y: size.width - point.x)
        default: point
        }
    }

    private func originalCoordinate(
        for point: CGPoint,
        in size: CGSize
    ) -> CGPoint {
        return switch quarterTurns {
        case 1: CGPoint(x: point.y, y: size.height - point.x)
        case 2: CGPoint(x: size.width - point.x, y: size.height - point.y)
        case 3: CGPoint(x: size.width - point.y, y: point.x)
        default: point
        }
    }

    private func rotatedImage(
        _ image: CGImage,
        quarterTurns: Int
    ) -> CGImage? {
        let orientation: CGImagePropertyOrientation = switch quarterTurns {
        case 1: .right
        case 2: .down
        case 3: .left
        default: .up
        }
        guard orientation != .up else { return image }
        let rotated = CIImage(cgImage: image).oriented(orientation)
        return Self.rotationContext.createCGImage(
            rotated,
            from: rotated.extent
        )
    }

    private static let rotationContext = CIContext(options: [
        .cacheIntermediates: true
    ])

    private func displayedPosition(
        for point: CGPoint,
        coordinateSize: CGSize,
        fittedSize: CGSize,
        origin: CGPoint
    ) -> CGPoint {
        CGPoint(
            x: origin.x + point.x / coordinateSize.width * fittedSize.width,
            y: origin.y + point.y / coordinateSize.height * fittedSize.height
        )
    }

    private func sourceCoordinate(
        for point: CGPoint,
        coordinateSize: CGSize,
        fittedSize: CGSize,
        origin: CGPoint
    ) -> CGPoint {
        CGPoint(
            x: min(max(
                (point.x - origin.x) / fittedSize.width * coordinateSize.width,
                0
            ), coordinateSize.width),
            y: min(max(
                (point.y - origin.y) / fittedSize.height * coordinateSize.height,
                0
            ), coordinateSize.height)
        )
    }

    private func loupePosition(
        near point: CGPoint,
        in visibleRect: CGRect,
        magnification: Double
    ) -> CGPoint {
        let scale = max(CGFloat(magnification), 0.001)
        let offset: CGFloat = 92 / scale
        let margin: CGFloat = 78 / scale
        let x = min(
            max(point.x + offset, visibleRect.minX + margin),
            visibleRect.maxX - margin
        )
        let proposedY = point.y - offset
        let y = proposedY >= visibleRect.minY + margin
            ? proposedY
            : min(point.y + offset, visibleRect.maxY - margin)
        return CGPoint(x: x, y: y)
    }

    private func aspectFit(_ content: CGSize, in container: CGSize) -> CGSize {
        let scale = min(
            container.width / max(content.width, 1),
            container.height / max(content.height, 1)
        )
        return CGSize(width: content.width * scale, height: content.height * scale)
    }

}

@MainActor
private struct ControlPointScreenMarker {
    let id: DiagnosticControlPoint.ID
    let number: Int
    let position: CGPoint
    let selected: Bool
}

@MainActor
private struct ControlPointMarkerLayer: View {
    let markers: [ControlPointScreenMarker]
    @ObservedObject var controller: ControlPointViewportController
    let fitMagnification: Double
    let onSelect: (DiagnosticControlPoint.ID) -> Void
    let onDragChanged: (DiagnosticControlPoint.ID, CGSize) -> Void
    let onDragEnded: () -> Void

    var body: some View {
        let inverseZoom = 1 / max(
            fitMagnification * controller.magnification,
            0.001
        )
        ZStack(alignment: .topLeading) {
            ForEach(markers.indices, id: \.self) { index in
                let marker = markers[index]
                Button {
                    onSelect(marker.id)
                } label: {
                    ZStack {
                        Circle()
                            .fill(
                                ControlPointMarkerPalette.color(marker.number - 1)
                                    .opacity(marker.selected ? 0.82 : 0.62)
                            )
                        Circle()
                            .stroke(
                                marker.selected ? .white : .black,
                                lineWidth: (marker.selected ? 2 : 1) * inverseZoom
                            )
                        Text("\(marker.number)")
                            .font(.system(
                                size: 11 * inverseZoom,
                                weight: .bold
                            ))
                            .foregroundStyle(.black)
                    }
                    .frame(width: 28 * inverseZoom, height: 28 * inverseZoom)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .position(marker.position)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged {
                            onDragChanged(marker.id, $0.translation)
                        }
                        .onEnded { _ in
                            onDragEnded()
                        }
                )
            }
        }
    }
}

@MainActor
private struct ControlPointZoomControls: View {
    @ObservedObject var controller: ControlPointViewportController

    var body: some View {
        Button {
            controller.zoom(by: 1 / 1.25)
        } label: {
            Image(systemName: "minus.magnifyingglass")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .disabled(controller.magnification <= 1)
        .help("Zooma ut bilden")

        Text("\(Int((controller.magnification * 100).rounded())) %")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(minWidth: 46)

        Button {
            controller.zoom(by: 1.25)
        } label: {
            Image(systemName: "plus.magnifyingglass")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .disabled(controller.magnification >= 8)
        .help("Zooma in bilden")
    }
}

@MainActor
private final class ControlPointViewportController: ObservableObject {
    @Published private(set) var magnification = 1.0
    @Published private(set) var isMovingPoint = false
    weak var scrollView: ControlPointNSScrollView?
    private var panOrigin: CGPoint?
    private var fitMagnification = 1.0

    var actualMagnification: Double {
        magnification * fitMagnification
    }

    var visibleDocumentRect: CGRect {
        scrollView?.documentVisibleRect ?? .zero
    }

    func zoom(by factor: Double) {
        guard let scrollView else { return }
        let center = CGPoint(
            x: scrollView.documentVisibleRect.midX,
            y: scrollView.documentVisibleRect.midY
        )
        scrollView.setMagnification(
            min(max(
                scrollView.magnification * factor,
                fitMagnification
            ), fitMagnification * 8),
            centeredAt: center
        )
        updateMagnification(scrollView.magnification)
    }

    func beginPan() {
        panOrigin = scrollView?.contentView.bounds.origin
    }

    func pan(translation: CGSize) {
        guard let origin = panOrigin else { return }
        guard let scrollView else { return }
        let scale = max(scrollView.magnification, 0.001)
        let proposed = CGRect(
            origin: CGPoint(
                x: origin.x - translation.width / scale,
                y: origin.y - translation.height / scale
            ),
            size: scrollView.contentView.bounds.size
        )
        let constrained = scrollView.contentView.constrainBoundsRect(proposed)
        scrollView.contentView.scroll(to: constrained.origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func endPan() {
        panOrigin = nil
    }

    func beginPointMove() {
        endPan()
        isMovingPoint = true
    }

    func endPointMove() {
        isMovingPoint = false
    }

    func updateMagnification(_ value: Double) {
        magnification = value / max(fitMagnification, 0.000_001)
    }

    func configureFitMagnification(_ value: Double) {
        fitMagnification = max(value, 0.000_001)
        updateMagnification(
            scrollView.map { Double($0.magnification) } ?? fitMagnification
        )
        // The relative zoom can remain exactly 1.0 while the native fit
        // magnification changes from its placeholder value. Marker sizes use
        // the absolute magnification, so they still need a redraw.
        objectWillChange.send()
    }
}

private final class ControlPointNSScrollView: NSScrollView {
    weak var viewportController: ControlPointViewportController?

    override func scrollWheel(with event: NSEvent) {
        let zoomDelta = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)
            ? event.scrollingDeltaY
            : event.scrollingDeltaX
        guard event.modifierFlags.contains(.option)
                || event.modifierFlags.contains(.shift),
              abs(zoomDelta) > 0.01,
              let documentView else {
            super.scrollWheel(with: event)
            return
        }
        let anchor = documentView.convert(event.locationInWindow, from: nil)
        let physicalDelta = event.isDirectionInvertedFromDevice
            ? -zoomDelta
            : zoomDelta
        let proposedTarget = magnification
            * exp(-physicalDelta * 0.008)
        let target = min(max(
            proposedTarget,
            minMagnification
        ), maxMagnification)
        guard abs(target - magnification) > 0.000_001 else { return }
        setMagnification(target, centeredAt: anchor)
        viewportController?.updateMagnification(magnification)
    }

    override func magnify(with event: NSEvent) {
        super.magnify(with: event)
        viewportController?.updateMagnification(magnification)
    }
}

private final class CenteringControlPointClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var bounds = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return bounds }
        if bounds.width > documentView.frame.width {
            bounds.origin.x = (documentView.frame.width - bounds.width) / 2
        }
        if bounds.height > documentView.frame.height {
            bounds.origin.y = (documentView.frame.height - bounds.height) / 2
        }
        return bounds
    }
}

private struct ControlPointHitTarget {
    let id: DiagnosticControlPoint.ID
    let position: CGPoint
}

private struct ControlPointNativeScrollView<Content: View>:
    NSViewRepresentable {
    let controller: ControlPointViewportController
    let protectedPoints: [ControlPointHitTarget]
    let fitMagnification: Double
    let backgroundPanEnabled: Bool
    let onCommandClick: (CGPoint) -> Void
    let onPointMouseDown: (DiagnosticControlPoint.ID) -> Void
    let onPointDragged: (DiagnosticControlPoint.ID, CGPoint) -> Void
    let onPointMouseUp: () -> Void
    let content: Content

    init(
        controller: ControlPointViewportController,
        protectedPoints: [ControlPointHitTarget],
        fitMagnification: Double,
        backgroundPanEnabled: Bool,
        onCommandClick: @escaping (CGPoint) -> Void,
        onPointMouseDown: @escaping (DiagnosticControlPoint.ID) -> Void,
        onPointDragged: @escaping (DiagnosticControlPoint.ID, CGPoint) -> Void,
        onPointMouseUp: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.controller = controller
        self.protectedPoints = protectedPoints
        self.fitMagnification = fitMagnification
        self.backgroundPanEnabled = backgroundPanEnabled
        self.onCommandClick = onCommandClick
        self.onPointMouseDown = onPointMouseDown
        self.onPointDragged = onPointDragged
        self.onPointMouseUp = onPointMouseUp
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeNSView(context: Context) -> ControlPointNSScrollView {
        let scrollView = ControlPointNSScrollView()
        scrollView.contentView = CenteringControlPointClipView()
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .windowBackgroundColor
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = fitMagnification
        scrollView.maxMagnification = fitMagnification * 8
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame.size = hostingView.fittingSize
        let panGesture = NSPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.panBackground(_:))
        )
        panGesture.buttonMask = 0x1
        hostingView.addGestureRecognizer(panGesture)
        scrollView.documentView = hostingView
        scrollView.viewportController = controller
        controller.scrollView = scrollView
        scrollView.magnification = fitMagnification
        controller.configureFitMagnification(fitMagnification)
        context.coordinator.scrollView = scrollView
        context.coordinator.protectedPoints = protectedPoints
        context.coordinator.onPointMouseDown = onPointMouseDown
        context.coordinator.onPointDragged = onPointDragged
        context.coordinator.onPointMouseUp = onPointMouseUp
        context.coordinator.backgroundPanEnabled = backgroundPanEnabled
        context.coordinator.onCommandClick = onCommandClick
        context.coordinator.installMouseMonitor()
        return scrollView
    }

    func updateNSView(
        _ scrollView: ControlPointNSScrollView,
        context: Context
    ) {
        guard let hostingView = scrollView.documentView
            as? NSHostingView<Content> else { return }
        hostingView.rootView = content
        let size = hostingView.fittingSize
        if hostingView.frame.size != size {
            hostingView.frame.size = size
        }
        scrollView.viewportController = controller
        controller.scrollView = scrollView
        if abs(scrollView.minMagnification - fitMagnification) > 0.000_001 {
            let relativeZoom = controller.magnification
            let center = CGPoint(
                x: scrollView.documentVisibleRect.midX,
                y: scrollView.documentVisibleRect.midY
            )
            scrollView.minMagnification = fitMagnification
            scrollView.maxMagnification = fitMagnification * 8
            scrollView.setMagnification(
                min(max(
                    fitMagnification * relativeZoom,
                    fitMagnification
                ), fitMagnification * 8),
                centeredAt: center
            )
            controller.configureFitMagnification(fitMagnification)
        }
        context.coordinator.scrollView = scrollView
        context.coordinator.protectedPoints = protectedPoints
        context.coordinator.onPointMouseDown = onPointMouseDown
        context.coordinator.onPointDragged = onPointDragged
        context.coordinator.onPointMouseUp = onPointMouseUp
        context.coordinator.backgroundPanEnabled = backgroundPanEnabled
        context.coordinator.onCommandClick = onCommandClick
    }

    static func dismantleNSView(
        _ scrollView: ControlPointNSScrollView,
        coordinator: Coordinator
    ) {
        coordinator.removeMouseMonitor()
    }

    @MainActor
    final class Coordinator: NSObject {
        let controller: ControlPointViewportController
        weak var scrollView: NSScrollView?
        var protectedPoints: [ControlPointHitTarget] = []
        var onPointMouseDown: (DiagnosticControlPoint.ID) -> Void = { _ in }
        var onPointDragged: (DiagnosticControlPoint.ID, CGPoint) -> Void = {
            _, _ in
        }
        var onPointMouseUp: () -> Void = {}
        var onCommandClick: (CGPoint) -> Void = { _ in }
        var backgroundPanEnabled = true
        private var mouseMonitor: Any?
        private var activePointID: DiagnosticControlPoint.ID?

        init(controller: ControlPointViewportController) {
            self.controller = controller
        }

        func installMouseMonitor() {
            guard mouseMonitor == nil else { return }
            mouseMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
            ) { [weak self] event in
                self?.handleMouseEvent(event) ?? event
            }
        }

        func removeMouseMonitor() {
            guard let mouseMonitor else { return }
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
            finishActiveMouseOperation()
        }

        private func handleMouseEvent(_ event: NSEvent) -> NSEvent? {
            // Mouse-up can belong to another view (or no window at all) when
            // the pointer leaves this pane during a drag. Always release the
            // CP lock before applying the usual window hit test.
            if event.type == .leftMouseUp,
               activePointID != nil {
                finishActiveMouseOperation()
                return nil
            }
            // Recover from a missed mouse-up before starting a new gesture.
            if event.type == .leftMouseDown,
               activePointID != nil {
                finishActiveMouseOperation()
            }
            guard let scrollView,
                  event.window === scrollView.window,
                  let documentView = scrollView.documentView else {
                return event
            }
            var location = documentView.convert(event.locationInWindow, from: nil)
            if !documentView.isFlipped {
                location.y = documentView.bounds.height - location.y
            }
            switch event.type {
            case .leftMouseDown:
                let pointInScrollView = scrollView.convert(
                    event.locationInWindow,
                    from: nil
                )
                guard scrollView.bounds.contains(pointInScrollView) else {
                    return event
                }
                if event.modifierFlags.contains(.command) {
                    onCommandClick(location)
                    return nil
                }
                let hitRadius = 24 / max(scrollView.magnification, 0.001)
                if let target = protectedPoints.min(by: {
                    hypot($0.position.x - location.x, $0.position.y - location.y)
                        < hypot($1.position.x - location.x, $1.position.y - location.y)
                }), hypot(
                    target.position.x - location.x,
                    target.position.y - location.y
                ) <= hitRadius {
                    activePointID = target.id
                    onPointMouseDown(target.id)
                    return nil
                }
                return event
            case .leftMouseDragged:
                if let activePointID {
                    onPointDragged(activePointID, location)
                    return nil
                }
                return event
            case .leftMouseUp:
                return event
            default:
                return event
            }
        }

        private func finishActiveMouseOperation() {
            if activePointID != nil {
                activePointID = nil
                onPointMouseUp()
            }
        }

        @objc func panBackground(_ gesture: NSPanGestureRecognizer) {
            guard activePointID == nil, let scrollView else { return }
            switch gesture.state {
            case .began:
                controller.beginPan()
            case .changed:
                let translation = gesture.translation(in: scrollView)
                controller.pan(translation: CGSize(
                    width: translation.x,
                    height: translation.y
                ))
            case .ended, .cancelled, .failed:
                controller.endPan()
            default:
                break
            }
        }

    }
}

private struct ControlPointLoupe: View {
    let sourceImage: CGImage
    let sourcePoint: CGPoint
    let coordinateSize: CGSize
    let viewportMagnification: Double

    private let diameter: CGFloat = 148
    private let relativeMagnification: CGFloat = 2

    private var croppedImage: CGImage? {
        let scaleX = CGFloat(sourceImage.width) / coordinateSize.width
        let scaleY = CGFloat(sourceImage.height) / coordinateSize.height
        let center = CGPoint(
            x: sourcePoint.x * scaleX,
            y: sourcePoint.y * scaleY
        )
        let cropSize = min(
            diameter / max(
                CGFloat(viewportMagnification) * relativeMagnification,
                0.001
            ),
            CGFloat(min(sourceImage.width, sourceImage.height))
        )
        let rect = CGRect(
            x: min(max(center.x - cropSize / 2, 0), CGFloat(sourceImage.width) - cropSize),
            y: min(max(center.y - cropSize / 2, 0), CGFloat(sourceImage.height) - cropSize),
            width: min(cropSize, CGFloat(sourceImage.width)),
            height: min(cropSize, CGFloat(sourceImage.height))
        ).integral
        return sourceImage.cropping(to: rect)
    }

    var body: some View {
        ZStack {
            if let croppedImage {
                Image(decorative: croppedImage, scale: 1)
                    .resizable()
                    .scaledToFill()
            }
            Circle()
                .stroke(.white, lineWidth: 3)
                .shadow(color: .black.opacity(0.8), radius: 3)
            Rectangle()
                .fill(.white)
                .frame(width: 18, height: 1)
            Rectangle()
                .fill(.white)
                .frame(width: 1, height: 18)
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay {
            Circle().stroke(.black.opacity(0.7), lineWidth: 1)
        }
    }
}

private actor ControlPointThumbnailCache {
    private struct Key: Hashable {
        let url: URL
        let maximumPixelSize: Int
    }

    static let shared = ControlPointThumbnailCache()
    private var images: [Key: CGImage] = [:]
    private var orientations: [URL: CGImagePropertyOrientation] = [:]

    func orientation(at url: URL) async -> CGImagePropertyOrientation {
        if let orientation = orientations[url] { return orientation }
        let orientation = await Task.detached(priority: .userInitiated) {
            Self.loadOrientation(at: url)
        }.value
        orientations[url] = orientation
        return orientation
    }

    func image(at url: URL, maximumPixelSize: Int) async -> CGImage? {
        let key = Key(url: url, maximumPixelSize: maximumPixelSize)
        if let image = images[key] {
            return image
        }
        let image = await Task.detached(priority: .userInitiated) {
            Self.loadImage(at: url, maximumPixelSize: maximumPixelSize)
        }.value
        if let image {
            images[key] = image
        }
        return image
    }

    nonisolated private static func loadImage(
        at url: URL,
        maximumPixelSize: Int
    ) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        )
    }

    nonisolated private static func loadOrientation(
        at url: URL
    ) -> CGImagePropertyOrientation {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(
                  source,
                  0,
                  nil
              ) as? [CFString: Any],
              let value = properties[kCGImagePropertyOrientation] as? NSNumber,
              let orientation = CGImagePropertyOrientation(
                  rawValue: value.uint32Value
              ) else {
            return .up
        }
        return orientation
    }
}
