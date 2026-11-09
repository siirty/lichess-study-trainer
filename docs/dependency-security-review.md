# Dependency and resource review — 9 November 2026

Follow-up implementation: [security hardening for preview 0.1.1](security-pass.md).

The main dependencies are established choices with current releases. The chess libraries are
smaller, but maintained by Lichess and used in its official mobile app. The Dart FSRS package
is the maintenance outlier: its last release and repository commit are from June 2025.
No applicable published vulnerability was identified in the checks below. That conclusion is
limited to the advisory sources, versions and code paths inspected; it is not a penetration test
or certification of the complete native software supply chain.

The practical concerns are signing-tool trust, readable study backups, unbounded local-file
reads, and build/update hardening. None of the mainstream dependencies currently needs replacing
on the evidence collected. Dependency upgrades should receive regression testing before a new IPA
is released.

## Scope and evidence

Reviewed repository commit `a10308e`; published iPhone preview compiled from
`68120bb7b25a87b3612c46eab83131bdea800864`. Dependency manifests and lockfiles match between
those revisions. Inspected all five project lockfiles, the standalone application's native
plugin manifests, authentication/import/backup code, workflows, and the downloaded iPhone IPA.
The four `trainer_*` packages are our own new code; they have no independent adoption or
maintenance history. Their automated tests help, but do not supply an external security review.

Fetched current pub.dev release metadata and 30-day download counts; GitHub repository status
and activity; OSV advisories; upstream Dart SDK security advisories; and official AltStore docs.
Counts include automated/CI downloads and are **not counts of unique users**. GitHub stars and
recent commits are supporting maintenance signals, not security guarantees.

[Collected evidence](dependency-review-evidence.json) records versions, statistics and scan scope.

## Library adoption and maintenance

All versions below are the ones locked by the standalone app. Latest means latest registry
release at review time, not an automatic recommendation to change the tested build.

