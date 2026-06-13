import SwiftUI

struct AboutSettingsTab: View {
    private static let repoURL = URL(string: "https://github.com/llyfn/clowder")!
    private static let releasesURL = URL(string: "https://github.com/llyfn/clowder/releases")!

    private var version: String {
        let short =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "cat.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Clowder").font(.title2.bold())
            Text("Version \(version)")
                .font(.callout).foregroundStyle(.secondary)
            Text("Free software, licensed under the GNU GPL-3.0.")
                .font(.caption).foregroundStyle(.secondary)
            Text("No warranty; see the license for details.")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Link("Source code", destination: Self.repoURL)
                Link("Check for updates", destination: Self.releasesURL)
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}
