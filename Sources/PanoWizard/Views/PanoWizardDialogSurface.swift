import SwiftUI

private struct PanoWizardDialogSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                .ultraThickMaterial,
                in: RoundedRectangle(cornerRadius: 24)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(.primary.opacity(0.22))
            }
            .shadow(color: .black.opacity(0.45), radius: 28, y: 12)
    }
}

extension View {
    func panoWizardDialogSurface() -> some View {
        modifier(PanoWizardDialogSurface())
    }
}
