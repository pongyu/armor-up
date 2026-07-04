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
    TurnSkipped(:final playerId) => '${nameOf(playerId)} skipped their turn (fasting)',
    CardDrawn(:final playerId) => '${nameOf(playerId)} drew a card',
    CardDiscarded(:final playerId, :final cardDefId) =>
      '${nameOf(playerId)} discarded ${cardDefById(cardDefId).name}',
    CardStolen(:final thiefId, :final victimId, :final cardDefId) =>
      '${nameOf(thiefId)} stole ${cardDefById(cardDefId).name} from ${nameOf(victimId)}',
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
