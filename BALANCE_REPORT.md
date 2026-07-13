# Armor Up! — Balance Report (Phase 2)

> **Report index:** this is the first of four balance reports, in order:
> `BALANCE_REPORT.md` (Phase 2 baseline, this file) →
> [BALANCE_REPORT_2.md](BALANCE_REPORT_2.md) (restoration-win-threshold
> patch) → [BALANCE_REPORT_4.md](BALANCE_REPORT_4.md) (delayed-Fasting
> patch, **current baseline**). There is no `_3`. See
> `packages/game_engine/sim_results/README.md` for the full run index and
> exact reproduction commands behind every number in all four reports.

Generated from `packages/game_engine/bin/simulate.dart` against random-legal-move
bots. All runs used base seed `12345`; raw JSON is in
`packages/game_engine/sim_results/` (see that directory's `README.md` for the
exact command behind every file). These are observations only — no card
changes are proposed here; rebalancing is a design decision for the human.

**Bugs fixed before any of this data was collected** (see repo-root
`CHANGES.md`/commit history for the full diagnosis): a harness bug in
`simulate.dart` that crashed on the first double-play attempt or first
pending group discard, and a genuine engine bug in `engine.dart` where a
single resolution eliminating *every* remaining player at once (not just
down to one) left `winner` unset and later hung the turn-advance loop
forever. Both are fixed; every number below comes from a codebase where
those fixes are in place. **No prior simulation output existed to
invalidate** — every run before this phase crashed or hung before
completing, so there is no earlier "trusted" dataset these results
supersede.

---

## E1 — Baseline per player count

1000 games each, `defend-rate 0.667` (bots decline 1-in-3 even when holding
a defense card — the original hardcoded harness behavior).

| Players | Completed | Turns avg | p10 | p50 | p90 | Elimination wins | Restoration wins | Deck-exhausted wins |
|---|---|---|---|---|---|---|---|---|
| 2 | 1000/1000 | 89.3 | 7 | 83 | 189 | 659 (65.9%) | 341 (34.1%) | 0 |
| 3 | 1000/1000 | 101.5 | 10 | 97 | 215 | 552 (55.2%) | 448 (44.8%) | 0 |
| 4 | 999/1000 | 114.2 | 14 | 117 | 232 | 553 (55.4%) | 446 (44.6%) | 0 |
| 5 | 1000/1000 | 130.4 | 17 | 142 | 268 | 554 (55.4%) | 446 (44.6%) | 0 |
| 6 | 998/1000 | 146.1 | 21 | 169 | 286 | 580 (58.1%) | 418 (41.9%) | 0 |

**Observations:**
- Game length scales roughly linearly with player count (+~14 turns per
  additional player at the median), which is expected — more players means
  more turns per round.
- 2-player games are the outlier: elimination wins dominate (65.9% vs.
  ~55% at 3-6 players) and the p10 game length (7 turns) is dramatically
  shorter than at any other player count. A 7-turn game is fast enough to
  suggest some 2-player games end via an early lucky Goliath's Taunt or
  chain of unanswered attacks before either side can stabilize.
- `deckExhausted` never occurred in any of the 5000 E1 games. See E5 below.
- A small number of games hit the 500-turn cap without resolving (1/1000
  at 4 players, 2/1000 at 6 players) — rare but non-zero; see "possible
  concerns" below.

## E2 — First-player advantage

Seat 0's (the player who goes first) win rate vs. the chance expectation
of `1/N`, from the E1 data above:

| Players | Seat 0 wins | Seat 0 rate | Expected (1/N) | Deviation |
|---|---|---|---|---|
| 2 | 561/1000 | 56.1% | 50.0% | **+6.1pp** |
| 3 | 350/1000 | 35.0% | 33.3% | +1.7pp |
| 4 | 257/999 | 25.7% | 25.0% | +0.7pp |
| 5 | 207/1000 | 20.7% | 20.0% | +0.7pp |
| 6 | 190/998 | 19.0% | 16.7% | +2.4pp |

Full per-seat breakdowns (not just seat 0) are in each `e1_players*.json`
under `aggregate.seatWinRatesByPlayerCount`.

**Observation, not a conclusion:** per the task's own rough guide
("deviations beyond ~3pp at N=4 deserve attention"), only the 2-player
case (+6.1pp) clears a threshold worth a second look — and even there,
1000 games is a modest sample for a binary outcome (the 95% confidence
interval on a 56.1% observed rate over 1000 trials is roughly ±3.1pp,
so +6.1pp is on the edge of, but not comfortably beyond, sampling noise
alone). The 3- and 6-player deviations (+1.7pp, +2.4pp) are smaller and,
notably, don't show a consistent seat-0-always-wins-more pattern across
every player count in the full per-seat tables (e.g. at 4 players seat 1
actually edges out seat 0). This reads as plausibly-real-but-small at 2
players and likely noise elsewhere — worth a larger run (5000+ games) at
2 players specifically before treating it as a confirmed advantage.

