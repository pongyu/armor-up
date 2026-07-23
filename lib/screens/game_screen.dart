import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:game_engine/game_engine.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../state/app_mode_controller.dart';
import '../state/character_controller.dart';
import '../state/game_controller.dart';
import '../state/game_providers.dart';
import '../state/turn_actor.dart';
import '../theme/armor_up_colors.dart';
import '../widgets/armor_widget.dart';
import '../widgets/card_display.dart';
import '../widgets/card_widget.dart';
import '../widgets/event_log_widget.dart';
import '../widgets/pixel_ui.dart';
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
        _ResolutionBeatHost(
          state: state,
          viewerId: ref.watch(localPlayerIdProvider),
        ),
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
    // A bystander during a pending interrupt gets the calm "waiting for
    // X" status (Phase 4 Part 2) instead of the plain read-only board -
    // reads current pendingInterrupt/currentActorId state directly (not a
    // one-shot event), so a client that connects or reconnects mid-
    // interrupt renders the right waiting view immediately, and it
    // updates on its own as Fellowship passes from helper to helper
    // without any bystander action. Group discard bystanders are
    // out of scope for this phase and keep seeing the plain read-only
    // board, same as before.
    if (state.pendingInterrupt != null) {
      return _WaitingForResponseView(state: state, respondingPlayerId: actorId);
    }
    return _MainBoardView(actorId: localPlayerId, readOnly: true);
  }
}

/// Shown to every connected LAN client except whoever must currently
/// respond to the pending attack - a calm, informational "waiting for X"
/// status instead of the plain read-only board, so bystanders know who's
/// being asked without it looking like nothing is happening. Never
/// reveals hand contents or how likely a response is; only names the
/// attacker, defender, and (if a Fellowship request is open) which helper
/// is currently being asked.
class _WaitingForResponseView extends StatelessWidget {
  final GameState state;
  final String respondingPlayerId;

  const _WaitingForResponseView({required this.state, required this.respondingPlayerId});

  @override
  Widget build(BuildContext context) {
    final pending = state.pendingInterrupt!;
    final attacker = state.playerById(pending.attackerId);
    final defender = state.playerById(pending.defenderId);
    final responder = state.playerById(respondingPlayerId);
    final isHelperStep = respondingPlayerId != pending.defenderId;

    final message = isHelperStep
        ? 'Waiting for ${responder.name} to help ${defender.name}...'
        : '${attacker.name} attacked ${defender.name}\'s '
            '${pending.targetArmor.displayName}.\n'
            'Waiting for ${defender.name} to respond...';

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: ArmorUpColors.fontColor),
              ),
            ],
          ),
        ),
      ),
    );
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

/// One classified, displayable outcome of a defense-interrupt resolution
/// step - the shared "what just happened" beat described in Phase 4 Part
/// 3. Deliberately narrower than the raw event union: several event
/// combinations map to the same displayed beat (e.g. a system-timeout
/// decline followed by ArmorWeakened/ArmorLost both read as "ran out of
/// time - the attack landed", the wasHelper distinction is folded into
/// the message rather than becoming a separate outcome kind).
class _ResolutionBeat {
  final String text;

  /// Short uppercase outcome tag shown as a colored chip (HIT /
  /// BLOCKED / REFLECTED / TIME UP), mirroring the battle log's tag
  /// treatment so outcomes read consistently across the redesign.
  final String tag;
  final Color color;

  /// Hits named in [text] beyond the first (0 for every outcome except a
  /// multi-target HIT beat - see _classify) - used to scale how long the
  /// toast stays up so a long Jericho March summary is still readable.
  final int extraHits;

  const _ResolutionBeat(this.text, this.tag, this.color, {this.extraHits = 0});
}

/// Watches [state]'s event log for newly-appended interrupt-resolution
/// events (block/reflect/land, with or without a timeout) and shows a
/// brief, shared, non-blocking beat naming the outcome - visible to every
/// connected client in LAN (each syncs the same event log) or on the one
/// shared screen in hotseat. Same length-diffing/auto-dismiss-Timer shape
/// as [_RestorationImminentBannerHost] (see that class's doc comment for
/// why length-based, not level-based) - deliberately not merged with it
/// into one host, since the two watch disjoint event types and showing
/// both from a single generic "any new event" host would make an
/// unrelated announcement dismiss this one's timer or vice versa.
///
/// Does not itself animate the affected armor slot - [ArmorRow]/
/// [ArmorBadge] already do that automatically from the same state change
/// (their own `didUpdateWidget` condition diff), for any of them that
/// happen to be mounted when the state updates. This host only supplies
/// the outcome text.
class _ResolutionBeatHost extends StatefulWidget {
  final GameState state;

  /// This device's own player id in LAN mode, so a beat naming a hit on
  /// this exact player can read "Your X" instead of "PlayerName's X".
  /// Null in hotseat mode, where the device is passed around and there is
  /// no single "you" - every beat there stays third-person, matching the
  /// rest of hotseat's shared-screen phrasing (see [localPlayerIdProvider]).
  final String? viewerId;

  const _ResolutionBeatHost({required this.state, required this.viewerId});

  @override
  State<_ResolutionBeatHost> createState() => _ResolutionBeatHostState();
}

