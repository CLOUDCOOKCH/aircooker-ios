import AirCookerCore
import Foundation
import LocalAuthentication
import Observation
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
  var photoRevision = 0
  var pending = 0
  var busy = false
  var error: String?
  var connected = false
  var locked = false
  var householdTimeZone =
    UserDefaults.standard.string(forKey: "householdTimeZone") ?? TimeZone.current.identifier
  var server = UserDefaults.standard.string(forKey: "server") ?? ""
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
      if !server.isEmpty {
        try configureClient()
        connected = true
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
    do {
      recipes = try await store.entities(kind: .recipe)
      meals = try await store.entities(kind: .meal)
      pantry = try await store.entities(kind: .pantry)
      templates = try await store.entities(kind: .template)
      pending = try await store.pendingCount()
      photoRevision += 1
      try publishWidget()
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
      connected = false
      client = nil
      syncEngine = nil
    } catch { report(error) }
  }
  func report(_ problem: any Error) {
    switch problem {
    case APIError.http(_, let code): error = String(localized: "server_error") + " " + code
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
    case StoreError.serverChanged: error = String(localized: "server_changed")
    default: error = String(localized: "operation_failed")
    }
  }
  func publishWidget() throws {
    guard let group = Bundle.main.object(forInfoDictionaryKey: "AirCookerAppGroup") as? String,
      let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    else { return }
    let today = dateString(Date())
    let snapshot = try MealPlanning.expand(meals, from: today, through: today).map { item in
      ["id": item.entityID.uuidString, "category": item.meal.category, "title": title(item.meal)]
    }
    try JSONEncoder().encode(["date": JSONValue.string(today), "meals": try Codec.json(snapshot)])
      .write(
        to: directory.appending(path: "today.json"),
        options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    WidgetCenter.shared.reloadAllTimelines()
  }
}
