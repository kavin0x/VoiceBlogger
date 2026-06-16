import XCTest

final class VoiceBloggerUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Screen screenshots

    @MainActor
    func testLaunchOnboardingWelcomeScreen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-onboardingComplete", "NO"]
        app.launch()

        XCTAssertTrue(app.staticTexts["VoiceBlogger"].waitForExistence(timeout: 5))
        addScreenshot(app, name: "Onboarding - Welcome")
    }

    @MainActor
    func testLaunchOnboardingPrivacyScreen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-onboardingComplete", "NO"]
        app.launch()

        app.buttons["Skip"].tap()
        XCTAssertTrue(app.staticTexts["Private by design"].waitForExistence(timeout: 5))
        addScreenshot(app, name: "Onboarding - Privacy & Download")
    }

    @MainActor
    func testLaunchModelDownloadScreen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-onboardingComplete", "YES"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Setting Up VoiceBlogger"].waitForExistence(timeout: 5))
        addScreenshot(app, name: "Model Download")
    }

    @MainActor
    func testLaunchRecordingScreen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-onboardingComplete", "YES"]
        app.launchEnvironment = ["UI_TESTING": "1"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Voice Blogger"].waitForExistence(timeout: 5))
        addScreenshot(app, name: "Recording View")
    }

    @MainActor
    func testLaunchHistoryEmptyScreen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-onboardingComplete", "YES"]
        app.launchEnvironment = ["UI_TESTING": "1"]
        app.launch()

        app.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
        addScreenshot(app, name: "History - Empty State")
    }

    @MainActor
    func testLaunchAboutScreen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-onboardingComplete", "YES"]
        app.launchEnvironment = ["UI_TESTING": "1"]
        app.launch()

        app.buttons["Settings"].tap()
        app.buttons["About"].tap()
        XCTAssertTrue(app.navigationBars["About"].waitForExistence(timeout: 5))
        addScreenshot(app, name: "About Sheet")
    }

    // MARK: - Helper

    private func addScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
