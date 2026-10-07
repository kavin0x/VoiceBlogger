import SwiftUI

struct OnboardingView: View {
    @Environment(ModelDownloadManager.self) var downloadManager
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @State private var currentPage = 0

    private let iCloudPage = 4

    var body: some View {
        ZStack {
            TabView(selection: $currentPage) {
                OnboardingWelcomePage()
                    .tag(0)
                OnboardingRecordPage()
                    .tag(1)
                OnboardingBlogPage()
                    .tag(2)
                OnboardingReadyPage {
                    withAnimation { currentPage = iCloudPage }
                }
                    .tag(3)
                OnboardingICloudPage { onboardingComplete = true }
                    .tag(iCloudPage)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack {
                HStack {
                    Spacer()
                    if currentPage < iCloudPage {
                        Button("Skip") {
                            withAnimation { currentPage = iCloudPage }
                        }
                        .foregroundStyle(.secondary)
                        .padding(.top, 56)
                        .padding(.trailing, 24)
                    }
                }
                Spacer()
                ZStack {
                    HStack(spacing: 6) {
                        ForEach(0..<5, id: \.self) { i in
                            Capsule()
                                .fill(i == currentPage ? Color.primary : Color.secondary.opacity(0.3))
                                .frame(width: i == currentPage ? 20 : 8, height: 8)
                                .animation(.spring(duration: 0.3), value: currentPage)
                        }
                    }
                    .accessibilityHidden(true)

                    if currentPage < iCloudPage {
                        HStack {
                            Spacer()
                            Button("Next") {
                                withAnimation { currentPage += 1 }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 52)
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
        .frame(maxWidth: 600)
        .onAppear { appeared = true }
    }
}

// MARK: - Page 2: Record

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
                Text("Record yourself talking about anything — no scripts or editing needed. Long recordings are fine too, just speak your mind!")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
            Spacer()
        }
        .frame(maxWidth: 600)
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
                Text("AI transcribes your speech and crafts it into a well-structured blog post, ready to share.")
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
        .frame(maxWidth: 600)
        .onAppear {
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                transformed = true
            }
        }
    }
}

// MARK: - Page 4: Privacy + download

private struct OnboardingReadyPage: View {
    @Environment(ModelDownloadManager.self) var downloadManager
    let onComplete: () -> Void

    @State private var downloadStarted = false
    @State private var selectedQuality = ModelQualityLevel.recommended
    @State private var hasChosenQuality = ModelQualityLevel.current != ModelQualityLevel.recommended
        || UserDefaults.standard.bool(forKey: "whisperModelReady_v4")

    private var showQualityPicker: Bool {
        !hasChosenQuality && !downloadStarted && !downloadManager.isDownloading && !downloadManager.allModelsReady
    }

    private var overallProgress: Double {
        (downloadManager.whisperProgress + downloadManager.llmProgress) / 2.0
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                headerSection

                if showQualityPicker {
                    ModelQualityPickerView(selection: $selectedQuality)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                statusSection

                actionSection
            }
            .padding(.horizontal, 32)
            .padding(.top, 72)
            .padding(.bottom, 96)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: 560)
        .animation(.easeInOut(duration: 0.3), value: showQualityPicker)
        .animation(.easeInOut(duration: 0.4), value: downloadManager.allModelsReady)
        .animation(.easeInOut(duration: 0.4), value: downloadManager.downloadError != nil)
        .animation(.easeInOut(duration: 0.4), value: downloadStarted)
        .onAppear {
            selectedQuality = ModelQualityLevel.current
            hasChosenQuality = UserDefaults.standard.bool(forKey: "whisperModelReady_v4")
            if downloadManager.isDownloading {
                downloadStarted = true
            }
        }
        .onChange(of: downloadManager.allModelsReady) { _, ready in
            guard ready else { return }
            ModelQualityLevel.lockExistingInstall(to: ModelQualityLevel.current)
        }
    }

    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Private by design")
                    .font(.title2.bold())
                Text("Every AI model runs on your device. iCloud sync is optional and private to your Apple ID — not a Voice Blogger account or server.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var statusSection: some View {
        if downloadManager.allModelsReady {
            Label("Ready to go!", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
        } else if let error = downloadManager.downloadError {
            VStack(spacing: 10) {
                Text("Download failed")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    downloadStarted = true
                    Task { await downloadManager.downloadAll() }
                }
                .font(.subheadline)
            }
            .frame(maxWidth: .infinity)
            .transition(.opacity)
        } else if downloadStarted || downloadManager.isDownloading {
            VStack(spacing: 10) {
                HStack {
                    Text("Downloading AI models…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(overallProgress.formatted(.percent.precision(.fractionLength(0))))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: overallProgress)
                    .tint(.blue)
                Text("Feel free to use your device — the download continues in the background.")
                    .font(.title3) // Make it bigger than caption
                    .foregroundStyle(.white) // Actually white text
                    .multilineTextAlignment(.center)
            }
            .transition(.opacity)
        }
   
    }

    @ViewBuilder
    private var actionSection: some View {
        if downloadManager.allModelsReady {
            Button("Get Started", action: onComplete)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
        } else if !downloadStarted && !downloadManager.isDownloading {
            VStack(spacing: 10) {
                Button("Download AI Models") {
                    ModelQualityLevel.select(selectedQuality, forNewInstall: !hasChosenQuality)
                    hasChosenQuality = true
                    downloadStarted = true
                    Task { await downloadManager.downloadAll() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)

                Text("Wi-Fi recommended · Download happens once")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        } else if downloadManager.downloadError == nil {
            Button("Setting up…") {}
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(true)
        }
    }
}

// MARK: - Page 5: iCloud choice

private struct OnboardingICloudPage: View {
    let onComplete: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 16) {
                    Image(systemName: "icloud.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue)
                        .accessibilityHidden(true)
                    VStack(spacing: 8) {
                        Text("Sync across your devices")
                            .font(.title2.bold())
                        Text("Posts, notes, captions, your dictionary, and recordings can sync through your private iCloud to your iPhone, iPad, and Mac. Speech and writing still happen on this device. The AI models stay here.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)

                ICloudSyncChoiceForm(onFinished: onComplete)
            }
            .padding(.horizontal, 32)
            .padding(.top, 72)
            .padding(.bottom, 96)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: 560)
    }
}

struct ICloudSyncChoiceForm: View {
    let onFinished: () -> Void

    @Environment(LibraryStore.self) private var library
    @State private var message: String?
    @State private var isWorking = false

    var body: some View {
        VStack(spacing: 12) {
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button("On this device only") {
                choose(enable: false)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .disabled(isWorking)

            Button("Sync with iCloud") {
                choose(enable: true)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .disabled(isWorking)

            Text("Uses your iCloud storage. If you sync, quit and reopen Voice Blogger once so it can start. You can change this later in Settings.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }

    private func choose(enable: Bool) {
        isWorking = true
        message = nil
        Task {
            let accountAvailable = enable ? await ICloudAccount.isAvailable() : true
            let failure = library.updateSync(enabled: enable, accountAvailable: accountAvailable)
            isWorking = false
            if let failure {
                message = failure
            } else if ICloudSyncSettings.canFinishSetup() {
                onFinished()
            }
        }
    }
}
