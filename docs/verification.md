# Verification report — 2026-11-09

Environment: Linux x86_64; Flutter 3.47.9 stable, Dart 3.13.7.

| Check | Result |
|---|---|
| Core analyzer and 14 tests | Pass: chess/PGN fixtures, FSRS vector, queue budgets, session identity/evidence, statistics and local calendar dates |
| Storage analyzer and 11 tests | Pass: reopen, reconciliation, backup/restore rollback, v1→v4 migration, legacy-event backfill, daily limits/midnight, stale-session/schedule rejection and atomic evidence/history/cursor updates |
| Network/auth analyzer and 8 tests | Pass: exports/rate limits, token header isolation, secure-vault behavior, cancellation/expiry, revocation and redacted errors |
| Flutter widget analyzer and 7 tests | Pass: move grading, recovered penalties, hint reveal after persistence, failed-save retry and duplicate-save prevention |
| Standalone analyzer and 3 host widget tests | Pass: actual SQLite reopen → resume mistaken attempt → Again history and budget UI, with no network |
| Real mobile dependency resolution | Pass with matching Flutter |
| Real mobile build_runner generation | Pass; 207 outputs generated in research checkout |
| Integration probe flutter analyze | Pass; exact source and log included in integration/lichess_mobile |
| Linux Flutter debug bundle (`flutter build bundle --debug --target-platform linux-x64`) | Pass: kernel and Flutter assets compiled; not an installable runner |
| Linux native build | Blocked: CMake missing; GTK development setup unverified; no package helper or sudo available |
| Android arm64 AOT preview APK | Pass: Flutter release compilation, R8/JNI packaging, APK v2 signature verification, 16 KB zip alignment and arm64 ELF checks; 35,030,075 bytes. Development key; not installed on a device |
| iOS device release build | Pass on macOS CI: arm64 iPhoneOS release IPA, minimum iOS 15; unsigned for local AltStore signing |
| iOS native simulator flow | Pass: actual keychain, SQLite, PGN UI import, touch board move, hint grading, saved review, database reopen and backup restore; simulator application also builds |
| Chromium widget test | Attempted; fails compilation in dartchess native integer implementation; web excluded |

The real mobile probe was a static analysis compilation against generated models, not a full
upstream binary. Native widget tests use Flutter's test runtime. They do not prove installed
app filesystem behavior, platform file-picker dialogs, OAuth or full end-to-end user flows.
SQLite uses an actual temporary file and closes/reopens it in tests; no live network is needed.
Android arm64 packaging now passes. Installed-device behavior and native OAuth remain unverified; the preview uses a development signing key.

Current automated total: 43 passing package/widget tests plus one passing native iOS integration test. Account transport tests use mocks; native OAuth
callback, Android keystore and real authenticated study exports remain unverified. The host
widget test exercises real database persistence and UI, but not OS installation or picker dialogs.

GitHub CI passed package checks and the iOS device/simulator builds and integration test.
[Native run](https://github.com/siirty/lichess-study-trainer/actions/runs/42635436689),
compiled source commit `68120bb7b25a87b3612c46eab83131bdea800864`.
No upstream PR submitted. Apple distribution signing is not configured; the public preview IPA
is signed locally by AltStore using the installer's own Apple account. Physical iPhone installation
and live OAuth remain unverified. The Android CI setup initially requested Google's removed SDK
`tools` package; the workflow now requests `platform-tools` explicitly.

Additional checks in this increment: one-source White/Black training across reopen; unchanged
and renamed/reordered chapters keep exact schedules; changed answers become due; deleted chapters
stay suspended; reintroduction retains history; v3 caches upgrade to both sides; stale answers and
callbacks cannot commit; a paused mixed-study queue retains unaffected sources; malformed PGN
containers reject before replacement. Widget tests verify hidden notes, glyphs/opponent reply,
localized prompts, correct SAN rendering, and stale asynchronous attempt handling. The standalone
startup retry test verifies that an opening failure neither exposes private exception text nor
replaces existing data. Source reconciliation is batched/indexed, but has no scale benchmark yet.

Android build details: JDK 21, SDK compile/target 36, minimum API 24, NDK 28.2.13676358,
Gradle 9.3.1, AGP 9.1.0. Initial debug packaging exceeded the 8 GB workspace. The stock NDK
archive was streamed and checked against Google's published checksum, then optional analysis,
debugger/sanitizer tools and non-arm64 target libraries were removed from the task-local SDK.
Compiler/linker, arm64 headers and normal target runtime libraries remained intact. The local
Gradle property android.injected.build.abi=arm64-v8a constrained JNI dependency compilation to
the same ABI. No dependency implementation or application code was patched to skip compilation.
An AOT release build with the project's development signing configuration succeeded, and was
rebuilt after the final source edit. The source CI jobs use a normal fully provisioned SDK.

The APK contains exactly four arm64 ELF libraries and the generated dependency license notices.
apksigner verifies APK Signature Scheme v2; zipalign verifies 16 KB native-library alignment.
The packaged manifest contains the AppAuth receiver/custom scheme and disables Android automatic
backup. adb device enumeration found no attached device, so installation, startup on Android,
OS file pickers, secure-vault behavior and browser callback return are still device-test items.

APK SHA-256: 8e4eed8fc690d6da4c1d2254bae01d30fc51c6fb385a9f162b9defd9152d6353

## Published iOS preview

Device IPA: 22,986,724 bytes; `org.studytrainer.standalone`, version 0.1.0 (1), iPhoneOS arm64.
SHA-256: `837e10caf60f9a667f034260850718db861c755f6296580ad1f2604115ce160f`.
The ZIP, Info.plist and ARM64 Mach-O executable were inspected after downloading the CI artifact.
The release asset is that exact device artifact; simulator output is separate. The successful
native integration test uses platform plugins on an iPhone simulator; it does not claim physical
device installation or Apple-account signing verification.
