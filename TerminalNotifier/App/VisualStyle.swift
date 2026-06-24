import SwiftUI

extension View {
    @ViewBuilder
    func tnGlassButtonIfAvailable() -> some View {
        self.buttonStyle(.bordered)
    }

    @ViewBuilder
    func tnGlassProminentButtonIfAvailable() -> some View {
        self.buttonStyle(.borderedProminent)
    }
}
