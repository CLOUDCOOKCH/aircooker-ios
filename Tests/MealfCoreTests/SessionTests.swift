import Foundation
import Testing

@testable import MealfCore

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

private func sessionTokens(_ prefix: String, sessionID: UUID = UUID()) -> Tokens {
  Tokens(
    accessToken: prefix + "-access", refreshToken: prefix + "-refresh", expiresIn: 900,
    sessionID: sessionID)
}
private actor SessionVault: TokenVault {
  private var data: Data
  var failWrites = false
  init(_ state: CredentialState = CredentialState()) throws {
    data = try JSONEncoder().encode(state)
  }
  init(data: Data) { self.data = data }
  func read() throws -> CredentialState {
    try JSONDecoder().decode(CredentialState.self, from: data)
  }
  func update(_ command: CredentialState.Update) throws -> CredentialState {
    var value = try read()
    value.apply(command)
    if failWrites { throw URLError(.cannotWriteToFile) }
    data = try JSONEncoder().encode(value)
    return value
  }
  func bytes() -> Data { data }
  func fail() { failWrites = true }
}
private struct Reply: Sendable {
  let status: Int
  var data = Data()
  var url: URL?
}
private actor SessionRouter {
  var handler: (@Sendable (URLRequest) async throws -> Reply)?
  func set(_ handler: @escaping @Sendable (URLRequest) async throws -> Reply) {
    self.handler = handler
  }
  func respond(_ request: URLRequest) async throws -> Reply {
    guard let handler else { throw URLError(.badServerResponse) }
    return try await handler(request)
  }
}
private final class SessionProtocol: URLProtocol {
  static let router = SessionRouter()
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let work = ProtocolWork(self)
    Task { await work.run() }
  }
  override func stopLoading() {}
}
// URLProtocol callbacks are thread-safe, but FoundationNetworking does not express
// that in Sendable annotations. Limit the test-only escape hatch to one request.
private final class ProtocolWork: @unchecked Sendable {
  let owner: SessionProtocol
  init(_ owner: SessionProtocol) { self.owner = owner }
  func run() async {
    let request = owner.request
    do {
      let reply = try await SessionProtocol.router.respond(request)
      let response = HTTPURLResponse(
        url: reply.url ?? request.url!, statusCode: reply.status,
        httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
      owner.client?.urlProtocol(owner, didReceive: response, cacheStoragePolicy: .notAllowed)
      owner.client?.urlProtocol(owner, didLoad: reply.data)
      owner.client?.urlProtocolDidFinishLoading(owner)
    } catch { owner.client?.urlProtocol(owner, didFailWithError: error) }
  }
}
private actor SessionGate {
  private var started = false
  private var released = false
  private var startWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
  func waitForStart() async {
    if started { return }
    await withCheckedContinuation { startWaiters.append($0) }
  }
  func pause() async {
    started = true
    for waiter in startWaiters { waiter.resume() }
    startWaiters = []
    if released { return }
    await withCheckedContinuation { releaseWaiters.append($0) }
  }
  func release() {
    released = true
    for waiter in releaseWaiters { waiter.resume() }
    releaseWaiters = []
  }
}
private func sessionClient(_ vault: SessionVault) throws -> APIClient {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [SessionProtocol.self]
  return try APIClient(
    baseURL: URL(string: "https://test.invalid")!, vault: vault,
    session: URLSession(configuration: configuration))
}

@Suite(.serialized) struct SessionTests {
  @Test func legacyEnvelopeUpgradeAndUnknownFormatsFailSafely() throws {
    let tokens = sessionTokens("legacy")
    let upgraded = try CredentialState.decodeStored(JSONEncoder().encode(tokens))
    #expect(upgraded.needsRewrite && upgraded.state.active?.sessionID == tokens.sessionID)
    let bytes = try JSONEncoder().encode(upgraded.state)
    let reread = try CredentialState.decodeStored(bytes)
    #expect(!reread.needsRewrite && reread.state.generation == upgraded.state.generation)
    var object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    object["formatVersion"] = 999
    let future = try JSONSerialization.data(withJSONObject: object)
    #expect(throws: APIError.self) { try CredentialState.decodeStored(future) }
    #expect(throws: (any Error).self) { try CredentialState.decodeStored(Data("{}".utf8)) }
  }
  @Test func logoutPreservesOfflineDraftsAndMutationIdentityAcrossRestart() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appending(path: "local.sqlite3")
    let store = try LocalStore(url: url)
    let recipeID = UUID()
    try await store.save(kind: .recipe, id: recipeID, value: Recipe(title: "Offline draft"))
    let before = try await store.pending()
    let vault = try SessionVault(CredentialState(legacy: sessionTokens("draft")))
    let client = try sessionClient(vault)
    try await client.signOut()
    let reopened = try LocalStore(url: url)
    let pending = try await reopened.pending()
    #expect(pending.count == 1 && pending[0].mutationID == before[0].mutationID)
    #expect(pending[0].entityID == recipeID)
    #expect(
      try await reopened.entities(kind: .recipe).first?.decode(Recipe.self).title == "Offline draft"
    )
  }
  @Test func credentialEnvelopeSurvivesRestartAndRejectsStaleResponses() throws {
    let original = sessionTokens("original")
    var state = CredentialState(legacy: original)
    let generation = state.generation
    state.apply(.signOut)
    state = try JSONDecoder().decode(CredentialState.self, from: JSONEncoder().encode(state))
    let rotated = sessionTokens("rotated", sessionID: original.sessionID)
    state.apply(
      .rotate(rotated, generation: generation, previousRefreshToken: original.refreshToken))
    #expect(state.active == nil)
    #expect(state.pending.count == 1)
    #expect(state.pending[0].refreshToken == original.refreshToken)
    let late = sessionTokens("late-login")
    state.apply(.install(late, generation: generation))
    #expect(state.active == nil)
    #expect(state.pending.count == 2)
    let new = sessionTokens("new-login")
    state.apply(.install(new, generation: state.generation))
    #expect(state.active?.sessionID == new.sessionID)
    // Acknowledging an old capability cannot clear a new active session.
    for item in state.pending { state.apply(.acknowledge(item.id)) }
    #expect(state.pending.isEmpty && state.active?.sessionID == new.sessionID)
  }
  @Test func offlineLogoutPersistsCapabilityAndRetrySendsNoBearer() async throws {
    let original = sessionTokens("offline")
    let vault = try SessionVault(CredentialState(legacy: original))
    let client = try sessionClient(vault)
    await SessionProtocol.router.set { _ in throw URLError(.notConnectedToInternet) }
    try await client.signOut()
    await #expect(throws: URLError.self) { try await client.retryRevocations() }
    #expect(try await vault.read().active == nil)
    let restarted = await SessionVault(data: vault.bytes())
    let reconnected = try sessionClient(restarted)
    await SessionProtocol.router.set { request in
      #expect(request.url?.path == "/api/v1/auth/revoke")
      #expect(request.httpMethod == "POST")
      #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
      var body = request.httpBody ?? Data()
      if body.isEmpty, let stream = request.httpBodyStream {
        stream.open()
        defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable && body.count < 4096 {
          let count = stream.read(&buffer, maxLength: buffer.count)
          if count <= 0 { break }
          body.append(contentsOf: buffer.prefix(count))
        }
      }
      let payload = try JSONDecoder().decode([String: String].self, from: body)
      #expect(payload["refresh_token"] == original.refreshToken)
      return Reply(status: 204)
    }
    try await reconnected.retryRevocations()
    try await reconnected.retryRevocations()
    #expect(try await reconnected.pendingRevocationCount() == 0)
    #expect(try await restarted.read().active == nil)
  }
  @Test func refreshCannotReauthenticateAfterLogout() async throws {
    let original = sessionTokens("before-race")
    let rotated = sessionTokens("after-race", sessionID: original.sessionID)
    let vault = try SessionVault(CredentialState(legacy: original))
    let client = try sessionClient(vault)
    let gate = SessionGate()
    await SessionProtocol.router.set { request in
      if request.url?.path == "/api/v1/auth/refresh" {
        await gate.pause()
        return Reply(status: 200, data: try JSONEncoder().encode(rotated))
      }
      return Reply(status: 401)
    }
    let request = Task { try await client.household() }
    await gate.waitForStart()
    try await client.signOut()
    await gate.release()
    do {
      _ = try await request.value
      Issue.record("Signed-out request unexpectedly succeeded")
    } catch {}
    let state = try await vault.read()
    #expect(state.active == nil && state.pending.count == 1)
    #expect(state.pending[0].sessionID == original.sessionID)
  }
  @Test func lateLoginIsQueuedForRevocationInsteadOfSaved() async throws {
    let vault = try SessionVault()
    let client = try sessionClient(vault)
    let tokens = sessionTokens("late")
    let gate = SessionGate()
    await SessionProtocol.router.set { _ in
      await gate.pause()
      return Reply(status: 200, data: try JSONEncoder().encode(tokens))
    }
    let request = Task {
      try await client.login(username: "test", password: "synthetic", deviceID: UUID())
    }
    await gate.waitForStart()
    try await client.signOut()
    await gate.release()
    do {
      try await request.value
      Issue.record("Late login unexpectedly succeeded")
    } catch {}
    let state = try await vault.read()
    #expect(state.active == nil && state.pending.count == 1)
    #expect(state.pending[0].sessionID == tokens.sessionID)
  }
  @Test func unconfirmedRevocationAndFailedKeychainWriteKeepCredentials() async throws {
    let vault = try SessionVault(CredentialState(legacy: sessionTokens("failure")))
    let client = try sessionClient(vault)
    await vault.fail()
    await #expect(throws: URLError.self) { try await client.signOut() }
    #expect(try await vault.read().active != nil)
    let goodVault = try SessionVault(CredentialState(legacy: sessionTokens("retry")))
    let other = try sessionClient(goodVault)
    try await other.signOut()
    for code in [200, 401, 404, 429, 500] {
      await SessionProtocol.router.set { _ in Reply(status: code) }
      do {
        try await other.retryRevocations()
        Issue.record("Unconfirmed revocation was accepted")
      } catch {}
      #expect(try await other.pendingRevocationCount() == 1)
    }
  }
  @Test func ordinaryRefreshRotatesAndUsesNewAccessToken() async throws {
    let original = sessionTokens("old")
    let rotated = sessionTokens("new", sessionID: original.sessionID)
    let vault = try SessionVault(CredentialState(legacy: original))
    let client = try sessionClient(vault)
    await SessionProtocol.router.set { request in
      if request.url?.path == "/api/v1/auth/refresh" {
        return Reply(status: 200, data: try JSONEncoder().encode(rotated))
      }
      if request.value(forHTTPHeaderField: "Authorization") == "Bearer " + rotated.accessToken {
        return Reply(status: 200, data: Data(#"{"name":"Synthetic"}"#.utf8))
      }
      return Reply(status: 401)
    }
    #expect(try await client.household()["name"] == "Synthetic")
    #expect(try await vault.read().active?.refreshToken == rotated.refreshToken)
    #expect(try await vault.read().pending.isEmpty)
  }
  @Test func wrongResponseOriginCannotAcknowledgeRevocation() async throws {
    let vault = try SessionVault(CredentialState(legacy: sessionTokens("origin")))
    let client = try sessionClient(vault)
    try await client.signOut()
    await SessionProtocol.router.set { _ in
      Reply(status: 204, url: URL(string: "https://test.invalid:444"))
    }
    await #expect(throws: APIError.self) { try await client.retryRevocations() }
    #expect(try await client.pendingRevocationCount() == 1)
  }
}
