import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:game_engine/game_engine.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../state/app_mode_controller.dart';
import '../state/game_controller.dart';
import '../state/game_providers.dart';
import '../state/turn_actor.dart';
import '../theme/armor_up_colors.dart';
import '../widgets/armor_widget.dart';
import '../widgets/card_widget.dart';
import 'pass_device_screen.dart';
import 'rules_sheet.dart';
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

  Widget _buildBody(BuildContext context, GameState state) {
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gameStateProvider);
    if (state == null) return const SizedBox.shrink();

    // The banner overlays every sub-view (pass screen, prompts, board)
    // rather than living inside just _MainBoardView, since the
    // RestorationImminent event that triggers it can in principle log on
    // any turn transition and the announcement is meant for the whole
    // table, not just whichever screen happens to be showing.
    return Stack(
      children: [
        _buildBody(context, state),
        _RestorationImminentBannerHost(state: state),
      ],
    );
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

/// Watches [state]'s event log for a newly-appended [RestorationImminent]
/// and shows [_RestorationImminentBanner] for it. Split out from
/// [_GameScreenState] so the "have we already shown this event" bookkeeping
/// (a length + id, not just "is there one in the log") lives in its own
/// small widget instead of growing the already-large screen state class.
///
/// Detection is length-based (new events appended since the last build)
/// rather than "does the log contain one" - the event log is permanent and
/// never truncated, so a level-based check would either show the banner
/// forever after the first restoration or never show it again after a
/// rebuild. A player can also become fully restored more than once in a
/// game (broken again, then re-restored) - see [RestorationImminent]'s own
/// doc comment - so re-firing on each new occurrence is correct, not a bug
/// to guard against.
class _RestorationImminentBannerHost extends StatefulWidget {
  final GameState state;

  const _RestorationImminentBannerHost({required this.state});

  @override
  State<_RestorationImminentBannerHost> createState() =>
      _RestorationImminentBannerHostState();
}

class _RestorationImminentBannerHostState extends State<_RestorationImminentBannerHost> {
  int _lastSeenEventCount = 0;
  RestorationImminent? _activeEvent;
  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();
    // Don't replay history: a game resumed mid-play (or a rebuild after a
    // hot reload) shouldn't suddenly announce an event that already
    // happened turns ago - only events appended AFTER this host first
    // mounts are new.
    _lastSeenEventCount = widget.state.eventLog.length;
  }

  @override
  void didUpdateWidget(covariant _RestorationImminentBannerHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final events = widget.state.eventLog;
    if (events.length > _lastSeenEventCount) {
      final newEvents = events.sublist(_lastSeenEventCount);
      final imminent = newEvents.whereType<RestorationImminent>();
      if (imminent.isNotEmpty) {
        // Last one wins if somehow more than one landed in a single
        // rebuild - showing the most recent is more useful than the
        // first. Timer is (re)started exactly once per new event here,
        // not in build() - starting it in build() would reschedule a
        // fresh 4s timer on every unrelated rebuild while the banner is
        // showing (e.g. a card played elsewhere), so it would never
        // actually reach zero, and would also leak a new Timer per
        // rebuild since nothing was tracking/cancelling the previous one.
        _autoDismissTimer?.cancel();
        setState(() => _activeEvent = imminent.last);
        _autoDismissTimer = Timer(const Duration(seconds: 4), _dismiss);
      }
    }
    _lastSeenEventCount = events.length;
  }

  void _dismiss() {
    _autoDismissTimer?.cancel();
    _autoDismissTimer = null;
    if (mounted) setState(() => _activeEvent = null);
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final event = _activeEvent;
    if (event == null) return const SizedBox.shrink();

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: _RestorationImminentBanner(
          playerName: widget.state.playerById(event.playerId).name,
          onDismiss: _dismiss,
        ),
      ),
    );
  }
}

/// Prominent, gold-bordered, full-width banner announcing that a player now
/// stands fully armored and can win by restoration at the start of their
/// next turn - the visible counterplay window the RestorationImminent event
/// exists to create (see that class's doc comment in game_event.dart).
/// Purely a visual overlay: it never intercepts taps outside its own
/// bounds, so the board underneath stays fully interactive while it shows.
class _RestorationImminentBanner extends StatelessWidget {
  final String playerName;
  final VoidCallback onDismiss;

