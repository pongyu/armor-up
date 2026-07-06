import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:game_engine/game_engine.dart';

import '../state/game_controller.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final List<TextEditingController> _nameControllers = [
    TextEditingController(text: 'Player 1'),
    TextEditingController(text: 'Player 2'),
  ];

  @override
  void dispose() {
    for (final c in _nameControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addPlayer() {
    if (_nameControllers.length >= maxPlayers) return;
    setState(() {
      _nameControllers.add(
        TextEditingController(text: 'Player ${_nameControllers.length + 1}'),
      );
    });
  }

  void _removePlayer() {
    if (_nameControllers.length <= minPlayers) return;
    setState(() {
      _nameControllers.removeLast().dispose();
    });
  }

  void _startGame() {
    final names = _nameControllers
        .map((c) => c.text.trim())
        .map((name) => name.isEmpty ? 'Player' : name)
        .toList();
    ref.read(gameControllerProvider.notifier).startGame(playerNames: names);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Armor Up!')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Suit up',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text('Enter names for 2-6 players (pass and play).'),
              const SizedBox(height: 24),
              Expanded(
                child: ListView.separated(
                  itemCount: _nameControllers.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    return TextField(
                      controller: _nameControllers[index],
                      decoration: InputDecoration(
                        labelText: 'Player ${index + 1}',
                        border: const OutlineInputBorder(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          _nameControllers.length > minPlayers ? _removePlayer : null,
                      icon: const Icon(Icons.remove),
                      label: const Text('Remove player'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          _nameControllers.length < maxPlayers ? _addPlayer : null,
                      icon: const Icon(Icons.add),
                      label: const Text('Add player'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _startGame,
                style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
                child: const Text('Start Game'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
