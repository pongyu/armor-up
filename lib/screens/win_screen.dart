import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:game_engine/game_engine.dart';

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
    final isElimination = winner.type == WinType.elimination;

    return Scaffold(
      appBar: AppBar(title: const Text('Victory!')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 24),
              Icon(
                isElimination ? Icons.gavel : Icons.shield,
                size: 96,
                color: isElimination ? Colors.red.shade400 : Colors.green.shade600,
              ),
              const SizedBox(height: 16),
              Text(
                '$winnerName wins!',
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                isElimination
                    ? 'Victory by elimination - every other player lost all their armor.'
                    : 'Victory by full restoration - all six pieces of armor, Strong once again.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Text('Game log', style: Theme.of(context).textTheme.titleSmall),
              const Divider(),
              Expanded(child: EventLogWidget(state: state)),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => ref.read(gameControllerProvider.notifier).endGame(),
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
