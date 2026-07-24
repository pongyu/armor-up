import 'package:shared_preferences/shared_preferences.dart';

/// Everything a client needs to call `GameClient.reconnect` again without
/// the user re-entering the host address or their name: captured once
/// `GameClient.lobbyStarted` fires (see `_AppRoot._listenToClient` in
/// `main.dart`), persisted to disk so it survives the app being killed and
/// relaunched, and cleared once the session ends for good (deliberate
/// "back to start", or the host/session ending unrecoverably).
///
/// Host-side: if the host's own process is killed, its `HostServer` and
/// all game state go with it - there is nothing durable on disk for a
/// killed host to resume from, so this only ever helps a *guest* reconnect
/// to a host that is still running.
class ReconnectInfo {
  final String hostAddress;
  final int hostPort;
  final String playerId;
  final String sessionToken;

  const ReconnectInfo({
    required this.hostAddress,
    required this.hostPort,
    required this.playerId,
    required this.sessionToken,
  });

  static const _keyHostAddress = 'reconnect.hostAddress';
  static const _keyHostPort = 'reconnect.hostPort';
  static const _keyPlayerId = 'reconnect.playerId';
  static const _keySessionToken = 'reconnect.sessionToken';

  static Future<void> save(ReconnectInfo info) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyHostAddress, info.hostAddress);
    await prefs.setInt(_keyHostPort, info.hostPort);
    await prefs.setString(_keyPlayerId, info.playerId);
    await prefs.setString(_keySessionToken, info.sessionToken);
  }

  /// Null if nothing is saved, or a prior save is incomplete/corrupt.
  static Future<ReconnectInfo?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final hostAddress = prefs.getString(_keyHostAddress);
    final hostPort = prefs.getInt(_keyHostPort);
    final playerId = prefs.getString(_keyPlayerId);
    final sessionToken = prefs.getString(_keySessionToken);
    if (hostAddress == null || hostPort == null || playerId == null || sessionToken == null) {
      return null;
    }
    return ReconnectInfo(
      hostAddress: hostAddress,
      hostPort: hostPort,
      playerId: playerId,
      sessionToken: sessionToken,
    );
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyHostAddress);
    await prefs.remove(_keyHostPort);
    await prefs.remove(_keyPlayerId);
    await prefs.remove(_keySessionToken);
  }
}
