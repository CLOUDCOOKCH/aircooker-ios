import MealfCore
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
  var syncIssues: [SyncIssue] = []
  var resyncRequired = false
  var resyncRebuilding = false
  var resyncStagedCount = 0
  var cachedRecordCount = 0
  var authenticationExpired = false
  private var synchronising = false
  var pending = 0
  var busy = false
  var error: String?
  var connected = false
  var isDemo = false
  var ready = false
  private var starting = false
  private var householdStore: LocalStore?
  private var householdDemoTimeZone: String?
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
    guard connected, !isDemo, !signingOut, let store else { return }
    do {
      let snapshot = try await store.planningSnapshot()
      let plan = try MealPresentation.reminders(
        snapshot: snapshot, preferences: reminderPreferences,
        timeZone: householdTimeZone, now: Date())
      guard connected, !signingOut else { return }
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
  // Reuse one actor per exact Keychain service, including requests still in flight.
  private var vaults: [String: KeychainVault] = [:]
  var pendingSignOuts = 0
  var retryingSignOuts = false
  private func vaultFor(_ server: String) -> KeychainVault {
    if let existing = vaults[server] { return existing }
    let value = KeychainVault(server: server)
    vaults[server] = value
    return value
  }
  func start() async {
    guard !ready, !starting else { return }
    starting = true
    defer {
      starting = false
      ready = store != nil
    }
    do {
      let directory = try FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true,
        attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
      if let group = Bundle.main.object(forInfoDictionaryKey: "MealfAppGroup") as? String,
        let shared = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
      {
        inbox = try ShareInbox(directory: shared)
      }
      store = try LocalStore(url: directory.appending(path: "mealf.sqlite3"))
      if !server.isEmpty {
        try configureClient()
        let active = try await vault?.read().active
        connected = !UserDefaults.standard.bool(forKey: "signedOut") && active != nil
        if !connected {
          client = nil
          syncEngine = nil
        }
      }
      Task { await retrySignOuts() }
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
    guard !isDemo else { throw APIError.signedOut }
    guard let url = URL(string: server) else { throw APIError.invalidServerURL }
    let vault = vaultFor(url.absoluteString)
    self.vault = vault
    let client = try APIClient(baseURL: url, vault: vault)
    self.client = client
    var known = UserDefaults.standard.stringArray(forKey: "revocationServers") ?? []
    if !known.contains(url.absoluteString) {
      known.append(url.absoluteString)
      UserDefaults.standard.set(known, forKey: "revocationServers")
    }
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
      authenticationExpired = false
      UserDefaults.standard.set(false, forKey: "signedOut")
      error = nil
      await synchronise()
    } catch { report(error) }
  }
  func synchronise() async {
    guard connected, !signingOut, !locked, !synchronising, let syncEngine else { return }
    synchronising = true
    busy = true
    defer {
      synchronising = false
      busy = false
    }
    do {
      var needsReview = false
      do { try await syncEngine.synchronise() } catch StoreError.syncNeedsAttention {
        needsReview = true
      }
      guard connected, !signingOut else { return }
      if let settings = try await client?.household(), let timezone = settings["timezone"] {
        householdTimeZone = timezone
        UserDefaults.standard.set(timezone, forKey: "householdTimeZone")
      }
      try await submitImports()
      if needsReview { report(StoreError.syncNeedsAttention) } else { error = nil }
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
      authenticationExpired = false
      UserDefaults.standard.set(false, forKey: "signedOut")
      await synchronise()
    } catch { report(error) }
  }
  func queueImport(url: String?, text: String?) async {
    guard !isDemo else {
      error = String(localized: "demo_server_features")
      return
    }
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
      let currentIssues = try await store.syncIssues()
      let recovery = try await store.recoveryStatus()
      guard generation == reloadGeneration else { return }
      recipes = snapshot.recipes
      meals = snapshot.meals
      leftovers = snapshot.leftovers
      pantry = currentPantry
      templates = currentTemplates
      pending = currentPending
      syncIssues = currentIssues
      resyncRequired = recovery.required
      resyncRebuilding = recovery.rebuilding
      resyncStagedCount = recovery.stagedCount
      cachedRecordCount = recovery.localCount
      photoRevision += 1
      if connected && !isDemo {
        try publishWidget()
        await refreshReminders()
      }
    } catch { report(error) }
  }
  func rebuildFromServer() async {
    guard !busy, !locked, let syncEngine else { return }
    busy = true
    synchronising = true
    do {
      try await syncEngine.rebuildFromServer()
      error = nil
    } catch { report(error) }
    await reload()
    busy = false
    synchronising = false
    if !resyncRequired { Task { await synchronise() } }
  }
  func retrySyncIssue(_ issue: SyncIssue) async -> Bool {
    guard !busy, let syncEngine else { return false }
    do {
      try await syncEngine.retry(issue)
      await reload()
      Task { await synchronise() }
      return true
    } catch {
      report(error)
      await reload()
      return false
    }
  }
  func resolveSyncIssue(_ issue: SyncIssue, keepRecipeCopy: Bool) async -> Bool {
    guard !busy, let syncEngine else { return false }
    busy = true
    defer { busy = false }
    do {
      _ = try await syncEngine.resolve(issue, keepRecipeCopy: keepRecipeCopy)
      error = nil
      await reload()
      Task { await synchronise() }
      return true
    } catch {
      report(error)
      await reload()
      return false
    }
  }
  func restoreArchivedRecipe(_ draft: ArchivedDraft) async -> Bool {
    guard !busy, let syncEngine else { return false }
    busy = true
    defer { busy = false }
    do {
      _ = try await syncEngine.restoreRecipe(draft)
      error = nil
      await reload()
      Task { await synchronise() }
      return true
    } catch {
      report(error)
      return false
    }
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
    if isDemo {
      await endDemo()
      return
    }
    guard !signingOut, let client else { return }
    signingOut = true
    defer { signingOut = false }
    do {
      try await client.signOut()
      // Only a successful atomic Keychain write permits disconnecting the UI.
      UserDefaults.standard.set(true, forKey: "signedOut")
      connected = false
      authenticationExpired = false
      pendingSignOuts = max(pendingSignOuts, 1)
      destination = nil
      self.client = nil
      syncEngine = nil
      error = nil
      clearWidget()
      do { try await reminders.reconcile([], showRecipeNames: false) } catch { report(error) }
      signingOut = false
      Task { await retrySignOuts() }
    } catch { report(error) }
  }
  var signingOut = false
  func beginDemo() async {
    guard ready, !connected, !busy, !signingOut, !isDemo, let currentStore = store else { return }
    busy = true
    defer { busy = false }
    do {
      let directory = try FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      let demo = try LocalStore(url: DemoWorkspace.databaseURL(in: directory))
      guard let asset = Bundle.main.url(forResource: "DemoChicken", withExtension: "png") else {
        throw StoreError.invalidPhoto
      }
      let photo = try await Task.detached(priority: .userInitiated) {
        try PhotoPreparation.prepare(Data(contentsOf: asset))
      }.value
      let zone = TimeZone.current.identifier
      let language = Locale.current.language.languageCode?.identifier ?? "en"
      let seed = try DemoWorkspace.seed(
        now: Date(), timeZone: zone, language: language, withPhoto: true)
      try await demo.initialiseDemo(seed, photos: [DemoWorkspace.photoID: photo])
      householdStore = currentStore
      householdDemoTimeZone = householdTimeZone
      client = nil
      syncEngine = nil
      vault = nil
      store = demo
      householdTimeZone = zone
      isDemo = true
      clearPresentation()
      clearWidget()
      do { try await reminders.reconcile([], showRecipeNames: false) } catch { report(error) }
      await reload()
      connected = true
    } catch { report(error) }
  }
  func endDemo() async {
    guard isDemo, !busy else { return }
    busy = true
    defer { busy = false }
    connected = false
    isDemo = false
    store = householdStore
    householdStore = nil
    householdTimeZone = householdDemoTimeZone ?? TimeZone.current.identifier
    householdDemoTimeZone = nil
    client = nil
    syncEngine = nil
    vault = nil
    clearPresentation()
    clearWidget()
    do { try await reminders.reconcile([], showRecipeNames: false) } catch { report(error) }
    await reload()
  }
  private func clearPresentation() {
    // Invalidate older actor reads before switching data sources. Clearing
    // derived views never removes a database record or queued mutation.
    reloadGeneration += 1
    recipes = []
    meals = []
    pantry = []
    leftovers = []
    templates = []
    pending = 0
    syncIssues = []
    resyncRequired = false
    resyncRebuilding = false
    resyncStagedCount = 0
    cachedRecordCount = 0
    authenticationExpired = false
    destination = nil
    error = nil
    photoRevision += 1
  }
  func retrySignOuts() async {
    guard !retryingSignOuts else { return }
    retryingSignOuts = true
    defer { retryingSignOuts = false }
    var jobs: [(APIClient, KeychainVault)] = []
    var total = 0
    for server in UserDefaults.standard.stringArray(forKey: "revocationServers") ?? [] {
      do {
        guard let url = URL(string: server) else { continue }
        let vault = vaultFor(server)
        let client = try APIClient(baseURL: url, vault: vault)
        let count = try await vault.read().pending.count
        total += count
        if count > 0 { jobs.append((client, vault)) }
      } catch { report(error) }
    }
    pendingSignOuts = total
    for (client, vault) in jobs {
      do {
        let before = try await vault.read().pending.count
        // Offline/old-server failures deliberately leave the capability in Keychain.
        do { try await client.retryRevocations() } catch {}
        let remaining = try await vault.read().pending.count
        pendingSignOuts = max(0, pendingSignOuts - before + remaining)
      } catch {
        // Keep the last known count and surface a secure-storage failure.
        report(error)
      }
    }
  }

  func report(_ problem: any Error) {
    switch problem {
    case APIError.http(let status, let code):
      if status == 401 { authenticationExpired = true }
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
    case APIError.signedOut: return
    case APIError.invalidServerURL: error = String(localized: "invalid_server")
    case APIError.incompatibleServer: error = String(localized: "incompatible_server")
    case StoreError.fullResyncRequired:
      error = String(localized: "server_history_recovery_required")
    case StoreError.syncNeedsAttention: error = String(localized: "sync_attention_hint")
    case StoreError.recoveryChanged: error = String(localized: "sync_review_changed")
    case StoreError.serverSnapshotUnavailable: error = String(localized: "sync_snapshot_missing")
    case StoreError.syncInProgress: error = String(localized: "sync_in_progress")
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
    guard let group = Bundle.main.object(forInfoDictionaryKey: "MealfAppGroup") as? String,
      let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    else { return }
    for name in ["today.json", "meals-widget-v1.json"] {
      try? FileManager.default.removeItem(at: directory.appending(path: name))
    }
    WidgetCenter.shared.reloadAllTimelines()
  }
  func publishWidget() throws {
    guard let group = Bundle.main.object(forInfoDictionaryKey: "MealfAppGroup") as? String,
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
