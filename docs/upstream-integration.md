# Lichess contribution path

Validated against mobile d8be33c0c15b436803806745fc16d3258b5733c5 with matching Flutter 3.47.9.
`integration/lichess_mobile/trainer_entry.dart` compiles against real Study/StudyChapter ID getters,
PgnGame and the reusable widget. Analyzer output: No issues found. This is a source-level adapter,
not a plugin and not an accepted contribution.

To reproduce, clone the pinned mobile commit beside this repository. Add path dependencies on
packages/trainer_core and packages/trainer_flutter to mobile/pubspec.yaml. Copy trainer_entry.dart
to mobile/lib/trainer_integration_probe.dart, run flutter pub get, then dart run build_runner build,
then flutter analyze lib/trainer_integration_probe.dart. Model getters require generation. The
artifact includes a verified dependency patch and the successful analysis log.

For a real feature PR:

1. Discuss the decision-level workflow and storage cost with maintainers after human review.
2. Use StudyRepository.getStudy and inject lichessClientProvider for authenticated public/private
   downloads; standalone public exports deliberately do not reuse undocumented browsing endpoints.
3. Wrap TrainerStore with a Riverpod provider and allocate namespaced trainer tables through the
   host database migration system. Do not invoke SqliteTrainerStore.open on the existing database
   with its independent schema version. No TTL deletion for review history.
4. Add a training action to StudyScreen using the current tab navigator's pushHidingTabBar and
   buildScreenRoute. Inject commit callbacks and preserve normal host back/lifecycle behavior.
5. Use PlatformScaffold/PlatformAppBar around the board, host board preferences and translations.
   The widget inherits Theme; TrainingStrings injects board feedback, prompts, notes and control labels. Map these to host localization rather than adding another localization system. No standalone account UI belongs in the upstream feature.
6. Add HTTP-level mock tests, host navigation/widget tests and upgrade tests using the host harness.
   Existing stricter immutability, formatting, import and linter conventions need a full pass.

OAuth: mobile uses its existing FlutterAppAuth/web:mobile flow and secure storage. Public standalone
imports need none; private API exports document study:read. Do not store bearer tokens in SQLite
or backups. The standalone shell now provides FlutterAppAuth PKCE with study:read, account verification, secure storage and revocation. Lichess explicitly permits unregistered public clients. Device validation remains required.

Upstream AI policy requires full disclosure of tool and extent: this code and documentation were
created with OpenAI Codex. A human must understand all code and review/edit submission content.
No issue, PR or message was submitted. Acceptance, production compatibility, migrations and
full app compilation are not implied by the adapter's successful analysis.

The storage contract now exposes durable history and monotonic attempt recording. Upstream should
adapt those calls to its own namespaced schema/provider, not reuse standalone OAuth or its schema
version. The widget optionally receives initialEvidence and onAttemptChanged; hosts which require
restart-safe grading must wire both. Its original onComplete callback remains source-compatible.

The prototype now returns a chapter-scoped, both-side snapshot. A chapter fetched by
StudyRepository must not replace a whole-study source. Pass the training side to trainingQueue,
not to the authoritative importer. Supply decision: currentDecision to schedule and preserve the
returned decisionRevision in the committed ScheduledReview; session commits require it. The
storage adapter also exposes lightweight source summaries and on-demand cached PGN for library
refresh/edit actions. Do not open the host database using this package's independent schema version.
