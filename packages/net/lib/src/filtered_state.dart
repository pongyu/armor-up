import 'package:game_engine/game_engine.dart';

import 'state_codec.dart';

/// Everything a single connected client is allowed to know about the game:
/// their own hand in full, every player's public info (armor, hand *size*
/// only, name), and all table-wide public state (piles, event log, turn,
/// pending interrupts). Deliberately a separate type from [GameState] -
/// there is no field here that could hold another player's [PlayerState]
/// or hand, so leaking one is a compile error, not a runtime discipline
/// problem.
///
/// Built server-side only, via [filterStateForPlayer]. Never constructed
/// from client input.
final class FilteredGameState {
  final String viewerId;
  final List<PublicPlayerView> players;
  final int activePlayerIndex;
  final int drawPileCount;
  final List<CardInstance> discardPile;
  final int turnNumber;
  final List<GameEvent> eventLog;
  final WinResult? winner;
  final PendingInterrupt? pendingInterrupt;
  final PendingGroupDiscard? pendingGroupDiscard;
  final bool hasDrawnThisTurn;
  final bool hasPlayedCardThisTurn;

  const FilteredGameState({
    required this.viewerId,
    required this.players,
    required this.activePlayerIndex,
    required this.drawPileCount,
    required this.discardPile,
    required this.turnNumber,
    required this.eventLog,
    this.winner,
    this.pendingInterrupt,
    this.pendingGroupDiscard,
    required this.hasDrawnThisTurn,
    required this.hasPlayedCardThisTurn,
  });

  Map<String, dynamic> toJson() => {
        'viewerId': viewerId,
        'players': players.map((p) => p.toJson()).toList(),
        'activePlayerIndex': activePlayerIndex,
        'drawPileCount': drawPileCount,
        'discardPile': discardPile.map((c) => c.toJson()).toList(),
        'turnNumber': turnNumber,
        'eventLog': eventLog.map((e) => e.toJson()).toList(),
        if (winner != null) 'winner': winner!.toJson(),
        if (pendingInterrupt != null)
          'pendingInterrupt': pendingInterrupt!.toJson(),
        if (pendingGroupDiscard != null)
          'pendingGroupDiscard': pendingGroupDiscard!.toJson(),
        'hasDrawnThisTurn': hasDrawnThisTurn,
        'hasPlayedCardThisTurn': hasPlayedCardThisTurn,
      };

  static FilteredGameState fromJson(Map<String, dynamic> json) =>
      FilteredGameState(
        viewerId: json['viewerId'] as String,
        players: (json['players'] as List)
            .map((p) => PublicPlayerView.fromJson(p as Map<String, dynamic>))
            .toList(),
        activePlayerIndex: json['activePlayerIndex'] as int,
        drawPileCount: json['drawPileCount'] as int,
        discardPile: (json['discardPile'] as List)
            .map((c) => CardInstanceJson.fromJson(c as Map<String, dynamic>))
            .toList(),
        turnNumber: json['turnNumber'] as int,
        eventLog: (json['eventLog'] as List)
            .map((e) => gameEventFromJson(e as Map<String, dynamic>))
            .toList(),
        winner: json['winner'] == null
            ? null
            : WinResultJson.fromJson(json['winner'] as Map<String, dynamic>),
        pendingInterrupt: json['pendingInterrupt'] == null
            ? null
            : PendingAttackJson.fromJson(
                json['pendingInterrupt'] as Map<String, dynamic>),
        pendingGroupDiscard: json['pendingGroupDiscard'] == null
            ? null
            : PendingGroupDiscardJson.fromJson(
                json['pendingGroupDiscard'] as Map<String, dynamic>),
        hasDrawnThisTurn: json['hasDrawnThisTurn'] as bool,
        hasPlayedCardThisTurn: json['hasPlayedCardThisTurn'] as bool,
      );
}

/// One player's view as seen by someone else: name, armor (always public),
/// and hand size, but never hand contents unless [hand] is populated for
/// the viewer themselves (see [PublicPlayerView.self]).
final class PublicPlayerView {
  final String id;
  final String name;
  final List<ArmorPiece> armor;
  final int handSize;
  final bool isFasting;
  final bool fastingScheduled;

  /// Mirrors [PlayerState.wasEverDamaged]. Public info (armor condition is
  /// already visible in [armor]), transmitted so a client can safely
  /// recompute [PlayerState.isFullyRestored] on a reconstructed state
  /// without a hidden gap in the wire format.
  final bool wasEverDamaged;

  /// The viewer's own full hand. Null for every player other than the
  /// viewer - this is the one field [filterStateForPlayer] populates
  /// conditionally, and it is the only path by which hand *contents* ever
  /// leave the host.
  final List<CardInstance>? hand;

  const PublicPlayerView({
    required this.id,
    required this.name,
    required this.armor,
    required this.handSize,
    required this.isFasting,
    required this.fastingScheduled,
    required this.wasEverDamaged,
    this.hand,
  });

  bool get isEliminated =>
      armor.every((piece) => piece.condition == ArmorCondition.lost);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'armor': armor.map((a) => a.toJson()).toList(),
        'handSize': handSize,
        'isFasting': isFasting,
        'fastingScheduled': fastingScheduled,
        'wasEverDamaged': wasEverDamaged,
        if (hand != null) 'hand': hand!.map((c) => c.toJson()).toList(),
      };

  static PublicPlayerView fromJson(Map<String, dynamic> json) =>
      PublicPlayerView(
        id: json['id'] as String,
        name: json['name'] as String,
        armor: (json['armor'] as List)
            .map((a) => ArmorPieceJson.fromJson(a as Map<String, dynamic>))
            .toList(),
        handSize: json['handSize'] as int,
        isFasting: json['isFasting'] as bool,
        fastingScheduled: json['fastingScheduled'] as bool,
        wasEverDamaged: json['wasEverDamaged'] as bool,
        hand: json['hand'] == null
            ? null
            : (json['hand'] as List)
                .map(
                    (c) => CardInstanceJson.fromJson(c as Map<String, dynamic>))
                .toList(),
      );
}

/// Builds the view of [state] that [viewerId] is allowed to see. This is
/// the single choke point for hand redaction: call it once per connected
/// client, right before sending, and never send a raw [GameState] (or a
/// [PlayerState] belonging to someone else) over the wire.
FilteredGameState filterStateForPlayer(GameState state, String viewerId) {
  return FilteredGameState(
    viewerId: viewerId,
    players: [
      for (final p in state.players)
        PublicPlayerView(
          id: p.id,
          name: p.name,
          armor: p.armor,
          handSize: p.hand.length,
          isFasting: p.isFasting,
          fastingScheduled: p.fastingScheduled,
          wasEverDamaged: p.wasEverDamaged,
          hand: p.id == viewerId ? p.hand : null,
        ),
    ],
    activePlayerIndex: state.activePlayerIndex,
    drawPileCount: state.drawPile.length,
    discardPile: state.discardPile,
    turnNumber: state.turnNumber,
    eventLog: state.eventLog,
    winner: state.winner,
    pendingInterrupt: state.pendingInterrupt,
    pendingGroupDiscard: state.pendingGroupDiscard,
    hasDrawnThisTurn: state.hasDrawnThisTurn,
    hasPlayedCardThisTurn: state.hasPlayedCardThisTurn,
  );
}
