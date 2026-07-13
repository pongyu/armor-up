# Phase 3: Armor State Visuals & Targeting UX

`lib/`-only. Reworks the three armor conditions (Strong/Weakened/Lost) to be
maximally distinct at a glance instead of "almost as dark" (a deliberate
choice from an earlier phase that playtesting/screenshot review showed
players couldn't actually read), fixes a muted-color bug in the full-size
armor badge, disables restore cards in hand when they have nowhere to go,
surfaces the engine's `RestorationImminent` announcement as an actual
on-screen banner plus a persistent fully-armored marker, and adds a
fasting-target marker plus damage/restore state-change animations. No
engine, net, or card-definition changes.

## Part 1 — Three-channel state visuals

**Files:** `lib/theme/armor_up_colors.dart`, `lib/widgets/armor_widget.dart`

- `ArmorUpColors.armorStrong`/`armorWeakened` recolored to gold and amber
  respectively (`armorLost` unchanged, already a dark charcoal) — the three
  border colors are now chosen to be distinct on hue *and* lightness from
  each other, not a graded darkening ramp.
- `_ArmorIcon`'s icon tint/brightness reworked: Strong now renders with no
  color filter at all (full brightness, was previously darkened too);
  Weakened uses a new `_weakenedFilter` at 0.65 base brightness plus a flat
  amber tint via the matrix's translation column (was crushed to ~0.18,
  nearly as dark as Lost); Lost stays a dark desaturated silhouette but
  raised slightly to 0.22 base brightness so it reads as "empty but
  recoverable" rather than blank. Verified against the actual pixel art
  (`assets/armor/*.png`, bright silver/steel on transparent) that the amber
  tint doesn't fight the source art before committing to this approach.
- New `_ArmorOverlayPainter` (`CustomPainter`, applied as a
  `foregroundPainter` over the icon): paints a jagged dark crack for
  Weakened, a red X (slight inset) for Lost, nothing for Strong. Painted,
  not a new image asset, so it scales with both badge sizes and works over
  every armor icon; stroke widths are proportional to the badge's own size.
  This is the primary legibility cue at compact/small sizes and gives the
  states a shape-based (color-blind-safe) distinction, not just a color one.

## Part 2 — Targeting & muted fixes

**Files:** `lib/widgets/armor_widget.dart`, `lib/screens/game_screen.dart`

- Fixed a pre-existing bug where the full-size `ArmorBadge` ignored `muted`
  for its border color entirely (only the compact variant dimmed to 35%
  alpha) — both variants now compute `displayColor` identically.
- New `_hasNoEligibleOwnArmorTarget(CardDef, PlayerState)` helper in
  `game_screen.dart`: true for a restore card targeting the player's own
  armor (Renewal/Armor Bearer — Fasting always returns false, since it
  accepts any condition) when none of the player's pieces currently satisfy
  the card's target rule. Wired into both the portrait board's
  `isCardDisabled` and the landscape board's `_HandCard` `disabled`
  expression (previously only handled `readOnly`/`isFasting`/
  `hasPlayedCardThisTurn`/defense-card exclusion) — a Renewal with no
  Weakened pieces, or an Armor Bearer with no Lost pieces, now shows
  disabled/grayed in hand up front instead of only failing at an
  all-muted, dead-end target-selection screen.
- New `_eligiblePulseController` on `ArmorBadge`: a continuous, subtle
  pulsing gold glow (alpha 0.35↔0.65, ~1s cycle) on badges that are
  currently selectable-but-unselected during target selection, so live
  choices are easy to spot without being as loud as the selected-state glow.
  Ineligible badges stay muted as before. Skipped when
  `MediaQuery.of(context).disableAnimations` is set.

## Part 2.5 — Restoration-imminent visibility

**Files:** `lib/screens/game_screen.dart`

- New `_RestorationImminentBannerHost` (mounted once, at the top of
  `GameScreen`'s `Stack`, above every sub-view — pass-device gate, defense
  prompt, board — since the announcement is for the whole table, not just
  whichever screen happens to be showing): diffs `state.eventLog`'s length
  across rebuilds to detect a newly-appended `RestorationImminent` event
  (length-based, not "does the log contain one" — the log is permanent and
  never truncated, so a level-based check would either show the banner
  forever or never re-show it) and displays `_RestorationImminentBanner`
  for it — a full-width, gold-bordered banner naming the player, auto-
  dismissing after 4s via a tracked `Timer` (cancelled on dispose and
  replaced rather than stacked if a second event lands before the first
  timer fires) or immediately on tap. Only counts events appended *after*
  the host first mounts, so resuming a game or a hot reload doesn't replay
  history. `_RestorationImminentBanner` is a plain non-blocking overlay
  (`Material`/`InkWell` sized to its own content, not a barrier) — the
  board underneath stays fully interactive while it shows.
