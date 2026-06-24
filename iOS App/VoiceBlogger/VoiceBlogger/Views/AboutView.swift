import SwiftUI

struct AboutView: View {
    @AppStorage(BetaFeatureSettings.automaticContentKindDetectionKey) private var automaticContentKindDetectionEnabled = false

    private let githubURL = URL(string: "https://github.com/kavin0x/voiceblogger") ?? URL(string: "https://github.com")!
    private let version: String = {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(build))"
    }()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Made by", value: "Kavin Shah")
                    LabeledContent("Version", value: version)
                    LabeledContent("License", value: "Open Source")
                }

                Section("Beta") {
                    Toggle("Automatic content type detection", isOn: $automaticContentKindDetectionEnabled)
                    Text("When enabled, transcripts are labeled as blog posts, meeting notes, or notes based on automatic classification. When off, the generator still uses the transcript's intent, but labels the result as a blog post.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Link(destination: githubURL) {
                        HStack {
                            Label("View on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
