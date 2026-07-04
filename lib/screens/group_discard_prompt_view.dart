part of 'game_screen.dart';

/// Shown to whoever still owes a discard from a table-wide event (e.g.
/// Wilderness Season): lists only this player's hand, each card tappable
/// to discard it. No other controls are offered - drawing, playing, and
/// ending the turn are all invalid while a group discard is pending.
class _GroupDiscardPromptView extends ConsumerWidget {
  final String actorId;

  const _GroupDiscardPromptView({required this.actorId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameStateProvider)!;
    final controller = ref.read(gameControllerProvider.notifier);
    final player = state.playerById(actorId);

    ref.listen(gameErrorProvider, (previous, next) {
      if (next != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(next)));
        controller.clearError();
      }
    });

    return Scaffold(
      appBar: AppBar(title: Text('Discard - ${player.name}')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                color: Colors.purple.withValues(alpha: 0.08),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('An event card requires every player to discard one card.'),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Choose a card to discard:',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final card in player.hand)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: CardWidget(
                          def: cardDefFor(card),
                          onTap: () => controller.dispatch(
                            DiscardCard(playerId: actorId, cardInstanceId: card.instanceId),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