- New `_FullyArmoredMarker`: a small gold trophy icon shown next to a
  player's name wherever it's rendered — the compact opponent row
  (`_PlayerListRow`), the landscape board's own-armor panel
  (`_ActivePlayerPortraitPanel`), and the portrait board's inline "Your
  Armor" header. Gated on `player.isFullyRestored && state.restorationWinEnabled`
  at each call site, threaded down through `_PlayerListPanel`'s new
  `restorationWinEnabled` parameter for the compact-row case. Deliberately
  derived from state on every build, not from the event or a one-shot
  flag: it needs no separate "restoration stopped" signal, since it simply
  stops rendering the next time `isFullyRestored` goes false — which
  already happens the moment any hit drops a piece below Strong, via the
  same rebuild that shows the normal damage event/log line. If the
  marked player later wins, `state.isGameOver` routes to `WinScreen` as
  normal, same as any other win.

## Part 3 — State-change animations & fasting marker

**Files:** `lib/widgets/armor_widget.dart`

- `ArmorBadge` converted to a `StatefulWidget` (`_ArmorBadgeState`) that
  diffs the piece's condition across rebuilds (`didUpdateWidget`) and
  drives two one-shot `AnimationController`s purely from that diff — no new
  engine events needed. Damage (severity increases) triggers a quick
  ~250ms shake (small sine-wobble translation); restore (severity
  decreases, including a Fasting completion landing on Strong) triggers a
  ~400ms gold glow bloom-and-fade, deliberately calm rather than flashy to
  contrast with the shake. Both respect `disableAnimations` (skipped
  entirely, state still applies immediately either way — animations are
  purely additive and never gate input or state application).
- New `_FastingMarker`: a small pulsing gold hourglass badge shown in the
  corner of whichever armor slot is `PlayerState.fastingRestoreTarget`.
  Wired through `ArmorRow` so it's visible on both the owner's full grid
  and every opponent's compact row — deliberately not hidden from
  opponents, since seeing the fasting target is the intended counterplay
  window Fasting's delayed-restore timing exists to create. Disappears
  automatically once `fastingRestoreTarget` clears (fast completes or the
  player is eliminated), since the marker is a pure mirror of that engine
  field with no independent state of its own.

## Part 4 — Tests & manual verification

**Files:** `test/armor_widget_test.dart` (new),
`test/game_screen_restore_disabled_test.dart` (new),
`test/game_screen_restoration_imminent_test.dart` (new)

- `armor_widget_test.dart`: overlay painter present/absent per condition
  (none for Strong, exactly one for Weakened/Lost); muted dims the border
  alpha identically in both compact and full-size variants (explicit
  regression coverage for the Part 2 bug fix); fasting marker shown when
  `fasting: true`, absent when `false`, and removed on a live update from
  true to false; `ArmorRow` wires the marker only onto the piece matching
  `fastingRestoreTarget`.
- `game_screen_restore_disabled_test.dart`: drives a real `GameController`
  with a crafted `GameState` (via `newGame` + `copyWith`) through the
  pass-device gate into the portrait board, then asserts on the presence of
  a `ColorFiltered` ancestor (the disabled-card visual treatment) — Renewal
  is disabled with an all-Strong hand and enabled once a piece is Weakened;
  Armor Bearer is disabled with no Lost pieces; Fasting is never disabled by
  eligibility (accepts any condition).
- `game_screen_restoration_imminent_test.dart`: banner appears when a
  `RestorationImminent` event is appended to a live state (not when it was
  already present at mount, confirming the no-replay-on-resume guard);
  auto-dismisses after the 4s timer and dismisses immediately on tap; the
  board stays interactive underneath (Draw still dispatches while the
  banner is showing); the fully-armored marker appears for a player with
  `isFullyRestored` on both the compact opponent row and the active
  player's own panel, is absent with no fully-restored player, disappears
  on the very next rebuild after a piece drops below Strong, and never
  renders when `restorationWinEnabled` is false. This test suite caught a
  real bug during development: the auto-dismiss timer was originally
  started directly in `build()`, which leaked a fresh uncancelled `Timer`
  on every unrelated rebuild while the banner was showing — fixed by
  tracking a single `Timer` field, started once per new event in
  `didUpdateWidget` and cancelled on dispose/replacement.
