import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif
public struct Tokens: Codable, Sendable {
  public var accessToken: String
  public var refreshToken: String
  public var expiresIn: Int
  public var sessionID: UUID
  enum CodingKeys: String, CodingKey {
    case accessToken = "access_token"
    case refreshToken = "refresh_token"
    case expiresIn = "expires_in"
    case sessionID = "session_id"
  }
}
public struct SystemInfo: Codable, Sendable {
  public var name: String
  public var instanceID: String?
  public var version: String
  public var apiMajor: Int
  public var syncProtocol: Int
  public var configured: Bool
  enum CodingKeys: String, CodingKey {
    case name
    case instanceID = "instance_id"
    case version
    case apiMajor = "api_major"
    case syncProtocol = "sync_protocol"
    case configured
  }
}
public enum APIError: Error, Sendable {
  case invalidServerURL, incompatibleServer
  case http(Int, String)
  case invalidResponse
}
public protocol TokenVault: Sendable {
  func load() async throws -> Tokens?
  func save(_ tokens: Tokens) async throws
  func clear() async throws
}
private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) { completionHandler(nil) }
}
public protocol SyncTransport: Sendable {
  func info() async throws -> SystemInfo
  func push(_ mutation: Mutation) async throws -> MutationResult
  func pull(cursor: Int, token: String) async throws -> PullPage
  func syncState(cursor: Int) async throws -> SyncState
  func snapshot(checkpoint: SyncAnchor, after: String?) async throws -> SyncSnapshot
  func uploadPhoto(_ photo: PendingPhoto) async throws -> MediaInfo
  func downloadPhoto(id: UUID) async throws -> Data
}
public actor APIClient: SyncTransport {
  private let baseURL: URL
  private let vault: any TokenVault
  private let session: URLSession
  private var refreshing: Task<Tokens, any Error>?
  private var pushCheckpoint: SyncAnchor?
  public init(baseURL: URL, vault: any TokenVault, session: URLSession? = nil) throws {
    guard baseURL.scheme == "https", baseURL.host != nil, baseURL.user == nil,
      baseURL.password == nil, baseURL.query == nil, baseURL.fragment == nil,
      baseURL.path.isEmpty || baseURL.path == "/"
    else { throw APIError.invalidServerURL }
    self.baseURL = baseURL
    self.vault = vault
    self.session =
      session ?? URLSession(configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil)
  }
  private func rawRequest(
    _ path: String, method: String = "GET", body: Data? = nil, authenticated: Bool = true,
    retry: Bool = true,
    contentType: String = "application/json", expectedType: String? = nil
  ) async throws -> Data {
    guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL, url.host == baseURL.host,
      url.scheme == "https"
    else { throw APIError.invalidServerURL }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.httpBody = body
    request.timeoutInterval = 30
    request.setValue(contentType, forHTTPHeaderField: "Content-Type")
    var usedAccessToken: String?
    if authenticated, let tokens = try await vault.load() {
      usedAccessToken = tokens.accessToken
      request.setValue("Bearer " + tokens.accessToken, forHTTPHeaderField: "Authorization")
    }
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
    // URLSession's default redirect handling must never forward credentials to another origin.
    guard http.url?.host == baseURL.host, http.url?.scheme == "https" else {
      throw APIError.invalidResponse
    }
    if http.statusCode == 401, authenticated, retry {
      guard let tokens = try await vault.load() else {
        throw APIError.http(401, "authentication_required")
      }
      if tokens.accessToken != usedAccessToken {
        return try await self.rawRequest(
          path, method: method, body: body, authenticated: true, retry: false,
          contentType: contentType, expectedType: expectedType)
      }
      if refreshing == nil {
        refreshing = Task {
          let refreshed: Tokens = try await self.request(
            "/api/v1/auth/refresh", method: "POST",
            body: JSONEncoder().encode(["refresh_token": tokens.refreshToken]),
            authenticated: false, retry: false)
          try await vault.save(refreshed)
          return refreshed
        }
      }
      do {
        _ = try await refreshing?.value
        refreshing = nil
      } catch {
        refreshing = nil
        throw error
      }
      return try await self.rawRequest(
        path, method: method, body: body, authenticated: true, retry: false,
        contentType: contentType, expectedType: expectedType)
    }
    guard (200..<300).contains(http.statusCode) else {
      let value = try? JSONDecoder().decode([String: [String: String]].self, from: data)
      throw APIError.http(http.statusCode, value?["error"]?["code"] ?? "request_failed")
    }
    if let expectedType {
      guard
        http.value(forHTTPHeaderField: "Content-Type")?.split(separator: ";").first?
          .trimmingCharacters(in: .whitespacesAndNewlines) == expectedType, data.count <= 1_048_576
      else { throw APIError.invalidResponse }
    }
    return data
  }
  private func request<T: Decodable & Sendable>(
    _ path: String, method: String = "GET", body: Data? = nil, authenticated: Bool = true,
    retry: Bool = true
  ) async throws -> T {
    try JSONDecoder().decode(
      T.self,
      from: await rawRequest(
        path, method: method, body: body, authenticated: authenticated, retry: retry))
  }
  public func uploadPhoto(_ photo: PendingPhoto) async throws -> MediaInfo {
    let boundary = "aircooker-" + UUID().uuidString
    var body = Data(
      "--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"photo.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n"
        .utf8)
    body.append(photo.data)
    body.append(Data("\r\n--\(boundary)--\r\n".utf8))
    let raw = try await rawRequest(
      "/api/v1/media/" + photo.id.uuidString, method: "PUT", body: body,
      contentType: "multipart/form-data; boundary=" + boundary)
    let info = try JSONDecoder().decode(MediaInfo.self, from: raw)
    guard info.id == photo.id, info.contentType == "image/jpeg",
      (1...1_048_576).contains(info.byteCount)
    else { throw APIError.invalidResponse }
    return info
  }
  public func downloadPhoto(id: UUID) async throws -> Data {
    try await rawRequest("/api/v1/media/" + id.uuidString, expectedType: "image/jpeg")
  }
  public func info() async throws -> SystemInfo {
    let info: SystemInfo = try await request("/api/v1/system/info", authenticated: false)
    guard info.apiMajor == 1, info.syncProtocol == 1 else { throw APIError.incompatibleServer }
    return info
  }
  public func login(username: String, password: String, deviceID: UUID) async throws {
    let body = try JSONEncoder().encode([
      "username": username, "password": password, "device_id": deviceID.uuidString,
    ])
    let tokens: Tokens = try await request(
      "/api/v1/auth/login", method: "POST", body: body, authenticated: false)
    try await vault.save(tokens)
  }
  public func push(_ mutation: Mutation) async throws -> MutationResult {
    guard let pushCheckpoint else { throw APIError.incompatibleServer }
    struct PushBody: Encodable {
      let mutations: [Mutation]
      let checkpoint: SyncAnchor
    }
    let results: [MutationResult] = try await request(
      "/api/v1/sync/push", method: "POST",
      body: JSONEncoder().encode(PushBody(mutations: [mutation], checkpoint: pushCheckpoint)))
    guard results.count == 1, results[0].mutationID == mutation.mutationID else {
      throw APIError.invalidResponse
    }
    return results[0]
  }
  public func pull(cursor: Int, token: String) async throws -> PullPage {
    guard SyncAnchor(cursor: cursor, token: token).valid else { throw APIError.invalidResponse }
    let page: PullPage = try await request(
      "/api/v1/sync/pull?cursor=\(cursor)&limit=100&token=\(token)")
    guard let returnedToken = page.cursorToken,
      SyncAnchor(cursor: page.cursor, token: returnedToken).valid
    else { throw APIError.invalidResponse }
    return page
  }
  public func syncState(cursor: Int) async throws -> SyncState {
    let state: SyncState = try await request("/api/v1/sync/state?cursor=\(cursor)")
    guard state.anchor.valid, state.requestedCursor == cursor else {
      throw APIError.invalidResponse
    }
    pushCheckpoint = state.anchor
    return state
  }
  public func snapshot(checkpoint: SyncAnchor, after: String?) async throws -> SyncSnapshot {
    guard checkpoint.valid else { throw APIError.invalidResponse }
    var components = URLComponents()
    components.path = "/api/v1/sync/snapshot"
    components.queryItems = [
      URLQueryItem(name: "cursor", value: String(checkpoint.cursor)),
      URLQueryItem(name: "token", value: checkpoint.token),
    ]
    if let after { components.queryItems?.append(URLQueryItem(name: "after", value: after)) }
    guard let path = components.string else { throw APIError.invalidServerURL }
    return try await request(path)
  }
  public func household() async throws -> [String: String] {
    try await request("/api/v1/household")
  }
  public func importDraft(id: UUID) async throws -> ImportDraft {
    try await request("/api/v1/imports/" + id.uuidString)
  }
  public func setup(
    username: String, password: String, deviceID: UUID, name: String, timezone: String,
    language: String, setupToken: String
  ) async throws {
    // Setup uses a one-time local administrator token; it never appears in a URL.
    guard let url = URL(string: "/api/v1/setup", relativeTo: baseURL) else {
      throw APIError.invalidServerURL
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 30
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(setupToken, forHTTPHeaderField: "X-Setup-Token")
    request.httpBody = try JSONEncoder().encode([
      "username": username, "password": password, "device_id": deviceID.uuidString, "name": name,
      "timezone": timezone, "language": language,
    ])
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 201 else {
      throw APIError.http((response as? HTTPURLResponse)?.statusCode ?? 0, "setup_failed")
    }
    try await vault.save(JSONDecoder().decode(Tokens.self, from: data))
  }
  public func beginImport(id: UUID = UUID(), url: String?, text: String?) async throws -> JSONValue
  {
    var body: [String: String] = ["request_id": id.uuidString]
    if let url { body["source_url"] = url }
    if let text { body["text"] = text }
    return try await request("/api/v1/imports", method: "POST", body: JSONEncoder().encode(body))
  }
}
public actor SyncEngine {
  private let store: LocalStore
  private let client: any SyncTransport
  private var running = false
  public init(store: LocalStore, client: any SyncTransport) {
    self.store = store
    self.client = client
  }
  public func retry(_ issue: SyncIssue) async throws {
    guard !running else { throw StoreError.syncInProgress }
    running = true
    defer { running = false }
    try await store.retry(issue)
  }
  @discardableResult public func resolve(_ issue: SyncIssue, keepRecipeCopy: Bool) async throws
    -> UUID?
  {
    guard !running else { throw StoreError.syncInProgress }
    running = true
    defer { running = false }
    return try await store.resolve(issue, keepRecipeCopy: keepRecipeCopy)
  }
  @discardableResult public func restoreRecipe(_ draft: ArchivedDraft) async throws -> UUID {
    guard !running else { throw StoreError.syncInProgress }
    running = true
    defer { running = false }
    return try await store.restoreRecipe(draft)
  }
  public func synchronise() async throws {
    guard !running else { return }
    running = true
    defer { running = false }
    do { try await runSync() } catch APIError.http(409, let code)
      where code == "sync_history_changed" || code == "cursor_ahead_of_server_full_resync_required"
    {
      try await store.requireFullResync(discardStaging: true)
      throw StoreError.fullResyncRequired
    }
  }
  private func runSync() async throws {
    let info = try await client.info()
    guard let instanceID = info.instanceID else { throw APIError.incompatibleServer }
    try await store.bind(instanceID: instanceID)
    if try await store.fullResyncState() != nil {
      try await resumeFullResync()
      return
    }
    if try await store.recoveryStatus().required { throw StoreError.fullResyncRequired }
    let cursor = try await store.cursor()
    let observed = try await store.observedAnchor()
    let state = try await client.syncState(cursor: observed?.cursor ?? cursor)
    guard state.instanceID == instanceID, state.anchor.valid,
      state.requestedCursor == (observed?.cursor ?? cursor)
    else { throw APIError.invalidResponse }
    guard let local = try await store.syncAnchor(), let observed,
      state.requestedToken == observed.token, state.cursor >= local.cursor
    else {
      try await store.requireFullResync()
      throw StoreError.fullResyncRequired
    }
    try await store.observe(state.anchor)
    while true {
      let photos = try await store.pendingPhotos()
      if photos.isEmpty { break }
      for photo in photos {
        try Task.checkCancellation()
        _ = try await client.uploadPhoto(photo)
        try await store.acknowledgePhoto(id: photo.id)
      }
    }
    // Always push before pull so remote deltas cannot overwrite pending local edits.
    while true {
      let pending = try await store.pending()
      if pending.isEmpty { break }
      for mutation in pending {
        // A photo may have been selected while an earlier network request was in flight.
        if mutation.kind == .recipe, let payload = mutation.payload,
          let recipe = try? JSONDecoder().decode(Recipe.self, from: JSONEncoder().encode(payload)),
          let imageID = recipe.imageID,
          let photo = try await store.pendingPhoto(id: imageID)
        {
          _ = try await client.uploadPhoto(photo)
          try await store.acknowledgePhoto(id: photo.id)
        }
        // Another request in this batch may have blocked this same entity.
        guard try await store.isReady(mutation) else { continue }
        do {
          let result = try await client.push(mutation)
          try await store.acknowledge(result, mutation: mutation)
        } catch StoreError.rejectedDeletion {
          // Durable rejection already recorded; continue other entities and pull the
          // server tombstone so the user can review a coherent recovery decision.
        } catch APIError.http(let status, let code)
          where [400, 404, 409, 413, 422].contains(status) && code != "sync_history_changed"
        {
          try await store.markFailure(mutation, code: code)
        }
      }
    }
    while true {
      let cursor = try await store.cursor()
      guard let anchor = try await store.syncAnchor() else { throw StoreError.fullResyncRequired }
      let page = try await client.pull(cursor: cursor, token: anchor.token)
      guard !page.hasMore || page.cursor > cursor else { throw APIError.invalidResponse }
      try await store.apply(page)
      if !page.hasMore { break }
    }
    for id in try await store.missingPhotos() {
      try Task.checkCancellation()
      let data = try await client.downloadPhoto(id: id)
      try await store.cachePhoto(id: id, data: data)
    }
    if try await !store.syncIssues().isEmpty { throw StoreError.syncNeedsAttention }
  }
  public func rebuildFromServer() async throws {
    guard !running else { throw StoreError.syncInProgress }
    running = true
    defer { running = false }
    let info = try await client.info()
    guard let instanceID = info.instanceID else { throw APIError.incompatibleServer }
    try await store.bind(instanceID: instanceID)
    // This method is invoked only after the explicit native confirmation. Persisting
    // its state authorises read-only continuation after a later launch/interruption.
    if try await store.fullResyncState() == nil {
      let state = try await client.syncState(cursor: 0)
      guard state.instanceID == instanceID, state.anchor.valid else {
        throw APIError.invalidResponse
      }
      try await store.beginFullResync(instanceID: instanceID, checkpoint: state.anchor)
    }
    do { try await resumeFullResync() } catch APIError.http(409, let code)
      where code == "sync_history_changed"
    {
      try await store.requireFullResync(discardStaging: true)
      throw StoreError.fullResyncRequired
    }
  }
  private func resumeFullResync() async throws {
    while let state = try await store.fullResyncState(), !state.complete {
      try Task.checkCancellation()
      let page = try await client.snapshot(checkpoint: state.checkpoint, after: state.after)
      try await store.stageSnapshot(page, expected: state)
    }
    guard let final = try await store.fullResyncState(), final.complete else {
      throw APIError.invalidResponse
    }
    let verified = try await client.syncState(cursor: final.checkpoint.cursor)
    guard verified.instanceID == final.instanceID, verified.requestedToken == final.checkpoint.token
    else {
      try await store.requireFullResync(discardStaging: true)
      throw StoreError.fullResyncRequired
    }
    try Task.checkCancellation()
    try await store.finishFullResync(expected: final, verified: verified)
  }

}
