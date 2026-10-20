import AirCookerCore
import Foundation
import LocalAuthentication
import Observation
import UserNotifications
import WidgetKit

@MainActor @Observable final class AppModel {
  var importIDs: [UUID] = (UserDefaults.standard.stringArray(forKey: "importIDs") ?? []).compactMap
  { UUID(uuidString: $0) }
  var inbox: ShareInbox?
  var store: LocalStore?
  var client: APIClient?
  var syncEngine: SyncEngine?
  var recipes: [LocalEntity] = []
  var meals: [LocalEntity] = []
  var pantry: [LocalEntity] = []
  var templates: [LocalEntity] = []
  var leftovers: [LocalEntity] = []
  var photoRevision = 0
  var pending = 0
  var busy = false
  var error: String?
  var connected = false
  var locked = false
  var householdTimeZone =
    UserDefaults.standard.string(forKey: "householdTimeZone") ?? TimeZone.current.identifier
  var server = UserDefaults.standard.string(forKey: "server") ?? ""
  var reminderPreferences =
    (UserDefaults.standard.data(forKey: "mealReminders")
      .flatMap { try? JSONDecoder().decode(ReminderPreferences.self, from: $0) })
    ?? ReminderPreferences()
  var reminderPermission = "not_determined"
  var scheduledReminders = 0
  var showWidgetNames = UserDefaults.standard.object(forKey: "showWidgetNames") as? Bool ?? true
  var destination: AppDestination?
  private let reminders = MealReminders()
  private var reloadGeneration = 0
  private var notificationRouter: NotificationRouter?
  init() {
    let router = NotificationRouter { [weak self] url in self?.openDestination(url) }
    notificationRouter = router
    UNUserNotificationCenter.current().delegate = router
  }
  func openDestination(_ url: URL) {
    if let value = AppDestination(url: url) { destination = value }
  }
  func setRemindersEnabled(_ value: Bool) async {
    do {
      if value {
        let permitted = try await reminders.requestPermission()
        if !permitted {
          reminderPermission = await reminders.permission()
          return
        }
      }
      var preferences = reminderPreferences
      preferences.enabled = value
      updateReminderPreferences(preferences)
    } catch { report(error) }
  }
  func updateReminderPreferences(_ preferences: ReminderPreferences) {
    do {
      let data = try JSONEncoder().encode(preferences)
      UserDefaults.standard.set(data, forKey: "mealReminders")
      reminderPreferences = preferences
      Task { await refreshReminders() }
    } catch { report(error) }
  }
  func refreshReminderStatus() async {
    reminderPermission = await reminders.permission()
    scheduledReminders = await reminders.count()
  }
  func refreshReminders() async {
    guard let store else { return }
    do {
      let snapshot = try await store.planningSnapshot()
      let plan = try MealPresentation.reminders(
        snapshot: snapshot, preferences: reminderPreferences,
        timeZone: householdTimeZone, now: Date())
      try await reminders.reconcile(plan, showRecipeNames: reminderPreferences.showRecipeNames)
      await refreshReminderStatus()
    } catch { report(error) }
  }
  func setWidgetNames(_ value: Bool) {
    showWidgetNames = value
    UserDefaults.standard.set(value, forKey: "showWidgetNames")
    do { try publishWidget() } catch { report(error) }
  }
  private var vault: KeychainVault?
  func start() async {
    do {
      let directory = try FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true,
        attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
      if let group = Bundle.main.object(forInfoDictionaryKey: "AirCookerAppGroup") as? String,
        let shared = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
      {
        inbox = try ShareInbox(directory: shared)
      }
      store = try LocalStore(url: directory.appending(path: "aircooker.sqlite3"))
      if !server.isEmpty && !UserDefaults.standard.bool(forKey: "signedOut") {
        try configureClient()
        connected = true
      }
      if !connected {
        clearWidget()
        try await reminders.reconcile([], showRecipeNames: false)
      }
      await reload()
      if UserDefaults.standard.bool(forKey: "biometricLock") {
        locked = true
        await unlock()
      }
      if !locked { await synchronise() }
    } catch { report(error) }
  }
  func configureClient() throws {
    guard let url = URL(string: server) else { throw APIError.invalidServerURL }
    let vault = KeychainVault(server: url.absoluteString)
    self.vault = vault
    let client = try APIClient(baseURL: url, vault: vault)
    self.client = client
    if let store { syncEngine = SyncEngine(store: store, client: client) }
  }
  func login(username: String, password: String) async {
    busy = true
    defer { busy = false }
    do {
      try configureClient()
      guard let client, let store else { throw StoreError.invalidRecord }
      let info = try await client.info()
      guard let instance = info.instanceID else { throw APIError.incompatibleServer }
      try await store.bind(instanceID: instance)
      let deviceID = try await store.deviceID()
      try await client.login(username: username, password: password, deviceID: deviceID)
      UserDefaults.standard.set(server, forKey: "server")
      connected = true
      UserDefaults.standard.set(false, forKey: "signedOut")
      error = nil
      await synchronise()
    } catch { report(error) }
  }
  func synchronise() async {
    guard !locked, let syncEngine else { return }
    busy = true
    defer { busy = false }
    do {
      try await syncEngine.synchronise()
      if let settings = try await client?.household(), let timezone = settings["timezone"] {
        householdTimeZone = timezone
        UserDefaults.standard.set(timezone, forKey: "householdTimeZone")
      }
      try await submitImports()
      error = nil
    } catch { report(error) }
    await reload()
  }
  func setup(username: String, password: String, token: String, name: String, timezone: String)
    async
  {
    busy = true
    defer { busy = false }
    do {
      try configureClient()
      guard let client, let store else { throw StoreError.invalidRecord }
      let deviceID = try await store.deviceID()
      let language = Locale.current.language.languageCode?.identifier == "de" ? "de" : "en"
      try await client.setup(
        username: username, password: password, deviceID: deviceID, name: name, timezone: timezone,
        language: language, setupToken: token)
      let info = try await client.info()
      guard let instance = info.instanceID else { throw APIError.incompatibleServer }
      try await store.bind(instanceID: instance)
      UserDefaults.standard.set(server, forKey: "server")
      connected = true
      UserDefaults.standard.set(false, forKey: "signedOut")
      await synchronise()
    } catch { report(error) }
  }
  func queueImport(url: String?, text: String?) async {
    do {
      guard let inbox else { throw StoreError.invalidRecord }
      if let url {
        guard let parsed = URL(string: url), parsed.scheme == "https", parsed.host != nil,
          parsed.user == nil, parsed.password == nil
        else { throw APIError.invalidServerURL }
      }
      try await inbox.enqueue(SharedImport(url: url, text: text))
      await synchronise()
    } catch { report(error) }
  }
  func submitImports() async throws {
    guard let inbox, let client else { return }
    for request in try await inbox.pending() {
      _ = try await client.beginImport(id: request.id, url: request.url, text: request.text)
      if !importIDs.contains(request.id) {
        importIDs.append(request.id)
        UserDefaults.standard.set(importIDs.map(\.uuidString), forKey: "importIDs")
      }
      try await inbox.acknowledge(request)
    }
  }
  func reload() async {
    guard let store else { return }
    reloadGeneration += 1
    let generation = reloadGeneration
    do {
      let snapshot = try await store.planningSnapshot()
      let currentPantry = try await store.entities(kind: .pantry)
      let currentTemplates = try await store.entities(kind: .template)
      let currentPending = try await store.pendingCount()
      guard generation == reloadGeneration else { return }
      recipes = snapshot.recipes
      meals = snapshot.meals
      leftovers = snapshot.leftovers
      pantry = currentPantry
      templates = currentTemplates
      pending = currentPending
      photoRevision += 1
      if connected {
        try publishWidget()
        await refreshReminders()
      }
    } catch { report(error) }
  }
  func save<T: Encodable & Sendable>(
    kind: EntityKind, id: UUID = UUID(), value: T, delete: Bool = false
  ) async -> Bool {
    guard let store else { return false }
    do {
      try await store.save(kind: kind, id: id, value: value, delete: delete)
      await reload()
      Task { await synchronise() }
      return true
    } catch {
      report(error)
      return false
    }
  }
  func saveRecipe(id: UUID, recipe: Recipe, photo: Data?) async -> Bool {
    guard let store else { return false }
    do {
      try await store.saveRecipe(id: id, recipe: recipe, photo: photo)
      await reload()
      Task { await synchronise() }
      return true
    } catch {
      report(error)
      return false
    }
  }
  func saveBatch(_ edits: [LocalEdit]) async -> Bool {
    guard let store else { return false }
    do {
      try await store.saveBatch(edits)
      await reload()
      Task { await synchronise() }
      return true
    } catch {
      report(error)
      return false
    }
  }
  func parsePortions(_ input: String, allowZero: Bool = false) throws -> Decimal {
    let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    return try PortionQuantity.parse(
      Locale.current.decimalSeparator == "," ? text.replacingOccurrences(of: ",", with: ".") : text,
      allowZero: allowZero)
  }
  func planningDate(_ text: String) -> Date? {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: householdTimeZone)
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.isLenient = false
    return formatter.date(from: text)
  }
  func displayPlanningDate(_ text: String) -> String {
    guard let date = planningDate(text) else { return text }
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(identifier: householdTimeZone)
    formatter.dateStyle = .medium
    return formatter.string(from: date)
  }
  func formatPortions(_ value: Decimal) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = false
    formatter.maximumFractionDigits = 38
    return formatter.string(from: NSDecimalNumber(decimal: value))
      ?? NSDecimalNumber(decimal: value).stringValue
  }
  func defaultLeftoverPortions(_ row: LocalEntity) -> String {
    guard let leftover = try? row.decode(Leftover.self),
      let recipe = self.recipe(leftover.recipeID),
      let amount = try? PortionQuantity.parse(recipe.servings),
      let available = try? LeftoverPlanning.available(id: row.id, leftover: leftover, meals: meals)
    else { return "1" }
    return formatPortions(min(amount, available))
  }
  func availablePortions(_ row: LocalEntity) -> String {
    guard
      let value = try? LeftoverPlanning.available(
        id: row.id,
        leftover: row.decode(Leftover.self), meals: meals)
    else { return "0" }
    return formatPortions(value)
  }
  func allocatedPortions(_ row: LocalEntity) -> String {
    let value = (try? LeftoverPlanning.allocated(id: row.id, meals: meals)) ?? 0
    return formatPortions(value)
  }
  func canScheduleLeftover(_ row: LocalEntity) -> Bool {
    guard let leftover = try? row.decode(Leftover.self), !leftover.discarded,
      recipe(leftover.recipeID) != nil
    else { return false }
    return ((try? LeftoverPlanning.available(id: row.id, leftover: leftover, meals: meals)) ?? 0)
      > 0
  }
  func saveLeftover(
    existing: LocalEntity?, source: MealOccurrence?, recipeID: UUID,
    unplanned: String, producedOn: String, discard: Bool
  ) async -> Bool {
    guard let store else { return false }
    do {
      if let source {
        try await store.recordLeftovers(
          from: source,
          portions: NSDecimalNumber(decimal: parsePortions(unplanned)).stringValue,
          today: dateString(Date()))
      } else {
        let canonical =
          discard
          ? "0"
          : NSDecimalNumber(decimal: try parsePortions(unplanned, allowZero: existing != nil))
            .stringValue
        try await store.setUnplannedPortions(
          id: existing?.id ?? UUID(), recipeID: recipeID,
          producedOn: producedOn, unplanned: canonical, discard: discard)
      }
      await reload()
      Task { await synchronise() }
      return true
    } catch {
      report(error)
      return false
    }
  }
  func scheduleLeftover(id: UUID, date: String, category: String, portions: String) async -> Bool {
    guard let store else { return false }
    do {
      guard let row = try await store.entities(kind: .leftover).first(where: { $0.id == id }) else {
        throw LeftoverError.unavailable
      }
      let value = try row.decode(Leftover.self)
      var meal = Meal(
        recipeID: value.recipeID, date: date, category: category,
        servings: NSDecimalNumber(decimal: try parsePortions(portions)).stringValue)
      meal.leftoverID = id
      try await store.save(kind: .meal, id: UUID(), value: meal)
      await reload()
      Task { await synchronise() }
      return true
    } catch {
      report(error)
      return false
    }
  }
  func applySuggestions(_ preview: WeeklyPreview, selected: Set<String>) async -> Bool {
    guard let store else { return false }
    do {
      try await store.applySuggestions(preview, selectedIDs: selected)
      await reload()
      Task { await synchronise() }
      return true
    } catch {
      report(error)
      return false
    }
  }
  func recipe(_ id: UUID) -> Recipe? {
    try? recipes.first(where: { $0.id == id })?.decode(Recipe.self)
  }
  func title(_ meal: Meal) -> String {
    recipe(meal.recipeID)?.title ?? String(localized: "recipe_unavailable")
  }
  func dateString(_ date: Date) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: householdTimeZone) ?? .current
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year ?? 2000, parts.month ?? 1, parts.day ?? 1)
  }
  func enableLocalLock() async -> Bool {
    let context = LAContext()
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
      error = String(localized: "biometric_unavailable")
      return false
    }
    do {
      return try await context.evaluatePolicy(
        .deviceOwnerAuthentication, localizedReason: String(localized: "unlock_reason"))
    } catch {
      report(error)
      return false
    }
  }
  func beginPasswordUnlock() {
    connected = false
    locked = false
  }
  func unlock() async {
    do {
      let context = LAContext()
      guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
        error = String(localized: "biometric_unavailable")
        return
      }
      locked =
        !(try await context.evaluatePolicy(
          .deviceOwnerAuthentication, localizedReason: String(localized: "unlock_reason")))
    } catch { report(error) }
  }
  func logout() async {
    // Preserve cached content and unsent edits. Server session revocation is available in the console.
    do {
      try await vault?.clear()
      UserDefaults.standard.set(true, forKey: "signedOut")
      connected = false
      destination = nil
      try await reminders.reconcile([], showRecipeNames: false)
      clearWidget()
      client = nil
      syncEngine = nil
    } catch { report(error) }
  }
  func report(_ problem: any Error) {
    switch problem {
    case APIError.http(_, let code):
      switch code {
      case "insufficient_leftover_portions": error = String(localized: "leftover_reserved_error")
      case "leftover_not_yet_produced", "leftover_produced_after_booking":
        error = String(localized: "leftover_production_error")
      case "leftover_in_use", "leftover_recipe_in_use":
        error = String(localized: "leftover_in_use_error")
      case "invalid_leftover", "leftover_not_found":
        error = String(localized: "leftover_unavailable_error")
      case "suggestion_preview_stale", "suggestion_slot_occupied":
        error = String(localized: "suggestions_stale")
      default: error = String(localized: "server_error") + " " + code
      }
    case APIError.invalidServerURL: error = String(localized: "invalid_server")
    case APIError.incompatibleServer: error = String(localized: "incompatible_server")
    case StoreError.rejectedDeletion: error = String(localized: "tombstone_conflict")
    case StoreError.invalidPhoto: error = String(localized: "photo_invalid")
    case StoreError.mediaStorageLimit: error = String(localized: "photo_storage_full")
    case PlanningError.leftoverCannotBeCopied: error = String(localized: "leftover_copy_error")
    case PlanningError.invalidDate, PlanningError.invalidWindow, PlanningError.invalidRecurrence:
      error = String(localized: "planning_date_error")
    case PlanningError.unavailableRecipe: error = String(localized: "template_recipe_missing")
    case PlanningError.invalidTemplate, PlanningError.tooManyChanges:
      error = String(localized: "template_invalid")
    case SuggestionError.stalePreview: error = String(localized: "suggestions_stale")
    case SuggestionError.invalidOptions: error = String(localized: "suggestions_options_error")
    case LeftoverError.invalidPortions: error = String(localized: "leftover_portions_error")
    case LeftoverError.insufficientPortions: error = String(localized: "leftover_reserved_error")
    case LeftoverError.notProduced: error = String(localized: "leftover_production_error")
    case LeftoverError.discarded: error = String(localized: "leftover_discarded_error")
    case LeftoverError.inUse, LeftoverError.recipeInUse:
      error = String(localized: "leftover_in_use_error")
    case LeftoverError.unavailable: error = String(localized: "leftover_unavailable_error")
    case StoreError.serverChanged: error = String(localized: "server_changed")
    default: error = String(localized: "operation_failed")
    }
  }
  func clearWidget() {
    guard let group = Bundle.main.object(forInfoDictionaryKey: "AirCookerAppGroup") as? String,
      let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    else { return }
    for name in ["today.json", "meals-widget-v1.json"] {
      try? FileManager.default.removeItem(at: directory.appending(path: name))
    }
    WidgetCenter.shared.reloadAllTimelines()
  }
  func publishWidget() throws {
    guard let group = Bundle.main.object(forInfoDictionaryKey: "AirCookerAppGroup") as? String,
      let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    else { return }
    let snapshot = try MealWidgetSnapshot.build(
      snapshot: PlanningSnapshot(recipes: recipes, meals: meals, leftovers: leftovers),
      timeZone: householdTimeZone, now: Date(), showNames: showWidgetNames)
    try JSONEncoder().encode(snapshot).write(
      to: directory.appending(path: "meals-widget-v1.json"),
      options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    try? FileManager.default.removeItem(at: directory.appending(path: "today.json"))
    WidgetCenter.shared.reloadAllTimelines()
  }
}
