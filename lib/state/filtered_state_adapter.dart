import 'package:game_engine/game_engine.dart';
import 'package:net/net.dart';

/// Sentinel [CardDef.id] used for placeholder cards standing in for
/// another player's hidden hand contents (see [reconstructFromFiltered]).
/// No real [CardDef] ever uses this id, so any code path that forgets the
/// hand it's reading might be hidden and tries to look up the card's
/// definition (e.g. via `cardDefById`) fails loudly with an error, rather
/// than silently rendering plausible-but-wrong data.
const hiddenCardDefId = '__hidden__';

/// Reconstructs a real [GameState] from a [FilteredGameState] so the
/// entire existing hotseat widget tree (GameScreen and everything under
/// it) can render LAN play unmodified - those widgets only ever know how
/// to read [GameState]/[PlayerState].
///
/// Other players' hidden hands become [handSize] placeholder
/// [CardInstance]s with defId [hiddenCardDefId]. This is safe because no
/// current widget reads hand *contents* for anyone but the viewer
/// themselves (only `hand.length` for everyone else) - if that ever
/// changes, a placeholder card fails loudly via a failed `cardDefById`
/// lookup instead of silently displaying wrong data. The viewer's own
/// hand, and every other field, is transmitted for real (see
/// `packages/net/lib/src/filtered_state.dart`), including
/// [PlayerState.wasEverDamaged], so [PlayerState.isFullyRestored] is safe
/// to read on the reconstructed state too.
///
/// [rngSeed]/[rngDrawCount]/[nextInstanceId] are meaningless here - the
/// client never calls `applyAction` on this state, only the host does.
GameState reconstructFromFiltered(FilteredGameState filtered) {
  return GameState(
    players: [
      for (final p in filtered.players)
        PlayerState(
          id: p.id,
          name: p.name,
          armor: p.armor,
          hand: p.hand ??
              List.generate(
                p.handSize,
                (i) => CardInstance(instanceId: '__hidden_${p.id}_$i', defId: hiddenCardDefId),
              ),
          isFasting: p.isFasting,
          fastingScheduled: p.fastingScheduled,
          wasEverDamaged: p.wasEverDamaged,
        ),
    ],
    activePlayerIndex: filtered.activePlayerIndex,
    drawPile: List.generate(
      filtered.drawPileCount,
      (i) => CardInstance(instanceId: '__hidden_draw_$i', defId: hiddenCardDefId),
    ),
    discardPile: filtered.discardPile,
    rngSeed: 0,
    rngDrawCount: 0,
    nextInstanceId: 0,
    turnNumber: filtered.turnNumber,
    eventLog: filtered.eventLog,
    winner: filtered.winner,
    pendingInterrupt: filtered.pendingInterrupt,
    pendingGroupDiscard: filtered.pendingGroupDiscard,
    hasDrawnThisTurn: filtered.hasDrawnThisTurn,
    hasPlayedCardThisTurn: filtered.hasPlayedCardThisTurn,
  );
}
