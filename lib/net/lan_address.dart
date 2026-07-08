import 'dart:io';

/// Finds this device's LAN-facing IPv4 address - the one joiners on the
/// same WiFi network would use to reach a [HostServer] bound to
/// [InternetAddress.anyIPv4]. Returns null if no non-loopback IPv4
/// interface is found (e.g. no network connection).
///
/// When multiple interfaces are up (uncommon on phones, more common on
/// desktop with both WiFi and Ethernet), the first one found is used -
/// good enough for a LAN party app where the host picks a network before
/// creating a lobby; a future improvement could let the host choose
/// explicitly if this guess is ever wrong in practice.
Future<String?> findLanAddress() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
    includeLinkLocal: false,
  );
  for (final interface in interfaces) {
    for (final address in interface.addresses) {
      if (!address.isLoopback) {
        return address.address;
      }
    }
  }
  return null;
}
