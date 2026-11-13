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
            throw PublishError.message("Enter a hostname, port (1–65535), username, remote directory and a valid HTML filename.")
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
            throw PublishError.message("Filename must be relative to Remote Directory. For example, enter 2019/Toscana/panorama.html.")
        }
        let components = path.split(separator: "/").map(String.init)
        guard !components.contains(".."), !components.contains(".") else {
            throw PublishError.message("Filename cannot contain . or .. path components.")
        }
        return components
    }

    static func publishDestination(
        _ input: String, defaultFilename: String
    ) throws -> (path: String, filename: String) {
        let value = input.trimmingCharacters(in: .whitespaces)
        if value.isEmpty { return ("", defaultFilename) }
        guard !value.hasSuffix("/") else {
            throw PublishError.message("Enter a filename after the last slash.")
        }
        let components = try subdirectories(value)
        guard let name = components.last else {
            throw PublishError.message("Enter a filename.")
        }
        let path = components.dropLast().joined(separator: "/")
        if name.lowercased().hasSuffix(".html") { return (path, name) }
        guard (name as NSString).pathExtension.isEmpty else {
            throw PublishError.message("Use the .html file extension or leave it out.")
        }
        return (path, name + ".html")
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
    private struct ThumbnailUploadError: LocalizedError {
        let underlying: any Error
        var errorDescription: String? {
            "HTML published successfully, but thumbnail publishing did not complete. \(underlying.localizedDescription)"
        }
    }

    static func upload(
        htmlURL: URL, thumbnailURL: URL, connection: SFTPConnection, filename: String, subdirectory: String = "",
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
                    throw PublishError.message("The filename resolves outside Remote Directory. Choose another destination.")
                }
                let attributes = try await sftp.getAttributes(at: resolved)
                guard let permissions = attributes.permissions, permissions & 0o170000 == 0o040000 else {
                    throw PublishError.message("“\(component)” in Filename is not a directory.")
                }
                directory = resolved
            }
            let prefix = directory.hasSuffix("/") ? directory : directory + "/"
            let htmlPath = prefix + filename
            let jpegPath = prefix + String(filename.dropLast(5)) + ".jpg"
            let htmlExists = try await remoteFileExists(htmlPath, inside: base, sftp: sftp)
            if htmlExists, !(await confirmOverwrite()) {
                throw CancellationError()
            }
            let jpegExists = try await remoteFileExists(jpegPath, inside: base, sftp: sftp)
            try await writeFile(htmlURL, to: htmlPath, replacing: htmlExists, sftp: sftp)
            do {
                try await uploadThumbnail(thumbnailURL, to: jpegPath, directoryPrefix: prefix,
                                          replacing: jpegExists, sftp: sftp)
            } catch {
                throw ThumbnailUploadError(underlying: error)
            }
            try await sftp.close()
            try await client.close()
        } catch {
            try? await client.close()
            if error is CancellationError || error is ThumbnailUploadError { throw error }
            throw PublishError.message("SFTP upload failed. Check the remote directory and write permissions. \(error.localizedDescription)")
        }
    }

    private static func remoteFileExists(_ path: String, inside base: String, sftp: SFTPClient) async throws -> Bool {
        do {
            _ = try await sftp.getAttributes(at: path)
            let resolved = try await sftp.getRealPath(atPath: path)
            let prefix = base.hasSuffix("/") ? base : base + "/"
            guard resolved.hasPrefix(prefix) else {
                throw PublishError.message("Destination resolves outside Remote Directory.")
            }
            return true
        } catch let status as SFTPMessage.Status where status.errorCode == .noSuchFile {
            return false
        }
    }

    private static func writeFile(_ localURL: URL, to path: String, replacing: Bool, sftp: SFTPClient) async throws {
        let flags: SFTPOpenFileFlags = replacing ? [.write, .create, .truncate] : [.write, .create, .forceCreate]
        try await sftp.withFile(filePath: path, flags: flags) { file in
            let input = try FileHandle(forReadingFrom: localURL)
            defer { try? input.close() }
            var offset: UInt64 = 0
            while let chunk = try input.read(upToCount: 32_768), !chunk.isEmpty {
                try Task.checkCancellation()
                try await file.write(ByteBuffer(bytes: chunk), at: offset)
                offset += UInt64(chunk.count)
            }
        }
    }

    private static func uploadThumbnail(_ localURL: URL, to path: String, directoryPrefix: String,
                                        replacing: Bool, sftp: SFTPClient) async throws {
        let staging = directoryPrefix + ".panowizard-" + UUID().uuidString + ".upload"
        let backup = directoryPrefix + ".panowizard-" + UUID().uuidString + ".backup"
        do {
            try await writeFile(localURL, to: staging, replacing: false, sftp: sftp)
            if replacing { try await sftp.rename(at: path, to: backup) }
            do {
                try await sftp.rename(at: staging, to: path)
            } catch {
                if replacing {
                    do { try await sftp.rename(at: backup, to: path) }
                    catch { throw PublishError.message("Thumbnail replacement failed. The previous JPEG is preserved at \(backup).") }
                }
                throw error
            }
            if replacing { try? await sftp.remove(at: backup) }
        } catch {
            try? await sftp.remove(at: staging)
            throw error
        }
    }
}
