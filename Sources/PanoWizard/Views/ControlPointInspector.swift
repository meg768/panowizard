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
    let diagnostics: ControlPointDiagnostics
    let selectedPairID: ControlPointPair.ID
    let leftImageIndex: Int
    let rightImageIndex: Int
    let onSelectImages: (Int, Int) -> Void
    let onMovePoint: (DiagnosticControlPoint.ID, Int, CGPoint) -> Void
    let onRemovePoint: (DiagnosticControlPoint.ID) -> Void
    let onAddPoint: (CGPoint, Int) -> DiagnosticControlPoint.ID
    let isSuggestingPoints: Bool
    let onSuggestPoints: () -> Void
    let onSuggestProjectPoints: () -> Void
    let onRegenerateProjectPoints: () -> Void
    let onRemoveAllPoints: () -> Void
    let onRemoveAllProjectPoints: () -> Void
    let onOptimize: () -> Void
    let isPoleAlignment: Bool
    @State private var selectedPointID: DiagnosticControlPoint.ID?
    @State private var magnifiedPointID: DiagnosticControlPoint.ID?
    @State private var isAddingPoint = false
    @State private var isCommandPressed = false
    @State private var isShiftPressed = false
    @State private var commandPreviewPoints: [Int: CGPoint] = [:]
    @State private var modifierMonitor: Any?
    @State private var deleteKeyMonitor: Any?
    @State private var pendingSelectionAfterDelete:
        DiagnosticControlPoint.ID?
    @State private var isDeleteDialogPresented = false
    @State private var isSuggestDialogPresented = false
    @State private var isRegenerateDialogPresented = false
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
                HStack {
                    Button {
                        isAddingPoint.toggle()
                        selectedPointID = nil
                    } label: {
                        Label(
                            isAddingPoint ? "Avbryt ny punkt" : "Lägg till punkt",
                            systemImage: isAddingPoint ? "xmark" : "plus"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isAddingPoint ? .orange : .accentColor)

                    Button {
                        if isPoleAlignment {
                            onSuggestPoints()
                        } else {
                            isSuggestDialogPresented = true
                        }
                    } label: {
                        Label(
                            isPoleAlignment ? "Föreslå om" : "Föreslå punkter…",
                            systemImage: "sparkles"
                        )
                    }
                    .disabled(isSuggestingPoints)
                    .confirmationDialog(
                        "Föreslå kontrollpunkter",
                        isPresented: $isSuggestDialogPresented,
                        titleVisibility: .visible
                    ) {
                        Button(
                            "Mellan bild \(leftImageIndex + 1) och "
                                + "\(rightImageIndex + 1)",
                            action: onSuggestPoints
                        )
                        if !isPoleAlignment {
                            Button(
                                "I hela projektet",
                                action: onSuggestProjectPoints
                            )
                            Button(
                                "Generera om alla punkter…",
                                role: .destructive
                            ) {
                                DispatchQueue.main.async {
                                    isRegenerateDialogPresented = true
                                }
                            }
                        }
                        Button("Avbryt", role: .cancel) {}
                    } message: {
                        Text(
                            "Välj om PanoWizard ska söka i det aktuella "
                                + "bildparet eller mellan alla projektets bilder."
                        )
                    }
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

                    Button {
                        isDeleteDialogPresented = true
                    } label: {
                        Label("Radera…", systemImage: "trash")
                    }
                    .disabled(diagnostics.cleanedPoints.isEmpty)
                    .confirmationDialog(
                        "Radera kontrollpunkter",
                        isPresented: $isDeleteDialogPresented,
                        titleVisibility: .visible
                    ) {
                        Button("Radera markerad punkt", role: .destructive) {
                            removeSelectedPoint()
                        }
                        .disabled(selectedPointID == nil)

                        Button(
                            "Radera alla mellan bild "
                                + "\(leftImageIndex + 1) och "
                                + "\(rightImageIndex + 1)",
                            role: .destructive,
                            action: onRemoveAllPoints
                        )
                        .disabled(displayedPoints.isEmpty)

                        if !isPoleAlignment {
                            Button(
                                "Radera alla kontrollpunkter i projektet",
                                role: .destructive,
                                action: onRemoveAllProjectPoints
                            )
                        }

                        Button("Avbryt", role: .cancel) {}
                    } message: {
                        Text("Välj vilka kontrollpunkter som ska tas bort.")
                    }

                    Button {
                        onOptimize()
                    } label: {
                        Label(
                            isPoleAlignment ? "Anpassa" : "Optimera",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                    .disabled(displayedPoints.count < 3)

                    Spacer()
                    Text(instruction)
                        .foregroundStyle(.secondary)
                }
                .padding()

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
                    let controlPointCoordinateSize =
                        ControlPointCoordinateSpace.orientedSize(
                            rawWidth: image.pixelWidth,
                            rawHeight: image.pixelHeight,
                            displayedWidth: sourceImage.width,
                            displayedHeight: sourceImage.height
                        )
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
                        displayedPosition(
                            for: displayCoordinate(
                                for: coordinates(for: point),
                                in: controlPointCoordinateSize
                            ),
                            coordinateSize: displayedCoordinateSize,
                            fittedSize: documentSize,
                            origin: origin
                        )
                    }
                    ControlPointNativeScrollView(
                        controller: viewport,
                        protectedPoints: markerLocations,
                        fitMagnification: fitMagnification
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
                            controller: viewport
                        )
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if draggedPointID == nil,
                                       !viewport.isPanning {
                                        if shouldAddPoint {
                                            return
                                        }
                                        draggedPointID = closestPoint(
                                            to: value.startLocation,
                                            coordinateSize: displayedCoordinateSize,
                                            fittedSize: documentSize,
                                            origin: origin
                                        )
                                        draggedPointStartCoordinate = points
                                            .first {
                                                $0.id == draggedPointID
                                            }
                                            .map {
                                                displayCoordinate(
                                                    for: coordinates(for: $0),
                                                    in: controlPointCoordinateSize
                                                )
                                            }
                                        onSelectPoint(draggedPointID)
                                        onMagnifyPoint(draggedPointID)
                                    }
                                    let distance = hypot(
                                        value.translation.width,
                                        value.translation.height
                                    )
                                    if let draggedPointID,
                                       let start = draggedPointStartCoordinate,
                                       distance >= 3 {
                                        let coordinate = CGPoint(
                                            x: min(max(
                                                start.x
                                                    + value.translation.width
                                                    / documentSize.width
                                                    * displayedCoordinateSize.width,
                                                0
                                            ), displayedCoordinateSize.width),
                                            y: min(max(
                                                start.y
                                                    + value.translation.height
                                                    / documentSize.height
                                                    * displayedCoordinateSize.height,
                                                0
                                            ), displayedCoordinateSize.height)
                                        )
                                        onMovePoint(
                                            draggedPointID,
                                            imageIndex,
                                            originalCoordinate(
                                                for: coordinate,
                                                in: controlPointCoordinateSize
                                            )
                                        )
                                    }
                                }
                                .onEnded { value in
                                    let distance = hypot(
                                        value.translation.width,
                                        value.translation.height
                                    )
                                    if shouldAddPoint, distance < 3 {
                                        onAddPoint(originalCoordinate(
                                            for: sourceCoordinate(
                                                for: value.location,
                                                coordinateSize: displayedCoordinateSize,
                                                fittedSize: documentSize,
                                                origin: origin
                                            ),
                                            in: controlPointCoordinateSize
                                        ))
                                    }
                                    draggedPointID = nil
                                    draggedPointStartCoordinate = nil
                                    onMagnifyPoint(nil)
                                }
                        )
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                guard commandAddsPoint else { return }
                                onCommandPreview(originalCoordinate(
                                    for: sourceCoordinate(
                                        for: location,
                                        coordinateSize: displayedCoordinateSize,
                                        fittedSize: documentSize,
                                        origin: origin
                                    ),
                                    in: controlPointCoordinateSize
                                ))
                            case .ended:
                                onCommandPreview(nil)
                            }
                        }
                        .onChange(of: commandAddsPoint) {
                            if !commandAddsPoint {
                                onCommandPreview(nil)
                            }
                        }

                        if let sourcePoint = commandPreviewPoint
                            ?? points.first(where: {
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
                                coordinateSize: displayedCoordinateSize
                            )
                            .position(loupePosition(
                                near: position,
                                in: viewport.visibleDocumentRect
                            ))
                            .allowsHitTesting(false)
                        }
                            }
                            .frame(
                                width: documentSize.width,
                                height: documentSize.height
                            )
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
            // ImageIO has applied the camera's EXIF orientation at this point.
            // Normalize the CP editor from the decoded dimensions rather than
            // the raw sensor dimensions stored in the project.
            if let resolvedImage {
                quarterTurns = resolvedImage.width > resolvedImage.height ? 1 : 0
            }
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

    private var shouldAddPoint: Bool {
        NSEvent.modifierFlags.contains(.command)
            || (isAddingPoint && allowsAdding)
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
        switch quarterTurns {
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
        switch quarterTurns {
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

    private func drawMarker(
        number: Int,
        at point: CGPoint,
        selected: Bool,
        in context: inout GraphicsContext
    ) {
        let label = Text("\(number)")
            .font(.caption2.bold())
            .foregroundStyle(.black)
        let resolved = context.resolve(label)
        let size = resolved.measure(in: CGSize(width: 60, height: 30))
        let diameter = max(size.width, size.height) + 12
        let box = CGRect(
            x: point.x - diameter / 2,
            y: point.y - diameter / 2,
            width: diameter,
            height: diameter
        )
        context.fill(
            Path(ellipseIn: box),
            with: .color(
                ControlPointMarkerPalette.color(number - 1)
                    .opacity(selected ? 0.82 : 0.62)
            )
        )
        context.stroke(
            Path(ellipseIn: box),
            with: .color(selected ? .white : .black),
            lineWidth: selected ? 2 : 1
        )
        context.draw(resolved, at: point)
    }

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

    private func closestPoint(
        to location: CGPoint,
        coordinateSize: CGSize,
        fittedSize: CGSize,
        origin: CGPoint
    ) -> DiagnosticControlPoint.ID? {
        points.compactMap { point -> (DiagnosticControlPoint.ID, CGFloat)? in
            let position = displayedPosition(
                for: displayCoordinate(
                    for: coordinates(for: point),
                    in: quarterTurns.isMultiple(of: 2)
                        ? coordinateSize
                        : CGSize(width: coordinateSize.height, height: coordinateSize.width)
                ),
                coordinateSize: coordinateSize,
                fittedSize: fittedSize,
                origin: origin
            )
            let distance = hypot(position.x - location.x, position.y - location.y)
            return distance <= 22 ? (point.id, distance) : nil
        }
        .min { $0.1 < $1.1 }?
        .0
    }

    private func loupePosition(
        near point: CGPoint,
        in visibleRect: CGRect
    ) -> CGPoint {
        let offset: CGFloat = 92
        let x = min(
            max(point.x + offset, visibleRect.minX + 78),
            visibleRect.maxX - 78
        )
        let proposedY = point.y - offset
        let y = proposedY >= visibleRect.minY + 78
            ? proposedY
            : min(point.y + offset, visibleRect.maxY - 78)
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
    let number: Int
    let position: CGPoint
    let selected: Bool
}

@MainActor
private struct ControlPointMarkerLayer: View {
    let markers: [ControlPointScreenMarker]
    @ObservedObject var controller: ControlPointViewportController

    var body: some View {
        Canvas { context, _ in
            let inverseZoom = 1 / max(
                controller.actualMagnification,
                0.001
            )
            for marker in markers {
                let label = Text("\(marker.number)")
                    .font(.system(
                        size: 11 * inverseZoom,
                        weight: .bold
                    ))
                    .foregroundStyle(.black)
                let resolved = context.resolve(label)
                let measured = resolved.measure(
                    in: CGSize(width: 60, height: 30)
                )
                let diameter = max(measured.width, measured.height)
                    + 12 * inverseZoom
                let box = CGRect(
                    x: marker.position.x - diameter / 2,
                    y: marker.position.y - diameter / 2,
                    width: diameter,
                    height: diameter
                )
                context.fill(
                    Path(ellipseIn: box),
                    with: .color(
                        ControlPointMarkerPalette.color(marker.number - 1)
                            .opacity(marker.selected ? 0.82 : 0.62)
                    )
                )
                context.stroke(
                    Path(ellipseIn: box),
                    with: .color(marker.selected ? .white : .black),
                    lineWidth: (marker.selected ? 2 : 1) * inverseZoom
                )
                context.draw(resolved, at: marker.position)
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
    weak var scrollView: ControlPointNSScrollView?
    private var panOrigin: CGPoint?
    private var fitMagnification = 1.0

    var isPanning: Bool { panOrigin != nil }
    var actualMagnification: Double {
        magnification * fitMagnification
    }

    var visibleOrigin: CGPoint {
        scrollView?.contentView.bounds.origin ?? .zero
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
        objectWillChange.send()
    }

    func endPan() {
        panOrigin = nil
    }

    func updateMagnification(_ value: Double) {
        magnification = value / max(fitMagnification, 0.000_001)
    }

    func configureFitMagnification(_ value: Double) {
        fitMagnification = max(value, 0.000_001)
        updateMagnification(
            scrollView.map { Double($0.magnification) } ?? fitMagnification
        )
    }
}

private final class ControlPointNSScrollView: NSScrollView {
    weak var viewportController: ControlPointViewportController?

    override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaY) > 0.01,
              let documentView else {
            super.scrollWheel(with: event)
            return
        }
        let anchor = documentView.convert(event.locationInWindow, from: nil)
        let target = min(max(
            magnification * exp(event.scrollingDeltaY * 0.008),
            minMagnification
        ), maxMagnification)
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

private struct ControlPointNativeScrollView<Content: View>:
    NSViewRepresentable {
    let controller: ControlPointViewportController
    let protectedPoints: [CGPoint]
    let fitMagnification: Double
    let content: Content

    init(
        controller: ControlPointViewportController,
        protectedPoints: [CGPoint],
        fitMagnification: Double,
        @ViewBuilder content: () -> Content
    ) {
        self.controller = controller
        self.protectedPoints = protectedPoints
        self.fitMagnification = fitMagnification
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
            action: #selector(Coordinator.pan(_:))
        )
        panGesture.buttonMask = 0x1
        panGesture.delegate = context.coordinator
        hostingView.addGestureRecognizer(panGesture)
        scrollView.documentView = hostingView
        scrollView.viewportController = controller
        controller.scrollView = scrollView
        scrollView.magnification = fitMagnification
        controller.configureFitMagnification(fitMagnification)
        context.coordinator.scrollView = scrollView
        context.coordinator.protectedPoints = protectedPoints
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
    }

    @MainActor
    final class Coordinator: NSObject, NSGestureRecognizerDelegate {
        let controller: ControlPointViewportController
        weak var scrollView: NSScrollView?
        var protectedPoints: [CGPoint] = []

        init(controller: ControlPointViewportController) {
            self.controller = controller
        }

        func gestureRecognizerShouldBegin(
            _ gestureRecognizer: NSGestureRecognizer
        ) -> Bool {
            guard let scrollView,
                  let documentView = scrollView.documentView else {
                return false
            }
            let clipView = scrollView.contentView
            let location = gestureRecognizer.location(in: clipView)
            return !protectedPoints.contains {
                let documentPoint = documentView.isFlipped
                    ? $0
                    : CGPoint(
                        x: $0.x,
                        y: documentView.bounds.height - $0.y
                    )
                let screenPoint = clipView.convert(
                    documentPoint,
                    from: documentView
                )
                return hypot(
                    screenPoint.x - location.x,
                    screenPoint.y - location.y
                ) <= 24
            }
        }

        @objc func pan(_ gesture: NSPanGestureRecognizer) {
            guard let scrollView else { return }
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

    private var croppedImage: CGImage? {
        let scaleX = CGFloat(sourceImage.width) / coordinateSize.width
        let scaleY = CGFloat(sourceImage.height) / coordinateSize.height
        let center = CGPoint(
            x: sourcePoint.x * scaleX,
            y: sourcePoint.y * scaleY
        )
        let cropSize: CGFloat = 110
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
        .frame(width: 148, height: 148)
        .clipShape(Circle())
        .overlay {
            Circle().stroke(.black.opacity(0.7), lineWidth: 1)
        }
    }
}

struct ControlPointPickerThumbnail: View {
    let url: URL
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.secondary.opacity(0.15)
                    .overlay { ProgressView().controlSize(.small) }
            }
        }
        .task(id: url) {
            image = await ControlPointThumbnailCache.shared.image(
                at: url,
                maximumPixelSize: 240
            )
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
