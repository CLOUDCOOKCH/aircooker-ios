# mealf-ios development guidance

Read README.md and docs/IMPLEMENTATION.md. This is an independent native SwiftUI repository,
with a tested Swift core and unverified Apple framework sources. Keep those claims separate.

Preserve local edits and their outbox in one transaction. Never discard rejected offline
drafts, mix backend identities, or use device clocks as the conflict authority. Keep secrets
in Keychain, shared content in bounded App Group files, and TLS validation enabled.

The server owns OpenAPI; update Contracts/pin.json only after reviewing an exact server
contract change. Run contract/localisation scripts, Swift core tests and swift format lint.
Apple UI/extension changes need Xcode and simulator/device checks before claiming success.
No real credentials, signing material, tracking, third-party brand assets or fabricated
product screenshots may be committed. Keep the phase checklist and privacy draft accurate.
