import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:net/net.dart';

import 'net/reconnect_info.dart';
import 'screens/connection_lost_screen.dart';
import 'screens/game_screen.dart';
import 'screens/host_disconnected_screen.dart';
import 'screens/host_lobby_screen.dart';
import 'screens/join_flow_screen.dart';
import 'screens/mode_select_screen.dart';
import 'screens/setup_screen.dart';
import 'screens/waiting_for_host_screen.dart';
import 'state/app_mode_controller.dart';
import 'state/game_providers.dart';
import 'state/net_game_controller.dart';
import 'theme/armor_up_colors.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Orientation is no longer locked: the game board now has a portrait
  // layout branch (see _MainBoardView's LayoutBuilder in game_screen.dart)
  // alongside the original landscape one, and every other screen (setup,
  // pass-device, defense/discard prompts) is a plain centered Column/
  // ListView with no wide-short assumptions, so they render fine in
  // either orientation without changes.
  runApp(const ProviderScope(child: ArmorUpApp()));
}

/// Fixed dark/charcoal brand theme. Only [MaterialApp.theme] is set (no
/// darkTheme) on purpose: the palette is brand color and must not shift
/// with the system dark/light mode.
///
/// [ArmorUpColors.cardStroke] is now a near-black outline color (it
/// doubled as "readable ink on light background" under the old
/// parchment theme) - anything that needs to read as foreground
/// text/icons/dividers against the dark [ArmorUpColors.boardBackground]
/// uses [ArmorUpColors.fontColor] (light warm off-white) instead.
ThemeData _buildArmorUpTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: ArmorUpColors.descriptionBackground,
    brightness: Brightness.dark,
  ).copyWith(
    primary: ArmorUpColors.goldAccent,
    onPrimary: ArmorUpColors.cardStroke,
    surface: ArmorUpColors.boardBackground,
    onSurface: ArmorUpColors.fontColor,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    // Pixel-art retro font app-wide (assets/fonts/EarlyGameBoy.ttf) so
    // text matches the hand-drawn card/armor art instead of the
    // platform default. Drop shadows are opted into per-TextStyle via
    // ArmorUpColors.titleOutline (see its own doc comment) rather than
    // forced here - a shadow on every small body-text label would go
    // muddy, so only headers/titles that call for it use it.
    fontFamily: 'EarlyGameBoy',
    scaffoldBackgroundColor: ArmorUpColors.boardBackground,
    appBarTheme: const AppBarTheme(
      backgroundColor: ArmorUpColors.cardStroke,
      foregroundColor: ArmorUpColors.fontColor,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ArmorUpColors.descriptionBackground,
        foregroundColor: ArmorUpColors.fontColor,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ArmorUpColors.fontColor,
        side: BorderSide(color: ArmorUpColors.goldAccent.withValues(alpha: 0.6)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: ArmorUpColors.goldAccent,
      ),
    ),
    dividerTheme: DividerThemeData(
      color: ArmorUpColors.fontColor.withValues(alpha: 0.2),
    ),
  );
}

class ArmorUpApp extends StatelessWidget {
  const ArmorUpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Armor Up!',
      theme: _buildArmorUpTheme(),
      home: const _AppRoot(),
    );
  }
}

/// Top-level router, switching on [AppModeController]'s current
/// [AppMode]. In the two "playing" modes (hotseat and net), whether a
/// game is actually in progress is decided the same way it always was -
/// purely by whether [gameStateProvider] holds a state - so [GameScreen]
/// itself needs no mode awareness at all.
class _AppRoot extends ConsumerStatefulWidget {
  const _AppRoot();

