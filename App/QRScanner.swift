import SwiftUI
import VisionKit

struct QRScanner: UIViewControllerRepresentable {
  var scanned: (String) -> Void
  func makeCoordinator() -> Coordinator { Coordinator(scanned: scanned) }
  func makeUIViewController(context: Context) -> DataScannerViewController {
    let scanner = DataScannerViewController(
      recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced,
      recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false,
      isPinchToZoomEnabled: true, isGuidanceEnabled: true, isHighlightingEnabled: true)
    scanner.delegate = context.coordinator
    try? scanner.startScanning()
    return scanner
  }
  func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}
  @MainActor final class Coordinator: NSObject, DataScannerViewControllerDelegate {
    var scanned: (String) -> Void
    init(scanned: @escaping (String) -> Void) { self.scanned = scanned }
    func dataScanner(
      _ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
      allItems: [RecognizedItem]
    ) {
      for item in addedItems {
        if case .barcode(let barcode) = item, let value = barcode.payloadStringValue,
          let url = URL(string: value), url.scheme == "https", url.host != nil, url.user == nil,
          url.password == nil, url.query == nil, url.fragment == nil,
          url.path.isEmpty || url.path == "/"
        {
          scanner.stopScanning()
          scanned(value)
          return
        }
      }
    }
  }
}
