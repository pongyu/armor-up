# Armor Up! — Balance Report 2 (Restoration Win Threshold + Mode Flag)

Generated from `packages/game_engine/bin/simulate.dart` against random-legal-move
bots, after the restoration-win-threshold patch: `PlayerState.wasEverDamaged`
(any piece below Strong) renamed to `wasEverBroken` (a piece must have
actually reached Lost) as the gate on `isFullyRestored`, plus new
`restorationWinEnabled`/`maxReshuffles` config. All runs used base seed
`12345`; raw JSON is in `packages/game_engine/sim_results/` (files prefixed
`r*`; see that directory's `README.md` for exact commands). These are
observations only — no card changes are proposed; rebalancing is a design
decision for the human.

**Baseline for comparison:** Phase 2's `BALANCE_REPORT.md` (files prefixed
`e*`), run under the pre-patch `wasEverDamaged` semantics at the same seed
and defend-rate, so every R-number below can be read directly against its
E-number counterpart.

---

## R1 — Baseline per player count, restoration ON (fixed threshold)

1000 games each, `defend-rate 0.667`, `restoration-win on`.

| Players | Completed | Turns avg | p10 | p50 | p90 | Elimination wins | Restoration wins | Deck-exhausted wins |
|---|---|---|---|---|---|---|---|---|
| 2 | 1000/1000 | 107.1 | 18 | 99 | 201 | 802 (80.2%) | 198 (19.8%) | 0 |
| 3 | 1000/1000 | 130.3 | 21 | 129 | 233 | 737 (73.7%) | 263 (26.3%) | 0 |
| 4 | 998/1000 | 145.6 | 26 | 151 | 248 | 738 (73.9%) | 260 (26.1%) | 0 |
| 5 | 1000/1000 | 165.1 | 28 | 177 | 285 | 734 (73.4%) | 266 (26.6%) | 0 |
| 6 | 997/1000 | 188.4 | 33 | 201 | 302 | 780 (78.2%) | 217 (21.8%) | 0 |

**Key question: restoration-win frequency per player count.** Reported
above explicitly: **19.8%-26.6%** depending on player count. The task's
suggested healthy band for a rare-but-real alternate path was roughly
5-15%; **every player count here lands above that band**, most by a wide
margin (up to ~1.8x the top of the suggested range at 5 players). This is
still a large drop from Phase 2's pre-patch numbers under the old
threshold (Phase 2 E1: 34.1%-44.8% restoration wins across the same
player counts) — the fix roughly halved restoration-win frequency, which
confirms the degenerate one-scratch-one-band-aid line was indeed a major
driver of restoration wins before. But it did not bring the rate down
into the suggested band by itself. This is reported as a number, not
tuned further, per the task's scope rules.

Compared to Phase 2's E1 baseline (same config, old threshold): game
length is also up noticeably at every player count (e.g. 2 players: 89.3
-> 107.1 avg turns; 6 players: 146.1 -> 188.4 avg turns) — consistent with
restoration wins now requiring more turns of actual damage-and-recovery
to trigger, rather than resolving on the first lucky scratch.

## R2 — Restoration OFF (basic mode)

1000 games each, `defend-rate 0.667`, `restoration-win off`.

| Players | Completed | Turns avg | p10 | p50 | p90 | Elimination wins | Restoration wins | Deck-exhausted wins |
|---|---|---|---|---|---|---|---|---|
| 2 | 1000/1000 | 129.5 | 65 | 116 | 213 | 1000 (100%) | 0 | 0 |
| 3 | 999/1000 | 166.8 | 99 | 155 | 258 | 999 (100%) | 0 | 0 |
| 4 | 998/1000 | 190.3 | 120 | 179 | 278 | 998 (100%) | 0 | 0 |
| 5 | 998/1000 | 213.6 | 144 | 201 | 304 | 998 (100%) | 0 | 0 |
| 6 | 997/1000 | 230.9 | 160 | 221 | 314 | 997 (100%) | 0 | 0 |

**Key question: does game length blow up without the restoration pacing
valve, especially at 5-6 players?**

Comparing R2 (restoration OFF) to R1 (restoration ON) at the same player
count:

| Players | R1 avg turns (restoration ON) | R2 avg turns (restoration OFF) | Increase |
|---|---|---|---|
| 2 | 107.1 | 129.5 | +20.9% |
| 3 | 130.3 | 166.8 | +28.0% |
| 4 | 145.6 | 190.3 | +30.7% |
| 5 | 165.1 | 213.6 | +29.4% |
| 6 | 188.4 | 230.9 | +22.6% |

