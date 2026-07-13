// Runs N full games with random-legal-move bots and reports balance
// statistics: game length distribution, win-type distribution, seat win
// rates (first-player advantage), per-card play/winner-correlation counts,
// reshuffle counts, and elimination counts. Every run is fully
// reproducible from its printed config (game count, base seed, player
// count mode, defend rate).
//
// Usage:
//   dart run bin/simulate.dart [--games N] [--seed N] [--players N|cycle]
//     [--defend-rate 0.0-1.0] [--out path.json]
//
// Positional args are still accepted for backward compatibility with the
// original [gameCount] [seed] usage, but the flag forms take precedence
// and are the documented interface going forward.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:game_engine/game_engine.dart';

/// Hard cap so a pathological bot loop (e.g. everyone always fasting)
/// cannot hang the simulation.
const int _maxTurnsPerGame = 500;

/// Parsed run configuration - printed in full with every run (stdout and
/// JSON) so any result can be reproduced exactly from those numbers alone.
final class _RunConfig {
  final int gameCount;
  final int baseSeed;
  final int? fixedPlayerCount; // null means "cycle 2..6"
  final double defendRate;
  final String? outPath;
  final bool restorationWinEnabled;
  final int? maxReshuffles; // null means "none" (unlimited, current behavior)

  const _RunConfig({
    required this.gameCount,
    required this.baseSeed,
    required this.fixedPlayerCount,
    required this.defendRate,
    required this.outPath,
    required this.restorationWinEnabled,
    required this.maxReshuffles,
  });

  Map<String, dynamic> toJson() => {
        'games': gameCount,
        'seed': baseSeed,
        'players': fixedPlayerCount?.toString() ?? 'cycle',
        'defendRate': defendRate,
        'restorationWin': restorationWinEnabled ? 'on' : 'off',
        'maxReshuffles': maxReshuffles?.toString() ?? 'none',
      };
}

_RunConfig _parseArgs(List<String> args) {
  var gameCount = 200;
  var baseSeed = 12345;
  int? fixedPlayerCount;
  var defendRate = 0.667;
  String? outPath;
  var restorationWinEnabled = true;
  int? maxReshuffles;

  // Positional fallback: [gameCount] [seed], preserved for compatibility
  // with the original CLI. Any recognized `--flag` below overrides it.
  final positional = <String>[];

  var i = 0;
  while (i < args.length) {
    final arg = args[i];
    String valueFor(String flag) {
      if (i + 1 >= args.length) {
        throw ArgumentError('$flag requires a value');
      }
      i++;
      return args[i];
    }

    switch (arg) {
      case '--games':
        gameCount = int.parse(valueFor(arg));
      case '--seed':
        baseSeed = int.parse(valueFor(arg));
      case '--players':
        final value = valueFor(arg);
        fixedPlayerCount = value == 'cycle' ? null : int.parse(value);
      case '--defend-rate':
        defendRate = double.parse(valueFor(arg));
        if (defendRate < 0.0 || defendRate > 1.0) {
          throw ArgumentError('--defend-rate must be between 0.0 and 1.0');
        }
      case '--out':
        outPath = valueFor(arg);
      case '--restoration-win':
        final value = valueFor(arg);
        switch (value) {
          case 'on':
            restorationWinEnabled = true;
          case 'off':
            restorationWinEnabled = false;
          default:
            throw ArgumentError('--restoration-win must be "on" or "off", got "$value"');
        }
      case '--max-reshuffles':
        final value = valueFor(arg);
        maxReshuffles = value == 'none' ? null : int.parse(value);
      default:
        positional.add(arg);
    }
    i++;
  }

  if (positional.isNotEmpty) gameCount = int.parse(positional[0]);
  if (positional.length > 1) baseSeed = int.parse(positional[1]);

  return _RunConfig(
    gameCount: gameCount,
    baseSeed: baseSeed,
    fixedPlayerCount: fixedPlayerCount,
    defendRate: defendRate,
    outPath: outPath,
    restorationWinEnabled: restorationWinEnabled,
    maxReshuffles: maxReshuffles,
  );
}

