import 'package:flutter/material.dart';

/// The Armor Up! brand palette. Hardcoded on purpose: this is fixed brand
/// color, not something that should shift with system dark/light mode.
/// Every screen and widget must reference these constants rather than
/// redeclaring colors locally, so a palette tweak stays a one-file change.
class ArmorUpColors {
  ArmorUpColors._();

  // Card face - dark charcoal/slate theme (matches the reference card UI:
  // near-black board, dark slate card interior, warm gold trim/text).
  static const cardBackground = Color(0xFF262A35);
  static const cardStroke = Color(0xFF14161C); // outer border
  static const cardInnerStroke = Color(
    0xFFEDE6D6,
  ); // inner ring, same as font color
  static const descriptionBackground = Color(0xFF3A3F4E);
  static const fontColor = Color(0xFFEDE6D6);
  static const fontStrokeColor = Colors.black;

  // Illustration medallion ring (the circular frame around card art,
  // reuses the same brown as descriptionBackground) and the thin gold
  // accent used on the medallion/banner/card border rings.
  static const medallionRing = descriptionBackground;
  static const goldAccent = Color(0xFFC9A24B);

  // Name banner, per card type.
  static const bannerAttack = Color(0xFF9B4040);
  static const bannerEvent = Color(0xFF8A56A0);
  static const bannerDefense = Color(0xFF78A8BA);
  static const bannerRestore = Color(0xFF989550);

  // Armor piece condition. Strong reuses the Restore banner olive so
  // "healthy" reads as "restoration"; Weakened is a warm bronze in the
  // same family; Lost is desaturated parchment-gray.
  static const armorStrong = Color(0xFF989550);
  static const armorWeakened = Color(0xFFC08A3E);
  static const armorLost = Color(0xFFA89A88);

  // App chrome: a near-black board surface darker than the card face so
  // cards still pop against it (inverted from the old light-parchment
  // scheme, where the board was lighter than the card).
  static const boardBackground = Color(0xFF14161C);

  /// Four offset shadows - up, down, left, right, no blur - that fake a
  /// text outline. Used on banner titles only; a real single-stroke
  /// border is illegible at small sizes, and the outline gets muddy on
  /// small body text.
  static const titleOutline = <Shadow>[
    Shadow(offset: Offset(1, 0), color: fontStrokeColor),
    Shadow(offset: Offset(-1, 0), color: fontStrokeColor),
    Shadow(offset: Offset(0, 1), color: fontStrokeColor),
    Shadow(offset: Offset(0, -1), color: fontStrokeColor),
  ];
}
