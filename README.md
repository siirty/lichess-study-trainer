# Offline Study Trainer

A GPL-3.0 Flutter implementation of decision-based training for Lichess studies.
Independent project; no Lichess endorsement. **Engineering preview, not a production release.**

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

A development-signed arm64 APK is supplied with this source snapshot. It supports Android 7.0+
(API 24), targets API 36 and was built using Flutter's AOT release mode. Native installation and
OAuth callback testing still require a device. See docs/verification.md for build/signature evidence.

```sh
adb install -r lichess-study-trainer-arm64-preview.apk
```

For a standard SDK installation, rebuild from apps/standalone with:

```sh
flutter build apk --release --target-platform android-arm64
```

The template currently signs release builds with a development key. Configure your own signing
before distribution. Keep a training backup when replacing builds signed by different keys;
Android may require uninstalling the previous app. Exported training backups exclude account tokens.