  @override
  ConsumerState<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends ConsumerState<_AppRoot> {
  StreamSubscription? _hostDisconnectedSub;
  StreamSubscription? _playerLeftSub;
  StreamSubscription? _connectionLostSub;
  Object? _listeningToClient;
  bool _checkedColdStartReconnect = false;
  ReconnectInfo? _coldStartInfo;

  /// Once, on first build: if the app relaunched with a [ReconnectInfo]
  /// still saved from a prior process (it was killed mid-session rather
  /// than backing out deliberately - see [AppModeController.
  /// returnToModeSelect] for the deliberate-exit clear), route straight to
  /// [AppMode.connectionLost] with a fresh [GameClient] instead of
  /// dropping the player on mode-select with no memory of the game they
  /// were just in. [_coldStartInfo] is threaded to [ConnectionLostScreen]
  /// as its `initialInfo` since the fresh client has no host/session
  /// details of its own yet (see that parameter's doc comment).
  void _checkColdStartReconnect() {
    if (_checkedColdStartReconnect) return;
    _checkedColdStartReconnect = true;
    ReconnectInfo.load().then((info) {
      if (!mounted || info == null) return;
      // Only relevant from a completely fresh app-mode state - if the user
      // has already navigated somewhere (e.g. this future resolved after
      // they'd already started a new hotseat game), don't yank them away.
      if (ref.read(appModeControllerProvider).mode != AppMode.modeSelect) return;
      setState(() => _coldStartInfo = info);
      ref.read(appModeControllerProvider.notifier).resumeFromColdStart(GameClient());
    });
  }

  /// Wires up the lifecycle listeners for whichever [GameClient] is
  /// currently live. This lives in [_AppRoot] - the one widget that is
  /// always mounted across every mode transition - rather than in the
  /// individual lobby screens, because those screens get disposed the
  /// moment their mode changes (e.g. join-flow -> waiting-for-host). A
  /// `whenStarted`/`hostDisconnected` callback closing over a disposed
  /// screen's `ref` would throw "Cannot use ref after the widget was
  /// disposed" and the transition it was supposed to drive would silently
  /// never happen.
  void _listenToClient(AppModeState modeState) {
    final client = modeState.client;
    if (identical(client, _listeningToClient)) return;

    _hostDisconnectedSub?.cancel();
    _playerLeftSub?.cancel();
    _connectionLostSub?.cancel();
    _listeningToClient = client;
    if (client == null) return;

    // Transition into gameplay once the host starts, for host and joiner
    // alike. whenStarted (not lobbyStarted.first) so a client that reaches
    // this point after the host already started still fires.
    client.whenStarted.then((_) {
      if (!mounted || !identical(ref.read(appModeControllerProvider).client, client)) {
        return;
      }
      ref.read(netGameControllerProvider.notifier).attach(client);
      ref.read(appModeControllerProvider.notifier).enterNetPlaying();
      // The reconnect token is only meaningful once the game has actually
      // started (LobbyStartedMessage is what carries playerId/sessionToken)
      // - persisting it here, not just on a fresh join, is what lets a
      // *reconnected* client that then drops again reconnect once more.
      if (client.hostAddress != null &&
          client.hostPort != null &&
          client.playerId != null &&
          client.sessionToken != null) {
        unawaited(ReconnectInfo.save(ReconnectInfo(
          hostAddress: client.hostAddress!,
          hostPort: client.hostPort!,
          playerId: client.playerId!,
          sessionToken: client.sessionToken!,
        )));
      }
    });

    _hostDisconnectedSub = client.hostDisconnected.listen((_) {
      unawaited(ReconnectInfo.clear());
      ref.read(appModeControllerProvider.notifier).hostDisconnected('The host ended the game.');
    });
    _playerLeftSub = client.playerLeft.listen((playerId) {
      unawaited(ReconnectInfo.clear());
      ref
          .read(appModeControllerProvider.notifier)
          .hostDisconnected('A player disconnected and the game ended.');
    });
    _connectionLostSub = client.connectionLost.listen((_) {
      ref.read(appModeControllerProvider.notifier).connectionLost();
    });
  }

  @override
  void dispose() {
    _hostDisconnectedSub?.cancel();
    _playerLeftSub?.cancel();
    _connectionLostSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final modeState = ref.watch(appModeControllerProvider);
    _listenToClient(modeState);
    _checkColdStartReconnect();

    switch (modeState.mode) {
      case AppMode.modeSelect:
        return const ModeSelectScreen();
      case AppMode.hotseatSetup:
        // Whether a hotseat game is actually in progress is decided the
        // same way it always was: purely by gameStateProvider, not a
        // separate mode transition SetupScreen would otherwise need to
        // remember to call.
        return ref.watch(gameStateProvider) != null ? const GameScreen() : const SetupScreen();
      case AppMode.hostSetup:
      case AppMode.hostLobby:
        return const HostLobbyScreen();
      case AppMode.joinFlow:
        return const JoinFlowScreen();
      case AppMode.waitingForHost:
        return const WaitingForHostScreen();
      case AppMode.netPlaying:
        return const GameScreen();
      case AppMode.hostDisconnected:
        return const HostDisconnectedScreen();
      case AppMode.connectionLost:
        return ConnectionLostScreen(initialInfo: _coldStartInfo);
    }
  }
}
