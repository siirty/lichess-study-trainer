# Standalone Lichess connection

Verified API sources: https://github.com/lichess-org/api/blob/master/doc/specs/lichess-api.yaml
(Authentication section), tags/oauth/oauth.yaml, tags/oauth/api-token.yaml, and
Lichess mobile's auth_repository.dart. Lichess permits unregistered public client IDs,
requires S256 PKCE and supports long-lived access tokens rather than refresh tokens.

The standalone shell uses FlutterAppAuth with the system browser, client ID
`org.studytrainer.standalone`, callback `org.studytrainer.standalone://oauth`, and only
`study:read`. Android declares appAuthRedirectScheme; iOS declares CFBundleURLSchemes.
AppAuth owns the verifier and state checks. No embedded webview, client secret or custom backend.

Tokens and cached username/expiry live only in FlutterSecureStorage (Android encrypted storage,
iOS Keychain). Anonymous public imports need no token. Session restoration reads the vault without
network traffic; offline training and startup are independent of an account request. Expired or
revoked authorization reports a reconnect error without deleting study data or review progress.

LichessConnection injects authorization only for HTTPS lichess.org:443 and disables authenticated
redirects. Account validation and cleanup requests also disable redirects. Tokens never reach the
core, SQLite settings, review history, backup JSON or logs. User-facing auth errors are sanitized.

Revoke and disconnect calls DELETE /api/token before clearing the vault. A failed revocation
retains the connection for retry. Disconnect this device only deletes the local vault and leaves
the server token valid until separately revoked on Lichess. If storing a newly authorized token
fails, a best-effort remote revocation avoids abandoning it silently.

Android automatic backup is disabled to avoid restoring encrypted credentials without their
keystore keys; explicit review-data backup remains available. Keychain/keystore behavior,
system-browser callback return and real private-study import require device testing before release.
Mocked tests verify transport isolation, redaction, cancellation, expiry, secure-vault failure
cleanup, offline restoration and both disconnect behaviors. They do not prove native OAuth works.

Desktop intentionally offers public imports and PGN without an account UI. The official mobile
host should inject its own auth client and never use the standalone vault or client ID.
