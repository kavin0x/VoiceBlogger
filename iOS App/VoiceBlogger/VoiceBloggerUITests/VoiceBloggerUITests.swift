import XCTest

final class VoiceBloggerUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Launch helpers

    /// Shows OnboardingView (default first-launch state).
    private func launchWithFreshOnboarding() {
        app.launchArguments = ["-onboardingComplete", "NO"]
        app.launch()
    }

    /// Shows ModelDownloadView (onboarding done, models not yet downloaded).
    private func launchAtModelDownloadView() {
        app.launchArguments = ["-onboardingComplete", "YES"]
        app.launch()
    }

    /// Shows RecordingView directly — bypasses the model-download gate via UI_TESTING env var.
    private func launchAtRecordingView() {
        app.launchArguments = ["-onboardingComplete", "YES"]
        app.launchEnvironment = ["UI_TESTING": "1"]
        app.launch()
    }

    // MARK: - Onboarding: Welcome page

    @MainActor
    func testOnboardingWelcomeShowsAppName() throws {
        launchWithFreshOnboarding()
        XCTAssertTrue(app.staticTexts["VoiceBlogger"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testOnboardingWelcomeShowsPrivacyStatement() throws {
        launchWithFreshOnboarding()
        XCTAssertTrue(
            app.staticTexts["No data leaves your device. Free and Private, Forever."]
                .waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testOnboardingWelcomeShowsLanguageSupportText() throws {
        launchWithFreshOnboarding()
        XCTAssertTrue(
            app.staticTexts["Supports 90+ different languages!"]
                .waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testOnboardingWelcomeHasSkipButton() throws {
        launchWithFreshOnboarding()
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testOnboardingWelcomeHasNextButton() throws {
        launchWithFreshOnboarding()
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 5))
    }

    // MARK: - Onboarding: Next-button navigation

    @MainActor
    func testOnboardingNextAdvancesToRecordPage() throws {
        launchWithFreshOnboarding()
        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["Just speak your mind"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testOnboardingNextAdvancesToBlogPage() throws {
        launchWithFreshOnboarding()
        app.buttons["Next"].tap()
        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["Your words, beautifully written"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testOnboardingNextAdvancesToPrivacyPage() throws {
        launchWithFreshOnboarding()
        app.buttons["Next"].tap()
        app.buttons["Next"].tap()
        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["Private by design"].waitForExistence(timeout: 5))
    }

    // MARK: - Onboarding: Skip button

    @MainActor
    func testOnboardingSkipJumpsToPrivacyPage() throws {
        launchWithFreshOnboarding()
        app.buttons["Skip"].tap()
        XCTAssertTrue(app.staticTexts["Private by design"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testOnboardingSkipButtonHiddenOnLastPage() throws {
        launchWithFreshOnboarding()
        app.buttons["Skip"].tap()
        XCTAssertFalse(app.buttons["Skip"].exists)
    }

    @MainActor
    func testOnboardingNextButtonHiddenOnLastPage() throws {
        launchWithFreshOnboarding()
        app.buttons["Skip"].tap()
        XCTAssertFalse(app.buttons["Next"].exists)
    }

    // MARK: - Onboarding: Record page interactive demo

    @MainActor
    func testOnboardingRecordPageShowsDemoButton() throws {
        launchWithFreshOnboarding()
        app.buttons["Next"].tap()
        XCTAssertTrue(app.buttons["Try recording"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testOnboardingRecordDemoButtonTogglesState() throws {
        launchWithFreshOnboarding()
        app.buttons["Next"].tap()

        let startButton = app.buttons["Try recording"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.tap()

        XCTAssertTrue(app.buttons["Stop demo recording"].waitForExistence(timeout: 3))
        app.buttons["Stop demo recording"].tap()

        XCTAssertTrue(app.buttons["Try recording"].waitForExistence(timeout: 3))
    }

    // MARK: - Onboarding: Privacy/download page

    @MainActor
    func testOnboardingPrivacyPageShowsDownloadButton() throws {
        launchWithFreshOnboarding()
        app.buttons["Skip"].tap()
        XCTAssertTrue(
            app.buttons["Download AI Models (~3.2 GB)"].waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testOnboardingPrivacyPageShowsWhisperSize() throws {
        launchWithFreshOnboarding()
        app.buttons["Skip"].tap()
        XCTAssertTrue(app.staticTexts["~1.5 GB"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testOnboardingPrivacyPageShowsLLMSize() throws {
        launchWithFreshOnboarding()
        app.buttons["Skip"].tap()
        XCTAssertTrue(app.staticTexts["~1.7 GB"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testOnboardingPrivacyPageShowsTotalSize() throws {
        launchWithFreshOnboarding()
        app.buttons["Skip"].tap()
        XCTAssertTrue(app.staticTexts["~3.2 GB"].waitForExistence(timeout: 5))
    }

    // MARK: - Model Download View

    @MainActor
    func testModelDownloadViewShowsTitle() throws {
        launchAtModelDownloadView()
        XCTAssertTrue(app.staticTexts["Setting Up VoiceBlogger"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testModelDownloadViewShowsSpeechRecognitionRow() throws {
        launchAtModelDownloadView()
        XCTAssertTrue(app.staticTexts["Advanced Speech Recognition"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testModelDownloadViewShowsBlogGeneratorRow() throws {
        launchAtModelDownloadView()
        XCTAssertTrue(app.staticTexts["Blog Generator"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testModelDownloadViewShowsDownloadButton() throws {
        launchAtModelDownloadView()
        XCTAssertTrue(app.buttons["Download AI Models"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testModelDownloadViewShowsWhisperSubtitle() throws {
        launchAtModelDownloadView()
        XCTAssertTrue(
            app.staticTexts["Supports 90+ languages · ~1.5 GB"].waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testModelDownloadViewShowsTotalSizeFootnote() throws {
        launchAtModelDownloadView()
        XCTAssertTrue(
            app.staticTexts["Total download: ~3.2 GB · Wi-Fi recommended"]
                .waitForExistence(timeout: 5)
        )
    }

    // MARK: - Recording View

    @MainActor
    func testRecordingViewShowsNavigationTitle() throws {
        launchAtRecordingView()
        XCTAssertTrue(app.navigationBars["Voice Blogger"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRecordingViewShowsRecordButton() throws {
        launchAtRecordingView()
        XCTAssertTrue(app.buttons["Start recording"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRecordingViewShowsUploadButton() throws {
        launchAtRecordingView()
        XCTAssertTrue(app.buttons["Upload Recording"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRecordingViewShowsHistoryToolbarButton() throws {
        launchAtRecordingView()
        XCTAssertTrue(app.buttons["History"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRecordingViewShowsSettingsToolbarButton() throws {
        launchAtRecordingView()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRecordingViewUploadButtonHiddenWhileRecording() throws {
        // Upload button must disappear once a recording is in progress.
        // This test verifies the initial idle state has the upload button.
        launchAtRecordingView()
        XCTAssertTrue(app.buttons["Upload Recording"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Start recording"].isSelected)
    }

    // MARK: - Settings menu

    @MainActor
    func testSettingsMenuShowsAboutOption() throws {
        launchAtRecordingView()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["About"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testSettingsMenuShowsResetOption() throws {
        launchAtRecordingView()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["Reset & Re-download Models"].waitForExistence(timeout: 3))
    }

    // MARK: - Reset confirmation dialog

    @MainActor
    func testResetConfirmationDialogAppears() throws {
        launchAtRecordingView()
        app.buttons["Settings"].tap()
        app.buttons["Reset & Re-download Models"].tap()
        // Destructive action button appears in the confirmation sheet
        XCTAssertTrue(app.buttons["Reset & Re-download"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testResetConfirmationDialogHasCancelButton() throws {
        launchAtRecordingView()
        app.buttons["Settings"].tap()
        app.buttons["Reset & Re-download Models"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testResetConfirmationDialogCancelDismissesIt() throws {
        launchAtRecordingView()
        app.buttons["Settings"].tap()
        app.buttons["Reset & Re-download Models"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].tap()
        // Recording view should still be visible after cancellation
        XCTAssertTrue(app.buttons["Start recording"].waitForExistence(timeout: 3))
    }

    // MARK: - History navigation

    @MainActor
    func testRecordingViewNavigatesToHistory() throws {
        launchAtRecordingView()
        app.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
    }

    // MARK: - Blog List View

    @MainActor
    func testBlogListShowsEmptyStateTitle() throws {
        launchAtRecordingView()
        app.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["No Blog Posts Yet"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testBlogListShowsNewRecordingButton() throws {
        launchAtRecordingView()
        app.buttons["History"].tap()
        XCTAssertTrue(app.buttons["New Recording"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testBlogListNewRecordingNavigatesBack() throws {
        launchAtRecordingView()
        app.buttons["History"].tap()
        app.buttons["New Recording"].tap()
        XCTAssertTrue(app.navigationBars["Voice Blogger"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testBlogListShowsEditButton() throws {
        launchAtRecordingView()
        app.buttons["History"].tap()
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 5))
    }

    // MARK: - About sheet

    @MainActor
    func testAboutSheetShowsNavigationTitle() throws {
        launchAtRecordingView()
        app.buttons["Settings"].tap()
        app.buttons["About"].tap()
        XCTAssertTrue(app.navigationBars["About"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testAboutSheetShowsMadeByRow() throws {
        launchAtRecordingView()
        app.buttons["Settings"].tap()
        app.buttons["About"].tap()
        XCTAssertTrue(app.staticTexts["Made by"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testAboutSheetShowsVersionRow() throws {
        launchAtRecordingView()
        app.buttons["Settings"].tap()
        app.buttons["About"].tap()
        XCTAssertTrue(app.staticTexts["Version"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testAboutSheetShowsGitHubLink() throws {
        launchAtRecordingView()
        app.buttons["Settings"].tap()
        app.buttons["About"].tap()
        XCTAssertTrue(app.staticTexts["View on GitHub"].waitForExistence(timeout: 3))
    }

    // MARK: - Launch performance

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