**"Blow up" is too strong a word, but the effect is real and grows with
player count before tapering slightly at 6.** Games get 21-31% longer on
average with restoration disabled, and — notably — the *floor* of the
distribution rises sharply: p10 goes from 18/21/26/28/33 turns (R1) to
65/99/120/144/160 turns (R2). In basic mode there is no fast escape route
at all (elimination is the only win condition, and eliminating an entire
table takes a while), so the shortest games in R2 are 3-9x longer than
the shortest games in R1. Incomplete-game (turn-cap-hit) counts are
comparable between R1 and R2 (both single digits per 1000 at higher
player counts) — the 500-turn cap is not meaningfully more strained
without restoration, but every game does take noticeably longer to
resolve. This is exactly the "pacing valve" effect the task asked about,
just not dramatic enough to call it blowing up.

## R3 — Defense value re-run (restoration ON, stricter threshold)

`players=4`, 1000 games per defend-rate, `restoration-win on`.

| Defend rate | Completed | Turns avg | Elimination wins | Restoration wins | Incomplete (hit cap) |
|---|---|---|---|---|---|
| 0.0 (never defend) | 1000/1000 | 107.2 | 877 (87.7%) | 123 (12.3%) | 0 |
| 0.33 | 1000/1000 | 127.7 | 779 (77.9%) | 221 (22.1%) | 0 |
| 0.667 (baseline) | 998/1000 | 145.6 | 738 (73.9%) | 260 (26.1%) | 2 |
| 1.0 (always defend) | 996/1000 | 160.6 | 721 (72.4%) | 275 (27.6%) | 4 |

**Key question: does defend-rate 1.0 still avoid stalling under the
stricter threshold?** Yes, in the same qualitative sense as Phase 2's E3:
the same clean, monotonic relationship holds (more defending -> longer
games, fewer elimination wins, more restoration wins), and the game still
resolves in the overwhelming majority of cases. The incomplete-game rate
at defend-rate 1.0 is 4/1000 (0.4%), up slightly from Phase 2's E3 result
under the old threshold (3/1000, also at defend-rate 1.0) — a small
further increase, consistent with restoration wins now taking longer to
land (per R1 above), giving marginally more opportunity for a game to
grind past the 500-turn cap before either win condition fires. Not a
concerning jump, but the direction is worth watching if defend-rate
tuning or the turn cap itself is ever revisited.

## R4 — Card power check (pooled across R1's 4995 completed games, 2-6 players)

Winner-correlation ratio, same methodology as Phase 2's E4 (player-count-weighted
baseline expectation).

| Card | Ratio | Actual | Expected | n (total plays) |
|---|---|---|---|---|
| **Armor Bearer** | **1.433** | 39.3% | 27.4% | 35,596 |
| **Fasting** | **1.425** | 39.0% | 27.4% | 35,527 |
| Renewal | 1.356 | 37.6% | 27.8% | 52,253 |
| **It Is Written** | **1.318** | 35.4% | 26.9% | 32,155 |
| **Goliath's Taunt** | **1.313** | 34.8% | 26.5% | 30,157 |
| Road to Damascus | 1.281 | 34.1% | 26.6% | 27,304 |
| Prayer | 1.270 | 34.2% | 26.9% | 64,624 |
| Fiery Dart | 1.247 | 33.0% | 26.5% | 89,150 |
| Fellowship | 1.162 | 31.3% | 27.0% | 31,926 |
| Wilderness Season | 1.151 | 31.5% | 27.4% | 24,813 |
| Pride | 1.149 | 30.2% | 26.3% | 42,969 |
| Deception | 1.147 | 30.1% | 26.3% | 42,917 |
| Discouragement | 1.144 | 30.1% | 26.3% | 42,891 |
| Confusion | 1.141 | 30.0% | 26.3% | 42,888 |
| Doubt | 1.133 | 29.7% | 26.2% | 42,889 |
| Jericho March | 1.127 | 31.0% | 27.5% | 13,235 |
| Strife | 1.120 | 29.4% | 26.3% | 42,730 |

**Key question: do Armor Bearer/Fasting drop from their 1.41/1.40 now
that the cheap comeback is gone?**

**No — if anything they went up slightly**: Armor Bearer 1.408 -> 1.433,
Fasting 1.401 -> 1.425 (Phase 2 E4 -> this R4). This was not the expected
direction going in, but makes sense in hindsight: the threshold change
didn't touch how strongly these two cards correlate with an eventual win
*when they are actually the card that turns a Lost piece back around* —
it just removed a large volume of restoration wins that never involved
Armor Bearer or Fasting at all (the one-Weakened-scratch-plus-Renewal
line went through Renewal alone, at Weakened, never touching a Lost
piece). Removing that low-signal noise from the restoration-win pool
concentrates the remaining restoration wins around the cards that
actually recover from Lost - i.e. Armor Bearer and Fasting specifically -
so their correlation ratio holds steady or rises even as the *overall*
restoration-win rate roughly halves (see R1 above).

