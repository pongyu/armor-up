import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:game_engine/game_engine.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../state/app_mode_controller.dart';
import '../state/game_providers.dart';
import '../state/turn_actor.dart';
import '../theme/armor_up_colors.dart';
import '../widgets/armor_widget.dart';
import '../widgets/card_widget.dart';
import 'pass_device_screen.dart';
import 'win_screen.dart';

part 'defense_prompt_view.dart';
part 'group_discard_prompt_view.dart';

/// Top-level router for an in-progress game: alternates between the
/// pass-the-phone screen and the active screen (game board or defense
/// prompt) whenever [currentActorId] changes, and shows the win screen
/// once the game ends.
///
/// Keeps the screen awake for the whole span of a game - players are
/// reading cards and passing the device around, not tapping constantly,
/// so the OS's idle-dim timeout would otherwise kick in mid-turn.
class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  String? _lastAcknowledgedActorId;
  bool _showingPassScreen = true;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gameStateProvider);
    if (state == null) return const SizedBox.shrink();

    if (state.isGameOver) {
      return WinScreen(state: state);
    }

    // In LAN mode every device is fixed to its own player and there is no
    // phone to pass, so it never shows the pass-device gate: it renders
    // its own player's view, interactive when that player must act and
    // read-only otherwise. In hotseat mode there is no local player, so
    // the board follows whoever must act next behind the pass gate.
    final localPlayerId = ref.watch(localPlayerIdProvider);
    if (localPlayerId != null) {
      return _buildNetworked(state, localPlayerId);
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

  /// LAN routing: [localPlayerId] is this device's own player. When it is
  /// this player's turn/response, show the same interactive views hotseat
  /// uses (just without a pass gate). When it is someone else's, show a
  /// read-only board from this player's own perspective so they can watch
  /// the game unfold without ever touching another player's hidden hand.
  Widget _buildNetworked(GameState state, String localPlayerId) {
    final actorId = currentActorId(state);
    if (actorId == localPlayerId) {
      if (state.pendingGroupDiscard != null) {
        return _GroupDiscardPromptView(actorId: localPlayerId);
      }
      return state.pendingInterrupt != null
          ? _DefensePromptView(actorId: localPlayerId)
          : _MainBoardView(actorId: localPlayerId);
    }
    return _MainBoardView(actorId: localPlayerId, readOnly: true);
  }
}

class _MainBoardView extends ConsumerStatefulWidget {
  final String actorId;

  /// LAN read-only mode: this is the local player's board shown while it
  /// is *someone else's* turn. The board renders from [actorId]'s
  /// perspective as usual, but the Draw/Play/End controls are disabled and
  /// the title reflects whose turn it actually is, so the player watches
  /// the game unfold without being able to act out of turn.
  final bool readOnly;

  const _MainBoardView({required this.actorId, this.readOnly = false});

  @override
  ConsumerState<_MainBoardView> createState() => _MainBoardViewState();
}

class _MainBoardViewState extends ConsumerState<_MainBoardView> {
  CardInstance? _selectedCard;
  String? _selectedTargetPlayerId;
  ArmorType? _selectedTargetArmor;

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
    final controller = ref.read(activeGameControllerProvider);
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

    final canPlaySelection =
        state.hasDrawnThisTurn &&
        !state.hasPlayedCardThisTurn &&
        def != null &&
        _isSelectionComplete(def);

