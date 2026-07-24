import Foundation
import Testing
@testable import PanoWizard

struct PanoramaEngineIntegrationTests {
    @Test
    func stitchesConfiguredProjectWhenRequested() async throws {
        guard let packagePath = ProcessInfo.processInfo.environment[
            "PANOWIZARD_INTEGRATION_PROJECT"
        ] else {
            return
        }

        let package = URL(fileURLWithPath: packagePath)
        let projectData = try Data(
            contentsOf: package.appending(path: "project.json")
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let project = try decoder.decode(PanoProject.self, from: projectData)
        let masksDirectory = package.appending(
            path: "masks",
            directoryHint: .isDirectory
        )
        var masks: [UUID: Data] = [:]
        if let files = try? FileManager.default.contentsOfDirectory(
            at: masksDirectory,
            includingPropertiesForKeys: nil
        ) {
            for file in files where file.pathExtension.lowercased() == "png" {
                guard let id = UUID(
                    uuidString: file.deletingPathExtension().lastPathComponent
                ) else {
                    continue
                }
                masks[id] = try Data(contentsOf: file)
            }
        }

        let result = try await HuginOpenCVPanoramaEngine().stitch(
            project.panorama,
            masks: masks,
            configuration: project.stitching,
            cachedRigImageLines: [:]
        )

        #expect(FileManager.default.fileExists(atPath: result.url.path()))
        #expect((try Data(contentsOf: result.url)).count > 100_000)
        print("PANOWIZARD_INTEGRATION_RESULT=\(result.url.path())")
    }
}
