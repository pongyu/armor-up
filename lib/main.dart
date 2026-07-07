import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/game_screen.dart';
import 'screens/setup_screen.dart';
import 'state/game_providers.dart';
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

/// Fixed warm/parchment brand theme. Only [MaterialApp.theme] is set (no
/// darkTheme) on purpose: the palette is brand color and must not shift
/// with the system dark/light mode.
ThemeData _buildArmorUpTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: ArmorUpColors.descriptionBackground,
  ).copyWith(
    primary: ArmorUpColors.descriptionBackground,
    onPrimary: ArmorUpColors.fontColor,
    surface: ArmorUpColors.boardBackground,
    onSurface: ArmorUpColors.cardStroke,
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
        foregroundColor: ArmorUpColors.cardStroke,
        side: BorderSide(color: ArmorUpColors.cardStroke.withValues(alpha: 0.6)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: ArmorUpColors.descriptionBackground,
      ),
    ),
    dividerTheme: DividerThemeData(
      color: ArmorUpColors.cardStroke.withValues(alpha: 0.25),
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

/// Switches between the setup screen (no game yet) and the in-progress
/// game screen based purely on whether [gameStateProvider] holds a state.
class _AppRoot extends ConsumerWidget {
  const _AppRoot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasGame = ref.watch(gameStateProvider) != null;
    return hasGame ? const GameScreen() : const SetupScreen();
  }
}