/// Everything recorded about one completed game, before aggregation.
final class _GameRecord {
  final int playerCount;
  final int winnerSeatIndex;
  final WinType winType;
  final int turns;
  final int reshuffles;
  final int eliminatedCount;
  final Map<String, int> winnerCardPlays;
  final Map<String, int> nonWinnerCardPlays;

  const _GameRecord({
    required this.playerCount,
    required this.winnerSeatIndex,
    required this.winType,
    required this.turns,
    required this.reshuffles,
    required this.eliminatedCount,
    required this.winnerCardPlays,
    required this.nonWinnerCardPlays,
  });

  Map<String, dynamic> toJson() => {
        'playerCount': playerCount,
        'winnerSeatIndex': winnerSeatIndex,
        'winType': winType.name,
        'turns': turns,
        'reshuffles': reshuffles,
        'eliminatedCount': eliminatedCount,
      };
}

void main(List<String> args) {
  final config = _parseArgs(args);

  final records = <_GameRecord>[];
  var incompleteGames = 0;

  for (var i = 0; i < config.gameCount; i++) {
    final playerCount = config.fixedPlayerCount ?? (2 + (i % 5));
    final playerNames = List.generate(playerCount, (p) => 'Bot$p');
    final seed = config.baseSeed + i;

    final record = _runOneGame(
      playerNames: playerNames,
      seed: seed,
      defendRate: config.defendRate,
      restorationWinEnabled: config.restorationWinEnabled,
      maxReshuffles: config.maxReshuffles,
    );

    if (record == null) {
      incompleteGames++;
      continue;
    }
    records.add(record);
  }

  final report = _buildReport(config: config, records: records, incompleteGames: incompleteGames);
  _printSummary(report);

  if (config.outPath != null) {
    final file = File(config.outPath!);
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report.toJson()));
    print('');
    print('Wrote JSON report to ${config.outPath}');
  }
}

// ---------------------------------------------------------------------------
// Game loop
// ---------------------------------------------------------------------------

_GameRecord? _runOneGame({
  required List<String> playerNames,
  required int seed,
  required double defendRate,
  required bool restorationWinEnabled,
  required int? maxReshuffles,
}) {
  final random = Random(seed);
  var state = newGame(
    playerNames: playerNames,
    seed: seed,
    restorationWinEnabled: restorationWinEnabled,
    maxReshuffles: maxReshuffles,
  );

  final winnerCardPlays = <String, int>{};
  final nonWinnerCardPlays = <String, int>{};
  // Recorded per-player (keyed by the engine's own player id, e.g. 'p0' -
  // NOT playerNames, which is a separate display-name space newGame does
  // not tie to ids) as cards are played, then split into winner/non-winner
  // buckets once the game ends and the winner is known (the winner isn't
  // decided until the last action of the game).
  final cardPlaysByPlayer = <String, Map<String, int>>{
    for (final p in state.players) p.id: <String, int>{},
  };
  void recordPlay(String playerId, String cardDefId) {
    final byPlayer = cardPlaysByPlayer[playerId]!;
    byPlayer[cardDefId] = (byPlayer[cardDefId] ?? 0) + 1;
  }

  while (!state.isGameOver && state.turnNumber <= _maxTurnsPerGame) {
    if (state.pendingInterrupt != null) {
      state = _resolveInterruptRandomly(state, random, defendRate, recordPlay);
      continue;
    }

    if (state.pendingGroupDiscard != null) {
      state = _resolveGroupDiscardRandomly(state, random);
      continue;
    }

    final activeId = state.activePlayer.id;

    if (!state.hasDrawnThisTurn) {
      state = _apply(state, DrawCard(playerId: activeId));
      continue;
    }

    if (!state.activePlayer.isFasting && !state.hasPlayedCardThisTurn) {
      final played = _tryPlayRandomCard(state, random, recordPlay);
      if (played != null) {
        state = played;
        continue;
      }
    }

    if (state.activePlayer.hand.length > maxHandSize) {
      final discardId = state.activePlayer.hand[random.nextInt(state.activePlayer.hand.length)].instanceId;
      state = _apply(state, DiscardCard(playerId: activeId, cardInstanceId: discardId));
      continue;
    }

    state = _apply(state, EndTurn(playerId: activeId));
  }

  if (!state.isGameOver) return null;

  final winnerId = state.winner!.winnerId;
  for (final entry in cardPlaysByPlayer.entries) {
    final target = entry.key == winnerId ? winnerCardPlays : nonWinnerCardPlays;
    for (final playEntry in entry.value.entries) {
      target[playEntry.key] = (target[playEntry.key] ?? 0) + playEntry.value;
    }
  }

  return _GameRecord(
    playerCount: playerNames.length,
    winnerSeatIndex: state.indexOfPlayer(winnerId),
    winType: state.winner!.type,
    turns: state.turnNumber,
    reshuffles: state.eventLog.whereType<DeckReshuffled>().length,
    eliminatedCount: state.players.where((p) => p.isEliminated).length,
    winnerCardPlays: winnerCardPlays,
    nonWinnerCardPlays: nonWinnerCardPlays,
  );
}

