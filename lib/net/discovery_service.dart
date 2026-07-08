import 'dart:async';
import 'dart:math';

import 'package:nsd/nsd.dart' as nsd;

/// The mDNS/DNS-SD service type Armor Up! hosts advertise under. Kept
/// separate from other apps' services on the same network.
const _serviceType = '_armorup._tcp';

/// A discovered host, as seen by a joiner browsing the network.
class DiscoveredGame {
  final String gameName;
  final String shortCode;
  final String address;
  final int port;

  const DiscoveredGame({
    required this.gameName,
    required this.shortCode,
    required this.address,
    required this.port,
  });
}

/// Generates a 4-character alphanumeric room code. Uppercase letters and
/// digits only, excluding visually ambiguous characters (0/O, 1/I/L) so
/// it's easy to read aloud and type back in on the manual-entry fallback.
String generateShortCode({Random? random}) {
  const chars = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  final rand = random ?? Random();
  return List.generate(4, (_) => chars[rand.nextInt(chars.length)]).join();
}

/// Publishes an mDNS service for [gameName] (with [shortCode] embedded in
/// the service name, e.g. "Mumu's Game [K7QP]") on [port]. Returns the
/// active registration handle - keep it and pass it to [stopAdvertising]
/// when the lobby closes or the host stops.
Future<nsd.Registration> advertiseGame({
  required String gameName,
  required String shortCode,
  required int port,
}) {
  return nsd.register(
    nsd.Service(
      name: buildServiceName(gameName: gameName, shortCode: shortCode),
      type: _serviceType,
      port: port,
    ),
  );
}

Future<void> stopAdvertising(nsd.Registration registration) => nsd.unregister(registration);

/// Builds the mDNS service name for [gameName]/[shortCode], e.g.
/// "Mumu's Game [K7QP]".
String buildServiceName({required String gameName, required String shortCode}) =>
    '$gameName [$shortCode]';

/// Parses a service name built by [buildServiceName] back into its
/// display name and short code. Returns null if [serviceName] doesn't
/// match the expected shape (e.g. a service from an unrelated app that
/// happens to share the service type, or a malformed name) - callers
/// should skip such entries rather than guess.
({String gameName, String shortCode})? parseServiceName(String serviceName) {
  final match = RegExp(r'^(.*) \[([A-Z0-9]{4})\]$').firstMatch(serviceName);
  if (match == null) return null;
  return (gameName: match.group(1)!, shortCode: match.group(2)!);
}

/// Browses for Armor Up! games on the local network. Yields the current
/// set of discovered games every time it changes (a service appearing or
/// disappearing) until [cancel] is called on the returned subscription's
/// controller - callers should call [stopDiscovery] with the same
/// [nsd.Discovery] handle when the join screen is dismissed.
class GameDiscovery {
  nsd.Discovery? _discovery;
  final _controller = StreamController<List<DiscoveredGame>>.broadcast();

  Stream<List<DiscoveredGame>> get games => _controller.stream;

  Future<void> start() async {
    final discovery = await nsd.startDiscovery(
      _serviceType,
      ipLookupType: nsd.IpLookupType.v4,
    );
    _discovery = discovery;
    discovery.addServiceListener((service, status) => _emit(discovery));
    _emit(discovery);
  }

  void _emit(nsd.Discovery discovery) {
    if (_controller.isClosed) return;
    final games = <DiscoveredGame>[];
    for (final service in discovery.services) {
      final name = service.name;
      final host = service.addresses?.firstOrNull?.address;
      final port = service.port;
      if (name == null || host == null || port == null) continue;
      final parsed = parseServiceName(name);
      if (parsed == null) continue;
      games.add(
        DiscoveredGame(
          gameName: parsed.gameName,
          shortCode: parsed.shortCode,
          address: host,
          port: port,
        ),
      );
    }
    _controller.add(games);
  }

  Future<void> stop() async {
    final discovery = _discovery;
    if (discovery != null) {
      await nsd.stopDiscovery(discovery);
    }
    await _controller.close();
  }
}
