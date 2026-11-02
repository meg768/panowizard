import Foundation
import Testing
import Citadel
@testable import PanoWizard

// Integration fixture: PanoWizard/TestSupport/sftp_server.py (development only).
struct SFTPPublisherTests {
    @Test("Connection setup persists one local configuration including credentials")
    func savedConnection() throws {
        let defaults = UserDefaults(suiteName: "SFTPPublisherTests-\(UUID())")!
        #expect(SFTPConnection.load(from: defaults).port == 22)
        #expect(SFTPConnection.load(from: defaults).hostname.isEmpty)
        var connection = SFTPConnection()
        connection.hostname = "example.com"
        connection.username = "publisher"
        connection.password = "local-test-password"
        connection.remoteDirectory = "/www/panoramas"
        try connection.save(to: defaults)
        #expect(SFTPConnection.load(from: defaults) == connection)
        // Configurations saved before the URL field must keep their credentials.
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(connection)) as! [String: Any]
        legacy.removeValue(forKey: "publicBaseURL")
        defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: SFTPConnection.preferencesKey)
        #expect(SFTPConnection.load(from: defaults) == connection)
        connection.publicBaseURL = "https://example.com/gallery"
        try connection.save(to: defaults)
        #expect(SFTPConnection.load(from: defaults) == connection)
        connection.username = "replacement"
        try connection.save(to: defaults)
        #expect(SFTPConnection.load(from: defaults).username == "replacement")
        defaults.removeObject(forKey: SFTPConnection.preferencesKey)
    }

    @Test("Optional paths stay relative and cannot traverse outside the base directory")
    func paths() throws {
        #expect(try SFTPConnection.subdirectories("") == [])
        #expect(try SFTPConnection.subdirectories("2019/Toscana") == ["2019", "Toscana"])
        #expect(try SFTPConnection.subdirectories("A/B/C/D") == ["A", "B", "C", "D"])
        for invalid in ["../outside", "A/../../B", "/absolute", "A/./B", "A\\B", "A\nB"] {
            #expect(throws: (any Error).self) { try SFTPConnection.subdirectories(invalid) }
        }
        #expect(SFTPConnection.defaultFilename(" My/Project ") == "My-Project.html")
    }

    @Test("Pasted web addresses normalize to an SFTP hostname without a public URL")
    func hostname() throws {
        var connection = SFTPConnection()
        connection.hostname = " http://server.example.com/ "
        connection.username = "publisher"
        connection.remoteDirectory = "/var/www/html/panorama"
        #expect(connection.serverHostname == "server.example.com")
        try connection.validate(filename: "test.html", subdirectory: "2019/Toscana")
        connection.hostname = "https://server.example.com"
        #expect(connection.serverHostname == "server.example.com")
        #expect(throws: (any Error).self) { try connection.validate(filename: "../test.html") }
    }

    @Test("Public URLs append encoded folder and filename components without changing the base path")
    func publicURLs() throws {
        var connection = SFTPConnection()
        connection.hostname = "sftp.example.com"
        connection.username = "publisher"
        connection.remoteDirectory = "/var/www/html/panoramas"
        for base in ["https://example.com/gallery", "https://example.com/gallery/"] {
            connection.publicBaseURL = base
            #expect(try connection.publicURL(filename: "panorama.html")?.absoluteString == "https://example.com/gallery/panorama.html")
            #expect(try connection.publicURL(filename: "Räksmörgås #1? 100%.html", subdirectory: "2019/Öland & Åre")?.absoluteString
                == "https://example.com/gallery/2019/%C3%96land%20%26%20%C3%85re/R%C3%A4ksm%C3%B6rg%C3%A5s%20%231%3F%20100%25.html")
        }
        connection.publicBaseURL = "https://example.com/redan%20kodad/"
        #expect(try connection.publicURL(filename: "åäö.html", subdirectory: "A/B/C/D")?.absoluteString
            == "https://example.com/redan%20kodad/A/B/C/D/%C3%A5%C3%A4%C3%B6.html")
        connection.publicBaseURL = "https://example.com"
        #expect(try connection.publicURL(filename: "panorama.html")?.absoluteString == "https://example.com/panorama.html")
        for empty in ["", "   ", "\n\t"] {
            connection.publicBaseURL = empty
            #expect(try connection.publicURL(filename: "panorama.html", subdirectory: "2019/Toscana") == nil)
        }
        for invalid in ["example.com", "ftp://example.com", "https://example.com/?x=1", "https://example.com/#part", "https://user:password@example.com"] {
            connection.publicBaseURL = invalid
            #expect(throws: (any Error).self) { try connection.publicURL(filename: "panorama.html") }
        }
    }

    @Test("SFTP uploads, rejects bad credentials, asks before replacing and reports unreachable servers",
          .enabled(if: ProcessInfo.processInfo.environment["PANOWIZARD_SFTP_TEST"] == "1"))
    func localServer() async throws {
        var connection = SFTPConnection()
        connection.hostname = "127.0.0.1"
        connection.port = 22229
        connection.username = "publisher"
        connection.password = "test-password"
        connection.remoteDirectory = "/"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).html")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("first panorama".utf8).write(to: url)
        let name = "test-\(UUID()).html"
        try await SFTPPublisher.upload(localURL: url, connection: connection, filename: name,
                                      verifyHost: { _ in }, confirmOverwrite: { Issue.record("Unexpected overwrite"); return false })
        try Data("replacement panorama".utf8).write(to: url)
        do {
            try await SFTPPublisher.upload(localURL: url, connection: connection, filename: name,
                                          verifyHost: { _ in }, confirmOverwrite: { false })
            Issue.record("Overwrite cancellation did not stop upload")
        } catch is CancellationError { }
        try await SFTPPublisher.upload(localURL: url, connection: connection, filename: name,
                                      verifyHost: { _ in }, confirmOverwrite: { true })
        // A real nested upload must create every missing directory and preserve the filename.
        connection.remoteDirectory = "/base"
        let nested = "2019/Toscana/\(UUID())/A/B/C/D"
        try await SFTPPublisher.upload(localURL: url, connection: connection, filename: name, subdirectory: nested,
                                      verifyHost: { _ in }, confirmOverwrite: { false })
        // Reuse all existing directories and overwrite only after confirmation.
        try await SFTPPublisher.upload(localURL: url, connection: connection, filename: name, subdirectory: nested,
                                      verifyHost: { _ in }, confirmOverwrite: { true })
        let reader = try await SSHClient.connect(host: connection.hostname, port: connection.port,
            authenticationMethod: .passwordBased(username: connection.username, password: connection.password),
            hostKeyValidator: .acceptAnything(), reconnect: .never)
        do {
            let sftp = try await reader.openSFTP()
            let data = try await sftp.withFile(filePath: "/base/\(nested)/\(name)", flags: .read) { file in
                try await file.read(length: 128)
            }
            #expect(String(decoding: data.readableBytesView, as: UTF8.self) == "replacement panorama")
            try await reader.close()
        } catch { try? await reader.close(); throw error }
        for path in ["denied/child", "not-a-directory/child", "escape/child"] {
            do {
                try await SFTPPublisher.upload(localURL: url, connection: connection, filename: name, subdirectory: path,
                                              verifyHost: { _ in }, confirmOverwrite: { false })
                Issue.record("Invalid directory was accepted: \(path)")
            } catch { #expect(error.localizedDescription.contains("SFTP upload failed")) }
        }
        connection.password = "incorrect"
        do {
            try await SFTPPublisher.upload(localURL: url, connection: connection, filename: name,
                                          verifyHost: { _ in }, confirmOverwrite: { false })
            Issue.record("Incorrect password was accepted")
        } catch { #expect(error.localizedDescription.contains("Authentication")) }
        connection.port = 22230
        do {
            try await SFTPPublisher.upload(localURL: url, connection: connection, filename: name,
                                          verifyHost: { _ in }, confirmOverwrite: { false })
            Issue.record("Unreachable server was accepted")
        } catch { #expect(error.localizedDescription.contains("Could not connect")) }
    }
}
