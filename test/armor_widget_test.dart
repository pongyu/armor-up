import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_engine/game_engine.dart';

import 'package:armor_up/theme/armor_up_colors.dart';
import 'package:armor_up/widgets/armor_widget.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  ArmorPiece piece(ArmorCondition condition) =>
      ArmorPiece(type: ArmorType.helmet, condition: condition);

  /// Finds the CustomPaint whose painter is specifically the private
  /// overlay painter (matched by its runtime type name, since it isn't
  /// exported) - other CustomPaints appear in the tree too (e.g. Material's
  /// ink splash from the badge's InkWell), so a bare `find.byType(CustomPaint)`
  /// over-matches.
  Finder overlayPaintFinder() => find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.foregroundPainter != null &&
            widget.foregroundPainter.runtimeType.toString() == '_ArmorOverlayPainter',
      );

  group('ArmorBadge overlay per condition', () {
    testWidgets('Strong renders no overlay CustomPaint', (tester) async {
      await tester.pumpWidget(wrap(ArmorBadge(piece: piece(ArmorCondition.strong))));
      expect(overlayPaintFinder(), findsNothing);
    });

    testWidgets('Weakened renders exactly one overlay CustomPaint (crack)', (tester) async {
      await tester.pumpWidget(wrap(ArmorBadge(piece: piece(ArmorCondition.weakened))));
      expect(overlayPaintFinder(), findsOneWidget);
    });

    testWidgets('Lost renders exactly one overlay CustomPaint (X)', (tester) async {
      await tester.pumpWidget(wrap(ArmorBadge(piece: piece(ArmorCondition.lost))));
      expect(overlayPaintFinder(), findsOneWidget);
    });
  });

  group('ArmorBadge muted', () {
    Color? borderColorOf(WidgetTester tester) {
      final container = tester.widget<Container>(
        find.descendant(of: find.byType(ArmorBadge), matching: find.byType(Container)).first,
      );
      final decoration = container.decoration as BoxDecoration;
      return (decoration.border as Border).top.color;
    }

    testWidgets('compact variant dims border alpha when muted', (tester) async {
      await tester.pumpWidget(wrap(ArmorBadge(
        piece: piece(ArmorCondition.strong),
        compact: true,
        muted: true,
      )));
      final color = borderColorOf(tester);
      expect(color, ArmorUpColors.armorStrong.withValues(alpha: 0.35));
    });

    testWidgets('full-size variant dims border alpha when muted (regression: '
        'previously only compact applied this)', (tester) async {
      await tester.pumpWidget(wrap(ArmorBadge(
        piece: piece(ArmorCondition.strong),
        compact: false,
        muted: true,
      )));
      final color = borderColorOf(tester);
      expect(color, ArmorUpColors.armorStrong.withValues(alpha: 0.35));
    });

    testWidgets('full-size variant uses full alpha when not muted', (tester) async {
      await tester.pumpWidget(wrap(ArmorBadge(
        piece: piece(ArmorCondition.strong),
        compact: false,
        muted: false,
      )));
      final color = borderColorOf(tester);
      expect(color, ArmorUpColors.armorStrong);
    });
  });

  group('ArmorBadge fasting marker', () {
    testWidgets('shown when fasting is true', (tester) async {
      await tester.pumpWidget(wrap(ArmorBadge(
        piece: piece(ArmorCondition.strong),
        fasting: true,
      )));
      expect(find.byIcon(Icons.hourglass_bottom), findsOneWidget);
    });

    testWidgets('absent when fasting is false', (tester) async {
      await tester.pumpWidget(wrap(ArmorBadge(
        piece: piece(ArmorCondition.strong),
        fasting: false,
      )));
      expect(find.byIcon(Icons.hourglass_bottom), findsNothing);
    });

    testWidgets('removed after an update from fasting true to false', (tester) async {
      await tester.pumpWidget(wrap(ArmorBadge(
        piece: piece(ArmorCondition.strong),
        fasting: true,
      )));
      expect(find.byIcon(Icons.hourglass_bottom), findsOneWidget);

      await tester.pumpWidget(wrap(ArmorBadge(
        piece: piece(ArmorCondition.strong),
        fasting: false,
      )));
      expect(find.byIcon(Icons.hourglass_bottom), findsNothing);
    });
  });

  group('ArmorRow fasting marker wiring', () {
    testWidgets('shown only on the row badge matching fastingRestoreTarget', (tester) async {
      final player = PlayerState(
        id: 'p0',
        name: 'Alice',
        armor: startingArmorSet(),
        hand: const [],
        fastingRestoreTarget: ArmorType.shield,
      );
      await tester.pumpWidget(wrap(ArmorRow(player: player)));
      expect(find.byIcon(Icons.hourglass_bottom), findsOneWidget);
    });

    testWidgets('absent when fastingRestoreTarget is null', (tester) async {
      final player = PlayerState(
        id: 'p0',
        name: 'Alice',
        armor: startingArmorSet(),
        hand: const [],
      );
      await tester.pumpWidget(wrap(ArmorRow(player: player)));
      expect(find.byIcon(Icons.hourglass_bottom), findsNothing);
    });
  });
}
