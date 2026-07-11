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
                  Icon(icon, size: iconSize, color: iconColor),
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
