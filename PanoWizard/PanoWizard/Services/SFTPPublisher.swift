import Foundation
import Citadel
import NIOCore
import NIOSSH

struct SFTPConnection: Codable, Equatable, Sendable {
    var hostname = ""
    var port = 22
    var username = ""
    var password = ""
    var remoteDirectory = ""
    var publicBaseURL = ""
    var hostKey: String?

    private enum CodingKeys: String, CodingKey {
        case hostname, port, username, password, remoteDirectory, publicBaseURL, hostKey
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        hostname = try values.decode(String.self, forKey: .hostname)
        port = try values.decode(Int.self, forKey: .port)
        username = try values.decode(String.self, forKey: .username)
        password = try values.decode(String.self, forKey: .password)
        remoteDirectory = try values.decode(String.self, forKey: .remoteDirectory)
        publicBaseURL = try values.decodeIfPresent(String.self, forKey: .publicBaseURL) ?? ""
        hostKey = try values.decodeIfPresent(String.self, forKey: .hostKey)
    }

    static let preferencesKey = "sftpPublishConnection"

    static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: preferencesKey),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }

    func save(to defaults: UserDefaults = .standard) throws {
        defaults.set(try JSONEncoder().encode(self), forKey: Self.preferencesKey)
    }

    var serverHostname: String {
        let value = hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parts = URLComponents(string: value),
           ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
           let host = parts.host { return host }
        return value
    }

    func validate(filename: String, subdirectory: String = "") throws {
        guard !serverHostname.isEmpty, !serverHostname.contains("/"),
              !serverHostname.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) }),
              (1...65535).contains(port), !username.isEmpty, !remoteDirectory.isEmpty,
              !remoteDirectory.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !filename.isEmpty, filename != ".", filename != "..",
              !filename.contains("/"), !filename.contains("\\"),
              !filename.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              filename.lowercased().hasSuffix(".html") else {
            throw PublishError.message("Enter a hostname, port (1–65535), username, remote directory and an HTML filename without path separators.")
        }
        _ = try Self.subdirectories(subdirectory)
    }

    func publicURL(filename: String, subdirectory: String = "") throws -> URL? {
        try validate(filename: filename, subdirectory: subdirectory)
        let address = publicBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return nil }
        guard var url = URLComponents(string: address),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw PublishError.message("Enter a Public Base URL starting with http:// or https://, without a query or fragment.")
        }
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let components = try Self.subdirectories(subdirectory) + [filename]
        let suffix = components.map { $0.addingPercentEncoding(withAllowedCharacters: unreserved)! }.joined(separator: "/")
        url.percentEncodedPath += (url.percentEncodedPath.hasSuffix("/") ? "" : "/") + suffix
        guard let result = url.url else { throw PublishError.message("The public panorama URL is invalid.") }
        return result
    }

    static func subdirectories(_ path: String) throws -> [String] {
        guard !path.hasPrefix("/"), !path.contains("\\"),
              !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw PublishError.message("Path must be relative to Remote Directory, for example 2019/Toscana.")
        }
        let components = path.split(separator: "/").map(String.init)
        guard !components.contains(".."), !components.contains(".") else {
            throw PublishError.message("Path cannot contain . or .. directory components.")
        }
        return components
    }

    static func defaultFilename(_ title: String) -> String {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: CharacterSet(charactersIn: "/\\").union(.controlCharacters))
            .joined(separator: "-")
        return (name.isEmpty ? "panorama" : name) + ".html"
    }
}

enum PublishError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { text } else { nil } }
}

private struct PublishHostValidator: NIOSSHClientServerAuthenticationDelegate {
    let verify: @Sendable (String) async throws -> Void

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let key = String(openSSHPublicKey: hostKey)
        validationCompletePromise.completeWithTask { try await verify(key) }
    }
}

