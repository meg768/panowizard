import Foundation

enum CubeMapError: LocalizedError, Equatable {
    case invalidDimensions(expectedWidth: Int, expectedHeight: Int, width: Int, height: Int)
    case invalidPanoramaDimensions(width: Int, height: Int)
    case incompleteFace

    var errorDescription: String? {
        switch self {
        case let .invalidDimensions(expectedWidth, expectedHeight, width, height):
            "Kubkartan måste vara \(expectedWidth) × \(expectedHeight) px, men bilden är \(width) × \(height) px."
        case let .invalidPanoramaDimensions(width, height):
            "Panoramat måste ha proportionen 2:1, men bilden är \(width) × \(height) px."
        case .incompleteFace:
            "En eller flera kubsidor har flyttats, roterats eller blivit transparenta. "
                + "Redigera bildinnehållet utan att ändra kubsidornas placering."
        }
    }
}

struct CubeMapService: Sendable {
    static let faceSize = 2_048
    static let columns = 4
    static let rows = 3

    private enum Face: CaseIterable {
        case left, front, right, back, zenith, nadir

        var tile: (column: Int, row: Int) {
            switch self {
            case .left: (0, 1)
            case .front: (1, 1)
            case .right: (2, 1)
            case .back: (3, 1)
            case .zenith: (1, 0)
            case .nadir: (1, 2)
            }
        }

        func direction(u: Double, v: Double) -> (x: Double, y: Double, z: Double) {
            switch self {
            case .left: (-1, -v, u)
            case .front: (u, -v, 1)
            case .right: (1, -v, -u)
            case .back: (-u, -v, -1)
            case .zenith: (u, 1, v)
            case .nadir: (u, -1, -v)
            }
        }
    }

    func exportMap(
        panoramaURL: URL,
        nadirOverlayURL: URL?,
        zenithOverlayURL: URL?,
        nadirRetouchURL: URL?,
        zenithRetouchURL: URL?,
        to destinationURL: URL,
        faceSize: Int = Self.faceSize
    ) throws {
        let hasLayers = nadirOverlayURL != nil || zenithOverlayURL != nil
            || nadirRetouchURL != nil || zenithRetouchURL != nil
        let flattenedURL = FileManager.default.temporaryDirectory.appending(
            path: "\(UUID().uuidString)-cube-map-source.png"
        )
        if hasLayers {
            try PoleRetouchService().flattenPanorama(
                panoramaURL: panoramaURL,
                nadirOverlayURL: nadirOverlayURL,
                zenithOverlayURL: zenithOverlayURL,
                nadirRetouchURL: nadirRetouchURL,
                zenithRetouchURL: zenithRetouchURL,
                to: flattenedURL
            )
        }
        defer {
            if hasLayers { try? FileManager.default.removeItem(at: flattenedURL) }
        }

        let panorama = try RGBAImage(
            contentsOf: hasLayers ? flattenedURL : panoramaURL
        )
        guard panorama.width == panorama.height * 2 else {
            throw CubeMapError.invalidPanoramaDimensions(
                width: panorama.width,
                height: panorama.height
            )
        }
        var map = RGBAImage(
            width: faceSize * Self.columns,
            height: faceSize * Self.rows
        )
        for face in Face.allCases {
            let tile = face.tile
            for y in 0..<faceSize {
                if Task.isCancelled { throw CancellationError() }
                let v = 2 * (Double(y) + 0.5) / Double(faceSize) - 1
                for x in 0..<faceSize {
                    let u = 2 * (Double(x) + 0.5) / Double(faceSize) - 1
                    let direction = face.direction(u: u, v: v)
                    let length = sqrt(
                        direction.x * direction.x
                            + direction.y * direction.y
                            + direction.z * direction.z
                    )
                    let longitude = atan2(direction.x, direction.z)
                    let latitude = asin(direction.y / length)
                    var pixel = panorama.sample(
                        x: 0.5 + longitude / (2 * .pi),
                        y: 0.5 - latitude / .pi,
                        wrappingX: true
                    )
                    pixel.a = 1
                    map.setPixel(
                        pixel,
                        x: tile.column * faceSize + x,
                        y: tile.row * faceSize + y
                    )
                }
            }
        }
        try map.writePNG(to: destinationURL)
    }

