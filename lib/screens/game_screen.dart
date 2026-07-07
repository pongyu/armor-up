import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:game_engine/game_engine.dart';

import '../state/game_controller.dart';
import '../state/game_providers.dart';
import '../state/turn_actor.dart';
import '../theme/armor_up_colors.dart';
import '../widgets/armor_widget.dart';
import '../widgets/card_widget.dart';
import '../widgets/event_log_widget.dart';
import 'pass_device_screen.dart';
import 'win_screen.dart';

part 'defense_prompt_view.dart';
part 'group_discard_prompt_view.dart';

/// Top-level router for an in-progress game: alternates between the
/// pass-the-phone screen and the active screen (game board or defense
/// prompt) whenever [currentActorId] changes, and shows the win screen
/// once the game ends.
class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  String? _lastAcknowledgedActorId;
  bool _showingPassScreen = true;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gameStateProvider);
    if (state == null) return const SizedBox.shrink();

    if (state.isGameOver) {
      return WinScreen(state: state);
    }

    final actorId = currentActorId(state);
    if (_lastAcknowledgedActorId != actorId) {
      _showingPassScreen = true;
    }

    if (_showingPassScreen) {
      final actorName = state.playerById(actorId).name;
      final reason = state.pendingGroupDiscard != null
          ? 'You need to discard a card.'
          : state.pendingInterrupt != null
              ? 'An attack needs your response.'
              : "It's your turn.";
      return PassDeviceScreen(
        nextPlayerName: actorName,
        reason: reason,
        onReady: () {
          setState(() {
            _showingPassScreen = false;
            _lastAcknowledgedActorId = actorId;
          });
        },
      );
    }

    if (state.pendingGroupDiscard != null) {
      return _GroupDiscardPromptView(actorId: actorId);
    }
    return state.pendingInterrupt != null
        ? _DefensePromptView(actorId: actorId)
        : _MainBoardView(actorId: actorId);
  }
}

class _MainBoardView extends ConsumerStatefulWidget {
  final String actorId;

  const _MainBoardView({required this.actorId});

  @override
  ConsumerState<_MainBoardView> createState() => _MainBoardViewState();
}

class _MainBoardViewState extends ConsumerState<_MainBoardView> {
  CardInstance? _selectedCard;
  String? _selectedTargetPlayerId;
  ArmorType? _selectedTargetArmor;
  bool _showEventLog = false;

  void _resetSelection() {
    setState(() {
      _selectedCard = null;
      _selectedTargetPlayerId = null;
      _selectedTargetArmor = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gameStateProvider)!;
    final controller = ref.read(gameControllerProvider.notifier);
    final me = state.playerById(widget.actorId);
    final def = _selectedCard == null ? null : cardDefFor(_selectedCard!);

    ref.listen(gameErrorProvider, (previous, next) {
      if (next != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(next)));
        controller.clearError();
      }
    });

    final canPlaySelection = state.hasDrawnThisTurn &&
        !state.hasPlayedCardThisTurn &&
        def != null &&
        _isSelectionComplete(def);

    return Scaffold(
      appBar: AppBar(
        title: Text("${me.name}'s turn - Turn ${state.turnNumber}"),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: _showEventLog ? 'Hide game log' : 'Show game log',
            isSelected: _showEventLog,
            onPressed: () => setState(() => _showEventLog = !_showEventLog),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 3,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  for (final player in state.players)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _PlayerArmorPanel(
                        player: player,
                        isSelf: player.id == widget.actorId,
                        selectable: def != null &&
                            _targetRuleNeedsArmor(def.targetRule) &&
                            (_targetRuleNeedsOwnPiece(def.targetRule)
                                ? player.id == widget.actorId
                                : player.id == _selectedTargetPlayerId),
                        selectedArmor: _selectedTargetArmor,
                        onSelectArmor: (armor) {
                          setState(() => _selectedTargetArmor = armor);
                        },
                        onSelectAsTarget: def != null &&
                                _targetRuleNeedsPlayer(def.targetRule) &&
                                player.id != widget.actorId &&
                                !player.isEliminated
                            ? () => setState(() => _selectedTargetPlayerId = player.id)
                            : null,
                        isSelectedTarget: player.id == _selectedTargetPlayerId,
                        isConditionSelectable: def == null
                            ? defaultIsConditionSelectable
                            : (condition) => _isConditionSelectable(def, condition),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            // The scrolling event log clutters the primary view, so it is
            // hidden unless toggled via the history button in the app bar.
            if (_showEventLog) ...[
              Expanded(
                flex: 2,
                child: EventLogWidget(state: state),
              ),
              const Divider(height: 1),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: state.hasDrawnThisTurn
                          ? null
                          : () => controller.dispatch(DrawCard(playerId: widget.actorId)),
                      icon: const Icon(Icons.style),
                      label: const Text('Draw'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: canPlaySelection
                          ? () {
                              controller.dispatch(
                                PlayCard(
                                  playerId: widget.actorId,
                                  cardInstanceId: _selectedCard!.instanceId,
                                  targetPlayerId: _selectedTargetPlayerId,
                                  targetArmor: _selectedTargetArmor,
                                ),
                              );
                              _resetSelection();
                            }
                          : null,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Play card'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: !state.hasDrawnThisTurn
                          ? null
                          : () => controller.dispatch(EndTurn(playerId: widget.actorId)),
                      icon: const Icon(Icons.check),
                      label: Text(me.hand.length > maxHandSize ? 'Discard first' : 'End turn'),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              // Card height + Discard button + vertical padding.
              height: CardWidget.cardHeight + 24 + 12,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (final card in me.hand)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      child: _HandCard(
                        card: card,
                        selected: _selectedCard?.instanceId == card.instanceId,
                        disabled: me.isFasting ||
                            state.hasPlayedCardThisTurn ||
                            cardDefFor(card).type == CardType.defense,
                        onTap: () {
                          setState(() {
                            if (_selectedCard?.instanceId == card.instanceId) {
                              _resetSelection();
                            } else {
                              _selectedCard = card;
                              _selectedTargetPlayerId = null;
                              _selectedTargetArmor = null;
                            }
                          });
                        },
                        onDiscard: state.hasDrawnThisTurn
                            ? () => controller.dispatch(
                                  DiscardCard(playerId: widget.actorId, cardInstanceId: card.instanceId),
                                )
                            : null,
                      ),
                    ),
                ],
              ),
            ),
            if (me.isFasting)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'You are fasting this turn: you may not play a card.',
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
              )
            else if (state.hasPlayedCardThisTurn)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  "You've already played a card this turn.",
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool _isSelectionComplete(CardDef def) {
    switch (def.targetRule) {
      case TargetRule.specificArmorOnPlayer:
      case TargetRule.singlePlayer:
        return _selectedTargetPlayerId != null;
      case TargetRule.anyPieceOnPlayer:
        return _selectedTargetPlayerId != null && _selectedTargetArmor != null;
      case TargetRule.ownArmorPiece:
        return _selectedTargetArmor != null;
      case TargetRule.allPlayers:
      case TargetRule.none:
        return true;
    }
  }

