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

    return Scaffold(
      appBar: AppBar(title: const Text('Victory!')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 24),
              Icon(icon, size: 96, color: iconColor),
              const SizedBox(height: 16),
              Text(
                '$winnerName wins!',
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Text('Game log', style: Theme.of(context).textTheme.titleSmall),
              const Divider(),
              Expanded(child: EventLogWidget(state: state)),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  final mode = ref.read(appModeControllerProvider).mode;
                  if (mode == AppMode.netPlaying) {
                    ref.read(appModeControllerProvider.notifier).returnToModeSelect();
                  } else {
                    ref.read(gameControllerProvider.notifier).endGame();
                  }
                },
                style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
                child: const Text('New game'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
