import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:net/net.dart';

import '../net/reconnect_info.dart';
import '../state/app_mode_controller.dart';
import '../state/net_game_controller.dart';

/// Shown when this device's own [GameClient] socket drops unexpectedly
/// (see [GameClient.connectionLost]'s doc comment) - a network blip, the
/// host briefly unreachable, or the app having been backgrounded. Unlike
/// [HostDisconnectedScreen], the host may well still be running and this
/// seat may still be held during its reconnect grace period, so this
/// screen offers a manual "Reconnect" action instead of only "Back to
/// start".
///
/// [initialInfo] covers the app-cold-start case: a freshly constructed
/// [GameClient] (handed in via [AppModeState.client] before this screen is
/// shown) has no [GameClient.hostAddress]/[GameClient.playerId] of its own
/// yet, since it never successfully connected - the persisted
/// [ReconnectInfo] from the previous process is used instead. Once
/// [GameClient.reconnect] succeeds, the client carries its own values for
/// any *subsequent* drop, so [initialInfo] is irrelevant after the first
/// attempt.
class ConnectionLostScreen extends ConsumerStatefulWidget {
  final ReconnectInfo? initialInfo;

  const ConnectionLostScreen({super.key, this.initialInfo});

  @override
  ConsumerState<ConnectionLostScreen> createState() => _ConnectionLostScreenState();
}

class _ConnectionLostScreenState extends ConsumerState<ConnectionLostScreen> {
  bool _reconnecting = false;
  String? _error;

  Future<void> _reconnect() async {
    final client = ref.read(appModeControllerProvider).client;
    final fallback = widget.initialInfo;
    final hostAddress = client?.hostAddress ?? fallback?.hostAddress;
    final hostPort = client?.hostPort ?? fallback?.hostPort;
    final playerId = client?.playerId ?? fallback?.playerId;
    final sessionToken = client?.sessionToken ?? fallback?.sessionToken;
    if (client == null ||
        hostAddress == null ||
        hostPort == null ||
        playerId == null ||
        sessionToken == null) {
      // Nothing to retry with - the client never got far enough to have a
      // reconnect token (e.g. it dropped before the game even started).
      setState(() => _error = 'Not enough information to reconnect. Please start over.');
      return;
    }

    setState(() {
      _reconnecting = true;
      _error = null;
    });

    try {
      await client.reconnect(hostAddress, hostPort, playerId, sessionToken);
    } catch (e) {
      if (mounted) {
        setState(() {
          _reconnecting = false;
          _error = 'Could not reconnect: $e';
        });
      }
      return;
    }

    // Whether the game had already started is normally known via
    // client.hasStarted (set by a LobbyStartedMessage) - but a client
    // reconnecting fresh after an app restart never received that message
    // in this process, and a mid-game HostServer._handleReconnect doesn't
    // resend one (see its doc comment): it goes straight to a StateMessage
    // instead. So a fresh client's only signal is which message actually
    // arrives - race the two possibilities the host might send next.
    final gameStarted = client.hasStarted ||
        await Future.any([
          client.states.first.then((_) => true),
          client.lobbyRoster.first.then((_) => false),
        ]);

    if (!mounted) return;
    // Re-attach so the game screen picks up the state the host resent as
    // part of accepting the rejoin, mirroring _AppRoot's normal
    // whenStarted transition.
    if (gameStarted) {
      ref.read(netGameControllerProvider.notifier).attach(client);
    }
    ref.read(appModeControllerProvider.notifier).resumeAfterReconnect(gameStarted: gameStarted);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connection lost'), toolbarHeight: 40),
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
                  'Lost connection to the host.',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'The host may still be waiting for you to come back.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: _reconnecting ? null : _reconnect,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
                  child: _reconnecting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Reconnect'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _reconnecting
                      ? null
                      : () => ref.read(appModeControllerProvider.notifier).returnToModeSelect(),
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
