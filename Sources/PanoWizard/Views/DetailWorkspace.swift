import SwiftUI

/// The shared visual frame for the detail column, with optional local controls.
struct DetailWorkspace<Controls: View, Content: View, Status: View>: View {
    let showsControls: Bool
    @ViewBuilder let controls: Controls
    @ViewBuilder let content: Content
    @ViewBuilder let status: Status

    var body: some View {
        VStack(spacing: 0) {
            if showsControls {
                controls
                    .frame(height: 44)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.bar)

                Divider()
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            status
                .frame(height: 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