GameState _apply(GameState state, GameAction action) {
  final result = applyAction(state, action);
  if (result is ActionFailure) {
    throw StateError('Bot produced an illegal action $action: ${result.reason}');
  }
  return (result as ActionSuccess).state;
}

/// Attempts to play one uniformly-random legal (card, target) combination
/// from the active player's hand. Returns null if no legal play exists
/// (forcing the caller to fall through to discard/end-turn).
GameState? _tryPlayRandomCard(
  GameState state,
  Random random,
  void Function(String playerId, String cardDefId) recordPlay,
) {
  final player = state.activePlayer;
  final candidates = <PlayCard>[];

  for (final card in player.hand) {
    final def = cardDefById(card.defId);
    if (def.type == CardType.defense) continue;
    candidates.addAll(_legalPlaysFor(state, player.id, card, def));
  }

  if (candidates.isEmpty) return null;

  final chosen = candidates[random.nextInt(candidates.length)];
  final defId = cardDefById(
    player.hand.firstWhere((c) => c.instanceId == chosen.cardInstanceId).defId,
  ).id;
  final result = _apply(state, chosen);
  recordPlay(player.id, defId);
  return result;
}

List<PlayCard> _legalPlaysFor(
  GameState state,
  String playerId,
  CardInstance card,
  CardDef def,
) {
  final others = state.players.where((p) => p.id != playerId && !p.isEliminated);

  switch (def.targetRule) {
    case TargetRule.specificArmorOnPlayer:
      return [
        for (final target in others)
          if (target.armorOf(def.fixedTarget!).condition != ArmorCondition.lost)
            PlayCard(playerId: playerId, cardInstanceId: card.instanceId, targetPlayerId: target.id),
      ];

    case TargetRule.anyPieceOnPlayer:
      return [
        for (final target in others)
          for (final piece in target.armor)
            if (piece.condition != ArmorCondition.lost)
              PlayCard(
                playerId: playerId,
                cardInstanceId: card.instanceId,
                targetPlayerId: target.id,
                targetArmor: piece.type,
              ),
      ];

    case TargetRule.singlePlayer:
      return [
        for (final target in others)
          if (target.hand.isNotEmpty)
            PlayCard(playerId: playerId, cardInstanceId: card.instanceId, targetPlayerId: target.id),
      ];

    case TargetRule.ownArmorPiece:
      final self = state.playerById(playerId);
      final requiredCondition =
          def.effect == EffectPrimitive.restoreOneStep ? ArmorCondition.weakened : ArmorCondition.lost;
      return [
        for (final piece in self.armor)
          if (piece.condition == requiredCondition)
            PlayCard(playerId: playerId, cardInstanceId: card.instanceId, targetArmor: piece.type),
      ];

    case TargetRule.allPlayers:
    case TargetRule.none:
      return [PlayCard(playerId: playerId, cardInstanceId: card.instanceId)];
  }
}

