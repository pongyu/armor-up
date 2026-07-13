# Simulation results — balance experiments

Files prefixed `e*` are from Phase 2; files prefixed `r*` are from the
restoration-win-threshold patch phase (rules change: `wasEverDamaged` ->
`wasEverBroken`, now requires a piece to have reached Lost, not just
Weakened; plus new `restorationWinEnabled`/`maxReshuffles` config); files
prefixed `f*` are from the delayed-Fasting + restoration-imminent
announcement patch phase (Fasting's restore now lands at the end of the
fasted turn instead of on play; the win check itself is unchanged). Every
run used `--seed 12345`. Full aggregate metrics, run config, and per-game
records are in each `.json` file; the matching `.stdout.txt` file is the
human-readable console summary printed at the time.

See `../../../BALANCE_REPORT.md` for the Phase 2 narrative,
`../../../BALANCE_REPORT_2.md` for the restoration-threshold-patch
narrative (R1-R5), and `../../../BALANCE_REPORT_4.md` for the
delayed-Fasting patch narrative (F1-F2).

**The `e*` and `r*` files remain valid as historical results from their
respective phases** but are no longer representative of current game
behavior for anything involving Fasting or restoration wins, since both
the win threshold (R-phase) and Fasting's timing (F-phase) changed after
they were generated — use the `f*` files for the current baseline.

## Files: restoration-win-threshold patch (R1-R5)

| File | Experiment | Command |
|---|---|---|
| `r1_players2.json` | R1 — baseline (fixed threshold), 2 players, restoration ON | `dart run bin/simulate.dart --games 1000 --seed 12345 --players 2 --defend-rate 0.667 --restoration-win on --out sim_results/r1_players2.json` |
| `r1_players3.json` | R1 — baseline, 3 players, restoration ON | `dart run bin/simulate.dart --games 1000 --seed 12345 --players 3 --defend-rate 0.667 --restoration-win on --out sim_results/r1_players3.json` |
| `r1_players4.json` | R1 — baseline, 4 players, restoration ON | `dart run bin/simulate.dart --games 1000 --seed 12345 --players 4 --defend-rate 0.667 --restoration-win on --out sim_results/r1_players4.json` |
| `r1_players5.json` | R1 — baseline, 5 players, restoration ON | `dart run bin/simulate.dart --games 1000 --seed 12345 --players 5 --defend-rate 0.667 --restoration-win on --out sim_results/r1_players5.json` |
| `r1_players6.json` | R1 — baseline, 6 players, restoration ON | `dart run bin/simulate.dart --games 1000 --seed 12345 --players 6 --defend-rate 0.667 --restoration-win on --out sim_results/r1_players6.json` |
| `r2_players2.json` | R2 — basic mode, 2 players, restoration OFF | `dart run bin/simulate.dart --games 1000 --seed 12345 --players 2 --defend-rate 0.667 --restoration-win off --out sim_results/r2_players2.json` |
| `r2_players3.json` | R2 — basic mode, 3 players, restoration OFF | `dart run bin/simulate.dart --games 1000 --seed 12345 --players 3 --defend-rate 0.667 --restoration-win off --out sim_results/r2_players3.json` |
| `r2_players4.json` | R2 — basic mode, 4 players, restoration OFF | `dart run bin/simulate.dart --games 1000 --seed 12345 --players 4 --defend-rate 0.667 --restoration-win off --out sim_results/r2_players4.json` |
| `r2_players5.json` | R2 — basic mode, 5 players, restoration OFF | `dart run bin/simulate.dart --games 1000 --seed 12345 --players 5 --defend-rate 0.667 --restoration-win off --out sim_results/r2_players5.json` |
| `r2_players6.json` | R2 — basic mode, 6 players, restoration OFF | `dart run bin/simulate.dart --games 1000 --seed 12345 --players 6 --defend-rate 0.667 --restoration-win off --out sim_results/r2_players6.json` |
| `r3_defend0.0.json` | R3 — defense value (restoration ON), defend-rate 0.0 | `dart run bin/simulate.dart --games 1000 --seed 12345 --players 4 --defend-rate 0.0 --restoration-win on --out sim_results/r3_defend0.0.json` |
| `r3_defend0.33.json` | R3 — defense value, defend-rate 0.33 | `dart run bin/simulate.dart --games 1000 --seed 12345 --players 4 --defend-rate 0.33 --restoration-win on --out sim_results/r3_defend0.33.json` |
| `r3_defend0.667.json` | R3 — defense value, defend-rate 0.667 | `dart run bin/simulate.dart --games 1000 --seed 12345 --players 4 --defend-rate 0.667 --restoration-win on --out sim_results/r3_defend0.667.json` |
| `r3_defend1.0.json` | R3 — defense value, defend-rate 1.0 | `dart run bin/simulate.dart --games 1000 --seed 12345 --players 4 --defend-rate 1.0 --restoration-win on --out sim_results/r3_defend1.0.json` |
| `r5_players5_cap1.json` | R5 — reshuffle cap probe, `--max-reshuffles 1` | `dart run bin/simulate.dart --games 1000 --seed 12345 --players 5 --defend-rate 0.667 --restoration-win on --max-reshuffles 1 --out sim_results/r5_players5_cap1.json` |
| `r5_players5_capnone.json` | R5 — reshuffle cap probe, `--max-reshuffles none` | `dart run bin/simulate.dart --games 1000 --seed 12345 --players 5 --defend-rate 0.667 --restoration-win on --max-reshuffles none --out sim_results/r5_players5_capnone.json` |

