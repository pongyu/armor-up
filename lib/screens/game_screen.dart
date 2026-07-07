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
import '../widgets/player_display.dart';
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
        toolbarHeight: 40,
        title: Text(
          "${me.name}'s turn - Turn ${state.turnNumber}",
          style: const TextStyle(fontSize: 15),
        ),
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              children: [
                Expanded(
                  child: _showEventLog
                      ? Row(
                          children: [
                            Expanded(child: _buildPanels(state, me, def)),
                            const VerticalDivider(width: 1),
                            Expanded(
                              flex: 2,
                              child: EventLogWidget(state: state),
                            ),
                          ],
                        )
                      : _buildPanels(state, me, def),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: state.hasDrawnThisTurn
                              ? null
                              : () =>
                                  controller.dispatch(DrawCard(playerId: widget.actorId)),
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
                              : () =>
                                  controller.dispatch(EndTurn(playerId: widget.actorId)),
                          icon: const Icon(Icons.check),
                          label: Text(
                              me.hand.length > maxHandSize ? 'Discard first' : 'End turn'),
                        ),
                      ),
                    ],
                  ),
                ),
                Builder(builder: (context) {
                  // On short (landscape phone) heights the fixed card size
                  // would otherwise crowd out the panels above it - shrink
                  // each card's real footprint (FittedBox around a bounded
                  // CardWidget, not the scrollable list itself) so the
                  // panels - the primary game-state view - always keep
                  // most of the vertical space, with no overflow and
                  // correctly mapped tap coordinates.
                  const naturalHandHeight = CardWidget.cardHeight + 24 + 12;
                  final availableForHand = constraints.maxHeight * 0.32;
                  final scale =
                      (availableForHand / naturalHandHeight).clamp(0.55, 1.0);
                  final handRowHeight = naturalHandHeight * scale;

                  return SizedBox(
                    height: handRowHeight,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            children: [
                              for (final card in me.hand)
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                  child: SizedBox(
                                    width: (CardWidget.cardWidth) * scale,
                                    height: handRowHeight,
                                    child: FittedBox(
                                      fit: BoxFit.contain,
                                      child: SizedBox(
                                        width: CardWidget.cardWidth,
                                        height: naturalHandHeight,
                                        child: _HandCard(
                                          card: card,
                                          selected: _selectedCard?.instanceId ==
                                              card.instanceId,
                                          disabled: me.isFasting ||
                                              state.hasPlayedCardThisTurn ||
                                              cardDefFor(card).type == CardType.defense,
                                          onTap: () {
                                            setState(() {
                                              if (_selectedCard?.instanceId ==
                                                  card.instanceId) {
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
                                                    DiscardCard(
                                                        playerId: widget.actorId,
                                                        cardInstanceId: card.instanceId),
                                                  )
                                              : null,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: _PileCountersColumn(state: state),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildPanels(
    GameState state,
    PlayerState me,
    CardDef? def,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 190,
          child: _ActivePlayerPortraitPanel(player: me, state: state),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _PlayerListPanel(
            actorId: widget.actorId,
            players: state.players,
            def: def,
            selectedTargetPlayerId: _selectedTargetPlayerId,
            onSelectTarget: (playerId) =>
                setState(() => _selectedTargetPlayerId = playerId),
            targetRuleNeedsPlayer: _targetRuleNeedsPlayer,
            selectedTargetArmor: _selectedTargetArmor,
            onSelectArmor: (armor) => setState(() => _selectedTargetArmor = armor),
            isConditionSelectable: def == null
                ? defaultIsConditionSelectable
                : (condition) => _isConditionSelectable(def, condition),
          ),
        ),
        const VerticalDivider(width: 1),
        SizedBox(
          width: 280,
          child: _MyArmorGridPanel(
            player: me,
            selectable: def != null &&
                _targetRuleNeedsArmor(def.targetRule) &&
                _targetRuleNeedsOwnPiece(def.targetRule),
            selectedArmor: _selectedTargetArmor,
            onSelectArmor: (armor) => setState(() => _selectedTargetArmor = armor),
            isConditionSelectable: def == null
                ? defaultIsConditionSelectable
                : (condition) => _isConditionSelectable(def, condition),
          ),
        ),
      ],
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

/// Left panel: the active player's portrait, name, and a turn-status line.
/// This is the single place turn/fasting/played-card status is shown - it
/// used to be a footer message repeated under the hand row.
class _ActivePlayerPortraitPanel extends StatelessWidget {
  final PlayerState player;
  final GameState state;

  const _ActivePlayerPortraitPanel({required this.player, required this.state});

  String get _statusLine {
    if (player.isFasting) return 'Fasting this turn';
    if (state.hasPlayedCardThisTurn) return 'Already played a card';
    if (!state.hasDrawnThisTurn) return 'Draw to begin your turn';
    return 'Choose a card to play';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            player.name,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: ArmorUpColors.cardStroke,
            ),
            textAlign: TextAlign.center,
          ),
          Text(
            '(active)',
            style: TextStyle(
              fontSize: 11,
              color: ArmorUpColors.cardStroke.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 10),
          PlayerPortrait(playerId: player.id, size: 76),
          const SizedBox(height: 10),
          Text(
            'Status: $_statusLine',
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: ArmorUpColors.cardStroke.withValues(alpha: 0.75),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Center panel: a glanceable, scrollable list of every player. The active
/// player's row is minimal (name only) since their armor is already shown
/// in full detail in the right-hand grid - repeating it here would show the
/// same data twice. Other players get a compact armor-badge row and remain
/// tap-to-target, unchanged from the previous per-player panel.
class _PlayerListPanel extends StatelessWidget {
  final String actorId;
  final List<PlayerState> players;
  final CardDef? def;
  final String? selectedTargetPlayerId;
  final ValueChanged<String> onSelectTarget;
  final bool Function(TargetRule rule) targetRuleNeedsPlayer;
  final ArmorType? selectedTargetArmor;
  final ValueChanged<ArmorType> onSelectArmor;
  final bool Function(ArmorCondition condition) isConditionSelectable;

  const _PlayerListPanel({
    required this.actorId,
    required this.players,
    required this.def,
    required this.selectedTargetPlayerId,
    required this.onSelectTarget,
    required this.targetRuleNeedsPlayer,
    required this.selectedTargetArmor,
    required this.onSelectArmor,
    required this.isConditionSelectable,
  });

  @override
  Widget build(BuildContext context) {
    // Cards like Fiery Dart or Goliath's Taunt (anyPieceOnPlayer) need a
    // specific armor piece picked on the targeted opponent, not just the
    // player themselves - so once that opponent is selected, their compact
    // armor row becomes the picker (their armor grid isn't shown anywhere
    // else, unlike the active player's).
    final needsArmorPick = def != null && def!.targetRule == TargetRule.anyPieceOnPlayer;

    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        for (final player in players)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _PlayerListRow(
              player: player,
              isSelf: player.id == actorId,
              isSelectedTarget: player.id == selectedTargetPlayerId,
              onSelectAsTarget: def != null &&
                      targetRuleNeedsPlayer(def!.targetRule) &&
                      player.id != actorId &&
                      !player.isEliminated
                  ? () => onSelectTarget(player.id)
                  : null,
              armorSelectable: needsArmorPick && player.id == selectedTargetPlayerId,
              selectedArmor: selectedTargetArmor,
              onSelectArmor: onSelectArmor,
              isConditionSelectable: isConditionSelectable,
            ),
          ),
      ],
    );
  }
}

class _PlayerListRow extends StatelessWidget {
  final PlayerState player;
  final bool isSelf;
  final bool isSelectedTarget;
  final VoidCallback? onSelectAsTarget;
  final bool armorSelectable;
  final ArmorType? selectedArmor;
  final ValueChanged<ArmorType> onSelectArmor;
  final bool Function(ArmorCondition condition) isConditionSelectable;

  const _PlayerListRow({
    required this.player,
    required this.isSelf,
    required this.isSelectedTarget,
    required this.onSelectAsTarget,
    required this.armorSelectable,
    required this.selectedArmor,
    required this.onSelectArmor,
    required this.isConditionSelectable,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isSelf
            ? ArmorUpColors.cardBackground.withValues(alpha: 0.2)
            : ArmorUpColors.cardBackground.withValues(alpha: 0.45),
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
        child: Row(
          children: [
            Expanded(
              child: Text(
                isSelf ? '${player.name} (you)' : player.name,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: ArmorUpColors.cardStroke.withValues(alpha: isSelf ? 0.55 : 1),
                ),
              ),
            ),
            if (player.isEliminated)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Chip(label: Text('Eliminated'), visualDensity: VisualDensity.compact),
              )
            else if (!isSelf)
              ArmorRow(
                player: player,
                compact: true,
                selectable: armorSelectable,
                selectedArmor: selectedArmor,
                onSelect: armorSelectable ? onSelectArmor : null,
                isConditionSelectable: isConditionSelectable,
              )
            else
              Text(
                'see your armor grid',
                style: TextStyle(
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                  color: ArmorUpColors.cardStroke.withValues(alpha: 0.4),
                ),
              ),
            if (onSelectAsTarget != null) ...[
              const SizedBox(width: 6),
              Text(
                '(tap to target)',
                style: TextStyle(
                  fontSize: 10,
                  color: ArmorUpColors.cardStroke.withValues(alpha: 0.55),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Right panel: the single detailed representation of the active player's
/// own armor, as a 3x2 grid of full-size badges.
class _MyArmorGridPanel extends StatelessWidget {
  final PlayerState player;
  final bool selectable;
  final ArmorType? selectedArmor;
  final ValueChanged<ArmorType> onSelectArmor;
  final bool Function(ArmorCondition condition) isConditionSelectable;

  const _MyArmorGridPanel({
    required this.player,
    required this.selectable,
    required this.selectedArmor,
    required this.onSelectArmor,
    required this.isConditionSelectable,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Your Armor',
            style: TextStyle(fontWeight: FontWeight.bold, color: ArmorUpColors.cardStroke),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // ArmorBadge has a fixed natural size; on short landscape
                // heights (real phones) the 2-row grid doesn't fit that
                // size, and GridView silently clips the second row instead
                // of erroring. Shrink each badge to fit its actual cell via
                // FittedBox rather than let it clip - all 6 pieces should
                // always be visible without scrolling.
                const columns = 3;
                const rows = 2;
                const spacing = 8.0;
                final cellWidth = (constraints.maxWidth - spacing * (columns - 1)) / columns;
                final cellHeight = (constraints.maxHeight - spacing * (rows - 1)) / rows;

                return GridView.count(
                  crossAxisCount: columns,
                  mainAxisSpacing: spacing,
                  crossAxisSpacing: spacing,
                  childAspectRatio: cellWidth / cellHeight,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (final piece in player.armor)
                      FittedBox(
                        fit: BoxFit.contain,
                        child: ArmorBadge(
                          piece: piece,
                          selectable: selectable && isConditionSelectable(piece.condition),
                          selected: selectedArmor == piece.type,
                          onTap: () => onSelectArmor(piece.type),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom-right stat readout: cards remaining in the draw pile and cards
/// in the discard pile. Simple, non-interactive.
class _PileCountersColumn extends StatelessWidget {
  final GameState state;

  const _PileCountersColumn({required this.state});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 12,
      color: ArmorUpColors.cardStroke.withValues(alpha: 0.8),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('Draw pile: ${state.drawPile.length}', style: style),
        const SizedBox(height: 4),
        Text('Discard pile: ${state.discardPile.length}', style: style),
      ],
    );
  }
}
