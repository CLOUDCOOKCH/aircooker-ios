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
public actor APIClient {
  private let baseURL: URL
  private let vault: any TokenVault
  private let session: URLSession
  private var refreshing: Task<Tokens, any Error>?
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
  private func request<T: Decodable & Sendable>(
    _ path: String, method: String = "GET", body: Data? = nil, authenticated: Bool = true,
    retry: Bool = true
  ) async throws -> T {
    guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL, url.host == baseURL.host,
      url.scheme == "https"
    else { throw APIError.invalidServerURL }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.httpBody = body
    request.timeoutInterval = 30
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
        return try await self.request(
          path, method: method, body: body, authenticated: true, retry: false)
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
      return try await self.request(
        path, method: method, body: body, authenticated: true, retry: false)
    }
    guard (200..<300).contains(http.statusCode) else {
      let value = try? JSONDecoder().decode([String: [String: String]].self, from: data)
      throw APIError.http(http.statusCode, value?["error"]?["code"] ?? "request_failed")
    }
    return try JSONDecoder().decode(T.self, from: data)
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
    let results: [MutationResult] = try await request(
      "/api/v1/sync/push", method: "POST", body: JSONEncoder().encode(["mutations": [mutation]]))
    guard results.count == 1, results[0].mutationID == mutation.mutationID else {
      throw APIError.invalidResponse
    }
    return results[0]
  }
  public func pull(cursor: Int) async throws -> PullPage {
    try await request("/api/v1/sync/pull?cursor=\(cursor)&limit=100")
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
  private let client: APIClient
  private var running = false
  public init(store: LocalStore, client: APIClient) {
    self.store = store
    self.client = client
  }
  public func synchronise() async throws {
    guard !running else { return }
    running = true
    defer { running = false }
    let info = try await client.info()
    guard let instanceID = info.instanceID else { throw APIError.incompatibleServer }
    try await store.bind(instanceID: instanceID)
    // Always push before pull so remote deltas cannot overwrite pending local edits.
    while true {
      let pending = try await store.pending()
      if pending.isEmpty { break }
      for mutation in pending {
        let result = try await client.push(mutation)
        try await store.acknowledge(result, mutation: mutation)
      }
    }
    while true {
      let cursor = try await store.cursor()
      let page = try await client.pull(cursor: cursor)
      try await store.apply(page)
      if !page.hasMore { break }
    }
  }
}
