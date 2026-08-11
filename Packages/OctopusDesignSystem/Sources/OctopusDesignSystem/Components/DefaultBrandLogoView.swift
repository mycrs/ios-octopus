import SwiftUI

/// Bayi logosu bulunmadığında uygulamanın kendi marka işaretini gösterir.
public struct DefaultBrandLogoView: View {

    public init() {}

    public var body: some View {
        Image("OctopusDefaultLogo")
            .resizable()
            .scaledToFit()
    }
}