/// Resolves a pending defense interrupt with a random legal response:
/// the eligible responder (defender, or a helper during a Fellowship
/// request) declares a defense card with probability [defendRate] if they
/// hold one, or declines otherwise. Mirrors what a hotseat UI or network
/// client would let a human choose.
GameState _resolveInterruptRandomly(
  GameState state,
  Random random,
  double defendRate,
  void Function(String playerId, String cardDefId) recordPlay,
) {
  final pending = state.pendingInterrupt!;

  final String responderId;
  if (pending.fellowshipRequested) {
    final undecided = state.players.where(
      (p) => p.id != pending.defenderId && p.id != pending.attackerId && !p.isEliminated && !pending.helpersDeclined.contains(p.id),
    );
    responderId = undecided.isNotEmpty ? undecided.first.id : pending.defenderId;
  } else {
    responderId = pending.defenderId;
  }

  final responder = state.playerById(responderId);
  final defenseCards = responder.hand.where((c) => cardDefById(c.defId).type == CardType.defense).toList();

  if (defenseCards.isEmpty || random.nextDouble() >= defendRate) {
    return _apply(state, DeclineDefense(playerId: responderId));
  }

  final chosen = defenseCards[random.nextInt(defenseCards.length)];
  recordPlay(responderId, chosen.defId);
  return _apply(state, DeclareDefense(playerId: responderId, cardInstanceId: chosen.instanceId));
}

/// Resolves a pending table-wide group discard obligation (currently only
/// from Wilderness Season) by having one arbitrary still-owing player
/// discard one uniformly-random card from their own hand. Any owed player
/// may act regardless of whose turn it is - this just always picks the
/// first one in owedPlayerIds, which is sufficient since applyAction
/// itself has no preferred order among them and this only needs to drain
/// the obligation, not model a particular real player's choice of when to
/// act.
GameState _resolveGroupDiscardRandomly(GameState state, Random random) {
  final pending = state.pendingGroupDiscard!;
  final owedId = pending.owedPlayerIds.first;
  final owed = state.playerById(owedId);
  final discardId = owed.hand[random.nextInt(owed.hand.length)].instanceId;
  return _apply(state, DiscardCard(playerId: owedId, cardInstanceId: discardId));
}

// ---------------------------------------------------------------------------
// Aggregation
// ---------------------------------------------------------------------------

int _percentile(List<int> sorted, double p) {
  if (sorted.isEmpty) return 0;
  final index = ((sorted.length - 1) * p).round().clamp(0, sorted.length - 1);
  return sorted[index];
}

final class _SimulationReport {
  final _RunConfig config;
  final List<_GameRecord> records;
  final int incompleteGames;

  const _SimulationReport({
    required this.config,
    required this.records,
    required this.incompleteGames,
  });

  int get completed => records.length;

  List<int> get _sortedTurns => records.map((r) => r.turns).toList()..sort();

  double get avgTurns =>
      records.isEmpty ? 0.0 : records.map((r) => r.turns).reduce((a, b) => a + b) / records.length;

  int get turnsP10 => _percentile(_sortedTurns, 0.10);
  int get turnsP50 => _percentile(_sortedTurns, 0.50);
  int get turnsP90 => _percentile(_sortedTurns, 0.90);

  Map<WinType, int> get winsByType {
    final result = <WinType, int>{for (final t in WinType.values) t: 0};
    for (final r in records) {
      result[r.winType] = result[r.winType]! + 1;
    }
    return result;
  }

