import SwiftUI

/// The fixed visual frame shared by every view in the detail column.
struct DetailWorkspace<Controls: View, Content: View, Status: View>: View {
    @ViewBuilder let controls: Controls
    @ViewBuilder let content: Content
    @ViewBuilder let status: Status

    var body: some View {
        VStack(spacing: 0) {
            controls
                .frame(height: 44)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)

            Divider()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            status
                .frame(height: 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