    func importMap(
        from sourceURL: URL,
        panoramaURL: URL,
        to destinationURL: URL,
        faceSize: Int = Self.faceSize
    ) throws {
        let map = try RGBAImage(contentsOf: sourceURL)
        let expectedWidth = faceSize * Self.columns
        let expectedHeight = faceSize * Self.rows
        guard map.width == expectedWidth, map.height == expectedHeight else {
            throw CubeMapError.invalidDimensions(
                expectedWidth: expectedWidth,
                expectedHeight: expectedHeight,
                width: map.width,
                height: map.height
            )
        }
        try Self.validateFaceCoverage(map, faceSize: faceSize)
        let panoramaSize = try RGBAImage(contentsOf: panoramaURL)
        guard panoramaSize.width == panoramaSize.height * 2 else {
            throw CubeMapError.invalidPanoramaDimensions(
                width: panoramaSize.width,
                height: panoramaSize.height
            )
        }
        var panorama = RGBAImage(
            width: panoramaSize.width,
            height: panoramaSize.height
        )
        for y in 0..<panorama.height {
            if Task.isCancelled { throw CancellationError() }
            let latitude = (
                0.5 - (Double(y) + 0.5) / Double(panorama.height)
            ) * .pi
            let directionY = sin(latitude)
            let horizontalRadius = cos(latitude)
            for x in 0..<panorama.width {
                let longitude = (
                    (Double(x) + 0.5) / Double(panorama.width) - 0.5
                ) * 2 * .pi
                let directionX = sin(longitude) * horizontalRadius
                let directionZ = cos(longitude) * horizontalRadius
                let coordinate = Self.faceCoordinate(
                    x: directionX,
                    y: directionY,
                    z: directionZ
                )
                var pixel = Self.sample(
                    map,
                    face: coordinate.face,
                    u: coordinate.u,
                    v: coordinate.v,
                    faceSize: faceSize
                )
                pixel.a = 1
                panorama.setPixel(pixel, x: x, y: y)
            }
        }
        try panorama.writePNG(to: destinationURL)
    }

    private static func validateFaceCoverage(
        _ map: RGBAImage,
        faceSize: Int
    ) throws {
        for face in Face.allCases {
            let tile = face.tile
            let originX = tile.column * faceSize
            let originY = tile.row * faceSize
            for y in originY..<(originY + faceSize) {
                for x in originX..<(originX + faceSize) {
                    guard map.pixel(x: x, y: y).a == 1 else {
                        throw CubeMapError.incompleteFace
                    }
                }
            }
        }
    }

    private static func faceCoordinate(
        x: Double,
        y: Double,
        z: Double
    ) -> (face: Face, u: Double, v: Double) {
        let absoluteX = abs(x)
        let absoluteY = abs(y)
        let absoluteZ = abs(z)
        if absoluteY >= absoluteX, absoluteY >= absoluteZ {
            if y >= 0 { return (.zenith, x / absoluteY, z / absoluteY) }
            return (.nadir, x / absoluteY, -z / absoluteY)
        }
        if absoluteX >= absoluteZ {
            if x >= 0 { return (.right, -z / absoluteX, -y / absoluteX) }
            return (.left, z / absoluteX, -y / absoluteX)
        }
        if z >= 0 { return (.front, x / absoluteZ, -y / absoluteZ) }
        return (.back, -x / absoluteZ, -y / absoluteZ)
    }

    private static func sample(
        _ map: RGBAImage,
        face: Face,
        u: Double,
        v: Double,
        faceSize: Int
    ) -> Pixel {
        let tile = face.tile
        let originX = tile.column * faceSize
        let originY = tile.row * faceSize
        let imageX = Double(originX) + (u + 1) * 0.5 * Double(faceSize) - 0.5
        let imageY = Double(originY) + (v + 1) * 0.5 * Double(faceSize) - 0.5
        let x0 = Int(floor(imageX))
        let y0 = Int(floor(imageY))
        let fractionX = imageX - Double(x0)
        let fractionY = imageY - Double(y0)

        func pixel(_ x: Int, _ y: Int) -> Pixel {
            map.pixel(
                x: min(max(x, originX), originX + faceSize - 1),
                y: min(max(y, originY), originY + faceSize - 1)
            )
        }
        let topLeft = pixel(x0, y0)
        let topRight = pixel(x0 + 1, y0)
        let bottomLeft = pixel(x0, y0 + 1)
        let bottomRight = pixel(x0 + 1, y0 + 1)

        func interpolate(_ keyPath: KeyPath<Pixel, Double>) -> Double {
            let top = topLeft[keyPath: keyPath] * (1 - fractionX)
                + topRight[keyPath: keyPath] * fractionX
            let bottom = bottomLeft[keyPath: keyPath] * (1 - fractionX)
                + bottomRight[keyPath: keyPath] * fractionX
            return top * (1 - fractionY) + bottom * fractionY
        }
        return Pixel(
            r: interpolate(\.r),
            g: interpolate(\.g),
            b: interpolate(\.b),
            a: interpolate(\.a)
        )
    }
}
