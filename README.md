# Armor Up!

A biblical "spiritual warfare" take-that card game (Ephesians 6 / Armor of
God), inspired by games like Organ Attack. **Phase 1**: a pure Dart rules
engine plus a hotseat (pass-and-play) Flutter UI. No networking yet.

## Project layout

```
armor_up/
  packages/
    game_engine/        # Pure Dart rules engine (no Flutter/network deps)
      lib/
      test/             # Unit tests for all rules
      bin/simulate.dart # Bot-driven balance simulator
  lib/                   # Flutter hotseat UI
    screens/
    widgets/
    state/               # Riverpod providers wrapping the engine
```

## Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (this project
  was built against Flutter 3.44 / Dart 3.12).
- A web browser (Chrome or Edge) is the easiest way to run the app - no
  extra setup required. Windows desktop builds also need Visual Studio
  with the "Desktop development with C++" workload installed; without it,
  `flutter run -d windows` will fail with "Unable to find suitable Visual
  Studio toolchain."

Check your setup with:

```bash
flutter doctor
```

If your terminal reports `flutter` (or `dart`) as not recognized, the
Flutter SDK's `bin` directory isn't on your `PATH`. Add it (adjust the path
to wherever your Flutter SDK actually lives) and restart your terminal:

```powershell
# PowerShell, permanent (user-level):
[Environment]::SetEnvironmentVariable("Path", [Environment]::GetEnvironmentVariable("Path", "User") + ";C:\flutter\bin", "User")
```

```bash
# Git Bash / current session only:
export PATH="/c/flutter/bin:$PATH"
```

## Running the app

From the repository root:

```bash
flutter pub get
flutter run -d chrome
```

This opens the game in a dedicated Chrome window with hot reload enabled
(press `r` in the terminal to hot reload, `R` to hot restart, `q` to quit).

To run on Edge instead: `flutter run -d edge`.

To run as a native Windows app (requires the Visual Studio C++ toolchain
mentioned above): `flutter run -d windows`.

### Building a standalone web build

If you'd rather not run the dev server, build a static bundle and serve it
yourself:

```bash
flutter build web --release
```

The output goes to `build/web/` - serve that directory with any static
file server (e.g. `npx serve build/web`) and open the printed URL.

## Running tests

Engine unit tests (pure Dart, fast):

```bash
cd packages/game_engine
dart test
```

Flutter widget tests:

```bash
flutter test
```

Static analysis:

```bash
flutter analyze
cd packages/game_engine && dart analyze
```

## Balance simulation

Runs N full games with random-legal-move bots and prints average game
length, win counts by win type, and play counts per card:

```bash
cd packages/game_engine
dart run bin/simulate.dart [gameCount] [seed]
```

Defaults to 200 games with a fixed seed if no arguments are given.

## How to play (hotseat)

1. On the setup screen, enter 2-6 player names and tap **Start Game**.
2. Each turn: pass the device to the named player, tap **I'm ready**, then
   **Draw**, optionally play one card, discard down to 5 if needed, then
   **End turn**.
3. When attacked, the defender gets a **Defense** screen to play a defense
   card (Prayer / It Is Written / Fellowship) or take the hit.
4. The game ends when one player is fully eliminated (all 6 armor pieces
   Lost) or fully restored (all 6 Strong at the start of their turn, after
   having been damaged at some point).