### Notes on R1-R5 overlap

- **R4** (card power check) has no dedicated files — it pools the
  `aggregate.cardWinnerCorrelation` blocks from all five `r1_players*.json`
  files, exactly like Phase 2's E4 did for `e1_players*.json`. The pooled
  table is reproduced in `BALANCE_REPORT_2.md`.
- **`r5_players5_capnone.json`** is the same run as `r1_players5.json`
  (identical seed/players/defend-rate/restoration-win, `--max-reshuffles
  none` is the engine default) — generated fresh under its own filename so
  R5's file set is self-contained, but the two are byte-for-byte
  equivalent aside from filename.

## Files: delayed-Fasting patch (F1-F2)

| File | Experiment | Command |
|---|---|---|
| `f1_players2.json` | F1 — R1 re-run (delayed Fasting), 2 players | `dart run bin/simulate.dart --games 1000 --seed 12345 --players 2 --defend-rate 0.667 --restoration-win on --out sim_results/f1_players2.json` |
| `f1_players3.json` | F1 — R1 re-run, 3 players | `dart run bin/simulate.dart --games 1000 --seed 12345 --players 3 --defend-rate 0.667 --restoration-win on --out sim_results/f1_players3.json` |
| `f1_players4.json` | F1 — R1 re-run, 4 players | `dart run bin/simulate.dart --games 1000 --seed 12345 --players 4 --defend-rate 0.667 --restoration-win on --out sim_results/f1_players4.json` |
| `f2_defend0.33.json` | F2 — 2-player defend-rate sweep, 0.33 | `dart run bin/simulate.dart --games 1000 --seed 12345 --players 2 --defend-rate 0.33 --restoration-win on --out sim_results/f2_defend0.33.json` |
| `f2_defend0.667.json` | F2 — 2-player defend-rate sweep, 0.667 | `dart run bin/simulate.dart --games 1000 --seed 12345 --players 2 --defend-rate 0.667 --restoration-win on --out sim_results/f2_defend0.667.json` |
| `f2_defend1.0.json` | F2 — 2-player defend-rate sweep, 1.0 | `dart run bin/simulate.dart --games 1000 --seed 12345 --players 2 --defend-rate 1.0 --restoration-win on --out sim_results/f2_defend1.0.json` |

### Notes on F1-F2

- **`f2_defend0.667.json`** is the same run as `f1_players2.json`
  (identical seed/players/defend-rate/restoration-win) - generated fresh
  under its own filename so F2's file set is self-contained, but the two
  are byte-for-byte equivalent aside from filename.
