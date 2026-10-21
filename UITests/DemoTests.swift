import XCTest

final class DemoTests: XCTestCase {
  @MainActor private func enterDemo(_ app: XCUIApplication, language: String = "en") {
    app.launchArguments = [
      "-AppleLanguages", "(\(language))", "-AppleLocale", language == "de" ? "de_DE" : "en_US",
    ]
    app.launch()
    let button = app.buttons["onboarding.demo"]
    XCTAssertTrue(button.waitForExistence(timeout: 20))
    let ready = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "enabled == true"), object: button)
    XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
    button.tap()
    XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
    XCTAssertTrue(app.buttons["demo.exit"].exists)
  }
  @MainActor private func capture(_ app: XCUIApplication, name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
  @MainActor private func type(_ text: String, into field: XCUIElement, in app: XCUIApplication)
    -> Bool
  {
    guard field.waitForExistence(timeout: 10) else {
      XCTFail("The editing field did not appear")
      return false
    }
    field.tap()
    // A newly booted hosted simulator can initialise its keyboard after the first tap.
    if !app.keyboards.firstMatch.waitForExistence(timeout: 10) { field.tap() }
    guard app.keyboards.firstMatch.waitForExistence(timeout: 10) else {
      XCTFail("The editing field did not open the keyboard")
      return false
    }
    field.typeText(text)
    return true
  }
  @MainActor func testDemoRecipePersistsAcrossAppRestartAndCanExit() {
    let app = XCUIApplication()
    enterDemo(app)
    capture(app, name: "demo-home-en")
    app.tabBars.buttons["Recipes"].tap()
    XCTAssertTrue(app.buttons["recipes.create"].waitForExistence(timeout: 10))
    capture(app, name: "demo-recipes-en")
    app.buttons["recipes.create"].tap()
    let title = app.textFields["recipe.title"]
    guard type("Review demo recipe", into: title, in: app) else { return }
    XCTAssertTrue(app.buttons["recipe.save"].isEnabled)
    app.buttons["recipe.save"].tap()
    XCTAssertTrue(app.buttons["recipes.create"].waitForExistence(timeout: 10))
    app.terminate()
    enterDemo(app)
    app.tabBars.buttons["Recipes"].tap()
    app.swipeDown()
    let search = app.searchFields.firstMatch
    guard type("Review demo recipe", into: search, in: app) else { return }
    XCTAssertTrue(app.staticTexts["Review demo recipe"].waitForExistence(timeout: 10))
    capture(app, name: "demo-persisted-recipe-en")
    app.buttons["demo.exit"].tap()
    XCTAssertTrue(app.textFields["onboarding.server"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["onboarding.connect"].isEnabled)
  }
  @MainActor func testGermanDemoNavigation() {
    let app = XCUIApplication()
    enterDemo(app, language: "de")
    XCTAssertTrue(app.tabBars.buttons["Rezepte"].exists)
    capture(app, name: "demo-home-de")
    app.tabBars.buttons["Rezepte"].tap()
    capture(app, name: "demo-recipes-de")
    app.buttons["demo.exit"].tap()
    XCTAssertTrue(app.buttons["onboarding.demo"].waitForExistence(timeout: 10))
  }
}
