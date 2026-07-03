import 'card.dart';
import 'game_event.dart';
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

  /// True once the active player has drawn for this turn. Guards against
  /// [DrawCard] being applied twice in one turn.
  final bool hasDrawnThisTurn;

  /// True once the active player has played their one card for this turn
  /// (attack, restore, or event - defense cards don't count, since they're
  /// played reactively during an interrupt, not as the turn's play step).
  /// Guards against playing more than one card per turn.
  final bool hasPlayedCardThisTurn;

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
    this.hasDrawnThisTurn = false,
    this.hasPlayedCardThisTurn = false,
  });

  PlayerState get activePlayer => players[activePlayerIndex];

  PlayerState playerById(String id) =>
      players.firstWhere((p) => p.id == id);

  int indexOfPlayer(String id) => players.indexWhere((p) => p.id == id);

  bool get isGameOver => winner != null;

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
    bool? hasDrawnThisTurn,
    bool? hasPlayedCardThisTurn,
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
        hasDrawnThisTurn: hasDrawnThisTurn ?? this.hasDrawnThisTurn,
        hasPlayedCardThisTurn: hasPlayedCardThisTurn ?? this.hasPlayedCardThisTurn,
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
