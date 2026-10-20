import Foundation

public struct SharedImport: Codable, Identifiable, Sendable {
  public let id: UUID
  public let url: String?
  public let text: String?
  public let createdAt: Date
  public init(url: String?, text: String?) {
    id = UUID()
    self.url = url
    self.text = text
    createdAt = Date()
  }
}
public actor ShareInbox {
  private let directory: URL
  public init(directory: URL) throws {
    self.directory = directory.appending(path: "imports", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
  }
  public func enqueue(_ request: SharedImport) throws {
    guard (request.url?.utf8.count ?? 0) <= 2048, (request.text?.utf8.count ?? 0) <= 100000,
      request.url != nil || request.text != nil
    else { throw StoreError.invalidRecord }
    try JSONEncoder().encode(request).write(
      to: directory.appending(path: request.id.uuidString + ".json"), options: .atomic)
  }
  public func pending() throws -> [SharedImport] {
    let files = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
      options: .skipsHiddenFiles)
    return try files.filter { $0.pathExtension == "json" }.sorted {
      $0.lastPathComponent < $1.lastPathComponent
    }.map { file in
      let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
      guard values.isRegularFile == true, (values.fileSize ?? Int.max) <= 110000 else {
        throw StoreError.invalidRecord
      }
      return try JSONDecoder().decode(SharedImport.self, from: Data(contentsOf: file))
    }
  }
  public func acknowledge(_ request: SharedImport) throws {
    try FileManager.default.removeItem(
      at: directory.appending(path: request.id.uuidString + ".json"))
  }
}