- Full existing suite (31 pre-existing tests) plus 24 new tests all pass;
  `flutter analyze lib/ test/` clean.
- **Manual verification checklist (not automated — screenshot these by
  hand before shipping):**
  - [ ] Compact opponent row shows all three conditions clearly
        distinguishable (gold/no-overlay, amber/crack, dark/red-X).
  - [ ] Full "Your Armor" grid shows the same three states clearly at the
        larger badge size.
  - [ ] Entering target-selection mode with a mixed board shows eligible
        badges pulsing gold and ineligible badges muted/dim.
  - [ ] A Fasting player's targeted slot shows the pulsing hourglass marker
        on their own grid *and* on every opponent's compact row.
  - [ ] Damage animation: hitting a Strong or Weakened piece shows a quick
        shake plus the crack/X fading in.
  - [ ] Restore animation: playing a restore/Fasting-completion shows the
        crack/X fade out plus a brief gold glow, and the fasting marker
        (if any) disappears with it.
  - [ ] Renewal/Armor Bearer show up grayed in hand exactly when they have
        zero eligible targets, in both portrait and landscape layouts.
  - [ ] Restoring a player's last Weakened piece to Strong shows the
        gold banner naming them, auto-dismissing after ~4s or on tap,
        without freezing the board underneath.
  - [ ] The fully-armored trophy icon appears by that player's name (their
        own panel and every opponent's compact row) and disappears the
        instant any piece of theirs is next hit.
  - [ ] In basic mode (restoration win off), neither the banner nor the
        trophy icon ever appears, even if a player's armor is fully Strong.

**Do NOT (per spec, and honored in this pass):** no layout structure
changes, no palette changes beyond the three state colors, no card art
changes, no engine/net code touched.

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

---

# Patch: Restoration Win Threshold + Mode Flag

Closes a playtesting-confirmed degenerate line: a single armor piece
dropping to Weakened and immediately patched with one Renewal used to
count as a full "comeback" and could win the game at the next turn
rotation. `PlayerState.wasEverDamaged` (any piece below Strong) is
renamed to `wasEverBroken` and now requires a piece to have actually
reached `ArmorCondition.lost` at some point. Restoration wins are also
now a configurable game mode (`restorationWinEnabled`), and a new
`maxReshuffles` rules variant caps how many times the discard pile may
be reshuffled before the game ends via deck-exhaustion ranking.

## Part 1 — Field rename + threshold change

**Files:** `packages/game_engine/lib/src/models/player.dart`,
`packages/net/lib/src/state_codec.dart`,
`packages/net/lib/src/filtered_state.dart`,
`lib/state/filtered_state_adapter.dart`,
`packages/game_engine/test/test_helpers.dart`,
`test/filtered_state_adapter_test.dart`

- `PlayerState.wasEverDamaged` renamed to `wasEverBroken` throughout the
  engine, net, and Flutter layers — no deprecated shim, no dual field; a
  straight rename plus semantics change in one pass, per the task's
  explicit "no deprecated shims" instruction.
- `withArmorCondition`'s set-site changed from `condition != strong` (any
  damage) to `condition == lost` (must actually bottom out) — the load-bearing
  line that fixes the degenerate line, since a Weakened piece patched by
  Renewal never triggers this anymore.
- `isFullyRestored = wasEverBroken && all pieces Strong` — same shape as
  before, new gating field.
- Mirrored end-to-end through the net layer exactly like every other
  player-state field: `PlayerStateJson` (raw codec), `PublicPlayerView`
  (per-viewer filtered view, public info — armor condition is already
  visible, so no redaction concern), and the Flutter LAN client's
  `reconstructFromFiltered`.
- Every pre-existing test/call site that referenced the old name was
  found via a full-repository search (not grep-and-hope) and updated;
  `dart analyze`/`flutter analyze` clean across all three packages with
  zero references to the old name remaining anywhere.

## Part 2 — Mode flag: `restorationWinEnabled`

