# Security

This unreleased development branch has no supported production release yet.
Do not deploy publicly until the release gates in the implementation checklist pass.

Report suspected vulnerabilities privately through GitHub's private vulnerability reporting
when enabled on the published repository. Until a private channel is published, avoid posting
credentials, household data or weaponised exploits in public issues. A maintainer security
contact and response policy must be established before the first public release.

Scope includes authentication, sync isolation, stale deletion handling, import SSRF, injection,
unsafe media, secret disclosure, Bring! ownership and persistence/backup integrity.
External services, compromised Docker hosts, and malicious household administrators are
outside the application's trust boundary, but document any resulting user exposure.

There are no bundled credentials, mandatory analytics or tracking SDKs. Do not disable TLS
verification, bypass platform access restrictions, or use production Bring! lists for tests.
