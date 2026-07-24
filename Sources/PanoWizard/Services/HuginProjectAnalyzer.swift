import Foundation

struct HuginImageOrientation: Equatable, Sendable {
    let index: Int
    let width: Int
    let height: Int
    let pitch: Double
}

struct HuginProjectAnalysis: Equatable, Sendable {
    let images: [HuginImageOrientation]

    var nadirImages: [HuginImageOrientation] {
        images.filter { $0.pitch < -70 }
    }
}

enum HuginProjectAnalyzer {
    static func analyze(_ projectURL: URL) throws -> HuginProjectAnalysis {
        analyze(try String(contentsOf: projectURL, encoding: .utf8))
    }

    static func analyze(_ contents: String) -> HuginProjectAnalysis {
        let imageLines = contents.split(separator: "\n").filter {
            $0.hasPrefix("i ")
        }

        let images: [HuginImageOrientation] = imageLines.enumerated().compactMap {
            index,
            line in
            guard let width = integer(named: "w", in: line),
                  let height = integer(named: "h", in: line),
                  let pitch = number(named: "p", in: line) else {
                return nil
            }
            return HuginImageOrientation(
                index: index,
                width: width,
                height: height,
                pitch: pitch
            )
        }
        return HuginProjectAnalysis(images: images)
    }

    private static func integer(
        named name: String,
        in line: Substring
    ) -> Int? {
        number(named: name, in: line).map { Int($0) }
    }

    private static func number(
        named name: String,
        in line: Substring
    ) -> Double? {
        let pattern = "(?:^|\\s)\(name)(-?[0-9]+(?:\\.[0-9]+)?)"
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let string = String(line)
        let range = NSRange(string.startIndex..., in: string)
        guard let match = expression.firstMatch(in: string, range: range),
              let valueRange = Range(match.range(at: 1), in: string) else {
            return nil
        }
        return Double(string[valueRange])
    }
}