**Files:** `packages/game_engine/lib/src/models/game_state.dart`,
`packages/game_engine/lib/src/engine.dart`,
`packages/game_engine/lib/src/setup.dart`,
`packages/net/lib/src/state_codec.dart`,
`packages/net/lib/src/filtered_state.dart`,
`lib/state/filtered_state_adapter.dart`

- New `GameState.restorationWinEnabled` (`bool`, **default `true`** —
  "full mode", preserves existing behavior for every test/call site that
  doesn't explicitly opt into basic mode).
- `_checkRestorationWin` gains a one-line early return when the flag is
  false: `if (!state.restorationWinEnabled) return state;` — elimination
  and deck-exhaustion ranking are completely untouched by the flag, so
  basic mode is exactly "full mode minus one win condition," not a
  parallel rules path.
- Threaded through `newGame(...)` as a new optional named parameter, and
  mirrored table-wide (not per-viewer — it's a table-wide rule, not a
  secret) through `FilteredGameState` and the raw `GameStateJson` codec,
  following the exact pattern `hasDrawnThisTurn`/`rngSeed` already
  established for scalar `GameState` fields in `state_codec.dart`.

## Part 2b — Rules variant: `maxReshuffles`

**Files:** same as Part 2, plus
`packages/game_engine/lib/src/models/game_state.dart` (`reshuffleCount`
getter)

- New `GameState.maxReshuffles` (`int?`, **default `null`** = unlimited,
  preserves original behavior).
- New `GameState.reshuffleCount` getter, derived from
  `eventLog.whereType<DeckReshuffled>().length` rather than a separate
  counter field — can never drift out of sync with the event log itself,
  and this is exactly the pattern `bin/simulate.dart` (Phase 2) already
  used at the harness level to count reshuffles; promoting it onto
  `GameState` itself means the engine can now enforce the cap directly
  instead of only the harness being able to observe it after the fact.
- Enforcement lives in `_drawCard` (`engine.dart`): when the draw pile is
  empty, the discard pile is non-empty (i.e. a reshuffle would normally
  happen), and `reshuffleCount >= maxReshuffles`, the game ends
  immediately via the existing `_declareDeckExhaustedWinner` — the exact
  same ranking (most Strong, then fewest Lost, then turn order) used for
  a literal double-empty-pile exhaustion. No new win type; a
  cap-triggered end is logged as `WinType.deckExhausted`, same as
  before, since from the ranking's perspective it's the identical
  situation one reshuffle earlier.

## Part 3 — Tests

**Files:** `packages/game_engine/test/win_condition_test.dart`,
`packages/game_engine/test/restore_and_event_test.dart`,
`packages/net/test/checkpoint_test.dart`,
`test/filtered_state_adapter_test.dart`

- The exact degenerate line from playtesting (Weakened -> Renewal -> turn
  rotation) is now a named regression test asserting no win.
- Lost -> Armor Bearer restore -> turn rotation asserts a real
  restoration win.
- A "sticky flag" test confirms `wasEverBroken`, once set, survives even
  when the armor is edited back to Strong through a path other than
  `withArmorCondition` (i.e. the flag itself is never implicitly cleared
  by having full Strong armor again).
- Three `restorationWinEnabled=false` tests: a would-be restoration
  winner does not win and the game continues; elimination still
  functions; deck-exhaustion ranking still functions.
- Three reshuffle-cap tests: `maxReshuffles=null` preserves unlimited
  behavior; `maxReshuffles=0` turns the very first reshuffle attempt
  into immediate exhaustion; `maxReshuffles=1` allows exactly one
  reshuffle and ends the game on the second attempt.
- JSON round-trip tests for `wasEverBroken`, `restorationWinEnabled`, and
  `maxReshuffles` (both set and the null/unset case) across `PlayerState`,
  `GameState`, and `FilteredGameState`.

## Part 4 — Sim harness

**Files:** `packages/game_engine/bin/simulate.dart`

- New `--restoration-win <on|off>` flag (**default `on`**), mapped to
  `newGame`'s `restorationWinEnabled`.
- New `--max-reshuffles <int|none>` flag (**default `none`** = unlimited,
  matching the engine default), mapped to `newGame`'s `maxReshuffles`.
- Both new flags are echoed in the stdout summary header and the JSON
  `config` block, alongside the pre-existing `--games`/`--seed`/
  `--players`/`--defend-rate`, so every run remains fully reproducible
  from its own printed config.

## Part 5 — Flutter UI

**Files:** `lib/screens/setup_screen.dart`, `lib/state/game_controller.dart`,
`packages/net/lib/src/host_server.dart`

- **Hotseat setup screen got a toggle** (a `SwitchListTile`, the first of
  its kind in this screen — inserted between the add/remove-player row
  and the Start Game button): "Restoration win", defaulting to on, wired
  through `GameController.startGame(restorationWinEnabled: ...)` into
  `newGame(...)`. This was judged to "obviously fit the existing setup UI
  pattern" per the scope rules — a single on/off `SwitchListTile` in an
  existing settings-style `Column`, no new screen or state-management
  pattern required.
- **`maxReshuffles` was deliberately left out of the UI entirely** and
  hardcoded to the engine default (`null`/unlimited) for both hotseat and
  LAN — there is no existing "reshuffle limit" concept anywhere in the
  app's UI to hang a toggle off of, and it reads as a simulation/testing
  knob rather than a player-facing option a family game night host would
  reach for. Flagging explicitly here for a later UI pass if a
  reshuffle-limit mode is ever wanted in the shipped app.
- `HostServer.startGame` gained the same two optional parameters
  (`restorationWinEnabled`, `maxReshuffles`) for API parity with
  `newGame`, but **no LAN lobby UI change was made** — no lobby screen
  currently exposes any rules-config toggle, so LAN games always start
  in the engine's default configuration (full mode, unlimited reshuffles)
  until a later UI pass.

## Config defaults (this patch)

| Config | Default | Notes |
|---|---|---|
| `GameState.restorationWinEnabled` | `true` | "full mode"; preserves Phase 1/2 behavior |
| `GameState.maxReshuffles` | `null` | unlimited; preserves original behavior |
| `simulate.dart --restoration-win` | `on` | maps to the flag above |
| `simulate.dart --max-reshuffles` | `none` | maps to the flag above |
| Setup screen "Restoration win" toggle | on | hotseat only; LAN has no UI toggle yet |

## New public API surface

- **Model:** `PlayerState.wasEverBroken` (renamed + new semantics from
  `wasEverDamaged`), `GameState.restorationWinEnabled`,
  `GameState.maxReshuffles`, `GameState.reshuffleCount` (derived getter).
- **Setup:** `newGame(..., restorationWinEnabled, maxReshuffles)` — both
  new optional named params, back-compatible defaults.
- **Net:** `FilteredGameState.restorationWinEnabled`,
  `FilteredGameState.maxReshuffles`, `HostServer.startGame(...,
  restorationWinEnabled, maxReshuffles)`.
- **Harness:** `simulate.dart --restoration-win <on|off>`,
  `--max-reshuffles <int|none>`.

## Tests added

- `packages/game_engine/test/win_condition_test.dart`: 8 new tests
  (degenerate line, Lost-then-restored win, sticky flag, 3x
  `restorationWinEnabled=false` behavior).
- `packages/game_engine/test/restore_and_event_test.dart`: 3 new tests
  (reshuffle cap: unlimited, `0`, `1`).
- `packages/net/test/checkpoint_test.dart`: 4 new tests (JSON round-trip
  for `wasEverBroken`, `restorationWinEnabled`/`maxReshuffles` on both
  `GameState` and `FilteredGameState`).
- `test/filtered_state_adapter_test.dart`: 1 new test (LAN
  reconstruction preserves the new rules config).

All pre-existing tests updated where the semantics change required it
(2 restoration-win tests in `win_condition_test.dart` rewritten to use
the new Lost-based threshold instead of Weakened) and otherwise pass
unmodified: `packages/game_engine` (83 total), `packages/net` (35
total), Flutter `test/` (31 total, 1 new).

## Balance re-run (R1-R5)

See `BALANCE_REPORT_2.md` for full numbers. Headline findings:
restoration-win frequency dropped from Phase 2's 34-45% to 20-27% under
the fixed threshold (still above the suggested 5-15% healthy band);
disabling restoration entirely lengthens games by 21-31% without
"blowing up"; Armor Bearer/Fasting's winner-correlation ratio held
steady or rose slightly rather than dropping, since the fix removed
low-signal restoration wins rather than touching how strongly those two
cards correlate with a genuine comeback; and a `--max-reshuffles 1` cap
demonstrably works, pushing 74% of games to end via deck-exhaustion
ranking (a code path that previously had zero simulated coverage).

---

# Patch: Delayed Fasting + Restoration-Imminent Announcement

Closes a second playtesting-confirmed degenerate line: Fasting used to
heal its chosen piece INSTANTLY on play, making its nominal cost (skip
next turn's play step) meaningless to a player already pursuing a
restoration win and not otherwise planning to attack. Fasting's
restoration now lands at the END of the fasted turn - commit, endure,
then restored - giving the table a genuine one-round window to punish
the fasting player before the heal lands. Separately, a new
`RestorationImminent` event announces the moment any player transitions
into `isFullyRestored`, making the table-wide counterplay window (which
already existed - restoration only wins at the start of the winner's
own next turn) actually visible rather than silent.

## Part 1 — Delayed Fasting

**Files:** `packages/game_engine/lib/src/models/player.dart`,
`packages/game_engine/lib/src/effects.dart`,
`packages/game_engine/lib/src/engine.dart`,
`packages/net/lib/src/state_codec.dart`,
`packages/net/lib/src/filtered_state.dart`,
`lib/state/filtered_state_adapter.dart`,
`lib/widgets/card_widget.dart`

- New `PlayerState.fastingRestoreTarget` (`ArmorType?`): the piece chosen
  when Fasting is played, pending restoration until the fast completes.
  Non-null from the moment Fasting is played until the end of the fasted
  turn. Target validation on play stays fully permissive (any own piece,
  any condition) - unchanged from before.
- `effects.dart`'s `skipNextTurnAndRestore` case no longer calls
  `_applyArmorCondition` at all - playing Fasting now only sets
  `fastingScheduled: true` and `fastingRestoreTarget: <chosen piece>`.
  Nothing heals, and no `ArmorRestored` event fires, until the fast is
  endured.
- `engine.dart`'s `_endTurn`: when the ending turn belongs to a player
  whose `isFasting` is true and `fastingRestoreTarget != null`, that
  piece restores to Strong **unconditionally** (regardless of its
  condition at that moment - it may have been attacked again, even back
  down to Lost, during the window; the fast still completes and still
  heals fully), `fastingRestoreTarget` is cleared, and `ArmorRestored` is
  logged. This happens before turn rotation and both win checks, so the
  restoration is visible to the start-of-next-turn restoration check one
  full round later, exactly per the design ruling.
- **Elimination during the window**: no explicit check was needed beyond
  a documentary `assert` - an eliminated player never becomes the active
  player again (turn order already skips them), so a pending fast for an
  eliminated player's own turn simply never gets an `_endTurn` call to
  trigger it. Verified by a dedicated test rather than assumed.
- **No overlap guard was added**: a player cannot have two pending fasts
  simultaneously by construction of the existing turn-flow guards
  (`isFasting` blocks `PlayCard` entirely during the fasted turn itself,
  and the turn in between - after playing Fasting but before it becomes
  their fasted turn - never offers them another play step), so no new
  validation was required; this was confirmed by tracing the guard
  chain, not just assumed.
- `fastingRestoreTarget` is serialized and mirrored through the net layer
  exactly like `wasEverBroken`/other player fields, **but deliberately
  public** (visible to every viewer via `PublicPlayerView`, not redacted
  like hand contents) - per the design ruling, seeing which piece an
  opponent is fasting for is the whole point of the counterplay window.
- Card text updated in `card_widget.dart`'s `describeEffect` (the actual
  location of the on-card description string - the task referenced
  `deck.dart`, but `deck.dart` has no free-text description field; the
  UI generates it dynamically from `EffectPrimitive` in `card_widget.dart`):
  "Skip your next turn; when the fast is complete, fully restore one
  piece."

## Part 2 — Restoration-imminent announcement

**Files:** `packages/game_engine/lib/src/models/game_event.dart`,
`packages/game_engine/lib/src/effects.dart`,
`packages/game_engine/lib/src/engine.dart`,
`packages/net/lib/src/state_codec.dart`,
`lib/widgets/event_log_widget.dart`

- New `RestorationImminent { turnNumber, playerId }` event, public
  (`visibleTo` null, the default).
- New shared helper `announceIfNewlyFullyRestored({before, after,
  playerId})` in `effects.dart` (exported, not private, since both
  `effects.dart`'s own `_applyArmorCondition` - covering Renewal/Armor
  Bearer - and `engine.dart`'s `_endTurn` - covering Fasting's delayed
  completion - need it, and a private function can't cross that library
  boundary). Compares `isFullyRestored` before/after a restore and logs
  the event only on the false-to-true transition; a no-op when
  `GameState.restorationWinEnabled` is false. Never fires repeatedly
  while the condition continues to hold, and fires again if a player is
  later knocked back below full and later re-achieves it (transition-based,
  not level-based) - all three properties verified by dedicated tests.
- `event_log_widget.dart` renders it as
  "`<PLAYER> STANDS FULLY ARMORED - STOP THEM BEFORE THEIR NEXT TURN!`"
  (uppercased player name via `.toUpperCase()`). Uses a plain hyphen, not
  an em-dash, matching this file's own established precedent for the
  app's pixel font's (`EarlyGameBoy`) limited glyph support - already
  documented as breaking `>` and `(` elsewhere in the codebase, and not
  worth risking for the highest-urgency line in the log.
- No change to the win check itself: `_checkRestorationWin` is untouched.
  This event is purely informational.

## Part 3 — Tests

**Files:** `packages/game_engine/test/fasting_timing_test.dart` (new),
`packages/game_engine/test/restoration_imminent_test.dart` (new),
`packages/game_engine/test/restore_and_event_test.dart`,
`packages/net/test/checkpoint_test.dart`

- `fasting_timing_test.dart` (8 tests): heal does not occur on play, only
  on end-of-fasted-turn; an unrelated piece attacked during the window is
  unaffected by Fasting's completion; the fasting TARGET itself re-attacked
  down to Lost during the window still restores to Strong unconditionally;
  fasting player eliminated during the window means the pending restore
  never fires; `fastingRestoreTarget` model-level check; fasting player
  can still declare a reactive defense card on a later turn (regression);
  plus the exact win-timing regression line from the task (Fasting played,
  fast endured, heal lands, opponent gets a full turn, win fires at next
  turn start ONLY if still fully Strong) and its negative case (opponent
  weakening any piece during that round prevents the win).
- `restoration_imminent_test.dart` (6 tests): emitted on transition;
  not re-emitted while the condition holds; re-emitted after knockdown
  and re-restoration; never emitted in basic mode; emitted specifically
  by Fasting's delayed completion (not by playing Fasting); event data
  sanity check.
- `restore_and_event_test.dart`: the 3 pre-existing Fasting tests that
  asserted immediate healing were rewritten to assert no immediate
  effect (piece condition unchanged right after play) plus the new
  `fastingScheduled`/`fastingRestoreTarget` state instead.
- `checkpoint_test.dart`: 3 new tests - `fastingRestoreTarget` JSON
  round-trip (including the "never present when unset" case, not just
  null), its cross-viewer visibility via `FilteredGameState` (public,
  unlike hand contents), and `RestorationImminent` JSON round-trip.

All pre-existing tests continue to pass unmodified except the 3 Fasting
tests listed above: `packages/game_engine` (97 total, 14 new),
`packages/net` (38 total, 3 new), Flutter `test/` (31 total, unchanged).

## New public API surface

- **Model:** `PlayerState.fastingRestoreTarget` (`ArmorType?`),
  `RestorationImminent` event.
- **Engine (exported, not private):** `announceIfNewlyFullyRestored` in
  `effects.dart`, callable from `engine.dart`.
- **Net:** `FilteredGameState`/`PublicPlayerView.fastingRestoreTarget`
  (public, not redacted).

## Balance re-run (F1-F2)

See `BALANCE_REPORT_4.md` for full numbers, with the explicit caveat that
the bot cannot react to the `RestorationImminent` announcement, so its
informational/gameplay value is unmeasured here - only Fasting's timing
mechanics are. Headline findings: delayed Fasting's effect on the
2-player restoration rush is modest on its own (p10 18->20 turns,
restoration share 19.8%->18.7% vs. R1's pre-patch numbers) but clearer at
3-4 players (restoration share down ~4pp at both, game length up
modestly); a 2-player defend-rate sweep (0.33/0.667/1.0) shows
restoration-win share rising with more defending but plateauing well
short of "dominant" (13.8% -> 18.7% -> 18.9%, elimination remains the
81-86% majority outcome throughout).