  const _RestorationImminentBanner({
    required this.playerName,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onDismiss,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: ArmorUpColors.boardBackground.withValues(alpha: 0.96),
            border: const Border(
              bottom: BorderSide(color: ArmorUpColors.goldAccent, width: 3),
            ),
            boxShadow: [
              BoxShadow(
                color: ArmorUpColors.goldAccent.withValues(alpha: 0.4),
                blurRadius: 12,
              ),
            ],
          ),
          child: Text(
            '${playerName.toUpperCase()} STANDS FULLY ARMORED - '
            'STOP THEM BEFORE THEIR NEXT TURN!',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: ArmorUpColors.goldAccent,
              shadows: ArmorUpColors.titleOutline,
            ),
          ),
        ),
      ),
    );
  }
}

/// Small gold icon shown next to a player's name whenever
/// [PlayerState.isFullyRestored] holds and restoration is a live win
/// condition ([GameState.restorationWinEnabled]). Deliberately derived
/// from state rather than tracked as a one-shot flag set by the
/// [RestorationImminent] event: state is self-correcting (it just
/// disappears the moment a piece drops below Strong, via the normal
/// rebuild from whatever damage event caused that - no separate
/// "restoration stopped" signal needed), where an event-driven flag would
/// need its own explicit clearing logic and could drift out of sync with
/// the board it's describing. Never rendered in basic mode
/// (`restorationWinEnabled == false`), since a condition that can't win
/// the game has nothing to flag.
class _FullyArmoredMarker extends StatelessWidget {
  final double size;

