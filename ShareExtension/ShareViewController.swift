import MealfCore
import UIKit
import UniformTypeIdentifiers

@MainActor final class ShareViewController: UIViewController {
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    view.backgroundColor = .systemBackground
    let label = UILabel()
    label.text = String(localized: "share_saving")
    label.numberOfLines = 0
    label.textAlignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(label)
    NSLayoutConstraint.activate([
      label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
      label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
    ])
    guard let input = extensionContext?.inputItems as? [NSExtensionItem],
      let providers = input.first?.attachments
    else {
      fail()
      return
    }
    if let provider = providers.first(where: {
      $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
    }) {
      provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) {
        [weak self] value, error in
        let url = (value as? URL)?.absoluteString ?? (value as? String)
        Task { @MainActor in
          guard error == nil, let url else {
            self?.fail()
            return
          }
          await self?.save(url: url, text: nil)
        }
      }
    } else if let provider = providers.first(where: {
      $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
    }) {
      provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) {
        [weak self] value, error in
        let text = value as? String
        Task { @MainActor in
          guard error == nil, let text else {
            self?.fail()
            return
          }
          await self?.save(url: nil, text: text)
        }
      }
    } else {
      fail()
    }
  }
  private func save(url: String?, text: String?) async {
    do {
      if let url {
        guard let parsed = URL(string: url), parsed.scheme == "https", parsed.host != nil,
          parsed.user == nil, parsed.password == nil
        else { throw StoreError.invalidRecord }
      }
      guard let group = Bundle.main.object(forInfoDictionaryKey: "MealfAppGroup") as? String,
        let directory = FileManager.default.containerURL(
          forSecurityApplicationGroupIdentifier: group)
      else { throw StoreError.invalidRecord }
      let inbox = try ShareInbox(directory: directory)
      try await inbox.enqueue(SharedImport(url: url, text: text))
      extensionContext?.completeRequest(returningItems: nil)
    } catch { fail() }
  }
  private func fail() {
    let alert = UIAlertController(
      title: String(localized: "share_error"), message: String(localized: "share_error_detail"),
      preferredStyle: .alert)
    alert.addAction(
      UIAlertAction(title: String(localized: "close"), style: .cancel) { [weak self] _ in
        self?.extensionContext?.cancelRequest(withError: StoreError.invalidRecord)
      })
    present(alert, animated: true)
  }
}
