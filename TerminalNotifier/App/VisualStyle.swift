import SwiftUI

extension View {
    @ViewBuilder
    func tnGlassSurface(cornerRadius: CGFloat) -> some View {
#if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
#else
        self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
#endif
    }

    @ViewBuilder
    func tnGlassButtonIfAvailable() -> some View {
#if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
#else
        self.buttonStyle(.bordered)
#endif
    }

    @ViewBuilder
    func tnGlassProminentButtonIfAvailable() -> some View {
#if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
#else
        self.buttonStyle(.borderedProminent)
#endif
    }
}
