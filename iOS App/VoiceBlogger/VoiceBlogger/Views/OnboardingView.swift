import SwiftUI

struct OnboardingView: View {
    @Environment(ModelDownloadManager.self) var downloadManager
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @State private var currentPage = 0

    var body: some View {
        ZStack {
            TabView(selection: $currentPage) {
                OnboardingWelcomePage()
                    .tag(0)
                OnboardingRecordPage()
                    .tag(1)
                OnboardingBlogPage()
                    .tag(2)
                OnboardingSupportPage()
                    .tag(3)
                OnboardingReadyPage { onboardingComplete = true }
                    .tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack {
                HStack {
                    Spacer()
                    if currentPage < 4 {
                        Button("Skip") {
                            withAnimation { currentPage = 4 }
                        }
                        .foregroundStyle(.secondary)
                        .padding(.top, 56)
                        .padding(.trailing, 24)
                    }
                }
                Spacer()
                HStack {
                    HStack(spacing: 6) {
                        ForEach(0..<5, id: \.self) { i in
                            Capsule()
                                .fill(i == currentPage ? Color.primary : Color.secondary.opacity(0.3))
                                .frame(width: i == currentPage ? 20 : 8, height: 8)
                                .animation(.spring(duration: 0.3), value: currentPage)
                        }
                    }
                    .accessibilityHidden(true)
                    Spacer()
                    if currentPage < 4 {
                        Button("Next") {
                            withAnimation { currentPage += 1 }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 52)
            }
        }
        .task {
            if !downloadManager.allModelsReady && !downloadManager.isDownloading {
                await downloadManager.downloadAll()
            }
        }
    }
}

// MARK: - Page 1: Welcome

private struct OnboardingWelcomePage: View {
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                ForEach([200, 150, 100], id: \.self) { size in
                    Circle()
                        .fill(.blue.opacity(0.06))
                        .frame(width: CGFloat(size), height: CGFloat(size))
                        .scaleEffect(appeared ? 1.1 : 1.0)
                        .animation(
                            .easeInOut(duration: 1.8 + Double(size) * 0.005)
                                .repeatForever(autoreverses: true),
                            value: appeared
                        )
                }
                Image(systemName: "mic.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 12) {
                Text("VoiceBlogger")
                    .font(.largeTitle.bold())
                Text("Turn your voice into a polished blog post — in minutes.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 48)
                Text("No data leaves your device. Free and Private, Forever.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 48)
                Text("Supports 90+ different languages!")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 48)
            }

            Spacer()
            Spacer()
        }
        .onAppear { appeared = true }
    }
}

// MARK: - Page 2: Record (interactive)

private struct OnboardingRecordPage: View {
    @State private var isRecording = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 10) {
                Button {
                    isRecording.toggle()
                } label: {
                    ZStack {
                        Circle()
                            .fill(isRecording ? Color.red : Color.blue)
                            .frame(width: 80, height: 80)
                            .shadow(
                                color: (isRecording ? Color.red : Color.blue).opacity(0.45),
                                radius: isRecording ? 24 : 10
                            )
                        Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isRecording ? "Stop demo recording" : "Try recording")
                .scaleEffect(isRecording ? 1.1 : 1.0)
                .animation(.spring(duration: 0.35), value: isRecording)

                Text(isRecording ? "Tap to stop" : "Tap to try it")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                Text("Just speak your mind")
                    .font(.title2.bold())
                Text("Record yourself talking about anything — no scripts or editing needed. Even long recording... Just fine, just speak your mind!")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
            Spacer()
        }
    }
}

// MARK: - Page 3: Blog generation visual

private struct OnboardingBlogPage: View {
    @State private var transformed = false

    private let voiceWidths: [CGFloat] = [70, 50, 65, 45]
    private let blogWidths: [CGFloat] = [80, 55, 72, 42]
    private let blogDelays: [Double] = [0.05, 0.15, 0.25, 0.35]

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            HStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 32))
                        .foregroundStyle(.blue)
                        .accessibilityHidden(true)
                    ForEach(0..<4, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.blue.opacity(0.25))
                            .frame(width: voiceWidths[i], height: 7)
                    }
                }

                Image(systemName: "arrow.right")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .opacity(transformed ? 1 : 0)
                    .scaleEffect(transformed ? 1 : 0.5)
                    .animation(.spring(duration: 0.4).delay(0.1), value: transformed)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    ForEach(0..<4, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.green.opacity(transformed ? 0.4 : 0))
                            .frame(width: blogWidths[i], height: 7)
                            .animation(.easeOut(duration: 0.3).delay(blogDelays[i]), value: transformed)
                    }
                }
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))

            VStack(spacing: 12) {
                Text("Your words, beautifully written")
                    .font(.title2.bold())
                Text("AI transcribes your speech and crafts it into a well-structured blog post, ready to share. ")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Text("Supports 90+ languages. Switch seamlessly, speak freely, and let it run as long as you need.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
            Spacer()
        }
        .onAppear {
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                transformed = true
            }
        }
    }
}

// MARK: - Page 4: Support

private struct OnboardingSupportPage: View {
    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "heart.fill")
                .font(.system(size: 52))
                .foregroundStyle(.pink)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text("Free & private, always")
                    .font(.title2.bold())
                Text("VoiceBlogger is completely free to use and all AI runs on your device — your data never leaves your phone, ever.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            VStack(spacing: 8) {
                Text("If you find it useful, the only way to support me is through GitHub Sponsors.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Link(destination: URL(string: "https://github.com/sponsors/kavin0x")!) {
                    Label("Support on GitHub", systemImage: "heart")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(.pink.opacity(0.12), in: Capsule())
                        .foregroundStyle(.pink)
                }
            }

            Spacer()
            Spacer()
        }
    }
}

// MARK: - Page 5: Privacy + download ready

private struct OnboardingReadyPage: View {
    @Environment(ModelDownloadManager.self) var downloadManager
    let onComplete: () -> Void

    private var overallProgress: Double {
        (downloadManager.whisperProgress + downloadManager.llmProgress) / 2.0
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 52))
                .foregroundStyle(.blue)
                .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text("Private by design")
                    .font(.title2.bold())
                Text("Every AI model runs on your device. Your voice and data never leave your phone.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 44)
            }

            // Compact download status
            Group {
                if downloadManager.allModelsReady {
                    Label("Ready to go!", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                } else if let error = downloadManager.downloadError {
                    VStack(spacing: 8) {
                        Text("Download failed")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        Button("Retry") {
                            Task { await downloadManager.downloadAll() }
                        }
                        .foregroundStyle(.blue)
                        .font(.subheadline)
                    }
                    .transition(.opacity)
                } else {
                    VStack(spacing: 6) {
                        HStack {
                            Text("Downloading AI models…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(overallProgress.formatted(.percent.precision(.fractionLength(0))))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: overallProgress)
                            .tint(.blue)
                    }
                    .padding(.horizontal, 40)
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: downloadManager.allModelsReady)
            .animation(.easeInOut(duration: 0.4), value: downloadManager.downloadError != nil)

            Button(downloadManager.allModelsReady ? "Get Started" : "Setting up…") {
                onComplete()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!downloadManager.allModelsReady)

            Spacer()
        }
    }
}
