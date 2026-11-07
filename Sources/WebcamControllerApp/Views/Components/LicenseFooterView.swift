import SwiftUI
import UVCCore

/// "Released under the MIT License. Copyright © 2026 SilverFeit." with both parts linking to GitHub.
public struct LicenseFooterView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 5) {
            Divider()
                .padding(.top, 4)
            Text(LocalizedStringKey(AppBuildInfo.licenseMarkdown))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.top, 2)
    }
}
