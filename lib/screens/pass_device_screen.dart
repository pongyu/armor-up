import 'package:flutter/material.dart';

/// Shown whenever control of the device needs to pass to a different
/// player - before a new active turn, and before a defender/helper
/// responds to a defense interrupt - so the previous player's hand isn't
/// visible to the next one.
class PassDeviceScreen extends StatelessWidget {
  final String nextPlayerName;
  final String reason;
  final VoidCallback onReady;

  const PassDeviceScreen({
    super.key,
    required this.nextPlayerName,
    required this.reason,
    required this.onReady,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.shield_moon, size: 72),
                const SizedBox(height: 24),
                Text(
                  'Pass the device to',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  nextPlayerName,
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  reason,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: onReady,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
                  child: const Text("I'm ready"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
