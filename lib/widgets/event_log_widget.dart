import 'package:flutter/material.dart';
import 'package:game_engine/game_engine.dart';

String describeEvent(GameEvent event, GameState state) {
  String nameOf(String playerId) => state.playerById(playerId).name;

  return switch (event) {
    CardPlayed(:final playerId, :final cardDefId, :final targetPlayerId) =>
      '${nameOf(playerId)} played ${cardDefById(cardDefId).name}'
          '${targetPlayerId != null ? ' on ${nameOf(targetPlayerId)}' : ''}',
    ArmorWeakened(:final playerId, :final armor) =>
      '${nameOf(playerId)}\'s ${armor.displayName} was weakened',
    ArmorLost(:final playerId, :final armor) =>
      '${nameOf(playerId)}\'s ${armor.displayName} was lost',
    ArmorRestored(:final playerId, :final armor, :final newCondition) =>
      '${nameOf(playerId)}\'s ${armor.displayName} restored to ${newCondition.name}',
    AttackBlocked(:final defenderId, :final byCardDefId, :final helperId) =>
      '${nameOf(defenderId)} blocked the attack with ${cardDefById(byCardDefId).name}'
          '${helperId != null ? ' (helped by ${nameOf(helperId)})' : ''}',
    AttackReflected(:final originalAttackerId, :final attackCardDefId) =>
      '${cardDefById(attackCardDefId).name} was reflected back at ${nameOf(originalAttackerId)}',
    PlayerShielded(:final playerId) =>
      '${nameOf(playerId)} is shielded for helping through Fellowship',
    AttackBlockedByShield(:final defenderId, :final attackCardDefId) =>
      '${nameOf(defenderId)}\'s shield blocked ${cardDefById(attackCardDefId).name}',
    TurnSkipped(:final playerId) => '${nameOf(playerId)} skipped their turn (fasting)',
    CardDrawn(:final playerId) => '${nameOf(playerId)} drew a card',
    CardDiscarded(:final playerId, :final cardDefId) =>
      '${nameOf(playerId)} discarded ${cardDefById(cardDefId).name}',
    // Redacted unconditionally, even on hotseat's single shared screen
    // where the engine holds the real CardStolen with cardDefId filled
    // in: the table sees THAT a card was stolen, never WHICH one, so the
    // thief's own knowledge of what they took is limited to seeing it in
    // their hand during their own turn (protected by the existing
    // pass-device gating), not to this log. A LAN client that isn't the
    // thief never even receives more than this - see
    // filterStateForPlayer's per-viewer event redaction - so this
    // renders identically for both transports.
    CardStolen(:final thiefId, :final victimId) ||
    CardStolenRedacted(:final thiefId, :final victimId) =>
      '${nameOf(thiefId)} stole a card from ${nameOf(victimId)}',
    DefenseTimedOut(:final playerId) => '${nameOf(playerId)} ran out of time to respond',
    PlayerEliminated(:final playerId) => '${nameOf(playerId)} was eliminated',
    // Plain hyphen, not an em-dash: EarlyGameBoy (the app's pixel font,
    // see card_widget.dart's describeEffect comment) has already shown
    // gaps for less common glyphs like '>' and '(' - not worth risking
    // for the highest-urgency announcement in the log.
    RestorationImminent(:final playerId) =>
      '${nameOf(playerId).toUpperCase()} STANDS FULLY ARMORED - STOP THEM BEFORE THEIR NEXT TURN!',
    DeckReshuffled() => 'The discard pile was reshuffled into the draw pile',
    GameEnded(:final winnerId, :final winType) =>
      '${nameOf(winnerId)} wins by ${switch (winType) {
        WinType.elimination => 'elimination',
        WinType.restoration => 'full restoration',
        WinType.deckExhausted => 'closest to restoration when the deck ran out',
      }}!',
  };
}

/// A simple scrolling text log of recent game events, most recent last.
class EventLogWidget extends StatelessWidget {
  final GameState state;
  final int maxEntries;

  const EventLogWidget({super.key, required this.state, this.maxEntries = 30});

  @override
  Widget build(BuildContext context) {
    final events = state.eventLog.length > maxEntries
        ? state.eventLog.sublist(state.eventLog.length - maxEntries)
        : state.eventLog;

    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: events.length,
      itemBuilder: (context, index) {
        final event = events[events.length - 1 - index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            describeEvent(event, state),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        );
      },
    );
  }
}
