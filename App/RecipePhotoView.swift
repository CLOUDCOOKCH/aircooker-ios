import AirCookerCore
import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Decode a bounded thumbnail rather than materialising a full-resolution camera image.
// A fresh JPEG encoder drops source location, camera and other metadata.
enum PhotoPreparation {
  nonisolated static func prepare(_ data: Data) throws -> Data {
    guard data.count <= 32 * 1024 * 1024,
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      CGImageSourceGetCount(source) == 1,
      let image = CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: 2048,
          kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary)
    else { throw StoreError.invalidPhoto }
    for quality in [0.85, 0.7, 0.5, 0.3] {
      let output = NSMutableData()
      guard
        let destination = CGImageDestinationCreateWithData(
          output, UTType.jpeg.identifier as CFString, 1, nil)
      else { throw StoreError.invalidPhoto }
      CGImageDestinationAddImage(
        destination, image,
        [
          kCGImageDestinationLossyCompressionQuality: quality
        ] as CFDictionary)
      if CGImageDestinationFinalize(destination), output.length <= 1_048_576 {
        return output as Data
      }
    }
    throw StoreError.invalidPhoto
  }
}

struct RecipePhotoView: View {
  @Environment(AppModel.self) private var model
  let imageID: UUID?
  @State private var data: Data?
  private var loadKey: String { "\(imageID?.uuidString ?? "none")-\(model.photoRevision)" }
  var body: some View {
    ZStack {
      Rectangle().fill(.green.opacity(0.1))
      if let data, let image = UIImage(data: data) {
        Image(uiImage: image).resizable().scaledToFill()
      } else {
        Image(systemName: imageID == nil ? "fork.knife" : "photo")
          .font(.title2).foregroundStyle(.green)
      }
    }.clipped().accessibilityHidden(true)
      .task(id: loadKey) {
        data = nil
        if let imageID { data = try? await model.store?.photoData(id: imageID) }
      }
  }
}
