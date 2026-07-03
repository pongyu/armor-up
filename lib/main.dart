import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/game_screen.dart';
import 'screens/setup_screen.dart';
import 'state/game_providers.dart';

void main() {
  runApp(const ProviderScope(child: ArmorUpApp()));
}

class ArmorUpApp extends StatelessWidget {
  const ArmorUpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Armor Up!',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: const _AppRoot(),
    );
  }
}

/// Switches between the setup screen (no game yet) and the in-progress
/// game screen based purely on whether [gameStateProvider] holds a state.
class _AppRoot extends ConsumerWidget {
  const _AppRoot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasGame = ref.watch(gameStateProvider) != null;
    return hasGame ? const GameScreen() : const SetupScreen();
  }
}
