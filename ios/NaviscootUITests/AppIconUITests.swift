import XCTest

final class AppIconUITests: XCTestCase {
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() {
        continueAfterFailure = false
    }

    // The simulator only repaints a changed appearance after a reboot, so the test shoots the current one.
    func testHomeScreenShowsTheIcon() {
        XCUIDevice.shared.press(.home)
        let icon = springboard.icons["Naviscoot"]
        XCTAssertTrue(icon.waitForExistence(timeout: 10))
        var swipes = 0
        while !icon.isHittable && swipes < 6 {
            springboard.swipeLeft()
            swipes += 1
        }
        XCTAssertTrue(icon.isHittable, "the Naviscoot icon is not on any home screen page")
        Thread.sleep(forTimeInterval: 2)
        screenshot(XCUIDevice.shared.appearance == .dark ? "home-dark" : "home-light")
    }

    private func screenshot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}
