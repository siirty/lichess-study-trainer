# Security hardening — iOS preview 0.1.1

This follows the [dependency review](dependency-security-review.md). No advisory-affected Dart
dependency was identified by that review; this pass addresses weaknesses in our own handling of
untrusted input and our build process. It is not a claim that the app has been penetration tested.

Implemented:

- Local PGN and backup files are streamed with authoritative byte limits before decoding: 5 MB
  for PGN and 25 MB for backup. Reported file size is only an early rejection; unknown or incorrect
  reported lengths cannot bypass the stream limit. Reads have a total 30-second deadline and
  subscriptions are cancelled on success, rejection and error.
- PGN validation limits variation nesting to 64, chapters to 1,000, total traversal to 50,000
  positions and non-comment/header move text to 750,000 non-whitespace characters. These are
  intentional preview limits, not a large-repertoire capacity promise. Multi-game splitting now
  uses a linear scan to avoid quadratic regex behavior on long blank-line runs.
- Backup parsing has a 64-level JSON depth guard, including JSON embedded in row strings, and
  a 100,000-row aggregate limit. Decoding/domain validation runs in an isolate before replacement.
  Duplicate IDs, unexpected columns/settings, mismatched identities, invalid schedules and invalid
  preferences are rejected. Existing v1–v4 formats remain supported. Replacement stays transactional.
- Export preflights row/payload limits and validates the resulting snapshot against the same restore
  rules. A privacy confirmation explains that exports contain private study text/history in readable
  JSON. Tokens are still excluded. Backups and the local database are not additionally encrypted.
- Raw parser, filesystem and unexpected exception details are hidden from the user interface to avoid
  exposing private input or file paths. Deliberately safe limit/account messages remain actionable.
- Study and account response bodies are bounded (5 MB / 64 KiB) with total deadlines. All study
  export redirects are refused, including public requests. URLs with user-info or nonstandard ports
  are rejected. Failure to validate an account still triggers best-effort token revocation.
- Actions are pinned to full commit SHAs. Workflows explicitly limit permissions and disable checkout
  credential persistence. Release dependency resolution enforces committed lockfiles. Manual
  publishing verifies the successful main-branch iOS build, source commit and device IPA checksum.
- Weekly Dependabot checks cover all Pub projects and GitHub Actions. A scheduled/manual/lockfile-PR
  OSV scan checks committed hosted package versions and fails on advisories, incomplete results or
  an unavailable service. This checks Dart package advisories, not every native/OS component.

Regression coverage includes UTF-8 boundaries, stream cancellation, deeply nested PGN/JSON,
chapter limits, malformed/oversized backup rollback, poisoned settings/schedules, UI error
redaction, export acknowledgement, public redirects and oversized account cleanup. Existing
schedule/persistence/session tests remain part of verification.

Remaining limits:

- The user must trust the official AltStore/AltServer installer and the Windows computer used for
  Apple signing. This app never receives an Apple password; free signing requires seven-day renewal.
- Live OAuth login/revocation, platform picker dialogs and the signed app still require testing on
  the user's physical iPhone. Simulator checks do not establish those physical-device results.
- SQLite/platform engines and signing-tool binaries are not covered by the Pub advisory scan.
  Keep iOS/Windows updated. The shared desktop FFI dependency still causes an extra native SQLite
  framework to ship on iOS; isolating desktop builds is follow-up architecture work.
- The FSRS Dart port remains at its tested 2.0.1 version; monitor upstream maintenance.
- Input limits prevent unbounded parsing; they are not a benchmark of peak memory or runtime at
  the maximum accepted size. Damaged local storage still needs the documented recovery/backup path.

## Verification

Local analyzers passed. All 58 package/widget tests passed (20 core, 13 storage, 11 network,
7 board and 7 standalone), including 15 additional security regressions. The committed-lockfile
OSV scan returned no matching advisories for 118 package/version pairs. Workflows were checked
for full action SHA pins, disabled checkout credential persistence and explicit permissions.
A fresh macOS device build and native integration test are required before publishing 0.1.1.
