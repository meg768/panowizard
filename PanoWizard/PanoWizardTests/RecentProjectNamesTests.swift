import Foundation
import Testing
@testable import PanoWizard

@Suite("Project window names")
struct RecentProjectNamesTests {
    @Test("Same project filenames include the shortest unique parent path")
    func duplicateFilenamesUseUniquePathSuffixes() {
        let urls = [
            URL(fileURLWithPath: "/Users/example/Trips/Paris/panorama.pw"),
            URL(fileURLWithPath: "/Users/example/Trips/Rome/panorama.pw")
        ]

        #expect(RecentProjectNames.titles(for: urls) == [
            "Paris/panorama.pw",
            "Rome/panorama.pw"
        ])
    }
}
