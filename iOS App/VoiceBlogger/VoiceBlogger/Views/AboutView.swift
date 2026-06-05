import SwiftUI

struct AboutView: View {
    private let githubURL = URL(string: "https://github.com/kavin0/voiceblogger")!
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

                Section {
                    Link(destination: githubURL) {
                        HStack {
                            Label("View on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
