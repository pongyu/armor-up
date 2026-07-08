import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_mode_controller.dart';

/// Shown when the host ends the session, deliberately or because a
/// dropped player's reconnect grace period expired
/// ([GameClient.hostDisconnected] / [GameClient.playerLeft]). The
/// host-authoritative model has no resume - the only way forward is back
/// to mode-select.
class HostDisconnectedScreen extends ConsumerWidget {
  const HostDisconnectedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reason =
        ref.watch(appModeControllerProvider).hostDisconnectedReason ?? 'The host ended the game.';

    return Scaffold(
      appBar: AppBar(title: const Text('Game ended'), toolbarHeight: 40),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off, size: 72),
                const SizedBox(height: 24),
                Text(
                  reason,
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: () =>
                      ref.read(appModeControllerProvider.notifier).returnToModeSelect(),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
                  child: const Text('Back to start'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
