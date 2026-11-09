# Dependency notices

Project: GPL-3.0; see LICENSE. No upstream endorsement.

- dartchess 0.15.0, lichess-org/dartchess: GPLv3, official chess rules and PGN.
- chessground 11.1.0, lichess-org/flutter-chessground: GPLv3, board UI and bundled pieces;
  retain package asset attributions and license in distributions.
- fsrs 2.0.1, open-spaced-repetition/dart-fsrs: MIT; full notice in FSRS-LICENSE.
- Flutter/Dart SDK: BSD-style licenses from their SDK distributions.
- flutter_appauth / native AppAuth: BSD/Apache package notices; flutter_secure_storage and platform implementations: retain their package notices. Used only in the standalone host.
- sqflite/sqflite_common/sqflite_common_ffi, path_provider, file_picker, http, crypto and
  transitive dependencies: retain their package LICENSE files. Flutter release bundles must
  include the generated license registry; add a user-visible license page before release.

No Chessdriller or NeuralPGN implementation code was copied. An upstream mobile checkout was
used only to inspect architecture and analyze an adapter, not bundled in this archive.
Locked pubspec.lock files record resolved packages. Generate final platform dependency notices
from Flutter's LicenseRegistry and native build outputs before distributing binaries.
