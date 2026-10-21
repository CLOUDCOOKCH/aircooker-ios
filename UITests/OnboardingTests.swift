import XCTest

final class OnboardingTests: XCTestCase {
  @MainActor func testWelcomeRequiresServerAndCredentials() {
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    app.launch()
    XCTAssertTrue(app.textFields["onboarding.server"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["onboarding.connect"].isEnabled)
    XCTAssertTrue(app.secureTextFields["onboarding.password"].exists)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "onboarding-en"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }
}
