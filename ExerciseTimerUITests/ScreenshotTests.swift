import XCTest

/// App Store screenshot capture, one test per scene. The app is launched in its DEBUG
/// `-screenshotMode` (seeded data, frozen clock) and jumps straight to the scene, so nothing here
/// taps through a flow. Each test waits on an accessibility identifier, then saves an attachment
/// named `NN_scene`; capture.sh exports them as `<device>_<lang>_<NN>_<scene>.png`.
///
/// Driven by capture.sh through TEST_RUNNER_ env vars (the prefix is stripped):
///   SCREENSHOT_DEVICE        tag used in file names, e.g. iphone69, duo_outer, duo_inner, ipad13
///   SCREENSHOT_LANG          e.g. en
///   SCREENSHOT_ORIENTATION   portrait (default) or landscape
final class ScreenshotTests: XCTestCase {

    private var app: XCUIApplication!
    private let env = ProcessInfo.processInfo.environment

    private var deviceTag: String { env["SCREENSHOT_DEVICE"] ?? "device" }
    private var lang: String { env["SCREENSHOT_LANG"] ?? "en" }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    // MARK: - Scenes (names match `ScreenshotScene` in the app)

    @MainActor func test01_plan() throws {
        try capture("01", "plan", waitFor: "plan.start")
    }

    @MainActor func test02_manualSet() throws {
        try capture("02", "manualSet", waitFor: "session.repsComplete")
        XCTAssertEqual(element("session.exerciseName").label, "Bench Press")
    }

    @MainActor func test03_superset() throws {
        try capture("03", "superset", waitFor: "session.countdown")
        XCTAssertEqual(element("session.exerciseName").label, "Mountain Climber")
    }

    @MainActor func test04_timedSuperset() throws {
        try capture("04", "timedSuperset", waitFor: "session.windowLeft")
        XCTAssertEqual(element("session.windowLeft").label, "7:42 left")
    }

    @MainActor func test05_restLog() throws {
        try capture("05", "restLog", waitFor: "session.logCard")
        XCTAssertEqual(element("session.phaseLabel").label, "REST")
    }

    @MainActor func test06_overview() throws {
        try capture("06", "overview", waitFor: "overview.list")
    }

    @MainActor func test07_recap() throws {
        try capture("07", "recap", waitFor: "recap.screen") {
            // Also grab the scrolled view, so Sets Logged is covered.
            self.app.swipeUp()
            self.pause(1)
            self.snap("07b", "recapLog")
        }
    }

    @MainActor func test08_routines() throws {
        try capture("08", "routines", waitFor: "routines.list")
    }

    @MainActor func test09_timer() throws {
        try capture("09", "timer", waitFor: "session.countdown")
        XCTAssertEqual(element("session.phaseLabel").label, "BREAK")
    }

    @MainActor func test10_createPlan() throws {
        try capture("10", "createPlan", waitFor: "createPlan.form")
    }

    // MARK: - Helpers

    /// Launches into `scene`, waits for `identifier`, lets the layout settle, then snaps.
    /// `after` runs once the main capture is saved (for extra shots of the same scene).
    @MainActor
    private func capture(_ number: String, _ scene: String, waitFor identifier: String, after: (() -> Void)? = nil) throws {
        XCUIDevice.shared.orientation = env["SCREENSHOT_ORIENTATION"] == "landscape" ? .landscapeLeft : .portrait
        app.launchArguments += [
            "-screenshotMode", "-screenshotScene", scene,
            "-AppleLanguages", "(\(lang))",
            "-AppleLocale", lang,
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL",
        ]
        app.launch()
        XCTAssertTrue(element(identifier).waitForExistence(timeout: 15),
                      "Scene \(scene) never showed '\(identifier)'")
        pause(1.2)
        snap(number, scene)
        after?()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// The Duo has two displays and `XCUIScreen.main` is the outer one. For the inner pass (tag
    /// contains "inner") use the biggest display, which is where the app is.
    private func largestScreenshot() -> XCUIScreenshot {
        guard deviceTag.contains("inner") else { return XCUIScreen.main.screenshot() }
        let shots = XCUIScreen.screens.map { $0.screenshot() }
        return shots.max { $0.image.size.width * $0.image.size.height < $1.image.size.width * $1.image.size.height }
            ?? XCUIScreen.main.screenshot()
    }

    private func snap(_ number: String, _ scene: String) {
        let attachment = XCTAttachment(screenshot: largestScreenshot())
        attachment.name = "\(number)_\(scene)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func pause(_ seconds: TimeInterval) {
        let done = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 2)
    }
}
