part of 'game_screen.dart';

/// Shown to whoever must respond to the current [PendingAttack]: the
/// defender, or (while a Fellowship request is open) the next
/// undecided helper. Offers their defense cards plus a Decline option.
class _DefensePromptView extends ConsumerStatefulWidget {
  final String actorId;

  const _DefensePromptView({required this.actorId});

  @override
  ConsumerState<_DefensePromptView> createState() => _DefensePromptViewState();
}

class _DefensePromptViewState extends ConsumerState<_DefensePromptView> {
  /// True for a brief moment right as this responder's own countdown
  /// hits zero (see [_ResponseCountdownBar.onTimeUp]) - shown ahead of
  /// the shared resolution beat so running out the clock never reads as
  /// a silent glitch to the player it happened to (Phase 4 Part 1).
  bool _showTimeUp = false;
  Timer? _timeUpFlashTimer;

  void _handleTimeUp() {
    _timeUpFlashTimer?.cancel();
    setState(() => _showTimeUp = true);
    _timeUpFlashTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _showTimeUp = false);
    });
  }

  @override
  void dispose() {
    _timeUpFlashTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final actorId = widget.actorId;
    final state = ref.watch(gameStateProvider)!;
    final controller = ref.read(activeGameControllerProvider);
    final pending = state.pendingInterrupt!;
    final responder = state.playerById(actorId);
    final isHelper = actorId != pending.defenderId;

    // This view is only ever constructed for the actual current responder
    // (see _buildBody/_buildNetworked in game_screen.dart) - LAN's deadline
    // countdown is therefore always "mine to show" here, never a bystander
    // leak, without needing an extra identity check against
    // localPlayerIdProvider.
    final responseDeadlineEpochMs = ref.watch(responseDeadlineEpochMsProvider);

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

    final attackDef = cardDefById(pending.attackCardDefId);
    final attackArt = displaySpecFor(attackDef.id).illustrationAssetPath;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Redesign header: DEFENSE title + responder subtitle,
                  // with the LAN countdown bar (when present) kept
                  // directly beneath so pacing stays obvious.
                  Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'DEFENSE',
                          style: TextStyle(
                            fontSize: 19,
                            color: ArmorUpColors.fontColor,
                            shadows: ArmorUpColors.titleOutline,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          responder.name.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: Color(0xFFE0A0A0),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (responseDeadlineEpochMs != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: _ResponseCountdownBar(
                          deadlineEpochMs: responseDeadlineEpochMs,
                          onTimeUp: _handleTimeUp,
                        ),
                      ),
                    ),
                  // Attack banner: what hit, from whom, on which piece.
                  Container(
                    decoration: BoxDecoration(
                      color: ArmorUpColors.bannerAttack.withValues(alpha: 0.15),
                      border: Border.all(color: ArmorUpColors.bannerAttack),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        if (attackArt != null) ...[
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: ArmorUpColors.bannerAttack,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Image.asset(
                              attackArt,
                              fit: BoxFit.cover,
                              filterQuality: FilterQuality.none,
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: Text(
                            isHelper
                                ? '${attacker.name} attacked ${defender.name}\'s '
                                    '${pending.targetArmor.displayName} with '
                                    '${attackDef.name}. ${defender.name} is '
                                    'asking for Fellowship help.'
                                : '${attacker.name} attacked your '
                                    '${pending.targetArmor.displayName} with '
                                    '${attackDef.name}'
                                    '${pending.isDoubleHit ? ' - double hit!' : ''}.',
                            style: const TextStyle(
                              fontSize: 11,
                              height: 1.4,
                              fontFamily: 'Roboto',
                              color: ArmorUpColors.fontColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Clash tableau: attacker card art squared off against
                  // the targeted armor piece, over a faint red glow.
                  Container(
                    height: 118,
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: [
                          ArmorUpColors.bannerAttack.withValues(alpha: 0.14),
                          Colors.transparent,
                        ],
                        radius: 0.9,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: ArmorUpColors.bannerAttack,
                              width: 3,
                            ),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: ArmorUpColors.bannerAttack
                                    .withValues(alpha: 0.5),
                                blurRadius: 16,
                              ),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: attackArt != null
                              ? Image.asset(
                                  attackArt,
                                  fit: BoxFit.cover,
                                  filterQuality: FilterQuality.none,
                                )
                              : const Icon(
                                  Icons.flash_on,
                                  color: ArmorUpColors.bannerAttack,
                                ),
                        ),
                        const SizedBox(width: 26),
                        Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F1015),
                            border: Border.all(
                              color: ArmorUpColors.goldAccent,
                              width: 3,
                            ),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: ArmorUpColors.goldAccent
                                    .withValues(alpha: 0.35),
                                blurRadius: 16,
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(9),
                          child: Image.asset(
                            armorIconAssetPath(pending.targetArmor)!,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    defenseCards.isEmpty
                        ? 'YOU HAVE NO DEFENSE CARDS.'
                        : 'CHOOSE A DEFENSE CARD, OR DECLINE:',
                    style: const TextStyle(
                      fontSize: 9,
                      letterSpacing: 0.5,
                      color: ArmorUpColors.mutedLabel,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // CardWidget has a fixed natural size; on short
                        // landscape heights (real phones) it doesn't fit -
                        // shrink it to the available height via FittedBox
                        // rather than let it clip against the Column below.
                        final scale =
                            (constraints.maxHeight / CardWidget.cardHeight).clamp(0.0, 1.0);
                        return ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            for (final card in defenseCards)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: SizedBox(
                                  width: CardWidget.cardWidth * scale,
                                  height: constraints.maxHeight,
                                  child: FittedBox(
                                    fit: BoxFit.contain,
                                    child: CardWidget(
                                      def: cardDefFor(card),
                                      onTap: () => controller.dispatch(
                                        DeclareDefense(
                                            playerId: actorId, cardInstanceId: card.instanceId),
                                      ),
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
                  OutlinedButton(
                    onPressed: () => controller.dispatch(DeclineDefense(playerId: actorId)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFE0A0A0),
                      side: const BorderSide(color: Color(0xFF6B4040), width: 2),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: Text(
                      isHelper ? 'DECLINE TO HELP' : 'TAKE THE HIT',
                      style: const TextStyle(fontSize: 10.5),
                    ),
                  ),
                ],
              ),
            ),
            if (_showTimeUp)
              IgnorePointer(
                child: Align(
                  alignment: const Alignment(0, -0.6),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: ArmorUpColors.boardBackground.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red, width: 2),
                    ),
                    child: const Text(
                      "Time's up!",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: ArmorUpColors.fontColor,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A thin shrinking bar counting down to [deadlineEpochMs], shown only to
/// whoever must currently respond (this widget is only ever mounted inside
/// [_DefensePromptView], which is itself only ever built for the actual
/// responder - see that class's doc comment). Resyncs against the synced
/// epoch on every tick rather than free-running from a locally-started
/// Duration, since the client clock is not assumed to be perfectly synced
/// with the host's - only the gap between "now" and the host's own epoch
/// matters, not any local start time.
class _ResponseCountdownBar extends StatefulWidget {
  final int deadlineEpochMs;

  /// Fired once, the instant this client's own clock reaches the
  /// deadline - see [_ResponseCountdownBarState._resync] for why this
  /// exists ahead of the shared resolution beat.
  final VoidCallback onTimeUp;

  const _ResponseCountdownBar({required this.deadlineEpochMs, required this.onTimeUp});

  @override
  State<_ResponseCountdownBar> createState() => _ResponseCountdownBarState();
}

class _ResponseCountdownBarState extends State<_ResponseCountdownBar> {
  Timer? _ticker;
  Duration _remaining = Duration.zero;

  bool _announcedTimeUp = false;

  @override
  void initState() {
    super.initState();
    _resync();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) => _resync());
  }

  @override
  void didUpdateWidget(covariant _ResponseCountdownBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new deadline (e.g. Fellowship passing to the next helper, each of
    // whom gets their own fresh window) replaces the old one outright -
    // recompute immediately rather than waiting for the next 100ms tick,
    // and re-arm the one-shot "time's up" flash for the new window.
    if (oldWidget.deadlineEpochMs != widget.deadlineEpochMs) {
      _announcedTimeUp = false;
      _resync();
    }
  }

  void _resync() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final remainingMs = widget.deadlineEpochMs - now;
    final remaining = Duration(milliseconds: remainingMs.clamp(0, 1 << 31));
    setState(() => _remaining = remaining);
    // Fires once per deadline, right as the client-side clock reaches
    // zero - this is deliberately ahead of the shared resolution beat
    // (_ResolutionBeatHost), which only appears once the host's own
    // timeout has actually fired *and* the resulting state has round-
    // tripped back to this client. Without this, the responder who ran
    // out the clock would see nothing happen for a beat and could easily
    // read that gap as a glitch instead of "your time ran out."
    if (remaining == Duration.zero && !_announcedTimeUp) {
      _announcedTimeUp = true;
      widget.onTimeUp();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Total window isn't known to the client (only the deadline instant
    // is synced, not the original duration) - approximated from the
    // default 20s response timeout for the purposes of the shrinking
    // bar's fill fraction. Slightly wrong if the host is configured with a
    // different timeout, but the bar still correctly hits empty exactly
    // at the real deadline (see _resync) and still escalates color in the
    // final 5 real seconds regardless, which is what matters for pacing.
    const assumedTotal = Duration(seconds: 20);
    final fraction = (_remaining.inMilliseconds / assumedTotal.inMilliseconds).clamp(0.0, 1.0);

    final secondsLeft = _remaining.inMilliseconds / 1000;
    final color = secondsLeft <= 5
        ? Color.lerp(Colors.amber, Colors.red, (1 - secondsLeft / 5).clamp(0.0, 1.0))!
        : Colors.green;

    return LinearProgressIndicator(
      value: fraction,
      minHeight: 6,
      backgroundColor: Colors.white24,
      valueColor: AlwaysStoppedAnimation<Color>(color),
    );
  }
}
