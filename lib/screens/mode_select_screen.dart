import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_mode_controller.dart';
import 'character_picker_screen.dart';

/// First screen: choose pass-and-play (existing hotseat flow, unchanged)
/// or a LAN game (host or join). Replaces [SetupScreen] as the app's
/// initial route; [SetupScreen] itself is unchanged, just reached via the
/// "Play pass-and-play" choice here instead of being the root.
///
/// All three choices just change [AppModeController]'s mode -
/// `_AppRoot` in `main.dart` is what actually swaps the visible screen,
/// consistent with every other mode transition in the app (no separate
/// Navigator stack for the LAN flow).
class ModeSelectScreen extends ConsumerWidget {
  const ModeSelectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Armor Up!'), toolbarHeight: 40),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'How are you playing?',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => ref.read(appModeControllerProvider.notifier).chooseHotseat(),
                  icon: const Icon(Icons.smartphone),
                  label: const Text('Play pass-and-play'),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
                ),
                const SizedBox(height: 12),
                const Text(
                  'One device, passed around the table.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 32),
                OutlinedButton.icon(
                  onPressed: () => ref.read(appModeControllerProvider.notifier).enterHostSetup(),
                  icon: const Icon(Icons.wifi_tethering),
                  label: const Text('Host a LAN game'),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(16)),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => ref.read(appModeControllerProvider.notifier).enterJoinFlow(),
                  icon: const Icon(Icons.search),
                  label: const Text('Join a LAN game'),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(16)),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Each player uses their own phone on the same WiFi network.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 24),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CharacterPickerScreen()),
                  ),
                  icon: const Icon(Icons.face),
                  label: const Text('CHARACTER'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