## E3 — Defense value

`players=4`, 1000 games per defend-rate.

| Defend rate | Completed | Turns avg | Elimination wins | Restoration wins | Incomplete (hit cap) |
|---|---|---|---|---|---|
| 0.0 (never defend) | 1000/1000 | 95.7 | 762 (76.2%) | 238 (23.8%) | 0 |
| 0.33 | 1000/1000 | 104.3 | 616 (61.6%) | 384 (38.4%) | 0 |
| 0.667 (baseline) | 999/1000 | 114.2 | 553 (55.4%) | 446 (44.6%) | 1 |
| 1.0 (always defend) | 997/1000 | 124.1 | 541 (54.3%) | 456 (45.7%) | 3 |

**Observations:**
- Clean, monotonic relationship in the expected direction: more defending
  → longer games, fewer elimination wins, more restoration wins. This is
  a sane, non-broken relationship — defense cards are doing what they
  should (preventing damage, which shifts the game toward the
  "out-heal the damage" win condition instead of "knock everyone out").
- **Always-defending does measurably increase stalling**, but modestly:
  incomplete-game rate rises from 0/1000 (never defend) to 1/1000
  (baseline, 0.667) to 3/1000 (always defend) — a real but small increase,
  topping out at 0.3% of games hitting the 500-turn cap at maximum
  defense. Not dramatic, but the trend is clearly upward and worth
  watching if the actual defend rate among real players tends higher than
  0.667 (bots that always block whenever possible are a reasonable proxy
  for a cautious human player).
- `deckExhausted` remained 0 across every defend-rate. Even maximal
  stalling behavior didn't exhaust the deck in this sample — see E5.

## E4 — Card power check (pooled across E1's 5000 games, 2-6 players)

