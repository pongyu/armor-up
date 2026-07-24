import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:net/net.dart';

import '../net/discovery_service.dart';
import '../state/app_mode_controller.dart';
import '../state/character_controller.dart';

/// Join flow: a live mDNS discovery list plus a manual IP:port fallback
/// field, and a display-name field. Selecting a discovered game or
/// submitting manual entry connects a [GameClient] to that host's lobby
/// and moves to [AppMode.waitingForHost].
class JoinFlowScreen extends ConsumerStatefulWidget {
  const JoinFlowScreen({super.key});

  @override
  ConsumerState<JoinFlowScreen> createState() => _JoinFlowScreenState();
}

class _JoinFlowScreenState extends ConsumerState<JoinFlowScreen> {
  final _nameController = TextEditingController(text: 'Player');
  final _manualAddressController = TextEditingController();
  final GameDiscovery _discovery = GameDiscovery();
  List<DiscoveredGame> _games = const [];
  String? _error;
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    _discovery.start();
    _discovery.games.listen((games) {
      if (mounted) setState(() => _games = games);
    });
  }

  @override
  void dispose() {
    _discovery.stop();
    _nameController.dispose();
    _manualAddressController.dispose();
    super.dispose();
  }

  Future<void> _join(String address, int port) async {
    final name = _nameController.text.trim().isEmpty ? 'Player' : _nameController.text.trim();
    setState(() {
      _connecting = true;
      _error = null;
    });

    final client = GameClient();
    final rejection = client.joinRejected.first;
    final palette = ref.read(characterControllerProvider).palette;
    try {
      await client.connectToLobby(address, port, name, avatar: palette.toLobbyAvatar());
    } catch (e) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = 'Could not connect: $e';
        });
      }
      return;
    }

    // A rejection (name taken, lobby full, game already started) arrives
    // as a message, not a connection failure, so give it a brief window
    // to show up before treating the join as successful.
    final reason = await rejection.timeout(
      const Duration(milliseconds: 500),
      onTimeout: () => '',
    );
    if (reason.isNotEmpty) {
      await client.close();
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = reason;
        });
      }
      return;
    }

    if (!mounted) return;
    // Hand the connected client to the app-mode controller and move to the
    // waiting screen. The transition into gameplay once the host starts is
    // driven centrally by _AppRoot (which is always mounted), not here -
    // this screen is disposed the moment the mode changes, so a callback
    // using its `ref` would throw after disposal.
    ref.read(appModeControllerProvider.notifier).enterWaitingForHost(client);
  }

  void _joinManual() {
    final input = _manualAddressController.text.trim();
    final parts = input.split(':');
    if (parts.length != 2) {
      setState(() => _error = 'Enter address as ip:port');
      return;
    }
    final port = int.tryParse(parts[1]);
    if (port == null) {
      setState(() => _error = 'Enter address as ip:port');
      return;
    }
    _join(parts[0], port);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join a LAN game'), toolbarHeight: 40),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Your name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Text('Games on this network', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Expanded(
                child: _games.isEmpty
                    ? const Center(child: Text('Searching...'))
                    : ListView.builder(
                        itemCount: _games.length,
                        itemBuilder: (context, index) {
                          final game = _games[index];
                          return ListTile(
                            leading: const Icon(Icons.wifi_tethering),
                            title: Text(game.gameName),
                            subtitle: Text('Code: ${game.shortCode}'),
                            onTap: _connecting
                                ? null
                                : () => _join(game.address, game.port),
                          );
                        },
                      ),
              ),
              const Divider(),
              Text("Can't see it? Enter the code's address manually:",
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _manualAddressController,
                      decoration: const InputDecoration(
                        labelText: 'ip:port',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _connecting ? null : _joinManual,
                    child: const Text('Connect'),
                  ),
                ],
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: const TextStyle(color: Colors.red)),
                ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.read(appModeControllerProvider.notifier).returnToModeSelect(),
                child: const Text('Back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
