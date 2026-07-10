import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  // The board layout is landscape-only; other screens (setup, pass-device,
  // defense prompt) aren't restyled yet, but locking orientation for the
  // whole session avoids a jarring rotate-back-and-forth as those appear
  // between turns.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
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
  Object? _listeningToClient;

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
    });

    _hostDisconnectedSub = client.hostDisconnected.listen((_) {
      ref.read(appModeControllerProvider.notifier).hostDisconnected('The host ended the game.');
    });
    _playerLeftSub = client.playerLeft.listen((playerId) {
      ref
          .read(appModeControllerProvider.notifier)
          .hostDisconnected('A player disconnected and the game ended.');
    });
  }

  @override
  void dispose() {
    _hostDisconnectedSub?.cancel();
    _playerLeftSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final modeState = ref.watch(appModeControllerProvider);
    _listenToClient(modeState);

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
    }
  }
}
