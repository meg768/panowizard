import Foundation

guard CommandLine.arguments.count == 4 else {
    fputs("usage: import_ptgui_project PTGUI.pts TEMPLATE.pw OUTPUT.pw\n", stderr)
    exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let templateURL = URL(fileURLWithPath: CommandLine.arguments[2])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[3])
let fileManager = FileManager.default
guard !fileManager.fileExists(atPath: outputURL.path) else {
    fputs("output already exists: \(outputURL.path)\n", stderr)
    exit(1)
}

func object(at url: URL) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        as! [String: Any]
}

var template = try object(
    at: templateURL.appending(path: "project.json")
)
let ptgui = try object(at: sourceURL)
let project = ptgui["project"] as! [String: Any]
let groups = project["imagegroups"] as! [[String: Any]]
let templateImages = template["images"] as! [[String: Any]]
let templateByName = Dictionary(uniqueKeysWithValues: templateImages.map {
    image -> (String, [String: Any]) in
    let url = URL(string: image["url"] as! String)!
    return (url.lastPathComponent, image)
})
let prototype = templateImages[0]
let sourceDirectory = sourceURL.deletingLastPathComponent()

var images: [[String: Any]] = []
for group in groups {
    let groupImages = group["images"] as! [[String: Any]]
    for sourceImage in groupImages {
        let filename = sourceImage["filename"] as! String
        var image: [String: Any]
        if let existing = templateByName[filename] {
            image = existing
        } else {
            let fileURL = sourceDirectory.appending(path: filename)
            guard fileManager.fileExists(atPath: fileURL.path) else {
                throw NSError(
                    domain: "PTGuiImport",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Missing image: \(filename)"]
                )
            }
            image = prototype
            image["id"] = UUID().uuidString
            image["url"] = fileURL.absoluteString
            image.removeValue(forKey: "captureDate")
        }
        image["direction"] = "horizontal"
        image["role"] = "alignment"
        images.append(image)
    }
}

let sourcePoints = project["controlpoints"] as! [[String: Any]]
let points: [[String: Any]] = sourcePoints.map { sourcePoint in
    let first = sourcePoint["0"] as! [NSNumber]
    let second = sourcePoint["1"] as! [NSNumber]
    return [
        "id": UUID().uuidString,
        "firstImage": first[0].intValue,
        "secondImage": second[0].intValue,
        "firstX": first[2].doubleValue,
        "firstY": first[3].doubleValue,
        "secondX": second[2].doubleValue,
        "secondY": second[3].doubleValue
    ]
}

template["id"] = UUID().uuidString
template["title"] = "PTGui"
template["createdAt"] = ISO8601DateFormatter().string(from: Date())
template["modifiedAt"] = ISO8601DateFormatter().string(from: Date())
template["images"] = images
template["controlPoints"] = points
template.removeValue(forKey: "controlPointMaskSignature")

try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: false)
let data = try JSONSerialization.data(
    withJSONObject: template,
    options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
)
try data.write(to: outputURL.appending(path: "project.json"), options: .atomic)
print("images=\(images.count) controlPoints=\(points.count)")
