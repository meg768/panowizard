import Foundation

struct ControlPointGeometryPrior: Sendable {
    let projectImageToRigImage: [Int: Int]
    let imageLines: [String]

    init?(
        images: [SourceImage],
        cachedImageLines: [UUID: String]
    ) {
        let rigEntries: [(projectIndex: Int, line: String)] = images
            .enumerated().compactMap { index, image in
            guard image.isEnabled, image.role == .alignment,
                  let line = cachedImageLines[image.id] else { return nil }
            return (projectIndex: index, line: line)
        }
        guard rigEntries.count >= 2 else { return nil }
        projectImageToRigImage = Dictionary(uniqueKeysWithValues:
            rigEntries.enumerated().map { ($0.element.projectIndex, $0.offset) }
        )
        imageLines = rigEntries.map { $0.line }
    }

    func filtering(
        _ points: [DiagnosticControlPoint]
    ) throws -> [DiagnosticControlPoint] {
        let remapped = points.compactMap { point
            -> (original: DiagnosticControlPoint, projected: DiagnosticControlPoint)? in
            guard let first = projectImageToRigImage[point.firstImage],
                  let second = projectImageToRigImage[point.secondImage]
            else { return nil }
            return (point, DiagnosticControlPoint(
                id: point.id,
                firstImage: first,
                secondImage: second,
                firstX: point.firstX,
                firstY: point.firstY,
                secondX: point.secondX,
                secondY: point.secondY
            ))
        }
        guard !remapped.isEmpty else { return [] }

        let directory = FileManager.default.temporaryDirectory.appending(
            path: "PanoWizard/GeometryPrior/\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let project = directory.appending(path: "geometry.pto")
        let contents = ([
            "# hugin project file",
            "p f2 w4000 h2000 v360 E0 R0 n\"TIFF_m\"",
            "m g1 i0 f0 m2 p0.00784314"
        ] + imageLines + [""]).joined(separator: "\n")
        try contents.write(to: project, atomically: true, encoding: .utf8)

        let errors = try HuginToolchain.live().controlPointErrors(
            in: project,
            points: remapped.map(\.projected)
        )
        let finite = errors.filter(\.isFinite).sorted()
        guard !finite.isEmpty else { return [] }
        let median = finite[finite.count / 2]
        // 40 px on the 4000 px equirectangular canvas is 3.6 degrees.
        // Permit a wider band when the whole pair exhibits handheld
        // parallax, but never let the prior become effectively unbounded.
        let threshold = min(max(40, median * 3), 120)
        return zip(remapped, errors).compactMap { entry, error in
            error.isFinite && error <= threshold ? entry.original : nil
        }
    }
}
