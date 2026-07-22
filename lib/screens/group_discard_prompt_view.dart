part of 'game_screen.dart';

/// Shown to whoever still owes a discard from a table-wide event (e.g.
/// Wilderness Season): lists only this player's hand. Tapping a card
/// SELECTS it (re-tappable to change your mind, matching the targeting
/// overlay's select-then-confirm pattern); only the CONFIRM DISCARD
/// button actually discards. No other controls are offered - drawing,
/// playing, and ending the turn are all invalid while a group discard
/// is pending.
class _GroupDiscardPromptView extends ConsumerStatefulWidget {
  final String actorId;

  const _GroupDiscardPromptView({required this.actorId});

  @override
  ConsumerState<_GroupDiscardPromptView> createState() =>
      _GroupDiscardPromptViewState();
}

class _GroupDiscardPromptViewState
    extends ConsumerState<_GroupDiscardPromptView> {
  String? _selectedInstanceId;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gameStateProvider)!;
    final controller = ref.read(activeGameControllerProvider);
    final player = state.playerById(widget.actorId);

    ref.listen(gameErrorProvider, (previous, next) {
      if (next != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(next)));
        controller.clearError();
      }
    });

    final selectedId = _selectedInstanceId;
    // Selection can go stale if the hand changes under us (e.g. a LAN
    // state resync) - only a card actually in hand is confirmable.
    final hasValidSelection =
        selectedId != null &&
        player.hand.any((c) => c.instanceId == selectedId);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Redesign header: DISCARD title + player subtitle in the
              // event purple, echoing the defense screen's layout.
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'DISCARD',
                      style: TextStyle(
                        fontSize: 19,
                        color: ArmorUpColors.fontColor,
                        shadows: ArmorUpColors.titleOutline,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      player.name.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: ArmorUpColors.bannerEvent,
                      ),
                    ),
                  ],
                ),
              ),
              // Event banner, same treatment as the defense screen's
              // attack banner but in the event color.
              Container(
                decoration: BoxDecoration(
                  color: ArmorUpColors.bannerEvent.withValues(alpha: 0.15),
                  border: Border.all(color: ArmorUpColors.bannerEvent),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: const Text(
                  'An event card requires every player to discard one card.',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    fontFamily: 'Roboto',
                    color: ArmorUpColors.fontColor,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'CHOOSE A CARD TO DISCARD:',
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 0.5,
                  color: ArmorUpColors.mutedLabel,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final scale =
                        (constraints.maxHeight / CardWidget.cardHeight)
                            .clamp(0.0, 1.0);
                    return ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final card in player.hand)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: SizedBox(
                              width: CardWidget.cardWidth * scale,
                              height: constraints.maxHeight,
                              child: FittedBox(
                                fit: BoxFit.contain,
                                child: CardWidget(
                                  def: cardDefFor(card),
                                  selected:
                                      card.instanceId == selectedId,
                                  onTap: () => setState(() {
                                    // Tap again to deselect.
                                    _selectedInstanceId =
                                        card.instanceId == selectedId
                                            ? null
                                            : card.instanceId;
                                  }),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              GoldPillButton(
                label: 'CONFIRM DISCARD',
                fontSize: 10.5,
                onPressed: hasValidSelection
                    ? () {
                        controller.dispatch(
                          DiscardCard(
                            playerId: widget.actorId,
                            cardInstanceId: selectedId,
                          ),
                        );
                        setState(() => _selectedInstanceId = null);
                      }
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