    return Scaffold(
      body: _VignetteBoardBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Column(
                children: [
                  Expanded(
                    child: _buildPanels(state, me, def, constraints.maxWidth),
                  ),
                  const Divider(height: 1),
                  Builder(
                    builder: (context) {
                      // On short (landscape phone) heights the fixed card size
                      // would otherwise crowd out the panels above it - shrink
                      // each card's real footprint (FittedBox around a bounded
                      // CardWidget, not the scrollable list itself) so the
                      // panels - the primary game-state view - always keep
                      // most of the vertical space, with no overflow and
                      // correctly mapped tap coordinates.
                      // 24: the Discard button's minimumSize height below the
                      // card. No other padding sits between the card and
                      // button, or after the button, so this must match
                      // _HandCard's actual content exactly - any slack here
                      // shows up as dead space under the cards once scaled up.
                      const naturalHandHeight = CardWidget.cardHeight + 24;
                      // Duplicate cards (countInDeck is 4 per attack card,
                      // so multiple copies in hand are common, not an edge
                      // case) collapse into one card widget with a count
                      // badge rather than rendering N identical cards side
                      // by side - groupBy defId, keep the first instance per
                      // group as the tap/discard target ("one at a time" is
                      // enough; a multi-discard picker would be more work
                      // for limited benefit). Computed here, before the
                      // sizing math below, since that math needs the
                      // collapsed count, not the raw hand length, or cards
                      // would shrink more than actually necessary once
                      // duplicates stop taking up their own slot.
                      final groupedHand = <String, List<CardInstance>>{};
                      for (final card in me.hand) {
                        groupedHand.putIfAbsent(card.defId, () => []).add(card);
                      }
                      final handStacks = groupedHand.values.toList();
                      // The action buttons used to have their own full-width row
                      // above the hand; folding them into a sidebar alongside the
                      // pile counters gives that space back to the hand, so cards
                      // can render bigger. Give the hand a bigger share of the
                      // vertical space than the top panels - the hand is what
                      // the player is actually reading/interacting with turn to
                      // turn, so it's fine for the portrait/opponent-list panels
                      // to run a bit shorter.
                      final availableForHand = constraints.maxHeight * 0.55;
                      var scale = (availableForHand / naturalHandHeight).clamp(
                        0.55,
                        1.35,
                      );
                      // On narrow (portrait phone) widths a fixed sidebar would
                      // starve or overflow the scrollable hand list - shrink it
                      // down (and let it wrap to icon-only buttons) rather than
                      // hold a fixed width regardless of available space.
                      final sidebarWidth = constraints.maxWidth < 500
                          ? 96.0
                          : 128.0;
                      // Hand size is normally capped at maxHandSize, but a
                      // just-drawn hand can briefly sit one over that limit
                      // until the player discards back down. Rather than let
                      // that transient extra card force horizontal scrolling,
                      // shrink every card just enough for all of them to fit
                      // the row width without scrolling - no fan/overlap
                      // layout (noted as a future idea), just a smaller flat
                      // row for the one turn it's needed.
                      if (me.hand.length > maxHandSize) {
                        const cardHorizontalSlot = CardWidget.cardWidth + 8;
                        final availableRowWidth =
                            constraints.maxWidth - sidebarWidth - 24 - 16;
                        // handStacks.length (rendered slots), not
                        // me.hand.length (raw card count) - duplicates
                        // collapse into one slot with a count badge, so
                        // the width math needs to match what's actually
                        // on screen or cards shrink more than necessary.
                        final widthScale =
                            availableRowWidth /
                            (cardHorizontalSlot * handStacks.length);
                        scale = scale < widthScale ? scale : widthScale;
                        scale = scale.clamp(0.4, 1.35);
                      }
                      final handRowHeight = naturalHandHeight * scale;

                      return SizedBox(
                        height: handRowHeight,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                children: [
                                  for (final stack in handStacks)
                                    Padding(
                                      // Extra top room (vs. the 4px everywhere
                                      // else) so the selected-card lift
                                      // (AnimatedSlide in _HandCard) has space
                                      // to paint into instead of getting
                                      // clipped by the ListView's viewport.
                                      padding: const EdgeInsets.fromLTRB(
                                        4,
                                        16,
                                        4,
                                        4,
                                      ),
                                      child: SizedBox(
                                        width: (CardWidget.cardWidth) * scale,
                                        height: handRowHeight,
                                        child: FittedBox(
                                          fit: BoxFit.contain,
                                          alignment: Alignment.topCenter,
                                          // FittedBox clips its child by
                                          // default - the count badge is
                                          // meant to hang partially off
                                          // the card's top-right corner
                                          // (like a wax seal), which
                                          // needs to paint outside this
                                          // box's exact bounds instead of
                                          // being silently clipped.
                                          clipBehavior: Clip.none,
                                          child: SizedBox(
                                            width: CardWidget.cardWidth,
                                            height: naturalHandHeight,
                                            child: Builder(
                                              builder: (context) {
                                                // Tap/discard always act on
                                                // the stack's first instance -
                                                // "one at a time" is enough
                                                // (see the groupedHand
                                                // comment above); if a
                                                // *different* instance in
                                                // this stack is the selected
                                                // one (e.g. after playing/
                                                // discarding the first),
                                                // still show the stack as
                                                // selected rather than
                                                // losing the highlight.
                                                final card = stack.first;
                                                final selectedInStack =
                                                    _selectedCard != null &&
                                                    stack.any(
                                                      (c) =>
                                                          c.instanceId ==
                                                          _selectedCard!
                                                              .instanceId,
                                                    );
                                                return _HandCard(
                                                  card: card,
                                                  count: stack.length,
                                                  selected: selectedInStack,
                                                  disabled:
                                                      widget.readOnly ||
                                                      me.isFasting ||
                                                      state.hasPlayedCardThisTurn ||
                                                      cardDefFor(card).type ==
                                                          CardType.defense,
                                                  onTap: () {
                                                    setState(() {
                                                      if (selectedInStack) {
                                                        _resetSelection();
                                                      } else {
                                                        _selectedCard = card;
                                                        _selectedTargetPlayerId =
                                                            null;
                                                        _selectedTargetArmor =
                                                            null;
                                                      }
                                                    });
                                                  },
                                                  onDiscard:
                                                      !widget.readOnly &&
                                                          state.hasDrawnThisTurn
                                                      ? () => controller
                                                            .dispatch(
                                                              DiscardCard(
                                                                playerId: widget
                                                                    .actorId,
                                                                cardInstanceId:
                                                                    card
                                                                        .instanceId,
                                                              ),
                                                            )
                                                      : null,
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              child: SizedBox(
                                width: sidebarWidth,
                                child: _ActionSidebar(
                                  state: state,
                                  canDraw:
                                      !widget.readOnly &&
                                      !state.hasDrawnThisTurn,
                                  canPlay: !widget.readOnly && canPlaySelection,
                                  canEndTurn:
                                      !widget.readOnly &&
                                      state.hasDrawnThisTurn,
                                  mustDiscardFirst:
                                      me.hand.length > maxHandSize,
                                  onDraw: () => controller.dispatch(
                                    DrawCard(playerId: widget.actorId),
                                  ),
                                  onPlay: () {
                                    controller.dispatch(
                                      PlayCard(
                                        playerId: widget.actorId,
                                        cardInstanceId:
                                            _selectedCard!.instanceId,
                                        targetPlayerId: _selectedTargetPlayerId,
                                        targetArmor: _selectedTargetArmor,
                                      ),
                                    );
                                    _resetSelection();
                                  },
                                  onEndTurn: () => controller.dispatch(
                                    EndTurn(playerId: widget.actorId),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPanels(
    GameState state,
    PlayerState me,
    CardDef? def,
    double availableWidth,
  ) {
    // The portrait panel has a natural fixed width; on narrow (portrait
    // phone) widths that plus the center list panel's minimum no longer
    // fits, so scale it down rather than let the Row overflow. The armor
    // grid panel is gone - the active player's own armor now lives inside
    // the portrait panel itself - so the center list panel gets everything
    // else via Expanded.
    const naturalPortraitWidth = 340.0;
    const centerPanelMinWidth = 220.0;
    const dividerAllowance = 1.0;
    final naturalTotal =
        naturalPortraitWidth + centerPanelMinWidth + dividerAllowance;
    final portraitWidth =
        naturalPortraitWidth * (availableWidth / naturalTotal).clamp(0.4, 1.0);

    final activePlayer = widget.readOnly ? state.activePlayer : me;
    final armorSelectable =
        def != null &&
        _targetRuleNeedsArmor(def.targetRule) &&
        _targetRuleNeedsOwnPiece(def.targetRule);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: portraitWidth,
          child: _ActivePlayerPortraitPanel(
            player: activePlayer,
            state: state,
            selectable: armorSelectable,
            selectedArmor: _selectedTargetArmor,
            onSelectArmor: (armor) =>
                setState(() => _selectedTargetArmor = armor),
            isConditionSelectable: def == null
                ? defaultIsConditionSelectable
                : (condition) => _isConditionSelectable(def, condition),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _PlayerListPanel(
            actorId: widget.actorId,
            hiddenPlayerId: activePlayer.id,
            players: state.players,
            def: def,
            selectedTargetPlayerId: _selectedTargetPlayerId,
            onSelectTarget: (playerId) =>
                setState(() => _selectedTargetPlayerId = playerId),
            targetRuleNeedsPlayer: _targetRuleNeedsPlayer,
            selectedTargetArmor: _selectedTargetArmor,
            onSelectArmor: (armor) =>
                setState(() => _selectedTargetArmor = armor),
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

  bool _targetRuleNeedsOwnPiece(TargetRule rule) =>
      rule == TargetRule.ownArmorPiece;

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

/// The game board's background: the flat [ArmorUpColors.boardBackground]
/// fill under a radial vignette that darkens toward the screen edges,
/// for a bit of depth without a busy texture competing with the panels.
/// A tiled paper texture (Tiny Swords' SpecialPaper.png) was tried here
/// and dropped - even its "plain" center cell showed visible tile seams
/// and was too high-contrast against the dark UI panels. A lightweight
/// stand-in for a fuller board frame - see the (currently unused, kept
/// for later) hand-drawn stone-brick assets under
/// assets/cards/templates/ for a heavier treatment considered and
/// backed out of for now.
class _VignetteBoardBackground extends StatelessWidget {
  final Widget child;

  const _VignetteBoardBackground({required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: ArmorUpColors.boardBackground),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // radius 1.4 (vs. the default 0.5) reaches past the screen's
          // corners on a wide landscape aspect ratio, so the darkening
          // is actually visible rather than undershooting off-screen;
          // stops start darkening at 0.3 so it reads clearly instead of
          // only tinting the very outer edge.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.4,
                colors: [Colors.transparent, Colors.black87],
                stops: [0.3, 1.0],
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _HandCard extends StatelessWidget {
  final CardInstance card;
  final int count;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;
  final VoidCallback? onDiscard;

  const _HandCard({
    required this.card,
    required this.count,
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
          // Selection used to rely solely on the frame's glow shadow, which
          // reads poorly now that the frame itself is a busy pixel-art
          // border - a physical lift makes the selected card unambiguous
          // even before the glow registers.
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            offset: selected ? const Offset(0, -0.08) : Offset.zero,
            child: AnimatedScale(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              scale: selected ? 1.05 : 1.0,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  CardWidget(
                    def: def,
                    selected: selected,
                    onTap: disabled ? null : onTap,
                  ),
                  // Duplicate-card count badge - only shown when the
                  // player actually holds more than one copy, per the
                  // groupedHand collapsing in _MainBoardViewState.build.
                  // Hangs partially off the card's top-right corner (like
                  // a wax seal) rather than sitting inset - the
                  // surrounding FittedBox needed clipBehavior: Clip.none
                  // (see that widget) for this negative offset to
                  // actually paint instead of getting clipped away.
                  if (count > 1)
                    Positioned(
                      top: -6,
                      right: -14,
                      child: _CountBadge(count: count),
                    ),
                ],
              ),
            ),
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

/// Small circular "xN" badge on a hand card's corner, shown when the
/// player holds more than one copy of that card - see _HandCard's
/// count field and the groupedHand collapsing in
/// _MainBoardViewState.build.
class _CountBadge extends StatelessWidget {
  final int count;

  const _CountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: ArmorUpColors.goldAccent,
        shape: count > 9 ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: count > 9 ? BorderRadius.circular(14) : null,
        // cardInnerStroke (light warm off-white, same ring color used
        // elsewhere in the card chrome) instead of the dark cardStroke -
        // a lighter ring reads better against the badge's own gold fill
        // and the dark card art it sits on top of.
        border: Border.all(color: ArmorUpColors.cardInnerStroke, width: 2),
      ),
      alignment: Alignment.center,
      // White text instead of dark-on-gold - dark text on gold read too
      // low-contrast against the busy card art behind the badge,
      // especially at this size. Outline uses cardStroke (warm dark
      // ink, matching the badge's own border) rather than
      // ArmorUpColors.titleOutline's pure black, so the whole badge
      // reads as one warm-toned unit instead of a black-outlined patch
      // stuck on top.
      child: Text(
        'x$count',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          height: 1,
          // 8-directional (cardinal + diagonal), not just 4 - a thicker
          // stroke than ArmorUpColors.titleOutline's cardinal-only
          // version, since this text sits smaller and needed to read
          // clearly at a glance against busy card art behind it.
          shadows: [
            Shadow(offset: const Offset(1, 0), color: ArmorUpColors.cardStroke),
            Shadow(offset: const Offset(-1, 0), color: ArmorUpColors.cardStroke),
            Shadow(offset: const Offset(0, 1), color: ArmorUpColors.cardStroke),
            Shadow(offset: const Offset(0, -1), color: ArmorUpColors.cardStroke),
            Shadow(offset: const Offset(1, 1), color: ArmorUpColors.cardStroke),
            Shadow(offset: const Offset(-1, -1), color: ArmorUpColors.cardStroke),
            Shadow(offset: const Offset(1, -1), color: ArmorUpColors.cardStroke),
            Shadow(offset: const Offset(-1, 1), color: ArmorUpColors.cardStroke),
          ],
        ),
      ),
    );
  }
}

/// Left panel: the active player's name, turn-status line, and their own
/// armor as a single row of six full badges underneath. This is the single
/// place turn/fasting/played-card status is shown - it used to be a footer
/// message repeated under the hand row - and, since the right-hand armor
/// grid panel was removed, the single place the active player's own armor
/// detail is shown at all.
///
/// No portrait image yet - the background is a plain placeholder fill so a
/// future full-panel character illustration can sit behind this text
/// without restructuring, rather than a separate circular avatar competing
/// with the armor row for the panel's limited height.
class _ActivePlayerPortraitPanel extends StatelessWidget {
  final PlayerState player;
  final GameState state;
  final bool selectable;
  final ArmorType? selectedArmor;
  final ValueChanged<ArmorType> onSelectArmor;
  final bool Function(ArmorCondition condition) isConditionSelectable;

  const _ActivePlayerPortraitPanel({
    required this.player,
    required this.state,
    required this.selectable,
    required this.selectedArmor,
    required this.onSelectArmor,
    required this.isConditionSelectable,
  });

  String get _statusLine {
    if (player.isFasting) return 'Fasting this turn';
    if (state.hasPlayedCardThisTurn) return 'Already played a card';
    if (!state.hasDrawnThisTurn) return 'Draw to begin your turn';
    return 'Choose a card to play';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: ArmorUpColors.cardBackground.withValues(alpha: 0.2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // FittedBox rather than a fixed fontSize: EarlyGameBoy's
          // letterforms are noticeably wider than the platform default
          // font this size was tuned for, so a fixed size started
          // truncating names/turn numbers that used to fit - scaling
          // down only as much as actually needed keeps the text as
          // large as possible instead of a blanket smaller size.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              // Dash, not "(active)" - EarlyGameBoy doesn't render
              // parenthesis glyphs cleanly (shows as a stray box/symbol
              // instead), so parens are avoided in this font wherever
              // the text isn't user-authored content (card names, etc.
              // sourced from data are left alone).
              '${player.name} - Turn ${state.turnNumber} - Active',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: ArmorUpColors.fontColor,
                shadows: ArmorUpColors.titleOutline,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _statusLine,
            style: TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: ArmorUpColors.fontColor.withValues(alpha: 0.75),
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          const Spacer(),
          const Text(
            'Your Armor',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: ArmorUpColors.fontColor,
            ),
          ),
          const SizedBox(height: 6),
          // Six full-size badges are wider than this panel - scale the
          // whole row down to fit rather than let it scroll out of view,
          // so all six conditions stay glanceable at once.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: ArmorRow(
              player: player,
              selectable: selectable,
              selectedArmor: selectedArmor,
              onSelect: onSelectArmor,
              isConditionSelectable: isConditionSelectable,
            ),
          ),
        ],
      ),
    );
  }
}

/// Center panel: a glanceable, scrollable list of every player except
/// [hiddenPlayerId] (the one whose detailed armor is already shown in the
/// left portrait panel - repeating them here would show the same data
/// twice). Every remaining player gets a compact armor-badge row and
/// remains tap-to-target.
class _PlayerListPanel extends StatelessWidget {
  final String actorId;
  final String hiddenPlayerId;
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
    required this.hiddenPlayerId,
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
    final needsArmorPick =
        def != null && def!.targetRule == TargetRule.anyPieceOnPlayer;
    final visiblePlayers = players.where((p) => p.id != hiddenPlayerId);

    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        for (final player in visiblePlayers)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _PlayerListRow(
              player: player,
              isSelf: player.id == actorId,
              isSelectedTarget: player.id == selectedTargetPlayerId,
              onSelectAsTarget:
                  def != null &&
                      targetRuleNeedsPlayer(def!.targetRule) &&
                      player.id != actorId &&
                      !player.isEliminated
                  ? () => onSelectTarget(player.id)
                  : null,
              armorSelectable:
                  needsArmorPick && player.id == selectedTargetPlayerId,
              // Once an opponent's armor is the thing being picked, every
              // other opponent's row mutes down - only the actual target's
              // pieces should read as live/actionable.
              armorMuted: needsArmorPick && player.id != selectedTargetPlayerId,
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
  final bool armorMuted;
  final ArmorType? selectedArmor;
  final ValueChanged<ArmorType> onSelectArmor;
  final bool Function(ArmorCondition condition) isConditionSelectable;

  const _PlayerListRow({
    required this.player,
    required this.isSelf,
    required this.isSelectedTarget,
    required this.onSelectAsTarget,
    required this.armorSelectable,
    required this.armorMuted,
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
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Plain ConstrainedBox, not Flexible: a Flexible sibling of the
            // armor cluster's Expanded would reserve half the row's flex
            // share for the name regardless of how little of it the text
            // actually uses - Flutter doesn't hand unused flex space back
            // to other flex children, it just sits blank in the Flexible's
            // own slot. A non-flex box takes only its intrinsic width, so
            // Expanded genuinely gets ~100% of what's left, which is what
            // makes the armor row actually reach the panel's right edge.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 90),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // FittedBox rather than a fixed fontSize: EarlyGameBoy's
                  // glyphs are wide enough that even a smaller fixed size
                  // still truncated longer names within this row's fixed
                  // 90px maxWidth - scaling down only as much as actually
                  // needed keeps the name fully readable instead of
                  // guessing a size that happens to fit every name.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      // Dash, not "(you)" - see the turn-header comment
                      // above on EarlyGameBoy's broken parenthesis glyph.
                      isSelf ? '${player.name} - You' : player.name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: ArmorUpColors.fontColor.withValues(
                          alpha: isSelf ? 0.55 : 1,
                        ),
                      ),
                      maxLines: 1,
                    ),
                  ),
                  // Stacked under the name rather than inline before the
                  // armor row: sharing a flex row with the badges made
                  // them visibly shrink/grow depending on whether this
                  // text was present, since both competed for the same
                  // leftover width.
                  if (onSelectAsTarget != null)
                    // Same FittedBox fix as the name label above -
                    // EarlyGameBoy's glyphs are too wide for this row's
                    // fixed 90px maxWidth at a fixed font size.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '-tap to target-',
                        style: TextStyle(
                          fontSize: 10,
                          color: ArmorUpColors.fontColor.withValues(
                            alpha: 0.55,
                          ),
                        ),
                        maxLines: 1,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            // Armor badges (or the placeholder/eliminated tag) claim all
            // remaining space and right-align within it.
            Expanded(
              child: player.isEliminated
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: const [
                        Chip(
                          label: Text('Eliminated'),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    )
                  // Expanded gives FittedBox a bounded width to scale down
                  // against; without it FittedBox reports its child's
                  // natural (unscaled) size when the incoming constraint is
                  // loose, which overflows on narrow panels instead of
                  // shrinking - the exact case this was meant to handle.
                  : Row(
                      children: [
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: ArmorRow(
                              player: player,
                              compact: true,
                              selectable: armorSelectable,
                              muted: armorMuted,
                              selectedArmor: selectedArmor,
                              onSelect: armorSelectable ? onSelectArmor : null,
                              isConditionSelectable: isConditionSelectable,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Right-of-hand sidebar: the three turn actions (Draw / Play card / End
/// turn) stacked as compact icon buttons, with the draw/discard pile
/// counts underneath. Replaces the old full-width button row so that
/// space goes back to the hand, letting cards render bigger.
class _ActionSidebar extends StatelessWidget {
  final GameState state;
  final bool canDraw;
  final bool canPlay;
  final bool canEndTurn;
  final bool mustDiscardFirst;
  final VoidCallback onDraw;
  final VoidCallback onPlay;
  final VoidCallback onEndTurn;

  const _ActionSidebar({
    required this.state,
    required this.canDraw,
    required this.canPlay,
    required this.canEndTurn,
    required this.mustDiscardFirst,
    required this.onDraw,
    required this.onPlay,
    required this.onEndTurn,
  });

  @override
  Widget build(BuildContext context) {
    final pileStyle = TextStyle(
      fontSize: 11,
      color: ArmorUpColors.fontColor.withValues(alpha: 0.8),
    );
    // The buttons keep a real tap target size rather than shrinking to fit,
    // so on short heights this scrolls instead of overflowing - matching
    // how the hand row already handles a horizontal equivalent.
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SidebarButton(
            icon: Icons.style,
            label: 'Draw',
            filled: false,
            onPressed: canDraw ? onDraw : null,
          ),
          const SizedBox(height: 4),
          _SidebarButton(
            icon: Icons.play_arrow,
            label: 'Play card',
            filled: true,
            onPressed: canPlay ? onPlay : null,
          ),
          const SizedBox(height: 4),
          _SidebarButton(
            icon: Icons.check,
            label: mustDiscardFirst ? 'Discard first' : 'End turn',
            filled: false,
            onPressed: canEndTurn ? onEndTurn : null,
          ),
          const SizedBox(height: 6),
          Text('Draw pile: ${state.drawPile.length}', style: pileStyle),
          Text('Discard pile: ${state.discardPile.length}', style: pileStyle),
        ],
      ),
    );
  }
}

class _SidebarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback? onPressed;

  const _SidebarButton({
    required this.icon,
    required this.label,
    required this.filled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    // ButtonStyle.textStyle doesn't reliably fall through to
    // ThemeData.fontFamily the way a plain Text widget does - a
    // TextStyle with fontFamily left null here rendered in the
    // platform default font instead of the app's pixel font, so the
    // family is set explicitly, read from the ambient theme so it
    // can't drift out of sync if the app font changes again.
    final fontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;
    final style = ButtonStyle(
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      minimumSize: WidgetStateProperty.all(const Size(0, 0)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: WidgetStateProperty.all(
        TextStyle(fontSize: 12, fontFamily: fontFamily),
      ),
    );
    final child = FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 16), const SizedBox(width: 6), Text(label)],
      ),
    );
    return filled
        ? FilledButton(onPressed: onPressed, style: style, child: child)
        : OutlinedButton(onPressed: onPressed, style: style, child: child);
  }
}
