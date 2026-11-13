import AppKit
import SwiftUI

struct PanoramaPublishView: View {
    @Environment(\.dismiss) private var dismiss
    let model: AppModel
    let size: HTMLPanoramaSize
    let jpegQuality: Double
    private let defaultFilename: String
    private let legacyDestination: (path: String, filename: String)?
    @State private var connection = SFTPConnection.load()
    @State private var filename: String
    @State private var uploadSucceeded = false
    @State private var publishedURL: URL?
    @State private var busy = false
    @State private var status = ""
    @State private var errorMessage: String?

    init(model: AppModel, projectName: String?, size: HTMLPanoramaSize, jpegQuality: Double) {
        self.model = model
        self.size = size
        self.jpegQuality = jpegQuality
        let project = model.project
        let defaults = UserDefaults.standard
        let legacyFilename = defaults.string(forKey: "sftpPublishFilename.\(project.id)")
        let legacyPath = defaults.string(forKey: "sftpPublishPath.\(project.id)")
        let defaultFilename = SFTPConnection.defaultFilename(projectName ?? project.title)
        let name = project.publishFilename ?? legacyFilename ?? defaultFilename
        let path = project.publishPath ?? legacyPath ?? ""
        self.defaultFilename = defaultFilename
        if (project.publishFilename == nil && legacyFilename != nil)
            || (project.publishPath == nil && legacyPath != nil) {
            legacyDestination = (path, name)
        } else {
            legacyDestination = nil
        }
        _filename = State(initialValue: Self.combinedFilename(name, path: path))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Publish Interactive Panorama").font(.headline)
            Form {
                TextField("Hostname", text: $connection.hostname)
                TextField("Port", value: $connection.port, format: .number.grouping(.never))
                TextField("Username", text: $connection.username)
                SecureField("Password", text: $connection.password)
                TextField("Remote Directory", text: $connection.remoteDirectory)
                TextField("Public Base URL", text: $connection.publicBaseURL)
                TextField("Filename", text: $filename)
                    .help("Enter a filename or include subfolders, such as 2019/Toscana/panorama. The .html extension is added automatically when omitted.")
            }
            .onChange(of: connection.hostname) { publishedURL = nil; uploadSucceeded = false }
            .onChange(of: connection.port) { publishedURL = nil; uploadSucceeded = false }
            .onChange(of: connection.username) { publishedURL = nil; uploadSucceeded = false }
            .onChange(of: connection.password) { publishedURL = nil; uploadSucceeded = false }
            .onChange(of: connection.remoteDirectory) { publishedURL = nil; uploadSucceeded = false }
            .onChange(of: connection.publicBaseURL) { publishedURL = nil; uploadSucceeded = false }
            .onChange(of: filename) { publishedURL = nil; uploadSucceeded = false }
            Text("Connection details are remembered when you publish. The password is stored locally without Keychain encryption.")
                .font(.caption).foregroundStyle(.secondary)
            if busy {
                HStack { ProgressView().controlSize(.small); Text(status) }
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red).textSelection(.enabled) }
            if uploadSucceeded {
                Label {
                    Text(successMessage(for: publishedURL))
                } icon: {
                    Image(systemName: "checkmark.circle")
                }
            }
            HStack {
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Publish") { publish() }.keyboardShortcut(.defaultAction)
                    .disabled(!model.canExportHTML)
            }
        }
        .padding(24).frame(width: 510)
        .disabled(busy)
        .interactiveDismissDisabled(busy)
        .onAppear {
            // Preserve destinations saved locally by earlier builds when moving them into the document.
            if let legacyDestination {
                model.project.setPublishDestination(
                    path: legacyDestination.path, filename: legacyDestination.filename
                )
            }
        }
    }

    private static func combinedFilename(_ filename: String, path: String) -> String {
        path.isEmpty || path.hasSuffix("/") ? path + filename : path + "/" + filename
    }

    private func successMessage(for url: URL?) -> AttributedString {
        var message = AttributedString("Uploaded successfully.")
        if let url {
            var link = AttributedString(" View Panorama")
            link.link = url
            message.append(link)
        }
        return message
    }

    private func publish() {
        guard let source = model.currentPanoramaURL else { return }
        let publicURL: URL?
        let destination: (path: String, filename: String)
        do {
            destination = try SFTPConnection.publishDestination(filename, defaultFilename: defaultFilename)
            connection.hostname = connection.serverHostname
            publicURL = try connection.publicURL(filename: destination.filename, subdirectory: destination.path)
            let saved = SFTPConnection.load()
            if saved.serverHostname != connection.hostname || saved.port != connection.port { connection.hostKey = nil }
            try connection.save()
            model.project.setPublishDestination(path: destination.path, filename: destination.filename)
        } catch { errorMessage = error.localizedDescription; return }
        let settings = connection
        let name = destination.filename
        let path = destination.path
        filename = Self.combinedFilename(name, path: path)
        let adjustments = model.panoramaAdjustments
        let title = model.project.title
        let viewpoint = model.panoramaViewpoint
        busy = true
        uploadSucceeded = false
        publishedURL = nil
        errorMessage = nil
        status = "Generating HTML…"
        Task { @MainActor in
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).html")
            let jpeg = temporary.deletingPathExtension().appendingPathExtension("jpg")
            defer { try? FileManager.default.removeItem(at: jpeg) }
            defer { try? FileManager.default.removeItem(at: temporary); busy = false }
            do {
                try await FilePanoramaExporter().exportHTML(
                    panoramaURL: source, adjustments: adjustments, title: title,
                    initialViewpoint: viewpoint, size: size, jpegQuality: jpegQuality, to: temporary
                )
                status = "Generating thumbnail…"
                try await PublishThumbnailRenderer.render(htmlURL: temporary, to: jpeg)
                status = "Connecting and uploading…"
                let verifyHost: @Sendable (String) async throws -> Void = { key in
                        try await MainActor.run {
                            if let trusted = SFTPConnection.load().hostKey ?? settings.hostKey {
                                guard trusted == key else { throw PublishError.message("The server’s SSH host key has changed. Publishing was stopped. Verify the server before publishing again.") }
                            } else {
                                let alert = NSAlert()
                                alert.messageText = "Trust this SFTP server?"
                                alert.informativeText = "Verify this SSH public key with your server administrator before continuing.\n\n\(settings.hostname):\(settings.port)\n\(key)"
                                alert.addButton(withTitle: "Trust and Continue")
                                alert.addButton(withTitle: "Cancel")
                                guard alert.runModal() == .alertFirstButtonReturn else { throw PublishError.message("Server trust was not approved.") }
                                var pinned = settings
                                pinned.hostKey = key
                                try pinned.save()
                            }
                        }
                    }
                let confirm: @Sendable () async -> Bool = {
                    await MainActor.run {
                        let alert = NSAlert()
                        alert.messageText = "Replace published panorama?"
                        alert.informativeText = "“\(name)” already exists on \(settings.hostname). Replace updates the HTML file and its JPEG thumbnail."
                        alert.addButton(withTitle: "Replace")
                        alert.addButton(withTitle: "Cancel")
                        return alert.runModal() == .alertFirstButtonReturn
                    }
                }
                try await SFTPPublisher.upload(
                    htmlURL: temporary, thumbnailURL: jpeg, connection: settings, filename: name, subdirectory: path,
                    verifyHost: verifyHost, confirmOverwrite: confirm
                )
                connection = SFTPConnection.load()
                publishedURL = publicURL
                uploadSucceeded = true
            } catch {
                connection = SFTPConnection.load()
                if !(error is CancellationError) { errorMessage = error.localizedDescription }
            }
        }
    }
}
