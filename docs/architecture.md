# Architecture assessment and implementation plan

## Verified upstream evidence

Inspected lichess-org/mobile at `d8be33c0c15b436803806745fc16d3258b5733c5` on 2026-11-09.
Its pubspec requires Flutter 3.47.9 / Dart ^3.13.0, chessground ^11.1.0,
dartchess ^0.15.0, Riverpod ^3.5.0 and sqflite ^2.4.5.

| Concern | Actual integration surface |
|---|---|
| Study data | `lib/src/model/study/study.dart`: Study, StudyChapter, StudyChapterMeta |
| Fetching | `study_repository.dart`: StudyRepository.getStudy returns Study, optional AnalysisSummary, PGN |
| Position tree | `study_controller.dart`: StudyController, PgnTreeNotifier, Root; parses with PgnGame |
| Existing interactive practice | `lib/src/view/study/study_gamebook.dart`, plus practice feature; reusable interaction ideas, no identified durable spaced-review scheduler |
| Host network | `lib/src/network/http.dart`: lichessClientProvider, authenticated platform HTTP clients |
| Auth | `lib/src/model/auth/auth_repository.dart`: FlutterAppAuth; auth_storage.dart delegates SecureStorage |
| Durable data | `lib/src/db/database.dart`: sqflite migrations, WAL configuration, repository providers |
| Views | `lib/src/view/study/study_screen.dart`: StudyScreen, platform scaffold, studyControllerProvider |
| Navigation | `lib/src/utils/navigation.dart`: buildScreenRoute, pushHidingTabBar on active tab navigator |
| Preferences | model/settings board_preferences.dart; study/study_preferences.dart; host styles/ and l10n_context.dart |
| Tests | mirrored test/model and test/view; HTTP-level mocks; strict analyzer, generated Freezed models |

Sources: https://github.com/lichess-org/mobile, https://github.com/lichess-org/dartchess,
https://github.com/lichess-org/flutter-chessground, https://lichess.org/api .
Upstream contribution instructions and AI_POLICY.md were inspected. All generated work here
was authored by OpenAI Codex and requires human understanding/review before upstream submission.

## Decisions

Keep the core free of Flutter, HTTP, database and filesystem dependencies. Wrap the official
rules engine and MIT Dart FSRS, rather than inventing chess or scheduling. Use SQLite via a
factory injected by the host; this fits existing mobile persistence without importing the
standalone shell. The training widget consumes one decision and an async commit callback;
Riverpod remains a host concern, so no competing state container is introduced.

Imports now derive both sides and source annotations once; queues select a training side without replacing stored content. Decision granularity avoids replaying known opening prefixes. Merge same-position alternatives
inside one chapter but retain separate context between chapters/studies. Jump directly to the
review FEN. This previews the practical workflow; user research on sequence rehearsal remains.

Source PGN is authoritative; normalized decisions are derived; history and schedules are local.
Parsing happens in a Flutter compute isolate in the shell. Store commits replace a source only
after the entire bounded import validates. No custom backend or write API is used.

## Existing alternatives

Inspected https://github.com/gtim/chessdriller at b0de0f32e6a406c78af2564d59c9fe5aafa570e4 (README, Svelte/Prisma structure): stores repertoire
as Lichess studies and uses Lichess login. Useful product precedent for keeping source content
in Lichess, but its server architecture is unsuitable for this offline Flutter feature. No
LICENSE file was present in the inspected root, so no implementation code was copied.
NeuralPGN repository discovery was unsuccessful (GitHub search returned Server Error; guessed
website unavailable). Its implementation and license are unverified, not a basis for reuse.

Inspected open-spaced-repetition/dart-fsrs at cd3df9cc5e3021be4940fa2c7b9aa46ce99a565b:
MIT, repository tests and explicit serialization. Pin published fsrs 2.0.1; validate its
published interval vector locally. There is no claim of FSRS-6 compatibility or parameter fitting.
Dartchess and chessground carry GPLv3 license files; this repository uses GPLv3. See notices.

## Delivery sequence and integration risk

Research → minimal host interface and widget → core/storage vertical slice → upstream adapter
analysis → standalone library/import/backup → deterministic tests. The adapter was validated
during implementation, but after the first core slice rather than before all core coding.
It required upstream generated Freezed models before Study getters were available.

Implemented next: durable daily budgets/attempt evidence, indexed history, persistent preferences, and host-only OAuth PKCE with secure storage. Lichess permits unregistered clients (API spec Authentication and tags/oauth/oauth.yaml). Remaining work includes native callback/device validation, richer source context and platform release testing.
Native dependency availability and upstream approval are independent risks. Analysis verifies
API/type compatibility only, not runtime integration, localization or release readiness.

Source refresh validation now covers renames/reordering, both-side preservation, changed-answer
revisions, removals/reintroduction, legacy cache migration and paused queues spanning studies.
A structural PGN guard rejects unfinished comments/headers/variations before source replacement;
it delegates chess parsing and legality to dartchess and does not claim full PGN conformance.
Startup storage/migration failures render a retry screen instead of an unhandled startup error.
