import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:game_engine/game_engine.dart';
import 'package:net/net.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../net/discovery_service.dart';
import '../net/lan_address.dart';
import '../state/app_mode_controller.dart';

/// Host flow: collect a display name + game name ([AppMode.hostSetup]),
/// then start [HostServer], mDNS-advertise, show the room code/QR and a
/// live roster ([AppMode.hostLobby]) until enough players have joined and
/// the host taps "Start Game".
class HostLobbyScreen extends ConsumerStatefulWidget {
  const HostLobbyScreen({super.key});

  @override
  ConsumerState<HostLobbyScreen> createState() => _HostLobbyScreenState();
}

class _HostLobbyScreenState extends ConsumerState<HostLobbyScreen> {
  final _hostNameController = TextEditingController(text: 'Host');
  final _gameNameController = TextEditingController(text: "Mumu's Game");

  HostServer? _server;
  String? _lanAddress;
  int? _port;
  String? _shortCode;
  dynamic _registration; // nsd.Registration, kept dynamic to avoid an
  // extra import here purely for the type - only ever passed back to
  // stopAdvertising.
  List<LobbyPlayer> _roster = const [];
  String? _error;

  @override
  void dispose() {
    _hostNameController.dispose();
    _gameNameController.dispose();
    super.dispose();
  }

  Future<void> _createLobby() async {
    final hostName = _hostNameController.text.trim().isEmpty
        ? 'Host'
        : _hostNameController.text.trim();
    final gameName = _gameNameController.text.trim().isEmpty
        ? "$hostName's Game"
        : _gameNameController.text.trim();

    final server = HostServer(hostDisplayName: hostName);
    final port = await server.start();
    final lanAddress = await findLanAddress();
    final shortCode = generateShortCode();

    final client = GameClient();
    client.lobbyRoster.listen((players) {
      if (mounted) setState(() => _roster = players);
    });
    client.joinRejected.listen((reason) {
      if (mounted) setState(() => _error = reason);
    });
    await client.connectToLobby('127.0.0.1', port, hostName);

    dynamic registration;
    if (lanAddress != null) {
      try {
        registration = await advertiseGame(gameName: gameName, shortCode: shortCode, port: port);
      } catch (_) {
        // mDNS advertise failing (unsupported platform, blocked network)
        // is not fatal - the room code/IP fallback still works.
      }
    }

    if (!mounted) return;
    setState(() {
      _server = server;
      _lanAddress = lanAddress;
      _port = port;
      _shortCode = shortCode;
      _registration = registration;
    });

    ref.read(appModeControllerProvider.notifier).enterHostLobby(server, client);
  }

  void _startGame() {
    final server = _server;
    if (server == null) return;
    try {
      server.startGame();
    } on StateError catch (e) {
      setState(() => _error = e.message);
      return;
    }
    // The host's own client receives LobbyStartedMessage over its loopback
    // connection just like any joiner; _AppRoot (always mounted) drives the
    // transition into gameplay from whenStarted, so nothing more to do here.
  }

  Future<void> _cancel() async {
    if (_registration != null) {
      await stopAdvertising(_registration);
    }
    await ref.read(appModeControllerProvider.notifier).returnToModeSelect();
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(appModeControllerProvider).mode;

    if (mode != AppMode.hostLobby) {
      return _buildSetup(context);
    }
    return _buildLobby(context);
  }

  Widget _buildSetup(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Host a LAN game'), toolbarHeight: 40),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _hostNameController,
                  decoration: const InputDecoration(
                    labelText: 'Your name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _gameNameController,
                  decoration: const InputDecoration(
                    labelText: 'Game name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _createLobby,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
                  child: const Text('Create lobby'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () =>
                      ref.read(appModeControllerProvider.notifier).returnToModeSelect(),
                  child: const Text('Back'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLobby(BuildContext context) {
    final joinUri = _lanAddress != null && _port != null
        ? 'ws://$_lanAddress:$_port'
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Lobby'), toolbarHeight: 40),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Players', style: Theme.of(context).textTheme.titleMedium),
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
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(_error!, style: const TextStyle(color: Colors.red)),
                      ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _roster.length >= minPlayers ? _startGame : null,
                      style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
                      child: Text(
                        _roster.length >= minPlayers
                            ? 'Start game'
                            : 'Waiting for at least $minPlayers players',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(onPressed: _cancel, child: const Text('Cancel')),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('Room code', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      _shortCode ?? '----',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(letterSpacing: 4),
                    ),
                    const SizedBox(height: 12),
                    if (joinUri != null) QrImageView(data: joinUri, size: 160),
                    const SizedBox(height: 8),
                    Text(
                      _lanAddress != null && _port != null
                          ? '$_lanAddress:$_port'
                          : 'No network address found',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