  /// Seat win rate: for each distinct player count present in [records],
  /// win counts and rates by starting seat index (0-based).
  Map<int, Map<int, _SeatStats>> get seatWinRatesByPlayerCount {
    final byPlayerCount = <int, List<_GameRecord>>{};
    for (final r in records) {
      byPlayerCount.putIfAbsent(r.playerCount, () => []).add(r);
    }
    final result = <int, Map<int, _SeatStats>>{};
    for (final entry in byPlayerCount.entries) {
      final playerCount = entry.key;
      final games = entry.value;
      final seatWins = <int, int>{for (var s = 0; s < playerCount; s++) s: 0};
      for (final r in games) {
        seatWins[r.winnerSeatIndex] = (seatWins[r.winnerSeatIndex] ?? 0) + 1;
      }
      result[playerCount] = {
        for (final seatEntry in seatWins.entries)
          seatEntry.key: _SeatStats(
            wins: seatEntry.value,
            totalGames: games.length,
            expectedRate: 1.0 / playerCount,
          ),
      };
    }
    return result;
  }

  Map<String, int> get totalPlayCounts {
    final result = <String, int>{for (final d in deckDefinitions) d.id: 0};
    for (final r in records) {
      for (final entry in r.winnerCardPlays.entries) {
        result[entry.key] = (result[entry.key] ?? 0) + entry.value;
      }
      for (final entry in r.nonWinnerCardPlays.entries) {
        result[entry.key] = (result[entry.key] ?? 0) + entry.value;
      }
    }
    return result;
  }

  /// Per-card "played by winner" rate vs. baseline expectation: a card
  /// with no effect on winning should trend toward 1/N (N = average
  /// player count weighted by how often that card was actually played,
  /// since games have varying player counts). Ratio > 1 means the card
  /// was played by the eventual winner more often than chance alone would
  /// predict; < 1 means less often.
  Map<String, _CardCorrelation> get cardWinnerCorrelation {
    final winnerCounts = <String, int>{for (final d in deckDefinitions) d.id: 0};
    final nonWinnerCounts = <String, int>{for (final d in deckDefinitions) d.id: 0};
    // Baseline expectation is weighted by 1/playerCount of the game each
    // play happened in, since a card played in a 2-player game has a much
    // higher baseline "played by the winner" chance than one played in a
    // 6-player game.
    final expectedWeightSum = <String, double>{for (final d in deckDefinitions) d.id: 0};
    final totalPlaysForExpectation = <String, int>{for (final d in deckDefinitions) d.id: 0};

    for (final r in records) {
      for (final entry in r.winnerCardPlays.entries) {
        winnerCounts[entry.key] = (winnerCounts[entry.key] ?? 0) + entry.value;
        expectedWeightSum[entry.key] =
            (expectedWeightSum[entry.key] ?? 0) + entry.value * (1.0 / r.playerCount);
        totalPlaysForExpectation[entry.key] = (totalPlaysForExpectation[entry.key] ?? 0) + entry.value;
      }
      for (final entry in r.nonWinnerCardPlays.entries) {
        nonWinnerCounts[entry.key] = (nonWinnerCounts[entry.key] ?? 0) + entry.value;
        expectedWeightSum[entry.key] =
            (expectedWeightSum[entry.key] ?? 0) + entry.value * (1.0 / r.playerCount);
        totalPlaysForExpectation[entry.key] = (totalPlaysForExpectation[entry.key] ?? 0) + entry.value;
      }
    }

    final result = <String, _CardCorrelation>{};
    for (final d in deckDefinitions) {
      final winnerPlays = winnerCounts[d.id] ?? 0;
      final nonWinnerPlays = nonWinnerCounts[d.id] ?? 0;
      final totalPlays = winnerPlays + nonWinnerPlays;
      final actualRate = totalPlays == 0 ? 0.0 : winnerPlays / totalPlays;
      final totalForExpectation = totalPlaysForExpectation[d.id] ?? 0;
      final expectedRate =
          totalForExpectation == 0 ? 0.0 : expectedWeightSum[d.id]! / totalForExpectation;
      final ratio = expectedRate == 0 ? 0.0 : actualRate / expectedRate;
      result[d.id] = _CardCorrelation(
        cardName: d.name,
        winnerPlays: winnerPlays,
        nonWinnerPlays: nonWinnerPlays,
        actualWinnerRate: actualRate,
        expectedWinnerRate: expectedRate,
        ratio: ratio,
      );
    }
    return result;
  }

