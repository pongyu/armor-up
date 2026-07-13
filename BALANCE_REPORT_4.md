# Armor Up! — Balance Report 4 (Delayed Fasting + Restoration-Imminent Announcement)

Generated from `packages/game_engine/bin/simulate.dart` against random-legal-move
bots, after the delayed-Fasting patch: Fasting's restore now lands at the
END of the fasted turn (after the fast is actually endured) rather than
instantly on play. The win check itself did not change - restoration
still only fires at the start of the winner's own next turn - this patch
only changed when Fasting's heal lands, closing the "commit and
instant-heal with a meaningless cost" line from playtesting. All runs
used base seed `12345`; raw JSON is in `packages/game_engine/sim_results/`
(files prefixed `f*`; see that directory's `README.md` for exact
commands). These are observations only - no further card changes are
proposed; rebalancing is a design decision for the human.

**Important caveat, stated per the task:** the bot has no special
awareness of the new `RestorationImminent` announcement event and cannot
react to it - it plays exactly as it did before (uniformly random legal
moves, `defend-rate`-gated defense). Any value the announcement adds by
letting a *human* table actually see and react to an imminent win ("stop
them before their next turn!") is invisible to these numbers entirely.
The announcement's gameplay value is a human-playtest question, not
something this simulation can measure.

**Baseline for comparison:** `BALANCE_REPORT_2.md`'s R1 (same seed,
same defend-rate, restoration ON, pre-this-patch Fasting timing).

---

## F1 — R1 re-run at players 2, 3, 4 (delayed Fasting)

1000 games each, `defend-rate 0.667`, `restoration-win on`.

| Players | Completed | Turns avg | p10 | p50 | p90 | Elimination wins | Restoration wins | Deck-exhausted |
|---|---|---|---|---|---|---|---|---|
| 2 | 999/1000 | 106.5 | 20 | 100 | 191 | 812 (81.3%) | 187 (18.7%) | 0 |
| 3 | 999/1000 | 134.1 | 25 | 135 | 227 | 779 (78.0%) | 220 (22.0%) | 0 |
| 4 | 998/1000 | 154.2 | 29 | 157 | 257 | 777 (77.9%) | 221 (22.1%) | 0 |

**Direct comparison to R1 (same config, old instant-heal Fasting):**

| Players | R1 turns avg | F1 turns avg | R1 p10 | F1 p10 | R1 restoration% | F1 restoration% |
|---|---|---|---|---|---|---|
| 2 | 107.1 | 106.5 | 18 | 20 | 19.8% | 18.7% |
| 3 | 130.3 | 134.1 | 21 | 25 | 26.3% | 22.0% |
| 4 | 145.6 | 154.2 | 26 | 29 | 26.1% | 22.1% |

**Key question: how much does delayed Fasting alone move the 2-player
rush (R1 p10 was 18 turns; restoration share was 19.8%)?**

Modestly, and mostly in the *tail-length* direction rather than the
*restoration-share* direction. At 2 players specifically: p10 barely
moved at all (18 -> 20 turns, essentially within noise for a fast-path
metric like p10) and restoration-win share actually went down slightly
(19.8% -> 18.7%). The more consistent, larger effect shows up at 3 and 4
players: p10 rose noticeably (21->25 at 3p, 26->29 at 4p) and restoration
share dropped by about 4 percentage points at both (26.3%->22.0%,
26.1%->22.1%). Average game length also rose modestly across all three
counts (+~4-9 turns).

**Reading this:** delayed Fasting's core effect - giving the table a
genuine one-round window to punish a Fasting player before their heal
lands - shows up more clearly at 3-4 players than at 2. This makes sense
structurally: at 2 players there's exactly one opponent who either
attacks during the window or doesn't, so the "commit -> endure ->
restored" cost is binary and the opponent was already free to attack on
their turn regardless of Fasting's old timing. At 3-4 players, more
opponents get a look at the fasting player during the window (more total
turns pass before the fast completes, since it's still exactly one
opponent-round per the design, but that round itself is a larger slice
of a longer multi-player rotation), which shows up as slightly fewer
restoration wins completing cleanly and slightly longer games overall.
The 2-player "rush" line specifically doesn't look dramatically closer to
solved by this change alone - see "possible concerns" below.

