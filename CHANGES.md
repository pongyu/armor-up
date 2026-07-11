# Phase 1: Engine & Net Foundations

Implements three engine/net features closing audit gaps #21 (defense-response
timeout), #18 (eliminated player's hand cleanup), and #14 (Road to Damascus
semi-secret steal). Engine-only where possible; net-layer where wall-clock
enforcement is required; one line of `lib/` UI touched per the Feature C spec
plus the compile fixes forced by new `GameEvent`/`GameAction` cases.

## Feature B — Eliminated player's hand cleanup

**Files:** `packages/game_engine/lib/src/effects.dart`,
`packages/game_engine/lib/src/models/game_event.dart`,
`packages/net/lib/src/state_codec.dart`, `lib/widgets/event_log_widget.dart`

- New event: `PlayerEliminated { playerId, cardsDiscarded }`.
- New private helper `_discardHandsOfNewlyEliminated(before, after)` in
  `effects.dart`: compares player-by-player elimination status before/after a
  state transition, moves any newly-eliminated player's hand to the discard
  pile, and logs one `PlayerEliminated` per player. Wired into both
  `landPendingAttack()` (normal/reflected attacks) and `_jerichoMarch()`
  (which can eliminate multiple players in a single resolution).
- Comparing against a `before` snapshot (rather than "hand non-empty")
  guarantees an already-eliminated player is never re-processed.
- Cards fed back into the discard pile are eligible for the normal
  reshuffle-into-draw-pile path, so this slightly increases effective deck
  size in games with eliminations — intended, per spec.

## Feature A1 — Engine: system decline action

**Files:** `packages/game_engine/lib/src/actions/game_action.dart`,
`packages/game_engine/lib/src/engine.dart`,
`packages/game_engine/lib/src/models/game_event.dart`,
`packages/net/lib/src/action_codec.dart`,
`packages/net/lib/src/state_codec.dart`, `lib/widgets/event_log_widget.dart`

- `DeclineDefense` extended with `bool isSystemDecline = false` (chose to
  extend rather than add a separate `ForcedDecline` action, per the spec's
  stated preference — the resolution logic is identical either way, so a
  parallel action type would have meant duplicating `_declineDefense`).
- New event: `DefenseTimedOut { playerId, wasHelper }`, logged by
  `_declineDefense` whenever `isSystemDecline` is true, in addition to (not
  instead of) the normal decline resolution (Fellowship fall-through to the
  next helper, or the attack landing). `wasHelper` distinguishes a
  Fellowship helper's window timing out from the defender's own window
  timing out.
- A system decline is valid for exactly the same responders a normal decline
  is (defender, or the currently-prompted Fellowship helper) — no new
  validation path.
- Determinism preserved: a system decline consumes no RNG draws; verified by
  a test asserting `rngDrawCount` is identical to an equivalent scripted
  normal decline.

## Feature A2/A3 — Net: host-side deadline enforcement

**Files:** `packages/net/lib/src/host_server.dart`,
`packages/net/lib/src/messages.dart`

- `HostServer` gains `Duration? defenseResponseTimeout` (**default: 20
  seconds**; `null` disables the mechanism entirely).
- `_currentPendingActorId(state)`: mirrors `lib/state/turn_actor.dart`'s
  `currentActorId` logic for the two obligations the timer cares about
  (`pendingInterrupt` — defender or next undecided Fellowship helper — and
  `pendingGroupDiscard` — first owed player), reimplemented locally since
  `packages/net` cannot depend on the Flutter-layer `lib/`.
- `_syncResponseTimer()`: called after every `_broadcastState()` (i.e. every
  successful action and `startGame`), and directly from the
  disconnect/reconnect paths. (Re)starts a fresh timer only when the current
  pending actor actually changes — not on every broadcast, so a chatty
  client can't indefinitely postpone a deadline just by causing unrelated
  traffic. Suppressed entirely while that actor's socket is disconnected
  (the existing `reconnectGracePeriod` governs that case instead); restarts
  fresh on reconnect.