  int get totalReshuffles => records.fold(0, (sum, r) => sum + r.reshuffles);

  double get avgReshuffles => records.isEmpty ? 0.0 : totalReshuffles / records.length;

  int get gamesWithAnyElimination => records.where((r) => r.eliminatedCount > 0).length;

  double get avgEliminatedPerGame =>
      records.isEmpty ? 0.0 : records.map((r) => r.eliminatedCount).reduce((a, b) => a + b) / records.length;

  Map<String, dynamic> toJson() => {
        'config': config.toJson(),
        'aggregate': {
          'gamesRequested': config.gameCount,
          'gamesCompleted': completed,
          'gamesIncomplete': incompleteGames,
          'turnCount': {
            'avg': avgTurns,
            'p10': turnsP10,
            'p50': turnsP50,
            'p90': turnsP90,
          },
          'winsByType': {for (final e in winsByType.entries) e.key.name: e.value},
          'seatWinRatesByPlayerCount': {
            for (final e in seatWinRatesByPlayerCount.entries)
              '${e.key}': {
                for (final seatEntry in e.value.entries)
                  '${seatEntry.key}': seatEntry.value.toJson(),
              },
          },
          'cardPlayCounts': totalPlayCounts,
          'cardWinnerCorrelation': {
            for (final e in cardWinnerCorrelation.entries) e.key: e.value.toJson(),
          },
          'reshuffles': {
            'total': totalReshuffles,
            'avgPerGame': avgReshuffles,
          },
          'eliminations': {
            'gamesWithAnyElimination': gamesWithAnyElimination,
            'avgEliminatedPerGame': avgEliminatedPerGame,
          },
        },
        'games': [for (final r in records) r.toJson()],
      };
}

final class _SeatStats {
  final int wins;
  final int totalGames;
  final double expectedRate;

  const _SeatStats({required this.wins, required this.totalGames, required this.expectedRate});

  double get actualRate => totalGames == 0 ? 0.0 : wins / totalGames;

  Map<String, dynamic> toJson() => {
        'wins': wins,
        'totalGames': totalGames,
        'actualRate': actualRate,
        'expectedRate': expectedRate,
      };
}

final class _CardCorrelation {
  final String cardName;
  final int winnerPlays;
  final int nonWinnerPlays;
  final double actualWinnerRate;
  final double expectedWinnerRate;
  final double ratio;

  const _CardCorrelation({
    required this.cardName,
    required this.winnerPlays,
    required this.nonWinnerPlays,
    required this.actualWinnerRate,
    required this.expectedWinnerRate,
    required this.ratio,
  });

  Map<String, dynamic> toJson() => {
        'cardName': cardName,
        'winnerPlays': winnerPlays,
        'nonWinnerPlays': nonWinnerPlays,
        'actualWinnerRate': actualWinnerRate,
        'expectedWinnerRate': expectedWinnerRate,
        'ratio': ratio,
      };
}

_SimulationReport _buildReport({
  required _RunConfig config,
  required List<_GameRecord> records,
  required int incompleteGames,
}) =>
    _SimulationReport(config: config, records: records, incompleteGames: incompleteGames);

// ---------------------------------------------------------------------------
// Stdout summary
// ---------------------------------------------------------------------------