- **F1 only covers players 2-4**, not 5-6 (unlike R1's full 2-6 sweep) -
  the task scoped F1 to "R1 re-run at players 2, 3, 4" specifically,
  since the key question was how much delayed Fasting alone moves the
  2-player rush, and 3-4 players give enough of a trend line without
  re-running the full 2-6 sweep.
- The bot harness has **no special-casing for Fasting's new timing** - it
  plays Fasting exactly as before (choosing a random legal target,
  currently restricted by the bot's own `_legalPlaysFor` to Lost pieces
  for any non-Renewal restore card) and lets the engine's own `_endTurn`
  logic handle when the heal actually lands. No harness changes were
  needed for this patch beyond the pre-existing `--restoration-win`/
  `--defend-rate`/`--players` flags from the prior phase.

## Files: Phase 2 (E1-E5)

| File | Experiment | Command |
|---|---|---|
| `e1_players2.json` | E1 — baseline, 2 players | `dart run bin/simulate.dart --games 1000 --seed 12345 --players 2 --defend-rate 0.667 --out sim_results/e1_players2.json` |
| `e1_players3.json` | E1 — baseline, 3 players | `dart run bin/simulate.dart --games 1000 --seed 12345 --players 3 --defend-rate 0.667 --out sim_results/e1_players3.json` |
| `e1_players4.json` | E1 — baseline, 4 players | `dart run bin/simulate.dart --games 1000 --seed 12345 --players 4 --defend-rate 0.667 --out sim_results/e1_players4.json` |
| `e1_players5.json` | E1 — baseline, 5 players | `dart run bin/simulate.dart --games 1000 --seed 12345 --players 5 --defend-rate 0.667 --out sim_results/e1_players5.json` |
| `e1_players6.json` | E1 — baseline, 6 players | `dart run bin/simulate.dart --games 1000 --seed 12345 --players 6 --defend-rate 0.667 --out sim_results/e1_players6.json` |
| `e3_defend0.0.json` | E3 — defense value, defend-rate 0.0 | `dart run bin/simulate.dart --games 1000 --seed 12345 --players 4 --defend-rate 0.0 --out sim_results/e3_defend0.0.json` |
| `e3_defend0.33.json` | E3 — defense value, defend-rate 0.33 | `dart run bin/simulate.dart --games 1000 --seed 12345 --players 4 --defend-rate 0.33 --out sim_results/e3_defend0.33.json` |
| `e3_defend0.667.json` | E3 — defense value, defend-rate 0.667 | `dart run bin/simulate.dart --games 1000 --seed 12345 --players 4 --defend-rate 0.667 --out sim_results/e3_defend0.667.json` |
| `e3_defend1.0.json` | E3 — defense value, defend-rate 1.0 | `dart run bin/simulate.dart --games 1000 --seed 12345 --players 4 --defend-rate 1.0 --out sim_results/e3_defend1.0.json` |
| `e5_players5.json` | E5 — deck economy, 5 players | identical to `e1_players5.json` (same config); copied under this name for discoverability |
| `e5_players6.json` | E5 — deck economy, 6 players | identical to `e1_players6.json` (same config); copied under this name for discoverability |

## Notes on experiment overlap

- **E2** (first-player advantage) has no dedicated files — it's an
  analysis of the seat win-rate data already present in the `e1_players*`
  files (`aggregate.seatWinRatesByPlayerCount`).
- **E4** (card power check) has no dedicated files either — it pools the
  `aggregate.cardWinnerCorrelation` blocks from all five `e1_players*.json`
  files. The pooled table is reproduced in `BALANCE_REPORT.md`.
- **E3's `defend0.667` point** is the same run as `e1_players4.json`
  (identical seed/players/defend-rate) — generated fresh as part of E3 for
  completeness of that experiment's file set, but the two are byte-for-byte
  equivalent aside from filename.
- **E5** reuses E1's 5- and 6-player runs verbatim (same seed, same
  defend-rate, same game count) since E1 already produced exactly the data
  E5 asks for (reshuffle counts, deck-exhaustion frequency) — no separate
  simulation run was needed.

## Reproducing any result

Every `.json` file's top-level `config` object records the exact
`--games`, `--seed`, `--players`, and `--defend-rate` used. Re-running
`bin/simulate.dart` with those same four values reproduces the identical
`games` array and `aggregate` block byte-for-byte, since the underlying
engine and bot RNG are fully seeded/deterministic.
