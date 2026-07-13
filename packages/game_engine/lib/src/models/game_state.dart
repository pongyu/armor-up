import 'card.dart';
import 'game_event.dart';
import 'pending_group_discard.dart';
import 'pending_interrupt.dart';
import 'player.dart';
import 'win_result.dart';

/// The complete, immutable state of one game. [applyAction] never mutates
/// an existing instance; it returns a new one via [copyWith].
///
/// Determinism: all randomness (shuffling, random-target selection) is
/// derived from [rngSeed] plus [rngDrawCount], which the engine increments
/// every time it consumes randomness. Replaying the same seed and action
/// sequence always reaches the same state.
final class GameState {
  final List<PlayerState> players;
  final int activePlayerIndex;
  final List<CardInstance> drawPile;
  final List<CardInstance> discardPile;

  final int rngSeed;
  final int rngDrawCount;

  /// Monotonically increasing counter used to mint unique
  /// [CardInstance.instanceId]s deterministically.
  final int nextInstanceId;

  final int turnNumber;

  final List<GameEvent> eventLog;

  /// Set once the game has ended; null while play continues.
  final WinResult? winner;

  /// Non-null while an attack awaits a defense response. See
  /// [PendingAttack] for the interrupt state machine this drives.
  final PendingInterrupt? pendingInterrupt;

  /// Non-null while a table-wide discard obligation (currently only from
  /// Wilderness Season) is outstanding. See [PendingGroupDiscard].
  final PendingGroupDiscard? pendingGroupDiscard;

  /// True once the active player has drawn for this turn. Guards against
  /// [DrawCard] being applied twice in one turn.
  final bool hasDrawnThisTurn;

  /// True once the active player has played their one card for this turn
  /// (attack, restore, or event - defense cards don't count, since they're
  /// played reactively during an interrupt, not as the turn's play step).
  /// Guards against playing more than one card per turn.
  final bool hasPlayedCardThisTurn;

  /// Game mode toggle, fixed for the whole game (set once at [newGame] and
  /// never changed afterward). True ("full mode") preserves restoration as
  /// a win condition; false ("basic mode", aimed at younger players) skips
  /// [_checkRestorationWin] entirely, leaving elimination and
  /// deck-exhaustion ranking as the only ways a game ends.
  final bool restorationWinEnabled;

  /// Rules-variant cap on how many times the discard pile may be
  /// reshuffled into a fresh draw pile before the deck is treated as
  /// exhausted (ends the game via the same ranking [_declareDeckExhaustedWinner]
  /// uses for a literal double-empty draw). Null (the default) preserves
  /// the original unlimited-reshuffle behavior. Fixed for the whole game,
  /// like [restorationWinEnabled].
  final int? maxReshuffles;

  const GameState({
    required this.players,
    required this.activePlayerIndex,
    required this.drawPile,
    required this.discardPile,
    required this.rngSeed,
    this.rngDrawCount = 0,
    this.nextInstanceId = 0,
    this.turnNumber = 1,
    this.eventLog = const [],
    this.winner,
    this.pendingInterrupt,
    this.pendingGroupDiscard,
    this.hasDrawnThisTurn = false,
    this.hasPlayedCardThisTurn = false,
    this.restorationWinEnabled = true,
    this.maxReshuffles,
  });

  PlayerState get activePlayer => players[activePlayerIndex];

  PlayerState playerById(String id) =>
      players.firstWhere((p) => p.id == id);

  int indexOfPlayer(String id) => players.indexWhere((p) => p.id == id);

  bool get isGameOver => winner != null;

  /// How many times the discard pile has been reshuffled into a fresh draw
  /// pile so far this game. Derived from [eventLog] (one [DeckReshuffled]
  /// per reshuffle) rather than a separate counter field, so it can never
  /// drift out of sync with the log itself. Used against [maxReshuffles].
  int get reshuffleCount => eventLog.whereType<DeckReshuffled>().length;

  GameState copyWith({
    List<PlayerState>? players,
    int? activePlayerIndex,
    List<CardInstance>? drawPile,
    List<CardInstance>? discardPile,
    int? rngSeed,
    int? rngDrawCount,
    int? nextInstanceId,
    int? turnNumber,
    List<GameEvent>? eventLog,
    WinResult? winner,
    bool clearWinner = false,
    PendingInterrupt? pendingInterrupt,
    bool clearPendingInterrupt = false,
    PendingGroupDiscard? pendingGroupDiscard,
    bool clearPendingGroupDiscard = false,
    bool? hasDrawnThisTurn,
    bool? hasPlayedCardThisTurn,
    bool? restorationWinEnabled,
    int? maxReshuffles,
    bool clearMaxReshuffles = false,
  }) =>
      GameState(
        players: players ?? this.players,
        activePlayerIndex: activePlayerIndex ?? this.activePlayerIndex,
        drawPile: drawPile ?? this.drawPile,
        discardPile: discardPile ?? this.discardPile,
        rngSeed: rngSeed ?? this.rngSeed,
        rngDrawCount: rngDrawCount ?? this.rngDrawCount,
        nextInstanceId: nextInstanceId ?? this.nextInstanceId,
        turnNumber: turnNumber ?? this.turnNumber,
        eventLog: eventLog ?? this.eventLog,
        winner: clearWinner ? null : (winner ?? this.winner),
        pendingInterrupt: clearPendingInterrupt
            ? null
            : (pendingInterrupt ?? this.pendingInterrupt),
        pendingGroupDiscard: clearPendingGroupDiscard
            ? null
            : (pendingGroupDiscard ?? this.pendingGroupDiscard),
        hasDrawnThisTurn: hasDrawnThisTurn ?? this.hasDrawnThisTurn,
        hasPlayedCardThisTurn: hasPlayedCardThisTurn ?? this.hasPlayedCardThisTurn,
        restorationWinEnabled: restorationWinEnabled ?? this.restorationWinEnabled,
        maxReshuffles: clearMaxReshuffles ? null : (maxReshuffles ?? this.maxReshuffles),
      );

  /// Returns a copy with [playerId]'s state replaced by the result of
  /// [update].
  GameState updatePlayer(
    String playerId,
    PlayerState Function(PlayerState) update,
  ) {
    final updated = [
      for (final p in players)
        if (p.id == playerId) update(p) else p,
    ];
    return copyWith(players: updated);
  }

  GameState appendEvent(GameEvent event) =>
      copyWith(eventLog: [...eventLog, event]);

  @override
  String toString() => 'GameState(turn $turnNumber, '
      'active=${activePlayer.id}, players=${players.length}, '
      'draw=${drawPile.length}, discard=${discardPile.length}, '
      'winner=$winner)';
}
