import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:game_engine/game_engine.dart';
import 'package:net/net.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../net/discovery_service.dart';
import '../net/lan_address.dart';
import '../state/app_mode_controller.dart';
import '../state/character_controller.dart';
import '../theme/armor_up_colors.dart';
import '../widgets/pixel_ui.dart';

/// Section title in the redesign template's style: uppercase pixel text
/// with a short gold underline bar.
class _PixelTitle extends StatelessWidget {
  final String text;

  const _PixelTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: const TextStyle(
            fontSize: 18,
            color: ArmorUpColors.fontColor,
            shadows: ArmorUpColors.titleOutline,
          ),
        ),
        const SizedBox(height: 6),
        Container(width: 56, height: 3, color: ArmorUpColors.goldAccent),
      ],
    );
  }
}

/// Dark boxed text field with a tiny uppercase label above it, matching
/// the template's YOUR NAME / GAME NAME inputs. [highlighted] gives the
/// gold border + soft glow the template puts on the game-name field.
class _PixelField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool highlighted;

  const _PixelField({
    required this.label,
    required this.controller,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = highlighted
        ? ArmorUpColors.goldAccent
        : ArmorUpColors.descriptionBackground;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 8.5,
            letterSpacing: 0.5,
            color: highlighted
                ? ArmorUpColors.goldAccent
                : ArmorUpColors.mutedLabel,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          decoration: highlighted
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [
                    BoxShadow(
                      color: ArmorUpColors.goldAccent.withValues(alpha: 0.25),
                      blurRadius: 10,
                    ),
                  ],
                )
              : null,
          child: TextField(
            controller: controller,
            style: const TextStyle(
              fontSize: 11,
              color: ArmorUpColors.fontColor,
            ),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: ArmorUpColors.boardBackground,
              contentPadding: const EdgeInsets.all(12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: accent, width: 2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide:
                    const BorderSide(color: ArmorUpColors.goldAccent, width: 2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One roster row in the broadcasting panel: status dot + name, filled
/// for joined players, muted "WAITING FOR PLAYER..." otherwise.
class _LobbySlotRow extends StatelessWidget {
  final String? name;

  const _LobbySlotRow({this.name});

  @override
  Widget build(BuildContext context) {
    final joined = name != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: ArmorUpColors.boardBackground,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: joined
                  ? ArmorUpColors.activeGreen
                  : const Color(0xFF4A4D5A),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              joined ? name!.toUpperCase() : 'WAITING FOR PLAYER...',
              style: TextStyle(
                fontSize: 9.5,
                color: joined
                    ? ArmorUpColors.fontColor
                    : const Color(0xFF6B6F7D),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

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
    final palette = ref.read(characterControllerProvider).palette;
    await client.connectToLobby('127.0.0.1', port, hostName, avatar: palette.toLobbyAvatar());

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
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _PixelTitle('HOST A LAN GAME'),
                  const SizedBox(height: 20),
                  _PixelField(label: 'YOUR NAME', controller: _hostNameController),
                  const SizedBox(height: 12),
                  _PixelField(
                    label: 'GAME NAME',
                    controller: _gameNameController,
                    highlighted: true,
                  ),
                  const SizedBox(height: 20),
                  GoldPillButton(label: 'CREATE LOBBY', onPressed: _createLobby),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => ref
                        .read(appModeControllerProvider.notifier)
                        .returnToModeSelect(),
                    child: const Text(
                      'BACK',
                      style: TextStyle(fontSize: 9.5),
                    ),
                  ),
                ],
              ),
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
    // Joined players plus muted "waiting" placeholder slots: always show
    // at least the minPlayers count, and one open slot beyond the
    // current roster while the table isn't full yet.
    final slotCount = (_roster.length + 1)
        .clamp(minPlayers, maxPlayers)
        .clamp(_roster.length, maxPlayers);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _PixelTitle('LOBBY'),
                  const SizedBox(height: 16),
                  // Broadcasting panel: live status + roster slots.
                  Container(
                    decoration: BoxDecoration(
                      color: ArmorUpColors.panelBackground,
                      border: Border.all(
                        color: ArmorUpColors.descriptionBackground,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const PulsingDot(size: 10),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'BROADCASTING ON YOUR WI-FI NETWORK',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: const Color(0xFF8FD48F),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        for (var i = 0; i < slotCount; i++)
                          _LobbySlotRow(
                            name: i < _roster.length
                                ? _roster[i].displayName
                                : null,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Room code + QR join info.
                  Container(
                    decoration: BoxDecoration(
                      color: ArmorUpColors.panelBackground,
                      border: Border.all(
                        color: ArmorUpColors.descriptionBackground,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        const Text(
                          'ROOM CODE',
                          style: TextStyle(
                            fontSize: 8.5,
                            letterSpacing: 1,
                            color: ArmorUpColors.mutedLabel,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _shortCode ?? '----',
                          style: const TextStyle(
                            fontSize: 22,
                            letterSpacing: 4,
                            color: ArmorUpColors.goldAccent,
                            shadows: ArmorUpColors.titleOutline,
                          ),
                        ),
                        if (joinUri != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(6),
                            color: Colors.white,
                            child: QrImageView(data: joinUri, size: 132),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          _lanAddress != null && _port != null
                              ? '$_lanAddress:$_port'
                              : 'No network address found',
                          style: const TextStyle(
                            fontSize: 8.5,
                            color: ArmorUpColors.mutedLabel,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          fontSize: 9.5,
                          color: Color(0xFFE0A0A0),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  GoldPillButton(
                    label: _roster.length >= minPlayers
                        ? 'START GAME'
                        : 'WAITING FOR $minPlayers PLAYERS',
                    onPressed: _roster.length >= minPlayers ? _startGame : null,
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _cancel,
                    child: const Text(
                      'CANCEL',
                      style: TextStyle(fontSize: 9.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