| Library/resource | Locked version | Adoption evidence | Maintenance assessment |
|---|---|---|---|
| [Flutter / Dart](https://github.com/flutter/flutter) | 3.47.9 / 3.13.7 | Flutter repository approximately 181,000 stars; major SDK ecosystem | Active; Flutter SDK build dated 29 Oct 2026; relevant recent SDK security fix included |
| [http](https://pub.dev/packages/http) | 1.6.0 | 14.60 million downloads/30 days; Dart publisher | Latest release; upstream repository active Nov 2026 |
| [crypto](https://pub.dev/packages/crypto) | 3.0.8 | 17.61 million/30 days; Dart publisher | Latest, released 26 Oct 2026; used here for SHA-256 identities, not to encrypt backups |
| [path](https://pub.dev/packages/path) | 1.9.1 | 13.03 million/30 days; Dart publisher | Stable release from Oct 2024; shared upstream repository active Nov 2026. An old release alone does not establish abandonment |
| [path_provider](https://pub.dev/packages/path_provider) | 2.1.6 | 10.35 million/30 days; Flutter publisher | Latest, June 2026; official plugin repository active |
| [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage) | 11.2.0 | 6.01 million/30 days | Latest, Sep 2026; upstream active Nov 2026. Registry's historical repository URL redirects to `juliansteenbakker/flutter_secure_storage` |
| [file_picker](https://pub.dev/packages/file_picker) | 13.3.2 | 5.06 million/30 days | Latest facade release, 2 Nov 2026; actively maintained under current publisher/repository `vicajilau/flutter_file_picker` |
| [sqflite](https://pub.dev/packages/sqflite) | 2.4.5 | 3.23 million/30 days; Flutter Favorite | Latest, 21 Oct 2026; active upstream |
| [sqflite_common](https://pub.dev/packages/sqflite_common) | 2.5.15 | 4.16 million/30 days | Latest, 4 Nov 2026; same maintained project |
| [sqflite_common_ffi](https://pub.dev/packages/sqflite_common_ffi) | 2.4.5 | 577,000/30 days | Latest, 22 Oct 2026; desktop database path |
| [sqlite3](https://pub.dev/packages/sqlite3) | 3.5.2 | 3.58 million/30 days | Active; newer 3.9.1 available, released 8 Nov 2026. No advisory match found for locked 3.5.2 |
| [flutter_appauth](https://pub.dev/packages/flutter_appauth) | 13.0.0 | 464,000/30 days | Latest, 30 Oct 2026; wraps OpenID AppAuth, rather than implementing OAuth ourselves |
| [dartchess](https://pub.dev/packages/dartchess) | 0.15.0 | 5,144/30 days; Lichess publisher; used by official Lichess mobile | Niche but active; released 5 Nov 2026 |
| [chessground](https://pub.dev/packages/chessground) | 11.1.0 | 4,869/30 days; Lichess publisher; used by official Lichess mobile | Niche but active; released 5 Nov 2026 |
| [fsrs](https://pub.dev/packages/fsrs) | 2.0.1 | 16,873/30 days; upstream repository 67 stars | Latest published version, but no repository commit/release since 20 Jun 2025. Monitor or be prepared to maintain this port; the algorithm's adoption elsewhere does not establish adoption of this Dart implementation |

None of these reviewed pub.dev packages is marked discontinued. The app also resolves platform
implementations and SDK/test dependencies; those were included in the lockfile advisory scan.
`flutter pub outdated --json` lists 17 newer transitive packages, including `file_picker_darwin`
2.5.0 and `sqlite3` 3.9.1. None of those reported entries is flagged as advisory-affected or
retracted. Updates remain useful maintenance work even without a security advisory.

## Advisory results and native limits

- Queried [OSV](https://osv.dev/) for **118 distinct package/version pairs, covering 110 distinct
  hosted Dart package names across five lockfiles**. All 118 queries returned results; none
  contained a matching advisory. The standalone lockfile itself contains 86 hosted packages.
- Checked upstream [Dart SDK security advisories](https://github.com/dart-lang/sdk/security/advisories).
  [GHSA-frr6-h895-5pxp](https://github.com/dart-lang/sdk/security/advisories/GHSA-frr6-h895-5pxp)
  describes a high-severity TLS interception risk from compromised CA certificates on Android,
  Windows and some Linux environments. Fixes are Dart 3.13.7 / Flutter 3.47.8. **Our SDK is patched;
  the advisory explicitly excludes iOS/macOS/web.** Older published SDK advisories inspected also
  have fix thresholds below our pinned versions.
- The actual Flutter AppAuth package pins **OpenID AppAuth-iOS 3.0.0** exactly in its Swift package
  manifest and **AppAuth-Android 0.11.1** in Gradle. OSV queries for those SwiftURL/Maven coordinates
  returned no matches. Public repository advisory listings for AppAuth-iOS and AppAuth-Android
  were empty at review time. That does not prove they have no undisclosed vulnerabilities.
- On iPhone, `openAppStore` selects `sqflite`'s mobile factory, whose native code uses SQLite.
  OS SQLite patch status depends on the installed iOS version, not just the Dart package version.
  The IPA also contains an additional `sqlite3.framework` because the desktop FFI dependency is
  imported in the shared shell. Consider separating desktop dependencies to reduce shipped native
  components. This review did not establish a complete native C/Swift/Android dependency SBOM or
  compare every embedded engine revision against all CVEs.
- The pub.dev scan does not by itself cover Flutter's engine/BoringSSL, Apple's frameworks,
  Windows iTunes/iCloud, AltServer binaries, every Gradle dependency or GitHub runner tooling.
  Keep iOS, Windows and signing tools updated. Do not interpret the Dart scan as an audit of those
  separately installed components.

## Findings, in priority order

### 1. Signing route introduces a sensitive trust boundary

AltStore is established: its public repository has approximately 14,900 stars and activity in
October 2026. The official [AltServer release notes](https://faq.altstore.io/release-notes/altserver)
list Windows 1.7.4 from 24 March 2026, fixing launch compatibility with iOS 26.4. This establishes
maintenance activity for Windows; it does not establish a security audit of the distributed binary.
We did not verify a separate public Windows source repository or reverse engineer the installer.

AltServer/AltStore handle Apple-account authentication and device signing/pairing. A compromised
Windows computer, counterfeit installer, or malicious source app could abuse that trust. Download
only from the [official Windows instructions](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows),
keep the tools current, and add only intended app sources. Enter account credentials locally.
Study Trainer itself never needs an Apple password. Developer Mode is required by this installation
route; it does not make arbitrary sideloaded apps trustworthy. Free signing still expires after
seven days. These are installation/trust considerations, not an identified AltStore exploit.

### 2. Local file imports can exhaust memory or stall the app — medium, requires user interaction

`apps/standalone/lib/main.dart:606` and `:811` read the complete selected PGN/backup before a byte
limit is enforced. PGN has a subsequent 5,000,000-character limit in `trainer_core.dart:202`, and
network study downloads are capped at 5 MB while streaming. However, a very large local file has
already been allocated and decoded by then. Backup restore at `trainer_storage.dart:484` also
parses JSON without a size/row-count limit. A malicious or accidentally enormous selected file
can crash or freeze the app. No code-execution finding was established.

Recommended: bounded streaming reads before decoding, a documented backup-size/row limit, and
bounded parsing work/depth. Keep validation and database replacement transactional. Importing only
trusted, reasonably sized files is the immediate workaround.

### 3. Backups expose private study contents — medium privacy consideration

`trainer_storage.dart:475` serializes study/source caches, schedules and history into ordinary
JSON; `main.dart:778` saves it without application-level encryption. Tokens are excluded, which
is good. Anyone who obtains an exported backup can read private repertoire content and history.
The SQLite database is also not separately encrypted by this app, relying on platform sandboxing
and device protections; this review did not verify its exact iOS file-protection class.

Keep backups in protected personal storage. Add a clear export privacy notice, and consider
password-encrypted exports if private studies are a central use case. Do not describe the `crypto`
dependency as providing backup encryption: it is used for identifiers.

### 4. Build actions and update monitoring need hardening — medium supply-chain consideration

Workflows use movable tags such as `actions/checkout@v4`, `actions/upload-artifact@v4` and
`subosito/flutter-action@v2`. The release workflow appropriately needs `contents: write`, but a
compromised action running there would inherit sensitive publishing access. No compromise was
observed. Package lockfiles already record hosted archive SHA-256 hashes, and the release workflow
checks the selected successful build, source commit and exact IPA checksum before upload.

Recommended: pin third-party actions to full reviewed commit SHAs, disable checkout credential
persistence where unnecessary, explicitly limit permissions in every workflow, enforce committed
lockfiles during release resolution, and add scheduled dependency/advisory monitoring. Preserve
the current separation between pull-request checks and the manually dispatched publishing job.
There is currently no Dependabot/Renovate configuration or scheduled advisory scan in this repo.
A checksum delivered from the same repository detects transfer mismatches but cannot defeat a
compromise of that repository's publishing authority.

### 5. FSRS port has a maintenance gap — low direct security risk, moderate maintenance risk

The last visible upstream commit is release 2.0.1 from June 2025. This is not evidence of an
exploit or definitive abandonment. Its role here is local schedule calculation, so defects are
more likely to affect review dates/progress than expose credentials. Keep deterministic schedule
fixtures, watch upstream, and document a fork/upgrade path. Replacing it solely because it is
small would require its own correctness assessment.

### 6. Physical-device account flow remains unverified — release verification gap

The app uses the system browser via AppAuth with PKCE/state handling and the narrow `study:read`
scope. Bearer tokens are restricted to HTTPS `lichess.org:443`; authenticated redirects are
disabled. Tokens live in platform secure storage and are excluded from the SQLite backup path.
The native iOS test proved a real keychain write/read/delete on a simulator, plus SQL persistence
and board interaction. It did **not** prove real private-study login, callback return, revocation
or AltStore re-signing behavior on the user's physical iPhone. Complete that flow before treating
account-connected use as fully verified. The custom callback scheme relies on AppAuth's PKCE/state
checks; it is not a claimed domain/universal link.

## Other resources and privacy

The app imports from Lichess's documented HTTPS study export and account endpoints. Public PGN
training requires no account or custom backend. The inspected app code has no advertising,
analytics or crash-reporting service. Network use for study imports/OAuth and installation/source
updates remains visible to the relevant providers; offline operation does not hide those requests.

The chessboard and piece artwork ship locally through chessground, rather than loading arbitrary
remote scripts. `dartchess` and chessground are GPL-3.0; our GPL source distribution is consistent
with that choice. Retain upstream license notices and check individual artwork attributions before
broader distribution. This was not a complete asset-license audit. The app icon remains Flutter's
template icon and should be replaced before a polished public release.

## Recommended next work

1. Bound local PGN/backup reads and parsing, and explain backup privacy in the export flow.
2. Pin CI actions, reduce workflow credentials, and automate advisory/update monitoring.
3. Test live OAuth and the installed app on the physical iPhone through the chosen signing route.
4. Update selected transitive dependencies in a separate tested preview; monitor FSRS and isolate
   unnecessary desktop native dependencies from the iOS build where practical.

This review changes documentation only. It does not silently upgrade dependencies, modify the
published IPA, or claim that the identified hardening work is already implemented.
