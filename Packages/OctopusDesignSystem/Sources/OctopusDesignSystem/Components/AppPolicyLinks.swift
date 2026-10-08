import SwiftUI

/// Kaynak eklemeden önce ve kurulumdan sonra aynı politika bağlantıları.
public struct AppPolicyLinks: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            policyLink("Gizlilik Politikası", icon: "hand.raised", address: "https://octopusplayer.com/privacy-policy/")
            policyLink("Kullanım Koşulları", icon: "doc.text", address: "https://www.apple.com/legal/itunes/appstore/dev/stdeula/")
            policyLink("Yardım ve Destek", icon: "questionmark.circle", address: "https://octopusplayer.com/support/")
        }
        .font(.subheadline)
    }

    @ViewBuilder
    private func policyLink(_ title: LocalizedStringKey, icon: String, address: String) -> some View {
        if let url = URL(string: address) {
            Link(destination: url) {
                Label(title, systemImage: icon)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityHint("Tarayıcıda açılır")
        }
    }
}
