import AppKit
import SwiftUI

/// A project without sources is ready to begin, regardless of its selected workspace.
struct EmptyProjectWelcomeView: View {
    let addImages: () -> Void
    private static let backgroundImage: NSImage? = {
        guard let directory = Bundle.main.resourceURL?.appendingPathComponent("Backgrounds"),
              let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
              ),
              let url = files.filter({ $0.pathExtension.lowercased() == "jpg" }).randomElement()
        else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.8))
            Text("Create a Panorama")
                .font(.system(size: 32, weight: .semibold))
            Text("Add overlapping photos, then create your panorama.")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.85))
            VStack(spacing: 12) {
                Button(action: addImages) {
                    Label("Add Images…", systemImage: "plus")
                }
                Button("Open Existing Panorama…") {
                    NSDocumentController.shared.openDocument(nil)
                }
            }
            .buttonStyle(WorkspaceToolbarPillStyle())
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.white)
        .padding(24)
        .opticalEmptyState()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            GeometryReader { geometry in
                ZStack {
                    if let image = Self.backgroundImage {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                    Color.black.opacity(0.58)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
            }
        }
        .environment(\.colorScheme, .dark)
    }
}
