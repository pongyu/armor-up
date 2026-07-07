import 'package:flutter/material.dart';

/// The Armor Up! brand palette. Hardcoded on purpose: this is fixed brand
/// color, not something that should shift with system dark/light mode.
/// Every screen and widget must reference these constants rather than
/// redeclaring colors locally, so a palette tweak stays a one-file change.
class ArmorUpColors {
  ArmorUpColors._();

  // Card face.
  static const cardBackground = Color(0xFFE8DFD0);
  static const cardStroke = Color(0xFF2A1C0F); // outer border
  static const cardInnerStroke = Color(0xFFEDDDC3); // inner ring, same as font color
  static const descriptionBackground = Color(0xFF7E584B);
  static const fontColor = Color(0xFFEDDDC3);
  static const fontStrokeColor = Colors.black;

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

  // App chrome, derived from the same warm family: a parchment board
  // surface lighter than the card face so cards still pop against it.
  static const boardBackground = Color(0xFFF3EBDC);

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
