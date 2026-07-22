import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:game_engine/game_engine.dart';

import '../state/app_mode_controller.dart';
import '../state/game_controller.dart';
import '../widgets/event_log_widget.dart';

/// Shown once [GameState.winner] is set. The message and icon differ by
/// [WinType] per the design spec, so future artwork/animations have a
/// clear hook to attach to.
class WinScreen extends ConsumerWidget {
  final GameState state;

  const WinScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final winner = state.winner!;
    final winnerName = state.playerById(winner.winnerId).name;
    final (icon, iconColor, message) = switch (winner.type) {
      WinType.elimination => (
          Icons.gavel,
          Colors.red.shade400,
          'Victory by elimination - every other player lost all their armor.',
        ),
      WinType.restoration => (
          Icons.shield,
          Colors.green.shade600,
          'Victory by full restoration - all six pieces of armor, Strong once again.',
        ),
      WinType.deckExhausted => (
          Icons.style,
          Colors.blueGrey.shade400,
          'The deck ran out - victory goes to whoever was closest to full '
              'restoration.',
        ),
    };

    void onNewGame() {
      final mode = ref.read(appModeControllerProvider).mode;
      if (mode == AppMode.netPlaying) {
        ref.read(appModeControllerProvider.notifier).returnToModeSelect();
      } else {
        ref.read(gameControllerProvider.notifier).endGame();
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Victory!'), toolbarHeight: 40),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // On short landscape phone heights the fixed header (big icon,
            // headline, message) plus the button would crowd out the
            // Expanded log and overflow. Shrink the celebratory chrome on
            // small heights so everything still fits without clipping.
            final tight = constraints.maxHeight < 420;
            final iconSize = tight ? 48.0 : 96.0;
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: tight ? 8 : 24),
              child: Column(
                children: [
                  if (!tight) const SizedBox(height: 24),
                  _VictoryIcon(icon: icon, color: iconColor, size: iconSize),
                  SizedBox(height: tight ? 8 : 16),
                  Text(
                    '$winnerName wins!',
                    style: tight
                        ? Theme.of(context).textTheme.titleLarge
                        : Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: tight ? 8 : 24),
                  Text('Game log', style: Theme.of(context).textTheme.titleSmall),
                  const Divider(),
                  Expanded(child: EventLogWidget(state: state)),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: onNewGame,
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.all(tight ? 10 : 16),
                    ),
                    child: const Text('New game'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The win screen's celebratory header: the win-type icon overshoots in
/// with an elastic bounce, then settles into a slow continuous pulse, with
/// a burst of confetti-like particles behind it on entrance. All driven by
/// two controllers (one-shot entrance, repeating pulse) rather than a
/// single shared one, since the pulse must keep running indefinitely while
/// the entrance is strictly one-and-done.
class _VictoryIcon extends StatefulWidget {
  final IconData icon;
  final Color color;
  final double size;

  const _VictoryIcon({required this.icon, required this.color, required this.size});

  @override
  State<_VictoryIcon> createState() => _VictoryIconState();
}

class _VictoryIconState extends State<_VictoryIcon> with TickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final AnimationController _pulseController;
  late final List<_ConfettiPiece> _confetti;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2));

    final reduceMotion = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    _confetti = List.generate(14, (i) => _ConfettiPiece.random(math.Random(i)));

    if (reduceMotion) {
      _entranceController.value = 1.0;
    } else {
      _entranceController.forward();
    }
    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Generous headroom around the icon for the confetti burst and the
    // overshoot scale to paint into without getting clipped.
    final fieldSize = widget.size * 2.6;

    return SizedBox(
      width: fieldSize,
      height: fieldSize,
      child: AnimatedBuilder(
        animation: Listenable.merge([_entranceController, _pulseController]),
        builder: (context, child) {
          final entrance = _entranceController.value;
          // Elastic overshoot: scales past 1.0 before settling, so the
          // icon "pops" in rather than just fading/growing smoothly.
          final scale = Curves.elasticOut.transform(entrance);
          final opacity = Curves.easeOut.transform(entrance.clamp(0.0, 1.0));
          final pulse = 1.0 + math.sin(_pulseController.value * math.pi) * 0.05;

          return Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size(fieldSize, fieldSize),
                painter: _ConfettiPainter(pieces: _confetti, progress: entrance),
              ),
              Opacity(
                opacity: opacity,
                child: Transform.scale(
                  scale: scale * pulse,
                  child: Icon(widget.icon, size: widget.size, color: widget.color, shadows: const [
                    Shadow(blurRadius: 18, color: Colors.black45),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One confetti particle's fixed launch parameters - direction, distance,
/// color, and a slight rotation - randomized once at init rather than
/// re-rolled every build, so the burst is stable across rebuilds instead
/// of jittering.
class _ConfettiPiece {
  final double angle;
  final double distance;
  final double size;
  final double rotationSpeed;
  final Color color;

  const _ConfettiPiece({
    required this.angle,
    required this.distance,
    required this.size,
    required this.rotationSpeed,
    required this.color,
  });

  factory _ConfettiPiece.random(math.Random rng) {
    const palette = [
      Color(0xFFC9A24B), // goldAccent
      Color(0xFFD4AF37), // armorStrong
      Color(0xFF9B4040), // bannerAttack
      Color(0xFF78A8BA), // bannerDefense
      Color(0xFF989550), // bannerRestore
    ];
    return _ConfettiPiece(
      angle: rng.nextDouble() * math.pi * 2,
      distance: 0.55 + rng.nextDouble() * 0.45,
      size: 4 + rng.nextDouble() * 4,
      rotationSpeed: (rng.nextDouble() - 0.5) * 6,
      color: palette[rng.nextInt(palette.length)],
    );
  }
}

/// Paints [pieces] flying outward from the center as [progress] runs 0->1,
/// fading out over the back half of the animation so they don't just stop
/// dead at full distance. A CustomPainter (not individual widgets) since
/// there's no interaction on the particles - just paint and forget.
class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiPiece> pieces;
  final double progress;

  const _ConfettiPainter({required this.pieces, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final center = size.center(Offset.zero);
    final maxRadius = size.shortestSide / 2;
    // Fade in fast, hold, then fade out over the last third of the burst.
    final fade = progress < 0.7 ? 1.0 : (1.0 - (progress - 0.7) / 0.3).clamp(0.0, 1.0);

    for (final piece in pieces) {
      final eased = Curves.easeOut.transform(progress);
      final radius = maxRadius * piece.distance * eased;
      final offset = Offset(math.cos(piece.angle), math.sin(piece.angle)) * radius;
      final paint = Paint()..color = piece.color.withValues(alpha: fade);

      canvas.save();
      canvas.translate(center.dx + offset.dx, center.dy + offset.dy);
      canvas.rotate(piece.rotationSpeed * progress * math.pi);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: piece.size, height: piece.size * 0.6),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.pieces != pieces;
}