enum SFTPPublisher {
    static func upload(
        localURL: URL, connection: SFTPConnection, filename: String, subdirectory: String = "",
        thumbnail: Bool = false,
        verifyHost: @escaping @Sendable (String) async throws -> Void,
        confirmOverwrite: @escaping @Sendable () async -> Bool
    ) async throws {
        try connection.validate(filename: filename, subdirectory: subdirectory)
        let client: SSHClient
        do {
            client = try await SSHClient.connect(
                host: connection.serverHostname, port: connection.port,
                authenticationMethod: .passwordBased(username: connection.username, password: connection.password),
                hostKeyValidator: .custom(PublishHostValidator(verify: verifyHost)),
                reconnect: .never, connectTimeout: .seconds(15)
            )
        } catch let error as PublishError { throw error }
        catch is AuthenticationFailed {
            throw PublishError.message("Authentication failed. Check the username and password.")
        } catch SSHClientError.allAuthenticationOptionsFailed {
            throw PublishError.message("Authentication failed. Check the username and password.")
        } catch SSHClientError.unsupportedPasswordAuthentication {
            throw PublishError.message("Authentication failed. This server does not allow password authentication.")
        } catch {
            throw PublishError.message("Could not connect to \(connection.hostname):\(connection.port). Check the server address, network and SSH access. \(error.localizedDescription)")
        }
        do {
            let sftp = try await client.openSFTP()
            let base = try await sftp.getRealPath(atPath: connection.remoteDirectory)
            var directory = base
            for component in try SFTPConnection.subdirectories(subdirectory) {
                let next = (directory.hasSuffix("/") ? directory : directory + "/") + component
                do { _ = try await sftp.getAttributes(at: next) }
                catch let status as SFTPMessage.Status where status.errorCode == .noSuchFile {
                    try await sftp.createDirectory(atPath: next)
                }
                let resolved = try await sftp.getRealPath(atPath: next)
                let prefix = base.hasSuffix("/") ? base : base + "/"
                guard resolved == base || resolved.hasPrefix(prefix) else {
                    throw PublishError.message("Path resolves outside Remote Directory. Choose another path.")
                }
                let attributes = try await sftp.getAttributes(at: resolved)
                guard let permissions = attributes.permissions, permissions & 0o170000 == 0o040000 else {
                    throw PublishError.message("A component of Path is not a directory: \(component)")
                }
                directory = resolved
            }
            let remoteName = thumbnail ? String(filename.dropLast(5)) + ".jpg" : filename
            let path = (directory.hasSuffix("/") ? directory : directory + "/") + remoteName
            var exists = false
            do {
                _ = try await sftp.getAttributes(at: path)
                let resolved = try await sftp.getRealPath(atPath: path)
                let prefix = base.hasSuffix("/") ? base : base + "/"
                guard resolved.hasPrefix(prefix) else {
                    throw PublishError.message("Destination resolves outside Remote Directory.")
                }
                exists = true
            }
            catch let status as SFTPMessage.Status where status.errorCode == .noSuchFile { }
            if exists, !(await confirmOverwrite()) {
                try await client.close()
                throw CancellationError()
            }
            let staging = thumbnail ? directory + "/.panowizard-" + UUID().uuidString + ".upload" : path
            let backup = directory + "/.panowizard-" + UUID().uuidString + ".backup"
            var backedUp = false
            do {
                let flags: SFTPOpenFileFlags = !thumbnail && exists ? [.write, .create, .truncate] : [.write, .create, .forceCreate]
                try await sftp.withFile(filePath: staging, flags: flags) { file in
                    let input = try FileHandle(forReadingFrom: localURL)
                    defer { try? input.close() }
                    var offset: UInt64 = 0
                    while let chunk = try input.read(upToCount: 32_768), !chunk.isEmpty {
                        try Task.checkCancellation()
                        try await file.write(ByteBuffer(bytes: chunk), at: offset)
                        offset += UInt64(chunk.count)
                    }
                }
                if thumbnail {
                    if exists {
                        try await sftp.rename(at: path, to: backup)
                        backedUp = true
                    }
                    do { try await sftp.rename(at: staging, to: path) }
                    catch {
                        if backedUp {
                            do { try await sftp.rename(at: backup, to: path); backedUp = false }
                            catch { throw PublishError.message("Thumbnail replacement failed. The previous JPEG is preserved at \(backup).") }
                        }
                        throw error
                    }
                    if backedUp { try? await sftp.remove(at: backup) }
                }
            } catch {
                if thumbnail { try? await sftp.remove(at: staging) }
                throw error
            }
            try await sftp.close()
            try await client.close()
        } catch {
            try? await client.close()
            if error is CancellationError { throw error }
            throw PublishError.message("SFTP upload failed. Check the remote directory and write permissions. \(error.localizedDescription)")
        }
    }
}