The same "every card has ratio >= 1.0" pattern flagged in Phase 2's E4
persists here too, and the same caveat applies: this is most likely a
survivorship-bias artifact of the metric (the winner, by definition,
survived longer and played more cards) rather than every card
independently helping you win. No card's ratio is extreme enough
relative to the others to flag as a standalone outlier beyond the
already-discussed Armor Bearer/Fasting/Renewal/It Is Written/Goliath's
Taunt cluster sitting clearly above the ~1.12-1.16 floor the "generic"
attack cards (Strife, Doubt, Confusion, Pride, Discouragement, Deception)
cluster around.

## R5 — Reshuffle cap probe

`players=5`, `restoration-win on`, `defend-rate 0.667`, 1000 games each.

| `--max-reshuffles` | Completed | Turns avg | p10 | p50 | p90 | Elimination | Restoration | Deck-exhausted |
|---|---|---|---|---|---|---|---|---|
| `1` | 1000/1000 | 71.0 | 28 | 82 | 88 | 0 (0.0%) | 261 (26.1%) | 739 (73.9%) |
| `none` (= R1's players=5) | 1000/1000 | 165.1 | 28 | 177 | 285 | 734 (73.4%) | 266 (26.6%) | 0 (0.0%) |

**Key question: what fraction of games end on the exhaustion clock, and
how does game length shift?**

The effect is large and immediate: with `--max-reshuffles 1`, **73.9% of
games end via deck-exhaustion ranking** (vs. 0% with unlimited
reshuffles), and average game length drops by more than half (165.1 ->
71.0 turns, a 57% reduction). Notably, `p90` compresses dramatically too
(285 -> 88 turns) — capping reshuffles doesn't just end games earlier on
average, it makes game length far more consistent/predictable, since
most games now hit the same hard exhaustion wall rather than playing out
to a "natural" elimination or restoration conclusion. Interestingly,
**elimination wins drop to zero** under the cap — with the deck running
out this fast, no game has enough turns left for anyone to actually
eliminate an opponent (going from Strong to fully Lost across an entire
table takes sustained play the capped deck doesn't allow), while
restoration-win frequency (26.1%) is essentially unchanged from the
uncapped baseline (26.6%) - restoration apparently still happens
opportunistically within the shortened window at about the same rate it
always did. `--max-reshuffles 1` is a very aggressive setting for
demonstrating the mechanism works; it is not a suggestion for what the
actual game should ship with.

---

## Possible concerns (observations only — no card/threshold changes proposed)

1. **Restoration-win frequency (19.8%-26.6%, R1) remains above the
   suggested healthy 5-15% band at every player count**, even after the
   fix roughly halved it from Phase 2's pre-patch levels. If a rate
   inside that band is actually desired, the Lost-then-restored threshold
   alone was not sufficient to get there — a further change (to the
   threshold itself, to restore-card availability, or to something else
   entirely) would be a separate design decision.
2. **Restoration OFF (R2) doesn't blow up game length, but it does add
   real, consistent overhead** (21-31% longer average games, and a much
   higher floor: the fastest basic-mode games are still 3-9x longer than
   the fastest full-mode games). Worth confirming this pacing is
   acceptable for the "younger kids" audience basic mode targets, since
   longer minimum game length may matter more for that audience than the
   average.
3. **Armor Bearer and Fasting's winner-correlation didn't drop as
   expected — it rose slightly.** Not concerning on its own (explained
   above as a concentration effect from removing low-signal restoration
   wins), but worth noting since the intuition going into this patch
   ("the cheap comeback is gone, so these cards' apparent power should
   drop") did not hold. Their correlation strength was never really about
   volume of restoration wins; it's about being the specific mechanism
   that ends a Lost-piece comeback, and that mechanism didn't change.
4. **`--max-reshuffles 1` eliminates elimination wins entirely** (0/1000)
   in this sample. If a reshuffle cap is ever considered for the shipped
   game (rather than purely as a simulation/testing knob), a cap that
   aggressive would functionally turn deck-exhaustion ranking into the
   dominant win condition rather than a rare tiebreak - a much higher cap,
   or none at all, is likely what any real ruling would want; this
   experiment used `1` specifically to make the mechanism's effect
   unambiguous in a 1000-game sample, not as a recommendation.
5. **The reshuffle-cap-triggered `deckExhausted` win type still uses the
   same most-Strong/fewest-Lost/turn-order tiebreak as literal deck
   exhaustion** (see engine.dart's `_declareDeckExhaustedWinner`, reused
   as-is by the cap). With elimination wins suppressed to zero under a
   tight cap, this tiebreak logic is now exercised far more heavily than
   it ever was in Phase 2 (where `deckExhausted` was 0/9000 across every
   experiment) - worth knowing this code path now has real simulated
   coverage where before it had none outside unit tests.

## Reproducing this report

Every number above traces back to a JSON file in
`packages/game_engine/sim_results/` (files prefixed `r*`), each of which
records its own exact `--games`/`--seed`/`--players`/`--defend-rate`/
`--restoration-win`/`--max-reshuffles` in its `config` block. See that
directory's `README.md` for the exact command for every file.
