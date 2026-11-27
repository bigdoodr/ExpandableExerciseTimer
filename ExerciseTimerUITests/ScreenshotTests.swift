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

    // MARK: - Video clip (Phase 3)

    /// The slow pass recorded for the App Preview and header video: capture/record script runs this
    /// while `simctl io recordVideo` is recording. Each step is held for `SCREENSHOT_SLOW` seconds
    /// (default 2.5). Raw length is kept; the video is trimmed afterwards.
    ///
    ///   1. Plan tab -> Start on the Up Next card -> Preview -> back -> Start Workout
    ///   2. Bump the reps stepper, complete the set, let the rest run, adjust the Log card weight
    ///   3. Jump to the superset scene and let 6 s of countdown play (clock ticking for this clip)
    ///   4. Show the recap
    @MainActor func testClipFlow() throws {
        let hold = TimeInterval(env["SCREENSHOT_SLOW"] ?? "") ?? 2.5
        XCUIDevice.shared.orientation = env["SCREENSHOT_ORIENTATION"] == "landscape" ? .landscapeLeft : .portrait
        // record_clip.sh starts the recorder when this appears and stops it at the finish marker,
        // so the recording holds the flow and not the test runner's start-up.
        marker("started")
        defer { marker("finished") }

        // 1. Plan -> Exercises -> Preview -> back -> Start Workout
        launch(scene: "plan")
        XCTAssertTrue(element("plan.start").waitForExistence(timeout: 15))
        pause(hold)
        element("plan.start").tap()
        pause(hold)
        let preview = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Preview'")).firstMatch
        scrollUntilHittable(preview)
        preview.tap()
        pause(hold)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        pause(hold)
        let start = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Start Workout'")).firstMatch
        scrollUntilHittable(start)
        start.tap()
        pause(1)
        let continueOnPhone = app.buttons.matching(NSPredicate(format: "label CONTAINS 'iPhone'")).firstMatch
        XCTAssertTrue(continueOnPhone.waitForExistence(timeout: 10))
        pause(hold)
        continueOnPhone.tap()

        // 2. A rep-based set, the rest, the Log card
        XCTAssertTrue(element("session.repsComplete").waitForExistence(timeout: 10))
        pause(hold)
        tapStepperPlus(element("session.repsStepper"))
        pause(hold)
        element("session.repsComplete").tap()
        XCTAssertTrue(element("session.logCard").waitForExistence(timeout: 10))
        pause(5)
        tapStepperPlus(element("session.logWeightStepper"))
        pause(hold)

        // 3. Superset countdown, ticking
        app.terminate()
        launch(scene: "superset", live: true)
        XCTAssertTrue(element("session.countdown").waitForExistence(timeout: 15))
        pause(6)

        // 4. Recap
        app.terminate()
        launch(scene: "recap")
        XCTAssertTrue(element("recap.screen").waitForExistence(timeout: 15))
        pause(hold + 1)
        app.swipeUp()
        pause(hold)
    }

    // MARK: - Helpers

    @MainActor
    private func launch(scene: String, live: Bool = false) {
        app.launchArguments = ["-screenshotMode", "-screenshotScene", scene,
                               "-AppleLanguages", "(\(lang))", "-AppleLocale", lang,
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        if live { app.launchArguments.append("-screenshotLive") }
        app.launch()
    }

    /// Taps the "+" half of a stepper. SwiftUI steppers don't reliably expose Increment/Decrement
    /// buttons to XCUITest, so tap where the "+" is: at the trailing end of the row.
    @MainActor
    private func tapStepperPlus(_ stepper: XCUIElement) {
        XCTAssertTrue(stepper.waitForExistence(timeout: 5), "stepper not found")
        let width = stepper.frame.width
        stepper.coordinate(withNormalizedOffset: CGVector(dx: max(0.5, (width - 24) / width), dy: 0.5)).tap()
    }

    /// Writes a marker file the recording script waits on (the simulator shares the host's /tmp).
    private func marker(_ name: String) {
        FileManager.default.createFile(atPath: "/tmp/eet-clip-\(name)", contents: Data())
    }

    /// Scrolls toward `element` until it is tappable.
    @MainActor
    private func scrollUntilHittable(_ element: XCUIElement, maxSwipes: Int = 10) {
        var count = 0
        while !element.isHittable && count < maxSwipes {
            app.swipeUp()
            count += 1
        }
    }

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