- `_handleResponseTimeout(actorId)`: fires a `DeclineDefense(isSystemDecline:
  true)` for a stalled `pendingInterrupt`, or a `DiscardCard` for a
  uniformly-random card (via `HostServer`'s existing `Random` instance) for
  a stalled `pendingGroupDiscard`, through the normal `applyAction` path —
  identical legality/resolution rules as a real player action — then
  broadcasts.
- **Deviation from spec wording, no behavior change:** the spec says
  "determinism of the CHOICE given the same state" for the group-discard
  timeout's random card pick. `HostServer` already uses a non-seeded
  `Random.secure()` by default (same as every other host-side random choice,
  e.g. session tokens) rather than the engine's seeded `GameRandom` — LAN
  play was never deterministic/replayable to begin with (the host is the
  sole source of truth and nothing replays it), so no seeded-RNG plumbing
  was added here; tests instead assert the *effect* (exactly one card
  removed from the correct player's hand) rather than exact card identity.
- `StateMessage` extended with `int? responseDeadlineEpochMs` (envelope-level
  metadata, per the spec's instruction not to put wall-clock data on
  `GameState`/`FilteredGameState`). Present only while a deadline is
  currently running; omitted from the JSON entirely otherwise (not just
  `null` — verified by a raw-WebSocket test inspecting the wire JSON
  directly). Purely informational for a future countdown UI; no client
  enforces anything from it.
- Hotseat is untouched: nothing in `lib/` starts these timers.

## Feature C — Road to Damascus semi-secret steal

**Files:** `packages/game_engine/lib/src/models/game_event.dart`,
`packages/net/lib/src/filtered_state.dart`,
`packages/net/lib/src/state_codec.dart`, `lib/widgets/event_log_widget.dart`

- `GameEvent` gains a `List<String>? get visibleTo` getter (default `null` =
  public, zero behavior change for every pre-existing event type) and a
  `GameEvent redacted()` method (default: returns `this`).
- **Deviation from spec wording, no behavior change:** the spec describes
  `visibleTo` as a constructor field; it's implemented as a getter instead
  so every event type — including `CardStolen` — can keep a plain `const`
  constructor. `CardStolen.visibleTo` overrides to `[thiefId]`, computed
  from the instance's own field rather than threaded through the
  constructor.
- `CardStolen.redacted()` returns a new `CardStolenRedacted { turnNumber,
  thiefId, victimId }` — a parallel event type (chosen over a nullable
  `cardDefId` on `CardStolen` itself) so the event union stays exhaustively
  switchable and no code path can accidentally treat a redacted instance as
  carrying real card data.
- `filterStateForPlayer` (the existing single choke point for hand
  redaction) now also maps the event log per viewer: any event whose
  `visibleTo` excludes the viewer is replaced by its `redacted()` form.
  Never dropped — log length and ordering are identical across every
  viewer's `FilteredGameState`, so position/count alone can't leak that a
  restricted event happened on a given turn.
- Both `CardStolen` and `CardStolenRedacted` round-trip through
  `state_codec.dart`'s JSON codec.
- **The one permitted `lib/` change:** `event_log_widget.dart`'s
  `describeEvent` renders `CardStolen` and `CardStolenRedacted` identically
  — "`<Thief> stole a card from <Victim>`" — via a single or-pattern switch
  case, so hotseat's shared screen (which holds the real, unredacted
  `CardStolen` in the engine's single-process state) never displays the
  stolen card's name either, matching the LAN behavior exactly. No reveal
  moment was added, per spec; the thief only ever sees the card by having it
  in their own hand during their own pass-device turn.

## Also touched (forced compile fixes, not new features)

- `lib/widgets/event_log_widget.dart` additionally gained `describeEvent`
  cases for `PlayerEliminated` and `DefenseTimedOut` (Feature B/A1's new
  event types) — required for the sealed `GameEvent` switch to stay
  exhaustive; no other `lib/` files needed changes.

## Config defaults

| Config | Default | Notes |
|---|---|---|
| `HostServer.defenseResponseTimeout` | `Duration(seconds: 20)` | `null` disables |
| `HostServer.reconnectGracePeriod` | `Duration(seconds: 60)` | unchanged from before this phase |

## New public API surface

- **Actions:** `DeclineDefense.isSystemDecline` (new optional field, default
  `false`, back-compatible).
- **Events:** `DefenseTimedOut`, `PlayerEliminated`, `CardStolenRedacted`.
- **Model:** `GameEvent.visibleTo` (getter), `GameEvent.redacted()`.
- **Net:** `HostServer.defenseResponseTimeout` (constructor param),
  `StateMessage.responseDeadlineEpochMs` (optional, envelope-only).

## Tests added

- `packages/game_engine/test/elimination_test.dart` (Feature B, 5 tests)
- `packages/game_engine/test/defense_timeout_test.dart` (Feature A1, 8 tests)
- `packages/net/test/defense_timeout_test.dart` (Feature A2/A3, 7 tests,
  real `HostServer`/`GameClient`/raw-WebSocket integration)
- `packages/net/test/event_redaction_test.dart` (Feature C, 11 tests)
- `test/event_log_widget_test.dart` (Feature C's `lib/` change, 6 tests)

All pre-existing tests continue to pass unmodified:
`packages/game_engine` (73 total), `packages/net` (31 total), Flutter
`test/` (existing suites unaffected; 6 new tests added).

## Known pre-existing issue (not touched this phase)

`packages/game_engine/bin/simulate.dart` (the bot balance-testing CLI)
throws `Bad state: Bot produced an illegal action ... Already played a card
this turn` partway through a run. Confirmed via `git stash` to reproduce
identically on the pre-Phase-1 codebase — unrelated to any change in this
phase, out of scope per the spec ("Do NOT ... refactor beyond what these
features require"), and not otherwise mentioned in the task. Flagging here
rather than silently leaving it unmentioned.
