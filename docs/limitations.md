# Release blockers and remaining work

This is a working-code engineering preview, not completion of the production definition of done.

- OAuth PKCE, secure vault adapters, account verification and revocation are implemented for Android/iOS,
  with mocked transport tests. Native system-browser return, OS keychain/keystore and real private-study
  import still require device validation. Desktop uses public imports only; study discovery is absent.
- A 35 MB arm64 Android preview APK now builds and passes signature/alignment checks. It uses a development signing key. No Android device was attached; installation/runtime OAuth and iOS/Xcode validation remain pending.
- Linux Flutter kernel/assets compile; native runner build blocked by CMake/GTK toolchain; no installed native app or screenshot verified.
- Browser test attempted, but dartchess 0.15.0 uses native 64-bit integer operations that fail JS
  compilation. Web support is excluded. Native widget tests pass.
- Interrupted positions restart their board, with persisted hint/mistake penalties; accepted-but-unsaved
  moves must be entered again. No automatic prefix replay or full variation rehearsal.
- Statistics provide history, accuracy, per-study totals and upcoming dates; no charts or long-term
  retention forecasting. Day budgets follow the device's local date; deliberate clock changes are not blocked.
- Source notes/NAGs and one opponent reply are shown after correct recall. Full variation rehearsal, automatic prefix playback and context-selection UI remain unimplemented.
- Refresh reparses bounded PGN; normalized decisions are cached, but very large-study performance
  has not been benchmarked. Failed downloads preserve local content; no ETag/Last-Modified cache.
- Local chapter Event names must remain distinct and stable. En-passant identity can under-merge
  transpositions. Both sides now coexist; separate whole-study versus chapter-only source scopes intentionally keep separate histories.
- Full malformed-PGN conformance/fuzz testing, additional corruption/fuzz coverage and migrations across future
  schema versions, accessibility audit and host navigation/lifecycle integration remain open.
- Backup restore requires explicit confirmation and replaces the local library. Backups are unencrypted.
- No platform code signing, release CI credentials, store packaging or final distribution branding.

Do not advertise as production-ready or an upstream drop-in module until these are resolved.

A fully emptied study with no trainable decisions is currently rejected rather than silently
replacing a source with empty content. Ordinary removed chapters/branches are reconciled when
some training material remains. A failed migration preserves its transaction and offers startup
retry; advanced repair/restore of an unreadable database still requires manual file recovery.
