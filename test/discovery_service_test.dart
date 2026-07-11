import 'dart:math';

import 'package:armor_up/net/discovery_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('generateShortCode', () {
    test('produces a 4-character uppercase alphanumeric code', () {
      final code = generateShortCode(random: Random(1));
      expect(code.length, 4);
      expect(code, matches(RegExp(r'^[A-Z0-9]{4}$')));
    });

    test('excludes visually ambiguous characters', () {
      // Run many samples to make the absence of 0/O/1/I/L a meaningful
      // assertion rather than luck.
      for (var seed = 0; seed < 200; seed++) {
        final code = generateShortCode(random: Random(seed));
        expect(code.contains('0'), isFalse);
        expect(code.contains('O'), isFalse);
        expect(code.contains('1'), isFalse);
        expect(code.contains('I'), isFalse);
        expect(code.contains('L'), isFalse);
      }
    });
  });

  group('buildServiceName / parseServiceName', () {
    test('round-trips a game name and short code', () {
      final name = buildServiceName(gameName: "Mumu's Game", shortCode: 'K7QP');
      expect(name, "Mumu's Game [K7QP]");

      final parsed = parseServiceName(name);
      expect(parsed, isNotNull);
      expect(parsed!.gameName, "Mumu's Game");
      expect(parsed.shortCode, 'K7QP');
    });

    test('returns null for a service name from an unrelated app', () {
      expect(parseServiceName('Some Other Service'), isNull);
      expect(parseServiceName('Printer [not-a-code]'), isNull);
    });
  });
}