  const _FullyArmoredMarker({this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Fully armored - can win by restoration next turn',
      child: Icon(
        Icons.emoji_events,
        size: size,
        color: ArmorUpColors.goldAccent,
        shadows: ArmorUpColors.titleOutline,
      ),
    );
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

  // Estimated natural height of one _PlayerListRow (8px top/bottom
  // padding + ~26px name/tap-target text column + 8px bottom spacing
  // from _PlayerListPanel's own per-row Padding) - used to size the
  // portrait carousel so up to maxPlayers-1 opponent rows fit without
  // scrolling on a typical phone, rather than a fixed fraction of
  // whatever height happens to be left over.
  static const double _playerRowHeight = 64;

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

    // def.type != CardType.defense: selecting a card no longer implies
    // it's playable now that disabled (unplayable) cards stay tappable
    // in the fanned hand so they can still be discarded (see
    // _HandCard's onTap comment) - previously this fell out for free
    // because a disabled card could never become _selectedCard at all.
    final canPlaySelection =
        state.hasDrawnThisTurn &&
        !state.hasPlayedCardThisTurn &&
        def != null &&
        def.type != CardType.defense &&
        _isSelectionComplete(def);

    return Scaffold(
      body: _VignetteBoardBackground(
        child: SafeArea(
          child: Stack(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  // Portrait vs. landscape branch, sharing all the same
                  // selection state/helpers (_selectedCard,
                  // _isSelectionComplete, etc.) and low-level widgets
                  // (_HandCard, ArmorRow, CardWidget, _ActionSidebar) rather
                  // than forking into a separate StatefulWidget - see the
                  // portrait-support plan discussed in conversation for why.
                  if (constraints.maxHeight > constraints.maxWidth) {
                    return _buildPortraitBoard(
                      state,
                      me,
                      def,
                      controller,
                      canPlaySelection,
                      constraints,
                    );
                  }
                  return _buildLandscapeBoard(
                    state,
                    me,
                    def,
                    controller,
                    canPlaySelection,
                    constraints,
                  );
                },
              ),
              // Reachable any time during play, not just for a brand new
              // player - card games regularly need a rules lookup mid-game
              // (e.g. "what does Weakened mean again"), so this sits above
              // both layout branches rather than being tucked into a menu.
              const Positioned(
                top: 4,
                right: 4,
                child: _RulesButton(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Portrait layout (Stage 2: player-row carousel + turn header,
  /// replacing Stage 1's stacked _ActivePlayerPortraitPanel/
  /// _PlayerListPanel split). Order matches the reference mockup: turn
  /// header, then a scrollable list of every OTHER player's compact
  /// armor row (_PlayerListPanel, same widget landscape already uses
  /// for its opponent list - just given more vertical room here since
  /// portrait has no side panel competing for width), then the active
  /// player's own full-size "Your Armor" row, then the hand.
  Widget _buildPortraitBoard(
    GameState state,
    PlayerState me,
    CardDef? def,
    GameActionDispatcher controller,
    bool canPlaySelection,
    BoxConstraints outerConstraints,
  ) {
    final armorSelectable =
        def != null &&
        _targetRuleNeedsArmor(def.targetRule) &&
        _targetRuleNeedsOwnPiece(def.targetRule);
    final statusLine = me.isFasting
        ? 'Fasting this turn'
        : state.hasPlayedCardThisTurn
        ? 'Already played a card'
        : !state.hasDrawnThisTurn
        ? 'Draw to begin your turn'
        : 'Choose a card to play';

    // Duplicate cards collapse into one card widget with a count badge -
    // see the identical comment on the landscape hand row below for why.
    final groupedHand = <String, List<CardInstance>>{};
    for (final card in me.hand) {
      groupedHand.putIfAbsent(card.defId, () => []).add(card);
    }
    final handStacks = groupedHand.values.toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${state.activePlayer.name} - Turn ${state.turnNumber} - Active',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: ArmorUpColors.fontColor,
                    shadows: ArmorUpColors.titleOutline,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                statusLine,
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: ArmorUpColors.fontColor.withValues(alpha: 0.75),
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Scrollable player-row carousel - every player except the
        // active one, same _PlayerListPanel/_PlayerListRow already used
        // for landscape's opponent list. Sized to comfortably fit the
        // max player count (6, so up to 5 opponent rows) without
        // needing to scroll on a typical phone screen, rather than a
        // fixed fraction of whatever height happens to be left over -
        // the fanned hand below only needs its own natural card height,
        // not an open-ended Expanded share, so giving the carousel more
        // room up front doesn't starve the hand. Clamped against the
        // screen's actual height (reserving ~430px for everything else
        // - header, armor row, fan, action bar, pile text) so a short
        // screen shrinks the carousel rather than overflowing; the
        // carousel's own ListView already scrolls internally, so
        // shrinking it here just means more scrolling, not lost
        // content.
        SizedBox(
          height: ((maxPlayers - 1) * _playerRowHeight).clamp(
            _playerRowHeight,
            (outerConstraints.maxHeight - 430).clamp(
              _playerRowHeight,
              double.infinity,
            ),
          ),
          child: _PlayerListPanel(
            actorId: widget.actorId,
            hiddenPlayerId: widget.actorId,
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
            restorationWinEnabled: state.restorationWinEnabled,
          ),
        ),
        const Divider(height: 1),
        // "Your Armor" row - the active player's own full-size (not
        // compact) badges, matching the mockup's dedicated row between
        // the player carousel and the hand.
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Your Armor',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: ArmorUpColors.fontColor,
                    ),
                  ),
                  if (me.isFullyRestored && state.restorationWinEnabled) ...[
                    const SizedBox(width: 6),
                    const _FullyArmoredMarker(size: 14),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: ArmorRow(
                  player: me,
                  selectable: armorSelectable,
                  selectedArmor: _selectedTargetArmor,
                  onSelect: (armor) =>
                      setState(() => _selectedTargetArmor = armor),
                  isConditionSelectable: def == null
                      ? defaultIsConditionSelectable
                      : (condition) => _isConditionSelectable(def, condition),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Fixed height (was Expanded, claiming all leftover space) -
        // the fan only ever needs its own natural footprint
        // (CardWidget.cardHeight plus _FannedHand's topInset/yDrop
        // headroom), not an open-ended share of whatever's left after
        // the carousel/armor row above it, which was leaving a large
        // dead gap between "Your Armor" and the action bar below on
        // taller screens or smaller player counts.
        SizedBox(
          height: CardWidget.cardHeight + 60,
          child: _FannedHand(
            stacks: handStacks,
            selectedCard: _selectedCard,
            isCardDisabled: (card) =>
                widget.readOnly ||
                me.isFasting ||
                state.hasPlayedCardThisTurn ||
                cardDefFor(card).type == CardType.defense ||
                _hasNoEligibleOwnArmorTarget(cardDefFor(card), me),
            onTapCard: (card, selectedInStack) {
              setState(() {
                if (selectedInStack) {
                  _resetSelection();
                } else {
                  _selectedCard = card;
                  _selectedTargetPlayerId = null;
                  _selectedTargetArmor = null;
                }
              });
            },
          ),
        ),
        const Divider(height: 1),
        // Action row: the same 3 actions as _ActionSidebar, laid out
        // horizontally instead of stacked in a narrow sidebar column -
        // portrait's width is the plentiful dimension here, not height.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: _SidebarButton(
                  icon: Icons.style,
                  label: 'Draw',
                  filled: false,
                  onPressed: !widget.readOnly && !state.hasDrawnThisTurn
                      ? () => controller.dispatch(
                          DrawCard(playerId: widget.actorId),
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _SidebarButton(
                  icon: Icons.play_arrow,
                  label: 'Play card',
                  filled: true,
                  onPressed: !widget.readOnly && canPlaySelection
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
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Builder(
                  builder: (context) {
                    // When over the hand limit, this button already
                    // told the player "Discard first" - but used to
                    // just dispatch EndTurn regardless (which the
                    // engine rejects with an error snackbar until the
                    // hand's back under the limit). Once a card is
                    // actually selected while over the limit, the
                    // button now really performs that discard instead
                    // of just describing what needs to happen -
                    // removes the redundant separate Discard button a
                    // per-card rotated one couldn't replace (see
                    // _FannedHand's onDiscard comment) without adding a
                    // 4th button to an already-3-wide row.
                    final overLimit = me.hand.length > maxHandSize;
                    final mustDiscardSelected = overLimit && _selectedCard != null;

                    return _SidebarButton(
                      icon: mustDiscardSelected
                          ? Icons.delete_outline
                          : Icons.check,
                      label: mustDiscardSelected
                          ? 'Discard'
                          : overLimit
                          ? 'Discard first'
                          : 'End turn',
                      filled: false,
                      onPressed: !widget.readOnly && state.hasDrawnThisTurn
                          ? () {
                              if (mustDiscardSelected) {
                                controller.dispatch(
                                  DiscardCard(
                                    playerId: widget.actorId,
                                    cardInstanceId: _selectedCard!.instanceId,
                                  ),
                                );
                                _resetSelection();
                              } else {
                                controller.dispatch(
                                  EndTurn(playerId: widget.actorId),
                                );
                              }
                            }
                          : null,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            'Draw pile: ${state.drawPile.length}   Discard pile: ${state.discardPile.length}',
            style: TextStyle(
              fontSize: 11,
              color: ArmorUpColors.fontColor.withValues(alpha: 0.8),
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  /// Today's original board layout: portrait/opponent panels side by
  /// side above a horizontal hand row + action sidebar. Unchanged in
  /// substance from before portrait support was added - only extracted
  /// into its own method so build() can branch on aspect ratio.
  Widget _buildLandscapeBoard(
    GameState state,
    PlayerState me,
    CardDef? def,
    GameActionDispatcher controller,
    bool canPlaySelection,
    BoxConstraints outerConstraints,
  ) {
    return Column(
      children: [
        Expanded(
          child: _buildPanels(state, me, def, outerConstraints.maxWidth),
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
                      final availableForHand = outerConstraints.maxHeight * 0.55;
                      var scale = (availableForHand / naturalHandHeight).clamp(
                        0.55,
                        1.35,
                      );
                      // On narrow (portrait phone) widths a fixed sidebar would
                      // starve or overflow the scrollable hand list - shrink it
                      // down (and let it wrap to icon-only buttons) rather than
                      // hold a fixed width regardless of available space.
                      final sidebarWidth = outerConstraints.maxWidth < 500
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
                            outerConstraints.maxWidth - sidebarWidth - 24 - 16;
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
                                                          CardType.defense ||
                                                      _hasNoEligibleOwnArmorTarget(
                                                        cardDefFor(card),
                                                        me,
                                                      ),
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
            player: me,
            turnPlayer: state.activePlayer,
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
            hiddenPlayerId: widget.actorId,
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
            restorationWinEnabled: state.restorationWinEnabled,
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

  /// True when [def] is a restore card that targets one of the player's
  /// own armor pieces (Renewal/Armor Bearer/Fasting) but [me] currently
  /// has no piece in the right condition to legally receive it (e.g.
  /// Renewal with no Weakened pieces). Used to disable/gray such a card
  /// in hand up front, rather than letting the player select it and
  /// discover only via a dead-end target-selection screen (every armor
  /// slot muted, "Play card" never enabling) that it currently has
  /// nowhere to go. Fasting always returns false here - it accepts any
  /// condition, so it can never be "no eligible targets" as long as the
  /// player has at least one armor piece, which is always true.
  bool _hasNoEligibleOwnArmorTarget(CardDef def, PlayerState me) {
    if (def.targetRule != TargetRule.ownArmorPiece) return false;
    return !me.armor.any((piece) => _isConditionSelectable(def, piece.condition));
  }
}

/// Small "?" icon button pinned over the board that opens [showRulesSheet]
/// - a quick-reference summary reachable at any point in a game, not just
/// for a brand new player.
class _RulesButton extends StatelessWidget {
  const _RulesButton();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ArmorUpColors.cardBackground.withValues(alpha: 0.7),
      shape: const CircleBorder(),
      child: IconButton(
        icon: const Icon(Icons.help_outline, color: ArmorUpColors.fontColor, size: 20),
        tooltip: 'How to play',
        onPressed: () => showRulesSheet(context),
      ),
    );
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

/// Portrait's fanned hand: cards overlap and rotate around a shared
/// bottom-center pivot, like a hand of real playing cards, instead of
/// the flat horizontal ListView landscape uses. The single genuinely
/// new geometry in this codebase's portrait-support work - no
/// precedent to follow, tuned by eye rather than derived.
///
/// Each card's position is computed relative to hand-center: card index
/// `i` of `n` gets a signed "slot" `i - (n-1)/2` (0 for the middle card,
/// negative left, positive right), which drives both the rotation angle
/// and the horizontal offset linearly - a plain fan, not a curved/arced
/// one (no per-card vertical lift). `Transform.rotate` pivots from
/// `Alignment.bottomCenter`, not the default center, so cards fan out
/// from a single point at the bottom like they're actually held in a
/// hand.
///
/// Selection reuses _HandCard's existing AnimatedSlide/AnimatedScale
/// lift unchanged, nested inside this widget's own rotation transform -
/// the lift still translates along the card's own (rotated) local Y
/// axis, which reads fine even at the fan's outer angles since the
/// lift distance is small relative to the rotation.
class _FannedHand extends StatelessWidget {
  final List<List<CardInstance>> stacks;
  final CardInstance? selectedCard;
  final bool Function(CardInstance card) isCardDisabled;
  final void Function(CardInstance card, bool selectedInStack) onTapCard;

  const _FannedHand({
    required this.stacks,
    required this.selectedCard,
    required this.isCardDisabled,
    required this.onTapCard,
  });

  // Total angular spread across the whole hand, and how far apart
  // (horizontally) adjacent cards sit - tuned by eye, not derived from
  // anything. Capped rather than growing unbounded with hand size (a
  // 10-card hand fanned at these same per-card values would spread off
  // both edges of the screen), matching the same
  // "shrink rather than overflow" philosophy the landscape hand row
  // already uses for its own over-maxHandSize case.
  static const double _maxTotalSpreadDegrees = 44;
  static const double _maxOverlapStep = 46;
  // How far outer cards drop below the center one, per slot^2 - see
  // the yDrop comment below for why this needs to be a parabola, not a
  // flat/linear offset.
  static const double _dropPerSlotSquared = 3.5;

  @override
  Widget build(BuildContext context) {
    final n = stacks.length;
    if (n == 0) {
      return const SizedBox.shrink();
    }

    // Fewer cards can use the full per-card spacing; a big hand needs
    // to compress both the angle-per-card and the offset-per-card so
    // the whole fan still fits within a couple hundred px of width
    // rather than running off-screen - same shrink-not-scroll approach
    // as the landscape hand row's own overflow handling.
    final anglePerCard = n > 1
        ? (_maxTotalSpreadDegrees / (n - 1)).clamp(4.0, 14.0)
        : 0.0;
    final overlapStep = n > 1
        ? (_maxOverlapStep - (n - 5).clamp(0, 6) * 4).clamp(24.0, _maxOverlapStep)
        : 0.0;

    // Paint order: left-to-right by default (so each card's right-hand
    // neighbor overlaps it, matching a normal held-card fan), but with
    // whichever stack is currently selected moved to the very end - a
    // Stack has no explicit z-index, only child order, and without this
    // a selected card near either edge of the fan would lift/scale up
    // but stay visually buried under its unselected neighbors toward
    // the center.
    final paintOrder = List<int>.generate(n, (i) => i);
    if (selectedCard != null) {
      final selectedIndex = paintOrder.indexWhere(
        (i) => stacks[i].any((c) => c.instanceId == selectedCard!.instanceId),
      );
      if (selectedIndex != -1) {
        paintOrder
          ..removeAt(selectedIndex)
          ..add(selectedIndex);
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final centerX = constraints.maxWidth / 2;
        // Anchored near the TOP of this widget's available space, not
        // the bottom - _FannedHand sits in an Expanded (so the action
        // bar below it stays pinned to the screen's true bottom
        // regardless of how much leftover height there is), but a
        // small hand doesn't need to visually float in the middle of
        // that space - it should hug the divider right above it. 16:
        // the same top-inset the old flat ListView used for the
        // selection-lift headroom.
        const topInset = 16.0;
        // Clamp the outermost card's horizontal offset (not just the
        // per-card overlapStep) to the actual available width, so a
        // wide hand shrinks its spread further rather than letting
        // cards run off either edge of the screen - overlapStep alone
        // already compresses somewhat as hand size grows, but that
        // compression is independent of how narrow the actual screen
        // is, so it isn't enough on its own.
        final maxOuterOffset = n > 1
            ? (constraints.maxWidth - CardWidget.cardWidth) / 2
            : 0.0;
        final naturalOuterOffset = n > 1 ? (n - 1) / 2 * overlapStep : 0.0;
        final widthClamp = naturalOuterOffset > maxOuterOffset && n > 1
            ? maxOuterOffset / naturalOuterOffset
            : 1.0;
        final clampedOverlapStep = overlapStep * widthClamp;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (final i in paintOrder)
              // Keyed on the card's own instanceId, not list position -
              // paintOrder reshuffles which index paints last whenever
              // selection changes, and without a stable key Flutter's
              // Stack reconciles children by position, not identity,
              // so a Builder/AnimatedSlide/AnimatedScale could get
              // silently reassigned to a DIFFERENT underlying card
              // than the one it was animating a moment ago - the
              // reported bug (the rightmost card visibly "bouncing"
              // when a different, unrelated card was tapped) was
              // exactly this: Flutter matched the wrong element across
              // the reorder and replayed/misapplied its animation.
              Builder(
                key: ValueKey(stacks[i].first.instanceId),
                builder: (context) {
                  final stack = stacks[i];
                  final card = stack.first;
                  final selectedInStack =
                      selectedCard != null &&
                      stack.any((c) => c.instanceId == selectedCard!.instanceId);

                  // Signed slot: 0 at the hand's center, negative to
                  // the left, positive to the right - drives both angle
                  // and horizontal offset from the same value so they
                  // stay proportional to each other regardless of hand
                  // size. Uses the card's original index i (its actual
                  // fan position), not its position in paintOrder,
                  // since reordering for painting shouldn't move the
                  // card itself.
                  final slot = i - (n - 1) / 2;
                  final angleDegrees = slot * anglePerCard;
                  final xOffset = slot * clampedOverlapStep;
                  // Shallow parabolic drop (slot^2, not linear) so
                  // outer cards sit lower than the center one - without
                  // this, rotating a card around its own bottom-center
                  // pivot visually lifts its outer top corner higher
                  // than an unrotated card's top edge, making the two
                  // ends of the fan look taller than the middle instead
                  // of forming a proper downward arc like a real held
                  // hand. _dropPerSlotSquared tuned by eye.
                  final yDrop = slot * slot * _dropPerSlotSquared;

                  return Positioned(
                    left: centerX + xOffset - CardWidget.cardWidth / 2,
                    top: topInset + yDrop,
                    child: Transform.rotate(
                      angle: angleDegrees * (3.14159265 / 180),
                      alignment: Alignment.bottomCenter,
                      child: SizedBox(
                        width: CardWidget.cardWidth,
                        child: _HandCard(
                          card: card,
                          count: stack.length,
                          selected: selectedInStack,
                          disabled: isCardDisabled(card),
                          onTap: () => onTapCard(card, selectedInStack),
                          // Not shown here: a rotated per-card Discard
                          // button (like landscape's _HandCard uses)
                          // becomes illegible/overlapping once the
                          // whole card is tilted in the fan - discard
                          // moves to the bottom action bar instead, see
                          // _buildPortraitBoard's action row.
                          onDiscard: null,
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        );
      },
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

  // Standard luminance-weighted grayscale matrix (same family as the
  // armor icon's weakened/lost desaturation filters in armor_widget.dart)
  // - replaces a flat opacity fade for "not currently playable" cards.
  // A full-opacity fade made the card read as untappable/broken once
  // disabled cards became selectable again (for discard - see the
  // onTap comment below); desaturating keeps the card fully visible
  // and clearly interactive while still reading as "muted."
  static const _disabledFilter = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final def = cardDefFor(card);
    // Selection used to rely solely on the frame's glow shadow, which
    // reads poorly now that the frame itself is a busy pixel-art
    // border - a physical lift makes the selected card unambiguous
    // even before the glow registers.
    final animatedCard = AnimatedSlide(
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
            // onTap always fires, even when disabled - "disabled" means
            // "not currently playable" (defense card, no turn drawn
            // yet, etc.), shown via the grayscale filter below, but the
            // card still needs to be selectable so it can be
            // discarded. Landscape's per-card Discard TextButton
            // sidesteps this (it's a separate always-enabled widget,
            // not gated on selection at all), but portrait's fanned
            // hand removed that button in favor of routing discard
            // through the bottom action bar's selection-gated button
            // (see _buildPortraitBoard), which only works if a
            // disabled card can still be tapped to select it in the
            // first place.
            CardWidget(def: def, selected: selected, onTap: onTap),
            // Duplicate-card count badge - only shown when the player
            // actually holds more than one copy, per the groupedHand
            // collapsing in _MainBoardViewState.build. Hangs partially
            // off the card's top-right corner (like a wax seal) rather
            // than sitting inset - the surrounding FittedBox needed
            // clipBehavior: Clip.none (see that widget) for this
            // negative offset to actually paint instead of getting
            // clipped away.
            if (count > 1)
              Positioned(
                top: -6,
                right: -14,
                child: _CountBadge(count: count),
              ),
          ],
        ),
      ),
    );

    return Column(
      children: [
        // Grayscale, not a flat opacity fade - see _disabledFilter's
        // doc comment above for why. Only wraps the card art itself,
        // not the Discard button below, since that button is always
        // meant to read as clearly actionable regardless of the card's
        // playability.
        disabled ? ColorFiltered(colorFilter: _disabledFilter, child: animatedCard) : animatedCard,
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

/// Left panel: [turnPlayer]'s name and turn-status line above [player]'s
/// own armor as a single row of six full badges. The two differ in LAN
/// read-only spectating - the title still names whoever's turn it
/// actually is, but the armor/status below always belongs to the local
/// viewer ([player]), never whoever they're watching. In hotseat and
/// interactive LAN turns the two are the same player. This is the single
/// place turn/fasting/played-card status is shown - it used to be a footer
/// message repeated under the hand row - and, since the right-hand armor
/// grid panel was removed, the single place the local player's own armor
/// detail is shown at all.
///
/// No portrait image yet - the background is a plain placeholder fill so a
/// future full-panel character illustration can sit behind this text
/// without restructuring, rather than a separate circular avatar competing
/// with the armor row for the panel's limited height.
class _ActivePlayerPortraitPanel extends StatelessWidget {
  final PlayerState player;

  /// Whoever's turn it actually is - only used for the "Turn N - Active"
  /// title. In LAN read-only spectating, [player] is always the local
  /// viewer (their own armor stays "Your Armor" regardless of whose turn
  /// it is), so this can differ from [player] and needs its own name.
  final PlayerState turnPlayer;
  final GameState state;
  final bool selectable;
  final ArmorType? selectedArmor;
  final ValueChanged<ArmorType> onSelectArmor;
  final bool Function(ArmorCondition condition) isConditionSelectable;

  const _ActivePlayerPortraitPanel({
    required this.player,
    required this.turnPlayer,
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
              '${turnPlayer.name} - Turn ${state.turnNumber} - Active',
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
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Your Armor',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: ArmorUpColors.fontColor,
                ),
              ),
              if (player.isFullyRestored && state.restorationWinEnabled) ...[
                const SizedBox(width: 6),
                const _FullyArmoredMarker(size: 14),
              ],
            ],
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
/// [hiddenPlayerId] (the local/viewing player - they're never their own
/// opponent, and in read-only LAN spectating their armor isn't the one
/// shown in the portrait panel above anyway, so listing them there too
/// would be confusing rather than just redundant). Every remaining player
/// gets a compact armor-badge row and remains tap-to-target.
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
  final bool restorationWinEnabled;

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
    required this.restorationWinEnabled,
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
              fullyArmored: player.isFullyRestored && restorationWinEnabled,
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
  final bool fullyArmored;

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
    required this.fullyArmored,
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
            if (fullyArmored) ...[
              const SizedBox(width: 4),
              const _FullyArmoredMarker(size: 14),
            ],
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
