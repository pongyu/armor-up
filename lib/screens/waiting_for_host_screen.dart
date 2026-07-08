import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:net/net.dart';

import '../state/app_mode_controller.dart';

/// Shown to a non-host client after joining a lobby, until the host
/// starts the game. Displays the live roster so the joiner can see who
/// else has connected while they wait.
class WaitingForHostScreen extends ConsumerStatefulWidget {
  const WaitingForHostScreen({super.key});

  @override
  ConsumerState<WaitingForHostScreen> createState() => _WaitingForHostScreenState();
}

class _WaitingForHostScreenState extends ConsumerState<WaitingForHostScreen> {
  List<LobbyPlayer> _roster = const [];

  @override
  void initState() {
    super.initState();
    final client = ref.read(appModeControllerProvider).client;
    // lobbyRoster is a broadcast stream with no replay - by the time this
    // screen subscribes, the host may already have sent the roster that
    // includes us. Seed from the last known roster so that first entry
    // isn't silently missed, then keep listening for further changes.
    _roster = client?.latestRoster ?? const [];
    client?.lobbyRoster.listen((players) {
      if (mounted) setState(() => _roster = players);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Waiting for host'), toolbarHeight: 40),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 16),
              Text(
                'Waiting for the host to start the game...',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Text('Players so far', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: _roster.length,
                  itemBuilder: (context, index) => ListTile(
                    leading: const Icon(Icons.person),
                    title: Text(_roster[index].displayName),
                  ),
                ),
              ),
              TextButton(
                onPressed: () =>
                    ref.read(appModeControllerProvider.notifier).returnToModeSelect(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