class _ResolutionBeatHostState extends State<_ResolutionBeatHost> {
  int _lastSeenEventCount = 0;
  _ResolutionBeat? _activeBeat;
  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();
    // Same "don't replay history on mount/resume" rule as
    // _RestorationImminentBannerHostState.
    _lastSeenEventCount = widget.state.eventLog.length;
  }

  @override
  void didUpdateWidget(covariant _ResolutionBeatHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final events = widget.state.eventLog;
    if (events.length > _lastSeenEventCount) {
      final newEvents = events.sublist(_lastSeenEventCount);
      final beat = _classify(newEvents, widget.state, widget.viewerId);
      if (beat != null) {
        _autoDismissTimer?.cancel();
        setState(() => _activeBeat = beat);
        // Base 2.5s, +600ms per extra named hit beyond the first (Jericho
        // March can land on several players at once - see _classify) so a
        // long multi-hit summary doesn't vanish before it can be read.
        final duration = Duration(milliseconds: 2500 + (beat.extraHits * 600));
        _autoDismissTimer = Timer(duration, _dismiss);
      }
    }
    _lastSeenEventCount = events.length;
  }

  /// Picks the single most relevant beat out of a batch of newly-appended
  /// events. A landed attack always appends ArmorWeakened/ArmorLost
  /// (optionally preceded by DefenseTimedOut in the same batch, when a
  /// system decline is what caused it to land) - checked first so a
  /// timed-out landing gets the "ran out of time" wording instead of the
  /// plain block/reflect checks below matching nothing and falling
  /// through to no beat at all. AttackBlocked and AttackReflected are
  /// each a complete batch on their own (see effects.dart's
  /// resolveDefense - reflection that doesn't immediately re-land is
  /// *not* accompanied by a damage event in the same batch, since the new
  /// defender still has to respond in turn).
  _ResolutionBeat? _classify(List<GameEvent> newEvents, GameState state, String? viewerId) {
    String nameOf(String playerId) => state.playerById(playerId).name;
    // "Your" when the affected player is this device's own player (LAN
    // only - viewerId is always null in hotseat, where the device is
    // passed around and no single player is "you"), else the normal
    // possessive name.
    String possessiveOf(String playerId) =>
        playerId == viewerId ? 'Your' : '${nameOf(playerId)}\'s';

    final timedOut = newEvents.whereType<DefenseTimedOut>().firstOrNull;
    final weakenedEvents = newEvents.whereType<ArmorWeakened>().toList();
    final lostEvents = newEvents.whereType<ArmorLost>().toList();
    if (weakenedEvents.isNotEmpty || lostEvents.isNotEmpty) {
      final prefix = timedOut != null
          ? '${timedOut.playerId == viewerId ? 'You' : nameOf(timedOut.playerId)} '
              'ran out of time - the attack landed. '
          : '';
      // A single-target attack always appends exactly one of these, but a
      // table-wide event card (Jericho March) can append one per player
      // whose piece was hit in the same batch - every one of them must be
      // named, not just the first, or the toast silently drops everyone
      // else's damage.
      final hits = [
        for (final e in weakenedEvents) (playerId: e.playerId, armor: e.armor, lost: false),
        for (final e in lostEvents) (playerId: e.playerId, armor: e.armor, lost: true),
      ];
      final summary = hits.length == 1
          ? '${possessiveOf(hits.single.playerId)} ${hits.single.armor.displayName} was '
              '${hits.single.lost ? 'lost' : 'weakened'}.'
          : hits
              .map((h) => '${possessiveOf(h.playerId)} ${h.armor.displayName} '
                  '${h.lost ? 'lost' : 'weakened'}')
              .join(', ');
      return _ResolutionBeat(
        '$prefix$summary',
        timedOut != null ? 'TIME UP' : 'HIT',
        ArmorUpColors.bannerAttack,
        extraHits: hits.length - 1,
      );
    }

    final blocked = newEvents.whereType<AttackBlocked>().firstOrNull;
    if (blocked != null) {
      return _ResolutionBeat(
        '${cardDefById(blocked.byCardDefId).name} blocked the attack!',
        'BLOCKED',
        ArmorUpColors.bannerDefense,
      );
    }

    final reflected = newEvents.whereType<AttackReflected>().firstOrNull;
    if (reflected != null) {
      final newDefender = reflected.newDefenderId == viewerId
          ? 'you'
          : nameOf(reflected.newDefenderId);
      return _ResolutionBeat(
        '${cardDefById(reflected.attackCardDefId).name}! Attack reflected to '
        '$newDefender!',
        'REFLECTED',
        ArmorUpColors.goldAccent,
      );
    }

    return null;
  }

  void _dismiss() {
    _autoDismissTimer?.cancel();
    _autoDismissTimer = null;
    if (mounted) setState(() => _activeBeat = null);
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final beat = _activeBeat;
    if (beat == null) return const SizedBox.shrink();

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        // Purely informational - never blocks taps on the board beneath
        // it, and requires no tap to dismiss (auto-clears via the timer
        // above), per the spec's "non-blocking past its duration" and
        // this app's existing convention (no tap-to-continue pattern
        // exists elsewhere for a transient beat like this - the closest
        // precedent, _RestorationImminentBanner, is tap-*dismissible* but
        // never tap-*required*, which this matches).
        // Material ancestor is required here: this overlay lives in a
        // Stack ABOVE the Scaffold, and Text without a Material falls
        // back to the framework's yellow double-underline error style
        // (which is exactly how this toast used to render).
        child: Material(
          type: MaterialType.transparency,
          child: Align(
            alignment: const Alignment(0, -0.5),
            child: TweenAnimationBuilder<double>(
              // Slide-down + fade entrance, matching the template's
              // pxSlideDown resolution banner.
              tween: Tween(begin: 0, end: 1),
              duration: MediaQuery.of(context).disableAnimations
                  ? Duration.zero
                  : const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              builder: (context, t, child) => Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, (1 - t) * -14),
                  child: child,
                ),
              ),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: ArmorUpColors.panelBackground.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: beat.color, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: beat.color.withValues(alpha: 0.35),
                      blurRadius: 14,
                    ),
                    const BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: beat.color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        beat.tag,
                        style: const TextStyle(
                          fontSize: 7,
                          letterSpacing: 0.5,
                          color: ArmorUpColors.boardBackground,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        beat.text,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          fontFamily: 'Roboto',
                          fontWeight: FontWeight.w600,
                          color: ArmorUpColors.fontColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
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

  // Portrait "CHOOSE A TARGET" overlay (redesign template): set to the
  // selected card's def when Play is pressed on an opponent-targeting
  // card, cleared on pick/cancel. Landscape keeps its inline
  // tap-the-row targeting and never sets this.
  CardDef? _targetingDef;

  // The target just tapped in the overlay, held for a brief
  // confirmation beat (picked badge glows + shakes, everything else
  // dims) before the card actually plays - without it the overlay
  // vanished the instant a target was tapped and the pick never felt
  // registered. Non-null only during that beat; further taps and
  // Cancel are ignored while set.
  ({String playerId, ArmorType? armor})? _pendingPick;
  Timer? _pickTimer;

  @override
  void dispose() {
    _pickTimer?.cancel();
    super.dispose();
  }

  // Every hand instanceId seen across all builds so far, used to detect
  // which card(s) are brand new this build (just drawn) so _HandCard can
  // play a one-shot deal-in animation for exactly those - a duplicate
  // card's stack widget is keyed on its *first* instance (stable across a
  // later draw of the same defId, see the groupedHand comment below), so
  // "this _HandCard widget was just created" alone can't detect a newly
  // drawn duplicate the way it can a brand new defId. Accumulates rather
  // than just diffing the previous build's hand against this one, since a
  // discard/play removing a card and a draw both changing hand size in the
  // same build could otherwise mask a genuinely new instanceId.
  final Set<String> _seenCardInstanceIds = {};
  // False until the first build has run once - guards against treating
  // every card already in hand as "just drawn" the moment this widget
  // mounts (e.g. every turn in hotseat mode, where the pass-device gate
  // tears down and recreates this whole subtree - see the pass-device
  // routing in _GameScreenState). Only draws that happen while the board
  // is already showing should deal in.
  bool _hasBuiltOnce = false;

  void _resetSelection() {
    _pickTimer?.cancel();
    setState(() {
      _selectedCard = null;
      _selectedTargetPlayerId = null;
      _selectedTargetArmor = null;
      _targetingDef = null;
      _pendingPick = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gameStateProvider)!;
    final controller = ref.read(activeGameControllerProvider);
    final me = state.playerById(widget.actorId);
    final def = _selectedCard == null ? null : cardDefFor(_selectedCard!);

    // Diff this build's hand against every instanceId seen so far - any
    // instanceId not already in _seenCardInstanceIds was just drawn.
    // Passed down as `justDrawn` so _HandCard can play its deal-in
    // animation only for the actual new arrival(s), not for every card
    // whenever the hand happens to rebuild (selection, discard, etc.).
    final justDrawnIds = <String>{
      if (_hasBuiltOnce)
        for (final card in me.hand)
          if (!_seenCardInstanceIds.contains(card.instanceId)) card.instanceId,
    };
    _seenCardInstanceIds.addAll(me.hand.map((c) => c.instanceId));
    _hasBuiltOnce = true;

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
                      justDrawnIds,
                    );
                  }
                  return _buildLandscapeBoard(
                    state,
                    me,
                    def,
                    controller,
                    canPlaySelection,
                    constraints,
                    justDrawnIds,
                  );
                },
              ),
              // Reachable any time during play, not just for a brand new
              // player - card games regularly need a rules lookup mid-game
              // (e.g. "what does Weakened mean again"). Landscape only:
              // the portrait redesign carries the same button inline in
              // its header row instead.
              if (MediaQuery.of(context).orientation == Orientation.landscape)
                const Positioned(
                  top: 4,
                  right: 4,
                  child: Column(
                    children: [
                      _RulesButton(),
                      SizedBox(height: 8),
                      _QuitButton(),
                    ],
                  ),
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
    Set<String> justDrawnIds,
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

    // Portrait "Play card" gating differs from landscape's
    // canPlaySelection: opponent targets are no longer picked inline
    // before pressing Play - pressing Play on an opponent-targeting
    // card opens the CHOOSE A TARGET overlay instead (redesign
    // template), so only own-armor cards still require a completed
    // selection up front.
    final canPlayPortrait =
        !widget.readOnly &&
        state.hasDrawnThisTurn &&
        !state.hasPlayedCardThisTurn &&
        def != null &&
        def.type != CardType.defense &&
        (def.targetRule != TargetRule.ownArmorPiece ||
            _selectedTargetArmor != null);

    final board = Column(
      children: [
        // Header: pixel avatar + "NAME - TURN N" + pulsing status line,
        // with the rules "?" button inline at the right edge.
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              PixelAvatar(
                seed: avatarSeedFor(me.id),
                palette: ref.watch(characterControllerProvider).palette,
                size: 34,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          Text(
                            state.activePlayer.name.toUpperCase(),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: ArmorUpColors.fontColor,
                              shadows: ArmorUpColors.titleOutline,
                            ),
                            maxLines: 1,
                          ),
                          Text(
                            ' - TURN ${state.turnNumber}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: ArmorUpColors.goldAccent,
                            ),
                            maxLines: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        PulsingDot(
                          color: widget.readOnly
                              ? ArmorUpColors.mutedLabel
                              : ArmorUpColors.activeGreen,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            widget.readOnly
                                ? 'WATCHING - NOT YOUR TURN'
                                : 'ACTIVE - ${statusLine.toUpperCase()}',
                            style: const TextStyle(
                              fontSize: 8.5,
                              letterSpacing: 0.5,
                              color: ArmorUpColors.mutedLabel,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const _RulesButton(),
              const SizedBox(width: 8),
              const _QuitButton(),
            ],
          ),
        ),
        // Turn-order threat tracker: the same opponent chips, but
        // ordered by who acts next (starting from the player after the
        // current one), with a PLAYING/NEXT tag and a strong-pieces
        // count so the strip answers "who's about to move and who's
        // close to winning", not just armor colors. Targeting itself
        // still happens in the overlay.
        Builder(
          builder: (context) {
            final allPlayers = state.players;
            final activeIdx = allPlayers
                .indexWhere((p) => p.id == state.activePlayer.id);
            // Everyone in the order they act after the active player;
            // the active player themselves lands at the end.
            final turnOrdered = [
              for (var i = 1; i <= allPlayers.length; i++)
                allPlayers[(activeIdx + i) % allPlayers.length],
            ];
            final nextActor =
                turnOrdered.firstWhere((p) => !p.isEliminated);
            // Chips lead with whoever is playing right now (only
            // visible when spectating - in hotseat that's the viewer,
            // who never appears in their own strip), then upcoming
            // players in act order.
            final chipPlayers = [
              if (state.activePlayer.id != widget.actorId)
                state.activePlayer,
              for (final p in turnOrdered)
                if (p.id != widget.actorId &&
                    p.id != state.activePlayer.id)
                  p,
            ];

            return Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 0, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'OPPONENTS - TURN ORDER',
                    style: TextStyle(
                      fontSize: 8,
                      letterSpacing: 1,
                      color: ArmorUpColors.mutedLabel,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 64,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(right: 14),
                      children: [
                        for (final opp in chipPlayers)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _OpponentChip(
                              player: opp,
                              fullyArmored: opp.isFullyRestored &&
                                  state.restorationWinEnabled,
                              isPlaying:
                                  opp.id == state.activePlayer.id,
                              isNext: opp.id == nextActor.id &&
                                  opp.id != state.activePlayer.id,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        // Battle log: the redesign's center panel. Takes whatever
        // vertical space is left between the fixed-height sections.
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: _BattleLogPanel(state: state),
          ),
        ),
        // "YOUR ARMOR" - full-size badges with the redesign's tiny
        // per-piece labels underneath.
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'YOUR ARMOR',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      letterSpacing: 1,
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
              Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: ArmorRow(
                    player: me,
                    selectable: armorSelectable,
                    selectedArmor: _selectedTargetArmor,
                    showLabels: true,
                    onSelect: (armor) =>
                        setState(() => _selectedTargetArmor = armor),
                    isConditionSelectable: def == null
                        ? defaultIsConditionSelectable
                        : (condition) => _isConditionSelectable(def, condition),
                  ),
                ),
              ),
            ],
          ),
        ),
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
            justDrawnIds: justDrawnIds,
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
        // Action bar: DRAW | PLAY CARD | END TURN/DISCARD, in the
        // redesign's flat-dark + gold-primary button style. Same
        // semantics as before (including the over-hand-limit discard
        // takeover of the third button - see the mustDiscardSelected
        // logic), only the chrome changed.
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
          child: Row(
            children: [
              Expanded(
                flex: 10,
                child: PixelActionButton(
                  label: 'DRAW',
                  onPressed: !widget.readOnly && !state.hasDrawnThisTurn
                      ? () => controller.dispatch(
                          DrawCard(playerId: widget.actorId),
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 13,
                child: PixelActionButton(
                  label: 'PLAY CARD',
                  primary: true,
                  onPressed: canPlayPortrait
                      ? () {
                          // Opponent-targeting cards open the CHOOSE A
                          // TARGET overlay; everything else plays
                          // immediately with whatever (own-armor)
                          // target is already selected.
                          if (_targetRuleNeedsPlayer(def.targetRule)) {
                            setState(() => _targetingDef = def);
                          } else {
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
                        }
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 10,
                child: Builder(
                  builder: (context) {
                    final overLimit = me.hand.length > maxHandSize;
                    final mustDiscardSelected =
                        overLimit && _selectedCard != null;

                    return PixelActionButton(
                      label: mustDiscardSelected
                          ? 'DISCARD'
                          : overLimit
                          ? 'DISCARD FIRST'
                          : 'END TURN',
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
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'DRAW PILE: ${state.drawPile.length}    DISCARD: ${state.discardPile.length}',
            style: const TextStyle(
              fontSize: 8.5,
              letterSpacing: 0.5,
              color: ArmorUpColors.mutedLabel,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );

    final targetingDef = _targetingDef;
    return Stack(
      children: [
        board,
        if (targetingDef != null && _selectedCard != null)
          Positioned.fill(
            child: _TargetingOverlay(
              def: targetingDef,
              opponents: [
                for (final p in state.players)
                  if (p.id != widget.actorId && !p.isEliminated) p,
              ],
              isConditionSelectable: (condition) =>
                  _isConditionSelectable(targetingDef, condition),
              resolving: _pendingPick,
              selectedPlayerId: _selectedTargetPlayerId,
              selectedArmor: _selectedTargetArmor,
              // Tap = select (freely re-tappable to change targets);
              // only CONFIRM below commits, so a mis-tap on a Fiery
              // Dart badge can still be changed.
              onSelect: (playerId, armor) {
                if (_pendingPick != null) return;
                setState(() {
                  _selectedTargetPlayerId = playerId;
                  _selectedTargetArmor = armor;
                });
              },
              onConfirm: _pendingPick == null &&
                      _selectedTargetPlayerId != null &&
                      (targetingDef.targetRule !=
                              TargetRule.anyPieceOnPlayer ||
                          _selectedTargetArmor != null)
                  ? () {
                      final playerId = _selectedTargetPlayerId!;
                      final armor = _selectedTargetArmor;
                      setState(
                        () => _pendingPick =
                            (playerId: playerId, armor: armor),
                      );
                      // Confirmation beat: let the picked target
                      // register (glow + shake, others dimmed) before
                      // the card resolves and the overlay closes.
                      _pickTimer =
                          Timer(const Duration(milliseconds: 550), () {
                        if (!mounted) return;
                        controller.dispatch(
                          PlayCard(
                            playerId: widget.actorId,
                            cardInstanceId: _selectedCard!.instanceId,
                            targetPlayerId: playerId,
                            targetArmor: armor,
                          ),
                        );
                        _resetSelection();
                      });
                    }
                  : null,
              onCancel: _pendingPick != null
                  ? null
                  : () => setState(() {
                        _targetingDef = null;
                        _selectedTargetPlayerId = null;
                        _selectedTargetArmor = null;
                      }),
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
    Set<String> justDrawnIds,
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
                                                  justDrawn: justDrawnIds
                                                      .contains(card.instanceId),
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
    // Redesign template: a gold-ringed "?" coin over the dark card
    // surface, replacing the old translucent Material icon button.
    return Material(
      color: ArmorUpColors.cardBackground,
      shape: const CircleBorder(
        side: BorderSide(color: ArmorUpColors.goldAccent, width: 2),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => showRulesSheet(context),
        child: const SizedBox(
          width: 34,
          height: 34,
          child: Center(
            child: Text(
              '?',
              style: TextStyle(
                fontSize: 14,
                color: ArmorUpColors.goldAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Same gold-ringed coin treatment as [_RulesButton], sat right beside it,
/// so quitting reads as one of this pair of board-level actions rather
/// than a random floating icon. A [ConsumerWidget] (not stateless) since
/// it needs `ref` to read the current [AppMode] and dispatch the actual
/// teardown once the player confirms.
class _QuitButton extends ConsumerWidget {
  const _QuitButton();

  Future<void> _confirmQuit(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quit game?'),
        content: const Text(
          'This will end the game for everyone and return to the start screen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Quit'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final mode = ref.read(appModeControllerProvider).mode;
    if (mode == AppMode.netPlaying) {
      await ref.read(appModeControllerProvider.notifier).returnToModeSelect();
    } else {
      ref.read(gameControllerProvider.notifier).endGame();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: ArmorUpColors.cardBackground,
      shape: const CircleBorder(
        side: BorderSide(color: ArmorUpColors.goldAccent, width: 2),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _confirmQuit(context, ref),
        child: const SizedBox(
          width: 34,
          height: 34,
          child: Center(
            child: Icon(Icons.close, size: 16, color: ArmorUpColors.goldAccent),
          ),
        ),
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
  final Set<String> justDrawnIds;

  const _FannedHand({
    required this.stacks,
    required this.selectedCard,
    required this.isCardDisabled,
    required this.onTapCard,
    this.justDrawnIds = const {},
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
                          justDrawn: justDrawnIds.contains(card.instanceId),
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

class _HandCard extends StatefulWidget {
  final CardInstance card;
  final int count;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;
  final VoidCallback? onDiscard;

  /// True the first time this exact card instance is rendered after being
  /// drawn (see _MainBoardViewState's justDrawnIds diff) - plays a one-shot
  /// "deal in" entrance on mount. False for every other render of the same
  /// instance (selection, disabling, re-layout), so the entrance never
  /// replays after its first play.
  final bool justDrawn;

  const _HandCard({
    required this.card,
    required this.count,
    required this.selected,
    required this.disabled,
    required this.onTap,
    required this.onDiscard,
    this.justDrawn = false,
  });

  @override
  State<_HandCard> createState() => _HandCardState();
}

class _HandCardState extends State<_HandCard> with SingleTickerProviderStateMixin {
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

  late final AnimationController _dealController;

  @override
  void initState() {
    super.initState();
    _dealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    final reduceMotion = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    if (widget.justDrawn && !reduceMotion) {
      _dealController.forward();
    } else {
      _dealController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _dealController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final count = widget.count;
    final selected = widget.selected;
    final disabled = widget.disabled;
    final onTap = widget.onTap;
    final onDiscard = widget.onDiscard;
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

    final column = Column(
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

    // Deal-in: rises up from below its resting slot while scaling up from
    // small and fading in, like the card is being dealt into the hand.
    // Curves.easeOutBack overshoots slightly past scale 1.0 before
    // settling, giving it a touch of the same "pop" the win screen's
    // entrance uses, rather than a flat linear grow.
    return AnimatedBuilder(
      animation: _dealController,
      builder: (context, child) {
        final t = Curves.easeOutBack.transform(_dealController.value);
        final linearT = _dealController.value;
        return Opacity(
          opacity: linearT.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - linearT) * 28),
            child: Transform.scale(scale: 0.6 + 0.4 * t, child: child),
          ),
        );
      },
      child: column,
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

/// Compact opponent chip for the portrait board's turn-order threat
/// tracker: pixel avatar + name (with a PLAYING/NEXT tag when
/// applicable) on top, six condition-colored armor squares plus a
/// strong-pieces count below. Purely informational - target picking
/// happens in [_TargetingOverlay], not here.
class _OpponentChip extends StatelessWidget {
  final PlayerState player;
  final bool fullyArmored;

  /// This chip's player is the one acting right now - only ever true
  /// while spectating (LAN read-only), since in hotseat the active
  /// player is the viewer and never appears in their own strip.
  final bool isPlaying;

  /// This chip's player is the next (non-eliminated) player to act.
  final bool isNext;

  const _OpponentChip({
    required this.player,
    required this.fullyArmored,
    this.isPlaying = false,
    this.isNext = false,
  });

  @override
  Widget build(BuildContext context) {
    final strongCount =
        player.armor.where((p) => p.condition == ArmorCondition.strong).length;
    // Fully-armored (restoration-imminent) is the loudest threat signal
    // the strip carries - the whole chip goes gold-bordered, on top of
    // the trophy marker next to the name.
    final borderColor = fullyArmored
        ? ArmorUpColors.goldAccent
        : ArmorUpColors.descriptionBackground;

    return Container(
      constraints: const BoxConstraints(minWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: ArmorUpColors.panelBackground,
        border: Border.all(
          color: borderColor,
          width: fullyArmored ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: fullyArmored
            ? [
                BoxShadow(
                  color: ArmorUpColors.goldAccent.withValues(alpha: 0.35),
                  blurRadius: 8,
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PixelAvatar(
                seed: avatarSeedFor(player.id),
                size: 20,
                borderColor: ArmorUpColors.descriptionBackground,
                borderWidth: 1,
              ),
              const SizedBox(width: 6),
              Text(
                player.name.toUpperCase(),
                style: const TextStyle(
                  fontSize: 8.5,
                  color: ArmorUpColors.fontColor,
                ),
                maxLines: 1,
              ),
              if (fullyArmored) ...[
                const SizedBox(width: 4),
                const _FullyArmoredMarker(size: 12),
              ],
              if (isPlaying)
                const _ChipTag(
                  label: 'PLAYING',
                  color: ArmorUpColors.activeGreen,
                )
              else if (isNext)
                const _ChipTag(
                  label: 'NEXT',
                  color: ArmorUpColors.goldAccent,
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (player.isEliminated)
            const Text(
              'ELIMINATED',
              style: TextStyle(
                fontSize: 7,
                letterSpacing: 0.5,
                color: ArmorUpColors.mutedLabel,
              ),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final piece in player.armor)
                  Padding(
                    padding: const EdgeInsets.only(right: 3),
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: colorForCondition(piece.condition),
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: [
                          BoxShadow(
                            color: colorForCondition(piece.condition)
                                .withValues(alpha: 0.6),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(width: 3),
                Text(
                  '$strongCount/${player.armor.length}',
                  style: TextStyle(
                    fontSize: 7,
                    color: strongCount == player.armor.length
                        ? ArmorUpColors.goldAccent
                        : ArmorUpColors.mutedLabel,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Plays a quick one-shot horizontal shake when first mounted - the
/// "hit registered" jolt on the picked target panel during the
/// targeting overlay's confirmation beat. Same sharp decaying wobble as
/// [_ArmorBadgeState]'s damage shake; holds still under reduce-motion
/// (the red border/TARGETED! tag carry the feedback instead).
class _ShakeOnMount extends StatefulWidget {
  final Widget child;

  const _ShakeOnMount({required this.child});

  @override
  State<_ShakeOnMount> createState() => _ShakeOnMountState();
}

class _ShakeOnMountState extends State<_ShakeOnMount>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    final reduceMotion = WidgetsBinding
        .instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    if (!reduceMotion) _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final shake = t <= 0 || t >= 1
            ? 0.0
            : math.sin(t * math.pi * 4) * (1 - t) * 5;
        return Transform.translate(offset: Offset(shake, 0), child: child);
      },
      child: widget.child,
    );
  }
}

/// Tiny uppercase status tag on an opponent chip (PLAYING / NEXT).
class _ChipTag extends StatelessWidget {
  final String label;
  final Color color;

  const _ChipTag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 6,
            letterSpacing: 0.5,
            color: ArmorUpColors.boardBackground,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/// The redesign's BATTLE LOG panel: recent noteworthy events, each with
/// a colored type tag (ATK/DEF/FIX/EVT), over a faint shield watermark.
/// Reuses [describeEvent] for the sentence itself; only the chrome and
/// the tag classification live here.
class _BattleLogPanel extends StatelessWidget {
  final GameState state;

  const _BattleLogPanel({required this.state});

  /// Events too noisy for a 3-5 line glanceable log (every draw/discard)
  /// are skipped; everything else gets a tag.
  (String, Color)? _tagFor(GameEvent event) {
    switch (event) {
      case CardDrawn():
      case CardDiscarded():
      // RestorationImminent already gets the full-width gold banner
      // (and the persistent trophy marker) - repeating its shouty
      // sentence in the log would double-announce it.
      case RestorationImminent():
        return null;
      case ArmorWeakened():
      case ArmorLost():
      case CardStolen():
      case CardStolenRedacted():
      case PlayerEliminated():
        return ('ATK', ArmorUpColors.bannerAttack);
      case AttackBlocked():
      case AttackReflected():
      case DefenseTimedOut():
        return ('DEF', ArmorUpColors.bannerDefense);
      case ArmorRestored():
        return ('FIX', ArmorUpColors.bannerRestore);
      case CardPlayed(:final cardDefId):
        final type = cardDefById(cardDefId).type;
        return switch (type) {
          CardType.attack => ('ATK', ArmorUpColors.bannerAttack),
          CardType.defense => ('DEF', ArmorUpColors.bannerDefense),
          CardType.restore => ('FIX', ArmorUpColors.bannerRestore),
          _ => ('EVT', ArmorUpColors.bannerEvent),
        };
      case GameEnded():
        return ('WIN', ArmorUpColors.goldAccent);
      default:
        return ('EVT', ArmorUpColors.bannerEvent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = <(String, Color, String)>[];
    for (final event in state.eventLog.reversed) {
      final tag = _tagFor(event);
      if (tag == null) continue;
      entries.add((tag.$1, tag.$2, describeEvent(event, state)));
      if (entries.length >= 12) break;
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            ArmorUpColors.descriptionBackground.withValues(alpha: 0.35),
            ArmorUpColors.boardBackground.withValues(alpha: 0.5),
          ],
        ),
        border: Border.all(color: ArmorUpColors.panelBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Stack(
        children: [
          Center(
            child: Opacity(
              opacity: 0.05,
              child: Image.asset(
                'assets/armor/shield.png',
                width: 120,
                filterQuality: FilterQuality.none,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'BATTLE LOG',
                style: TextStyle(
                  fontSize: 8,
                  letterSpacing: 1,
                  color: ArmorUpColors.mutedLabel,
                ),
              ),
              const SizedBox(height: 7),
              Expanded(
                child: entries.isEmpty
                    ? const SizedBox.shrink()
                    : ListView.builder(
                        // Most recent entry pinned at the top, like the
                        // template's mock; older entries scroll below.
                        padding: EdgeInsets.zero,
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final (tag, color, text) = entries[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 7),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    tag,
                                    style: const TextStyle(
                                      fontSize: 6.5,
                                      color: ArmorUpColors.boardBackground,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    text,
                                    style: TextStyle(
                                      fontSize: 11,
                                      height: 1.4,
                                      // Readable sans body text like the
                                      // template's log copy - the pixel
                                      // font stays on labels/tags only.
                                      fontFamily: 'Roboto',
                                      color: const Color(0xFFC9CBD4),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Full-board "CHOOSE A TARGET" overlay (redesign template): shown when
/// Play is pressed on an opponent-targeting card. Tapping an opponent's
/// panel (player-only rules) or an exact armor badge (anyPieceOnPlayer
/// rules) only SELECTS the target - freely re-tappable to change your
/// mind - and CONFIRM is what actually commits the attack. Cancel
/// returns to the board with the card still selected.
class _TargetingOverlay extends StatelessWidget {
  final CardDef def;
  final List<PlayerState> opponents;
  final bool Function(ArmorCondition condition) isConditionSelectable;

  /// The currently selected (not yet confirmed) target.
  final String? selectedPlayerId;
  final ArmorType? selectedArmor;

  /// Tap handler for panels/badges - selection only, never commits.
  final void Function(String playerId, ArmorType? armor) onSelect;

  /// Commits the selected target. Null while nothing (complete) is
  /// selected or the confirmation beat is running - the CONFIRM button
  /// disables itself accordingly.
  final VoidCallback? onConfirm;

  /// Null while the confirmation beat is running - Cancel is disabled
  /// so the pick can't be backed out of mid-resolve.
  final VoidCallback? onCancel;

  /// The target currently in its confirmation beat (see
  /// [_MainBoardViewState._pendingPick]): that player's panel shakes
  /// and goes attack-red while every other panel dims, so the tap
  /// visibly registers before the overlay closes.
  final ({String playerId, ArmorType? armor})? resolving;

  const _TargetingOverlay({
    required this.def,
    required this.opponents,
    required this.isConditionSelectable,
    required this.selectedPlayerId,
    required this.selectedArmor,
    required this.onSelect,
    required this.onConfirm,
    required this.onCancel,
    this.resolving,
  });

  @override
  Widget build(BuildContext context) {
    final needsArmorPick = def.targetRule == TargetRule.anyPieceOnPlayer;

    return Container(
      color: const Color(0xE605060A),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'CHOOSE A TARGET',
            style: TextStyle(
              fontSize: 13,
              color: ArmorUpColors.fontColor,
              shadows: ArmorUpColors.titleOutline,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'PLAYING: ${def.name.toUpperCase()}',
            style: const TextStyle(
              fontSize: 9.5,
              color: ArmorUpColors.goldAccent,
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: ListView(
              children: [
                for (final opp in opponents)
                  Builder(
                    builder: (context) {
                      final isPicked = resolving?.playerId == opp.id;
                      final dimmed = resolving != null && !isPicked;
                      final isSelected =
                          resolving == null && selectedPlayerId == opp.id;

                      // Border/glow priority: confirming (attack red)
                      // beats selected (gold) beats idle.
                      final borderColor = isPicked
                          ? ArmorUpColors.bannerAttack
                          : isSelected
                              ? ArmorUpColors.goldAccent
                              : ArmorUpColors.descriptionBackground;
                      final glowColor = isPicked
                          ? ArmorUpColors.bannerAttack
                          : isSelected
                              ? ArmorUpColors.goldAccent
                              : null;

                      Widget panel = Material(
                        color: ArmorUpColors.panelBackground,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: needsArmorPick || resolving != null
                              ? null
                              : () => onSelect(opp.id, null),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: borderColor,
                                width: isPicked || isSelected ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: glowColor != null
                                  ? [
                                      BoxShadow(
                                        color: glowColor.withValues(
                                          alpha: isPicked ? 0.5 : 0.35,
                                        ),
                                        blurRadius: 14,
                                      ),
                                    ]
                                  : null,
                            ),
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    PixelAvatar(
                                      seed: avatarSeedFor(opp.id),
                                      size: 24,
                                      borderColor:
                                          ArmorUpColors.descriptionBackground,
                                      borderWidth: 1,
                                    ),
                                    const SizedBox(width: 7),
                                    Expanded(
                                      child: Text(
                                        opp.name.toUpperCase(),
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: ArmorUpColors.fontColor,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isPicked)
                                      const Text(
                                        'TARGETED!',
                                        style: TextStyle(
                                          fontSize: 7,
                                          letterSpacing: 0.5,
                                          color: ArmorUpColors.bannerAttack,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      )
                                    else if (isSelected)
                                      const Text(
                                        'SELECTED',
                                        style: TextStyle(
                                          fontSize: 7,
                                          letterSpacing: 0.5,
                                          color: ArmorUpColors.goldAccent,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      )
                                    else if (!needsArmorPick)
                                      const Text(
                                        'TAP TO TARGET',
                                        style: TextStyle(
                                          fontSize: 7,
                                          letterSpacing: 0.5,
                                          color: ArmorUpColors.mutedLabel,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: ArmorRow(
                                    player: opp,
                                    selectable: needsArmorPick,
                                    // The tapped badge keeps its
                                    // stronger selected glow/border
                                    // while selected AND through the
                                    // confirmation beat.
                                    selectedArmor: isPicked
                                        ? resolving!.armor
                                        : isSelected
                                            ? selectedArmor
                                            : null,
                                    onSelect: needsArmorPick
                                        ? (armor) {
                                            if (resolving == null) {
                                              onSelect(opp.id, armor);
                                            }
                                          }
                                        : null,
                                    isConditionSelectable:
                                        isConditionSelectable,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );

                      if (isPicked) {
                        panel = _ShakeOnMount(child: panel);
                      } else if (dimmed) {
                        panel = Opacity(opacity: 0.35, child: panel);
                      }

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: panel,
                      );
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                flex: 10,
                child: OutlinedButton(
                  onPressed: onCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ArmorUpColors.mutedLabel,
                    side: const BorderSide(
                      color: ArmorUpColors.descriptionBackground,
                      width: 2,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child:
                      const Text('CANCEL', style: TextStyle(fontSize: 10)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 13,
                child: GoldPillButton(
                  label: 'CONFIRM',
                  fontSize: 10,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  onPressed: onConfirm,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
