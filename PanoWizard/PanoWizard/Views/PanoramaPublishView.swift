import AppKit
import SwiftUI

struct PanoramaPublishView: View {
    @Environment(\.dismiss) private var dismiss
    let model: AppModel
    let size: HTMLPanoramaSize
    let jpegQuality: Double
    @AppStorage("PanoWizard.Publish.generateThumbnail") private var generateThumbnail = true
    @State private var connection = SFTPConnection.load()
    @State private var filename: String
    @State private var subdirectory: String
    @State private var uploadSucceeded = false
    @State private var publishedURL: URL?
    @State private var busy = false
    @State private var status = ""
    @State private var errorMessage: String?

    init(model: AppModel, projectName: String?, size: HTMLPanoramaSize, jpegQuality: Double) {
        self.model = model
        self.size = size
        self.jpegQuality = jpegQuality
        _filename = State(initialValue: model.project.publishFilename ?? UserDefaults.standard.string(forKey: "sftpPublishFilename.\(model.project.id)")
                          ?? SFTPConnection.defaultFilename(projectName ?? model.project.title))
        _subdirectory = State(initialValue: model.project.publishPath ?? UserDefaults.standard.string(forKey: "sftpPublishPath.\(model.project.id)") ?? "")
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
                TextField("Path (Optional)", text: $subdirectory, prompt: Text("2019/Toscana"))
                    .help("Subfolders inside Remote Directory. Missing folders are created automatically.")
                TextField("Filename", text: $filename)
                Toggle("Generate thumbnail", isOn: $generateThumbnail)
            }
            .onChange(of: connection.hostname) { publishedURL = nil; uploadSucceeded = false }
            .onChange(of: connection.port) { publishedURL = nil; uploadSucceeded = false }
            .onChange(of: connection.username) { publishedURL = nil; uploadSucceeded = false }
            .onChange(of: connection.password) { publishedURL = nil; uploadSucceeded = false }
            .onChange(of: connection.remoteDirectory) { publishedURL = nil; uploadSucceeded = false }
            .onChange(of: connection.publicBaseURL) { publishedURL = nil; uploadSucceeded = false }
            .onChange(of: filename) { publishedURL = nil; uploadSucceeded = false }
            .onChange(of: generateThumbnail) { publishedURL = nil; uploadSucceeded = false }
            .onChange(of: subdirectory) { publishedURL = nil; uploadSucceeded = false }
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
            let defaults = UserDefaults.standard
            if (model.project.publishFilename == nil && defaults.string(forKey: "sftpPublishFilename.\(model.project.id)") != nil)
                || (model.project.publishPath == nil && defaults.string(forKey: "sftpPublishPath.\(model.project.id)") != nil) {
                model.project.setPublishDestination(path: subdirectory, filename: filename)
            }
        }
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
        do {
            connection.hostname = connection.serverHostname
            publicURL = try connection.publicURL(filename: filename, subdirectory: subdirectory)
            let saved = SFTPConnection.load()
            if saved.serverHostname != connection.hostname || saved.port != connection.port { connection.hostKey = nil }
            try connection.save()
            model.project.setPublishDestination(path: subdirectory, filename: filename)
        } catch { errorMessage = error.localizedDescription; return }
        let settings = connection
        let name = filename
        let path = subdirectory
        let includeThumbnail = generateThumbnail
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
            var htmlUploaded = false
            defer { try? FileManager.default.removeItem(at: jpeg) }
            defer { try? FileManager.default.removeItem(at: temporary); busy = false }
            do {
                try await FilePanoramaExporter().exportHTML(
                    panoramaURL: source, adjustments: adjustments, title: title,
                    initialViewpoint: viewpoint, size: size, jpegQuality: jpegQuality, to: temporary
                )
                if includeThumbnail {
                    status = "Generating thumbnail…"
                    try await PublishThumbnailRenderer.render(htmlURL: temporary, to: jpeg)
                }
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
                let confirm: @Sendable (String) async -> Bool = { remoteName in
                    await MainActor.run {
                        let alert = NSAlert()
                        alert.messageText = "Replace \(remoteName)?"
                        alert.informativeText = "This file already exists on \(settings.hostname). Replacing it overwrites the published file."
                        alert.addButton(withTitle: "Replace")
                        alert.addButton(withTitle: "Cancel")
                        return alert.runModal() == .alertFirstButtonReturn
                    }
                }
                try await SFTPPublisher.upload(
                    localURL: temporary, connection: settings, filename: name, subdirectory: path,
                    verifyHost: verifyHost, confirmOverwrite: { await confirm(name) }
                )
                htmlUploaded = true
                if includeThumbnail {
                    status = "Uploading thumbnail…"
                    let jpegName = String(name.dropLast(5)) + ".jpg"
                    try await SFTPPublisher.upload(
                        localURL: jpeg, connection: settings, filename: name, subdirectory: path,
                        thumbnail: true, verifyHost: verifyHost,
                        confirmOverwrite: { await confirm(jpegName) }
                    )
                }
                connection = SFTPConnection.load()
                publishedURL = publicURL
                uploadSucceeded = true
            } catch {
                connection = SFTPConnection.load()
                if htmlUploaded {
                    errorMessage = "HTML published successfully, but thumbnail publishing did not complete. " +
                        (error is CancellationError ? "Thumbnail replacement was cancelled." : error.localizedDescription)
                } else if !(error is CancellationError) { errorMessage = error.localizedDescription }
            }
        }
    }
}