Winner-correlation ratio: how much more (or less) often the eventual
winner played this card, vs. what a player-count-weighted baseline
("no effect on winning" should trend toward each game's own `1/N`) would
predict. Ratio 1.0 = no correlation either way; >1.0 = winners played it
more; <1.0 = winners played it less.

| Card | Ratio | Actual | Expected | n (total plays) |
|---|---|---|---|---|
| **Armor Bearer** | **1.408** | 39.0% | 27.7% | 27,664 |
| **Fasting** | **1.401** | 38.8% | 27.7% | 27,529 |
| Renewal | 1.395 | 39.2% | 28.1% | 41,435 |
| **It Is Written** | **1.315** | 35.5% | 27.0% | 25,998 |
| **Goliath's Taunt** | **1.291** | 34.4% | 26.6% | 24,181 |
| Prayer | 1.267 | 34.3% | 27.1% | 52,460 |
| Road to Damascus | 1.245 | 33.4% | 26.8% | 21,690 |
| Fiery Dart | 1.217 | 32.4% | 26.6% | 71,588 |
| Fellowship | 1.149 | 31.1% | 27.1% | 25,779 |
| Wilderness Season | 1.135 | 31.4% | 27.7% | 19,456 |
| Deception | 1.134 | 29.9% | 26.4% | 34,339 |
| Discouragement | 1.123 | 29.6% | 26.4% | 34,248 |
| Jericho March | 1.122 | 31.2% | 27.8% | 10,323 |
| Confusion | 1.121 | 29.6% | 26.4% | 34,320 |
| Pride | 1.121 | 29.7% | 26.5% | 34,375 |
| Doubt | 1.118 | 29.5% | 26.4% | 34,208 |
| Strife | 1.093 | 28.9% | 26.5% | 34,249 |

**The four cards named in the task, specifically:**
- **Goliath's Taunt: ratio 1.291** — moderately winner-correlated, the
  4th-highest of the 17 cards. Consistent with it being the highest-impact
  single attack in the deck (a guaranteed double hit, Strong straight to
  Lost).
- **It Is Written: ratio 1.315** — the 4th-highest overall. Makes sense:
  it doesn't just block, it turns a hit back on the attacker, so playing
  it well plausibly correlates with a game state already favoring you
  (you have both the card and the position to punish an attacker).
- **Armor Bearer: ratio 1.408** — the single highest ratio of the whole
  deck. It only becomes playable when you already have a Lost piece, so
  by construction it's disproportionately played by players who took
  damage and recovered — i.e., exactly the "comeback" pattern the
  restoration win condition is built around.
- **Fasting: ratio 1.401** — essentially tied with Armor Bearer for
  highest. Same logic: it's a full-restore card, so its use correlates
  strongly with games that go the restoration-comeback route.

**Flag: no card has a ratio below 1.0.** Every single card in the 17-card
deck trends toward being played more by winners than the baseline
predicts, including cards with no plausible direct causal link to
winning (Strife, Doubt, Pride, Confusion — all attack cards with
`fixedTarget`, ratio 1.09-1.12). This is very unlikely to mean every card
independently helps you win; the much more likely explanation is a
**measurement artifact**: the winner of a game, by definition, survived
longer and therefore took more turns and played more cards overall than
players who got eliminated partway through. The per-player-count
weighting in this ratio corrects for player count but not for "the
winner simply had more turns to play any card at all" — so a uniform
floor around 1.1-1.2 for "generic" cards (Strife, Doubt, Confusion, Pride)
is probably that survivorship effect, not a real balance signal. The
cards that clear meaningfully above that floor (Armor Bearer, Fasting,
Renewal, It Is Written, Goliath's Taunt, at 1.29-1.41) stand out **above**
the apparent survivorship baseline, which is a more meaningful signal
than the raw ratio number alone.

## E5 — Deck economy after Phase 1 (eliminated-hand discard)

`players=5` and `players=6`, 1000 games each (reusing E1's data for these
two player counts, since it's the identical configuration E5 asks for).

| Players | Total reshuffles | Avg reshuffles/game | Deck-exhausted wins |
|---|---|---|---|
| 5 | 2283 | 2.28 | 0/1000 |
| 6 | 2753 | 2.76 | 0/998 |

**Observation:** reshuffling happens routinely (roughly 2-3 times per
game at these player counts — expected, since the standard 62-card deck
plus starting hands means the draw pile empties well before a typical
100-170-turn game ends), but **the deck never actually ran fully dry**
(both draw AND discard piles simultaneously empty) in any of the 1998
completed games across both player counts. Phase 1's change — feeding an
eliminated player's hand into the discard pile instead of leaving it
stranded — adds cards back into circulation exactly the way reshuffling
already recycles the discard pile, so it's consistent that this didn't
push the game toward exhaustion; if anything it very slightly *delays*
exhaustion by keeping more cards circulating. This establishes the
current baseline cleanly: **deck exhaustion is, in practice, a
non-event at 5-6 players with this bot policy** — the game reliably ends
by elimination or restoration long before the deck could run out.

---

## Possible concerns (observations only — no changes proposed)

1. **2-player seat-0 advantage (E2).** +6.1pp over 1000 games is on the
   edge of statistical noise but consistently the largest deviation
   observed, paired with 2-player games having by far the shortest tail
   (p10 = 7 turns). Worth a larger dedicated run (5000+ games, 2 players
   only) to confirm or rule out before treating it as real.
2. **Every card in E4 has ratio ≥ 1.0.** As discussed above, this is most
   likely a survivorship-bias artifact of the metric (winners get more
   turns to play cards, full stop) rather than 17 independently
   overpowered cards. If a cleaner signal is wanted later, a metric
   normalized by "plays per turn survived" rather than raw play count
   would separate the survivorship effect from genuine power.
3. **A small but non-zero incomplete-game rate exists** at higher player
   counts and higher defend-rates (up to 3/1000 at defend-rate 1.0,
   players=4). These games hit the 500-turn cap without a winner — not
   common, but worth knowing the 500-turn cap is occasionally actually
   reached rather than being a purely theoretical safety net.
4. **`deckExhausted` was 0/9000 across every experiment in this report.**
   Not necessarily a problem — it may be an intentionally rare tiebreak
   path — but it means that win condition currently has zero simulated
   coverage of its actual selection logic (most-Strong/fewest-Lost/turn-order
   tiebreak) in bulk play; the only place it's exercised is the engine's
   own unit tests.
5. **2-player games resolve unusually fast at the low end (p10 = 7
   turns).** Worth a human read of a few of the actual 7-turn game
   records (in `e1_players2.json`'s `games` array, filter for `turns`
   near 7) to sanity-check whether that's a legitimate "got unlucky
   early" outcome or a sign that 2-player openings are swingier than
   intended.

## Reproducing this report

Every number above traces back to a JSON file in
`packages/game_engine/sim_results/`, each of which records its own exact
`--games`/`--seed`/`--players`/`--defend-rate` in its `config` block. See
that directory's `README.md` for the exact command for every file.
