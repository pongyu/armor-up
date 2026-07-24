import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// Auto-loaded by `flutter_test` for every test file in this directory (and
/// subdirectories) before its `main()` runs. Without this, any test that
/// exercises a code path touching `SharedPreferences` (e.g.
/// `AppModeController.returnToModeSelect` clearing the persisted
/// `ReconnectInfo` - see `lib/net/reconnect_info.dart`) throws
/// `MissingPluginException`, since no platform channel implementation is
/// registered in a plain widget-test environment.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  SharedPreferences.setMockInitialValues({});
  await testMain();
}
