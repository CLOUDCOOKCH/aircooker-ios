# TestFlight and App Store release gates

No application has been signed, archived, uploaded or submitted from this environment.
A source tree and workflow file do not constitute a distributable iOS release.

1. Build all native targets using current production Xcode 27 and verify iOS 26 and 27.
2. Register unique app/extension bundle IDs and one App Group on an Apple developer team.
3. Configure signing certificates/profiles through protected CI secrets; never commit them.
4. Complete native UI/device tests, accessibility, performance and offline scenarios.
   Verify Liquid Glass contrast over bright/dark/missing photos, Reduce Transparency,
   increased contrast, Reduce Motion, accessibility text and native tab-bar restoration.
5. Finish photo cleanup/quotas, advanced planning, backup/deletion and all checklist requirements.
6. Provide original app icons, genuine screenshots in English/German and support/privacy URLs.
7. Provide an accessible fully functional review backend with an explicit demo account,
   or implement a complete, clearly labelled local demo. Neither currently exists.
8. Finalise App Privacy declarations based on the implemented data flows; no tracking claim
   should extend to independently configured third-party providers.
9. Re-read Apple's current review/SDK rules. Supply review instructions explaining self-hosting
   while allowing reviewers to use the core product without running Docker.
10. Create a versioned release candidate, archive, validate and upload through App Store
    Connect using protected environment credentials. Preserve archive, dSYMs and test results.

The release workflow requires an explicit manual dispatch. Apple account credentials,
certificate material and export configuration are setup prerequisites. No acceptance by
Apple is guaranteed. Stable server and iOS releases version independently; pin compatible
API-major and sync protocol.

Draft metadata (requires editorial/legal review):

English: “Plan meals together with your household. Keep recipes, plan your week and connect
to your own aircooker server. Optional AI extraction and Bring shopping integration are
configured on your server.”

German: “Plane Mahlzeiten gemeinsam mit deinem Haushalt. Verwalte Rezepte und deinen
Wochenplan auf deinem eigenen aircooker-Server. Optionale KI-Extraktion und die
Bring!-Einkaufsintegration werden auf deinem Server eingerichtet.”

Descriptions must be revised to match verified release functionality. Do not advertise
unsupported social imports or unverified Bring compatibility as guaranteed features.


The protected distribution environment must define `RELEASE_ACCEPTANCE_VERIFIED=true`
only after documented product, security and release acceptance is actually complete.
It is intentionally unset for this development implementation.