## F2 — 2-player defend-rate sweep (delayed Fasting, restoration ON)

`players=2`, 1000 games per defend-rate.

| Defend rate | Completed | Turns avg | p10 | p50 | p90 | Elimination wins | Restoration wins |
|---|---|---|---|---|---|---|---|
| 0.33 | 1000/1000 | 90.5 | 21 | 91 | 148 | 862 (86.2%) | 138 (13.8%) |
| 0.667 (baseline) | 999/1000 | 106.5 | 20 | 100 | 191 | 812 (81.3%) | 187 (18.7%) |
| 1.0 (always defend) | 997/1000 | 121.3 | 21 | 114 | 225 | 808 (81.0%) | 189 (18.9%) |

**Key question: at 2 players specifically, does heavy defending + delayed
Fasting make restoration dominant or keep it contested?**

**Contested, not dominant, at every defend-rate tested.** Restoration-win
share rises with more defending (13.8% -> 18.7% -> 18.9%) but plateaus
well short of 50%, let alone "dominant" - elimination wins remain the
clear majority outcome (81-86%) even when bots always defend whenever
possible. Notably, the jump from 0.33 to 0.667 defend-rate (+4.9pp
restoration share) is much larger than the jump from 0.667 to 1.0
(+0.2pp, essentially flat) - defending more helps a restoration path up
to a point, then further defending stops moving the needle much,
suggesting the counterplay window (not the defend-rate) is the binding
constraint on how often a restoration comeback actually completes, not
how often damage gets blocked in general. This is consistent with the
delayed-heal window working as intended: it gives the opponent a shot
regardless of how cautiously the fasting player's opponent otherwise
plays.

---

## Possible concerns (observations only — no further card changes proposed)

1. **The 2-player restoration-win rate barely moved from this patch alone
   (19.8% -> 18.7%, F1 vs. R1).** If the goal was specifically to reduce
   how often 2-player games resolve via a Fasting-driven restoration
   comeback, this patch's effect is small at 2 players and clearer at 3-4.
   The earlier restoration-threshold patch (R-phase) did most of the
   heavy lifting on 2-player restoration frequency already; this patch's
   marginal contribution on top of that is modest.
2. **p10 game length at 2 players is still short (20 turns, F1) relative
   to 3-4 players (25, 29 turns).** The 2-player "fast game" pattern
   flagged in earlier reports persists after this patch - it wasn't
   solved by delayed Fasting, and per Balance Report 2's own note, may
   be a structurally different question (something about 2-player
   openings being swingier in general) than what Fasting's timing alone
   can address.
3. **The `RestorationImminent` announcement's actual gameplay value is
   completely unmeasured here**, per the caveat at the top of this
   report - the bot cannot react to it. If the announcement is meant to
   meaningfully change how often a table actually punishes an imminent
   restoration win (as opposed to just making the fact visible), that
   would require either a bot capable of reacting to the event, or human
   playtesting - this simulation only measures the mechanical effect of
   Fasting's delayed timing, not the informational effect of the
   announcement layered on top of it.
4. **F1 stopped at 4 players, not the full 2-6 range R1 covered.** Per
   the task's own scope, this was deliberate (F1 asks specifically about
   "players 2, 3, 4"), but it means there's no fresh 5-6 player data
   point for this patch - if delayed Fasting's effect continues to grow
   with player count (as the 2->3->4 trend suggests), a full 5-6 player
   re-run might show an even larger shift than what's reported here.

## Reproducing this report

Every number above traces back to a JSON file in
`packages/game_engine/sim_results/` (files prefixed `f*`), each of which
records its own exact `--games`/`--seed`/`--players`/`--defend-rate`/
`--restoration-win`/`--max-reshuffles` in its `config` block. See that
directory's `README.md` for the exact command for every file.