void _printSummary(_SimulationReport report) {
  final c = report.config;
  print(
    '=== Armor Up! simulation: games=${c.gameCount} seed=${c.baseSeed} '
    'players=${c.fixedPlayerCount?.toString() ?? 'cycle'} defendRate=${c.defendRate} '
    'restorationWin=${c.restorationWinEnabled ? 'on' : 'off'} '
    'maxReshuffles=${c.maxReshuffles?.toString() ?? 'none'} ===',
  );
  print('${report.completed} completed, ${report.incompleteGames} hit the $_maxTurnsPerGame-turn cap');
  print('');
  print('Game length (turns): avg=${report.avgTurns.toStringAsFixed(1)} '
      'p10=${report.turnsP10} p50=${report.turnsP50} p90=${report.turnsP90}');
  print('');
  print('Win counts by type:');
  for (final type in WinType.values) {
    print('  ${type.name}: ${report.winsByType[type]}');
  }
  print('');
  print('Reshuffles: total=${report.totalReshuffles} avg/game=${report.avgReshuffles.toStringAsFixed(2)}');
  print(
    'Eliminations: games with >=1 elimination=${report.gamesWithAnyElimination}/${report.completed} '
    'avg eliminated/game=${report.avgEliminatedPerGame.toStringAsFixed(2)}',
  );
  print('');

  print('Seat win rates by player count (actual vs. expected 1/N):');
  final playerCounts = report.seatWinRatesByPlayerCount.keys.toList()..sort();
  for (final playerCount in playerCounts) {
    final seats = report.seatWinRatesByPlayerCount[playerCount]!;
    print('  $playerCount players:');
    final seatIndices = seats.keys.toList()..sort();
    for (final seat in seatIndices) {
      final stats = seats[seat]!;
      final deltaPct = (stats.actualRate - stats.expectedRate) * 100;
      final sign = deltaPct >= 0 ? '+' : '';
      print(
        '    seat $seat: ${stats.wins}/${stats.totalGames} '
        '(${(stats.actualRate * 100).toStringAsFixed(1)}%, expected '
        '${(stats.expectedRate * 100).toStringAsFixed(1)}%, $sign${deltaPct.toStringAsFixed(1)}pp)',
      );
    }
  }
  print('');

  print('Play counts per card:');
  final playCounts = report.totalPlayCounts;
  final sortedIds = playCounts.keys.toList()..sort((a, b) => playCounts[b]!.compareTo(playCounts[a]!));
  for (final id in sortedIds) {
    final def = cardDefById(id);
    print('  ${def.name.padRight(20)} ${playCounts[id]}');
  }
  print('');

  final correlations = report.cardWinnerCorrelation.values.toList()
    ..sort((a, b) => b.ratio.compareTo(a.ratio));
  final withPlays = correlations.where((c) => c.winnerPlays + c.nonWinnerPlays > 0).toList();

  print('Top 5 cards by winner-correlation ratio (played by eventual winner more than chance):');
  for (final c in withPlays.take(5)) {
    print(
      '  ${c.cardName.padRight(20)} ratio=${c.ratio.toStringAsFixed(2)} '
      '(actual=${(c.actualWinnerRate * 100).toStringAsFixed(1)}%, '
      'expected=${(c.expectedWinnerRate * 100).toStringAsFixed(1)}%, '
      'n=${c.winnerPlays + c.nonWinnerPlays})',
    );
  }
  print('');
  print('Bottom 5 cards by winner-correlation ratio (played by eventual winner less than chance):');
  for (final c in withPlays.reversed.take(5)) {
    print(
      '  ${c.cardName.padRight(20)} ratio=${c.ratio.toStringAsFixed(2)} '
      '(actual=${(c.actualWinnerRate * 100).toStringAsFixed(1)}%, '
      'expected=${(c.expectedWinnerRate * 100).toStringAsFixed(1)}%, '
      'n=${c.winnerPlays + c.nonWinnerPlays})',
    );
  }
}
