part of 'game_screen.dart';

/// Shown to whoever must respond to the current [PendingAttack]: the
/// defender, or (while a Fellowship request is open) the next
/// undecided helper. Offers their defense cards plus a Decline option.
class _DefensePromptView extends ConsumerWidget {
  final String actorId;

  const _DefensePromptView({required this.actorId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameStateProvider)!;
    final controller = ref.read(gameControllerProvider.notifier);
    final pending = state.pendingInterrupt!;
    final responder = state.playerById(actorId);
    final isHelper = actorId != pending.defenderId;

    ref.listen(gameErrorProvider, (previous, next) {
      if (next != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(next)));
        controller.clearError();
      }
    });

    final hasEligibleHelper = state.players.any(
      (p) => p.id != pending.attackerId && p.id != pending.defenderId && !p.isEliminated,
    );

    // Fellowship asks the rest of the table for help; with no one else
    // left to ask (2-player games, or everyone else eliminated), offering
    // it would just be a dead end - it gets discarded for nothing since
    // there's no one to decline or help. Hide it in that case so the
    // defender only sees choices that can actually do something.
    final defenseCards = responder.hand
        .where((c) => cardDefFor(c).type == CardType.defense)
        .where((c) => hasEligibleHelper || c.defId != 'fellowship')
        .toList();
    final attacker = state.playerById(pending.attackerId);
    final defender = state.playerById(pending.defenderId);

    return Scaffold(
      appBar: AppBar(title: Text('Defense - ${responder.name}')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                color: Colors.red.withValues(alpha: 0.08),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    isHelper
                        ? '${attacker.name} attacked ${defender.name}\'s '
                            '${pending.targetArmor.displayName} with '
                            '${cardDefById(pending.attackCardDefId).name}.\n'
                            '${defender.name} is asking for Fellowship help.'
                        : '${attacker.name} attacked your ${pending.targetArmor.displayName} '
                            'with ${cardDefById(pending.attackCardDefId).name}'
                            '${pending.isDoubleHit ? ' (double hit!)' : ''}.',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                defenseCards.isEmpty
                    ? 'You have no defense cards.'
                    : 'Choose a defense card to play, or decline:',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final card in defenseCards)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: CardWidget(
                          def: cardDefFor(card),
                          onTap: () => controller.dispatch(
                            DeclareDefense(playerId: actorId, cardInstanceId: card.instanceId),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => controller.dispatch(DeclineDefense(playerId: actorId)),
                child: Text(isHelper ? 'Decline to help' : 'Take the hit'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
