# Training and scheduling

Published `fsrs: 2.0.1` is pinned. The wrapper calls Scheduler.reviewCard with UTC timestamps,
90% desired retention and fuzzing disabled for reproducibility. FSRS owns learning, relearning,
stability, difficulty and interval mathematics; no custom scheduling formula is introduced.

A successful recall is a legal included UCI move with no previous mistake or hint: Good. An
incorrect move leaves the board unchanged and increments durable attempt evidence. A hint shows
a source square only after its penalty has been persisted. Completing a penalized attempt saves
Again after an accepted move. There is no partial-success grade or manual Easy/Hard choice.

Interrupted decisions are ungraded and restart their board position, but retain hints and mistake
counts. Session event IDs survive relaunch; review event, FSRS state, and the remaining queue
advance in one transaction. Retrying a committed event is idempotent. Stale sessions, stale
schedule versions and attempts to submit Good after persisted penalties are rejected.

Each item starts directly at its decision FEN. Opponent turns and memorized prefixes do not need
user replay. After a correct move the widget can play one included opponent continuation, selected deterministically by UCI order. This is optional and does not rehearse a whole sequence. Any repertoire
continuation at the same chapter position is accepted; unrelated legal chess moves are rejected.

The core test reproduces Dart FSRS's published 13-rating vector:
Good ×6, Again ×2, Good ×5 → whole-day intervals
0,4,14,45,135,372,0,0,2,5,10,20,40.
This validates the integration against package behavior, not an independent mathematical audit.

Queue selection prioritizes existing due reviews, then new material; ties are deterministic.
Defaults are 20 new / 100 previously studied distinct items per local calendar day, adjustable
and persisted in Settings (including zero). The limit applies to scheduled, study/chapter and
mistakes practice alike. Items introduced or reviewed earlier today may repeat their learning
steps without consuming another slot. SQLite checks the budget at commit, so an old queue or
second session cannot bypass it. A blocked commit leaves schedule, history and queue unchanged.
Desired retention is configurable (80/85/90/95 percent) and used on subsequent grades.

Each event stores the local date at completion, alongside its UTC instant. Changing time zone
can change the current local day; existing event dates do not move. Midnight resets available
slots by selecting the new day's events, rather than clearing counters. Practice may include
future-due items and updates their schedules. Mistakes practice selects items whose latest event
is Again, including failures in the initial learning state and on earlier days.

Progress shows completed events, unassisted recall, hint/mistake totals, per-study review counts,
the latest 30 events and upcoming item due dates. Legacy events have no reliable hint/mistake
evidence, so those totals cover newly recorded evidence. Accuracy uses all recorded grades.

Imports derive both sides while review queues select the chosen side. Review IDs are unchanged
from side-scoped imports. Daily limits are shared across sides and studies. Source comments,
move NAGs and reply notation appear only after the correct decision; comments cannot bypass
hint grading. Board feedback is injectable through TrainingStrings for host localization.
Session reviews include a decision revision. A source refresh which changes accepted answers
rejects an old grade and invalidates affected paused-session tokens without dropping other studies.
