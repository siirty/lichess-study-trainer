# Data and durability

Position identity uses the first four FEN fields: pieces, turn, castling and en-passant.
Counters are omitted. En-passant remains conservative: positions with an irrelevant en-passant
field may stay separate, preventing an unsafe merge of different legal move sets.

A decision unions legal outgoing UCI moves at the same position within a chapter. Its SHA-256
identity includes source scope, chapter, training side and position. PGN nodes, positions,
decisions and scheduled reviews remain distinct. One authoritative source import now derives
both sides in a single parse; side selection filters queues, not stored study content.

Source scopes are explicit. A full-study URL uses `lichess:<studyId>`; a chapter URL uses
`lichess:<studyId>/<chapterId>`. A chapter snapshot must not replace the full-study scope.
Importing both scopes intentionally creates separate training contexts and histories.
Lichess chapter IDs come from Site tags. Local chapters fall back to Event plus initial FEN;
renaming a local Event conservatively creates new items unless a stable Site identifies it.
Duplicate chapter identities reject the import rather than guessing which history belongs where.

Each decision also caches source comments, move annotations/NAGs and included opponent replies.
These do not affect review identity. Comments are displayed as plain text after recall, never
as markup or as a pre-answer hint. The original PGN retains complete variation context.

| Source change | Review behavior |
|---|---|
| Rename with stable chapter ID, reorder moves, edit comments | Keep schedule and history exactly |
| Add a new position | New item, with no inherited history |
| Change an accepted move set | Keep memory parameters/history, make due now |
| Remove a position/chapter | Suspend schedule and retain events |
| Reintroduce the same identity | Resume retained state, due now |
| Replace a chapter with another ID at the same chess position | Separate items; no history reassignment |

Decision revision hashes include the stable ID and sorted accepted moves. Session commits must
supply this revision, so a pre-refresh answer cannot update a changed decision. Refresh repairs
paused queues in the same transaction, retaining other studies and surviving hint/mistake evidence.
A changed/removed queued answer rotates the session token to reject stale callbacks.

SQLite versions:

- v1 stores decisions, states, immutable events and source PGN.
- v2 adds settings, including session cursors and preferences.
- v3 indexes event UTC time, local completion date, introduction status, source and chapter.
- v4 adds local cache timestamps and a source index, then rebuilds both sides and annotation
  caches from existing PGN without network access. PGN reconstruction runs in a background
  isolate. Matching review state and history remain intact; suspended opposite-side items resume.

Refresh uses bounded batches inside an outer transaction and indexed lookups instead of a
per-item linear search through the previous graph. Unchanged schedules are not rewritten.
Cache timestamps describe local imports/reconstruction, not server Last-Modified values.

Review state, event and remaining queue commit together. Attempt evidence persists before hint
reveal, merges monotonically and survives restart/session switching. Stable event IDs make retry
idempotent. Budgets derive from recorded local dates and distinct decision IDs. Legacy dates use
UTC when the old event lacks a local date; first available events are inferred introductions.
Legacy events without source metadata retain the label Archived source.

Backups are transactional snapshots. Restore accepts v1–v4, validates decisions/review payloads,
rolls back invalid data, and normalizes older source caches. Future versions are rejected before
mutation. No learner-data TTL or automatic deletion is applied. Backups are unencrypted and may
contain private studies. Tokens stay in the platform secure vault and never enter this database.
SQLite provides crash atomicity, not protection against media failure; keep external backups.