  bool _targetRuleNeedsPlayer(TargetRule rule) =>
      rule == TargetRule.specificArmorOnPlayer ||
      rule == TargetRule.anyPieceOnPlayer ||
      rule == TargetRule.singlePlayer;

  bool _targetRuleNeedsArmor(TargetRule rule) =>
      rule == TargetRule.anyPieceOnPlayer || rule == TargetRule.ownArmorPiece;

  bool _targetRuleNeedsOwnPiece(TargetRule rule) => rule == TargetRule.ownArmorPiece;

  bool _isConditionSelectable(CardDef def, ArmorCondition condition) {
    switch (def.effect) {
      case EffectPrimitive.restoreOneStep:
        return condition == ArmorCondition.weakened;
      case EffectPrimitive.restoreFullyFromLost:
        return condition == ArmorCondition.lost;
      case EffectPrimitive.skipNextTurnAndRestore:
        return true;
      default:
        return condition != ArmorCondition.lost;
    }
  }
}

class _HandCard extends StatelessWidget {
  final CardInstance card;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;
  final VoidCallback? onDiscard;

  const _HandCard({
    required this.card,
    required this.selected,
    required this.disabled,
    required this.onTap,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    final def = cardDefFor(card);
    return Column(
      children: [
        Opacity(
          opacity: disabled ? 0.5 : 1,
          child: CardWidget(
            def: def,
            selected: selected,
            onTap: disabled ? null : onTap,
          ),
        ),
        if (onDiscard != null)
          TextButton(
            onPressed: onDiscard,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(60, 24),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Discard', style: TextStyle(fontSize: 11)),
          ),
      ],
    );
  }
}

class _PlayerArmorPanel extends StatelessWidget {
  final PlayerState player;
  final bool isSelf;
  final bool selectable;
  final ArmorType? selectedArmor;
  final ValueChanged<ArmorType>? onSelectArmor;
  final VoidCallback? onSelectAsTarget;
  final bool isSelectedTarget;
  final bool Function(ArmorCondition condition) isConditionSelectable;

  const _PlayerArmorPanel({
    required this.player,
    required this.isSelf,
    required this.selectable,
    required this.selectedArmor,
    required this.onSelectArmor,
    required this.onSelectAsTarget,
    required this.isSelectedTarget,
    this.isConditionSelectable = defaultIsConditionSelectable,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: ArmorUpColors.cardBackground.withValues(alpha: 0.45),
        border: Border.all(
          color: isSelectedTarget
              ? ArmorUpColors.bannerAttack
              : ArmorUpColors.cardStroke.withValues(alpha: 0.35),
          width: isSelectedTarget ? 2.5 : 1,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: InkWell(
        onTap: onSelectAsTarget,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  isSelf ? '${player.name} (you)' : player.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: ArmorUpColors.cardStroke,
                  ),
                ),
                if (player.isEliminated) ...[
                  const SizedBox(width: 8),
                  const Chip(label: Text('Eliminated'), visualDensity: VisualDensity.compact),
                ],
                if (onSelectAsTarget != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    '(tap to target)',
                    style: TextStyle(
                      fontSize: 11,
                      color: ArmorUpColors.cardStroke.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            ArmorRow(
              player: player,
              selectable: selectable,
              selectedArmor: selectedArmor,
              onSelect: onSelectArmor,
              isConditionSelectable: isConditionSelectable,
            ),
          ],
        ),
      ),
    );
  }
}
