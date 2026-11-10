# Offline Study Trainer

A GPL-3.0 Flutter implementation of decision-based training for Lichess studies.
Independent project; no Lichess endorsement. **Engineering preview, not a production release.**

## Install on iPhone using Windows

[Download the iPhone preview](https://github.com/siirty/lichess-study-trainer/releases/tag/ios-preview-v0.1.0)
and follow the [Windows installation guide](docs/install-iphone-windows.md).
Use AltStore Classic with your own free Apple account; no Mac or paid developer membership is
required. Free signing needs renewal every seven days through AltServer on Windows.
iOS 15 or later is required. The iPhone release build and a native simulator import → board move
→ save → reopen/backup test passed [macOS CI](https://github.com/siirty/lichess-study-trainer/actions/runs/42635436689).

After installing AltStore, add this source URL:

```text
https://raw.githubusercontent.com/siirty/lichess-study-trainer/main/altstore-source.json
```

## Run

Use Flutter 3.47.9 / Dart 3.13.7 (the versions validated against current Lichess mobile).
Install the usual Android SDK/NDK and JDK 21, or Xcode on macOS. Allow at least 16 GB for Android SDK/build caches on a fresh machine. Linux needs CMake, Ninja, clang,
pkg-config, GTK development libraries, libsecret/libjsoncpp development libraries for secure-storage linking, and SQLite runtime support.

```sh
cd apps/standalone
flutter pub get
flutter run
```

Import `fixtures/repertoire.pgn` using Open PGN file, or paste its text. Import once, then choose White or Black in the Library. Both sides remain available offline. Study URLs and single-chapter URLs use the documented export API. On Android/iOS, connect in Settings through Lichess OAuth to read private studies with study:read permission. Tokens stay in platform secure storage and never enter review backups. Device callback validation remains a release requirement.
Use Refresh from Lichess in the library, or reimport the same local source ID. Cached timestamps show the last local import. Reordered/renamed Lichess chapters retain compatible progress; changed answers become due again. After import, disconnect:
library, training, schedules and backups operate entirely locally.

Start due reviews from Library, or practice a study/chapter for the selected side. Play any included continuation
using tap or drag, including promotion. A correct move can automatically play an included opponent reply and reveal source notes/annotations. Disable replies in Settings. A wrong move or hint forces Again (including after an interruption); an unassisted
correct move gives Good. Save review commits the schedule and history together. Relaunch
restores the remaining queue; the interrupted decision starts over without a fabricated grade.
Settings provides persistent daily new/review limits, retention and theme/side preferences, and exports/restores a complete JSON backup. Limits count unique items across all sessions in the local calendar day; repeat learning steps cost no additional slots. Progress displays review history, unassisted recall, hints/mistakes and per-study totals. Restore replaces the current library;
keep a separate backup first. Android release builds include INTERNET permission.

## Structure

- `trainer_core`: Dart-only PGN decision extraction, identities, host storage contract, FSRS.
- `trainer_flutter`: injected, theme-inheriting chessground widget; no app navigation or auth.
- `trainer_storage`: SQLite adapter with transactions, migrations, snapshots and backups.
- `trainer_lichess`: documented read-only exports with injected HTTP client, bounds/timeouts.
- `apps/standalone`: mobile/desktop shell, file selection, library and settings.
- `integration/lichess_mobile`: adapter validated against actual upstream model types.

## Verify

```sh
(cd packages/trainer_core && dart pub get && dart test && dart analyze)
(cd packages/trainer_storage && dart pub get && dart test && dart analyze)
(cd packages/trainer_lichess && dart pub get && dart test && dart analyze)
(cd packages/trainer_flutter && flutter pub get && flutter test && flutter analyze)
(cd apps/standalone && flutter pub get && flutter analyze && flutter test)
```

See [verification](docs/verification.md), [architecture](docs/architecture.md),
[data model](docs/data-model.md), [algorithm](docs/training-algorithm.md),
[upstream integration](docs/upstream-integration.md) and [remaining work](docs/limitations.md).

## Android preview

Every push to `main` builds a test APK (arm64, Android 7.0+). To install it on a phone:

1. Open the latest successful [checks run on main](https://github.com/siirty/lichess-study-trainer/actions/workflows/check.yml?query=branch%3Amain+event%3Apush)
   while signed in to GitHub, and download the `android-test-apk` artifact (kept 14 days).
2. Unzip it in Files, optionally compare the APK with `SHA256SUMS.txt`, and tap the APK.
   Allow installs from that app when Android asks.

Each build is signed with a new throwaway test key. To install a newer build, export a backup,
uninstall the old app, install, then restore. Only use APKs from this repository's `main` runs;
this is a personal test build, not a distributable release.

For a standard SDK installation, rebuild from apps/standalone with:

```sh
flutter build apk --release --target-platform android-arm64
```

The template currently signs release builds with a development key. Configure your own signing
before distribution. Keep a training backup when replacing builds signed by different keys;
Android may require uninstalling the previous app. Exported training backups exclude account tokens.
