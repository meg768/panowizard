import SwiftUI

@main
struct PanoWizardApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: PanoProjectDocument()) { file in
            ProjectDocumentView(document: file.$document)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1_240, height: 780)
    }
}

private struct ProjectDocumentView: View {
    @Binding var document: PanoProjectDocument
    @State private var model: AppModel

    init(document: Binding<PanoProjectDocument>) {
        _document = document
        _model = State(initialValue: AppModel.live(
            project: document.wrappedValue.project,
            masks: document.wrappedValue.masks,
            panoramaData: document.wrappedValue.panoramaData,
            nadirOverlayData: document.wrappedValue.nadirOverlayData
        ))
    }

    var body: some View {
        ContentView(model: model)
            .onChange(of: model.project) { _, project in
                document.project = project
            }
            .onChange(of: model.maskRevision) {
                document.masks = model.maskDataByImageID
            }
            .onChange(of: model.panoramaRevision) {
                document.panoramaData = model.panoramaData
                document.nadirOverlayData = model.nadirOverlayData
            }
    }
}
