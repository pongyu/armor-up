import 'package:flutter/material.dart';
import 'package:net/net.dart';

import '../theme/armor_up_colors.dart';

/// Shared building blocks of the redesign template (claude.ai/design
/// "Armor Up Redesign"): the 8x8 pixel-head avatar, the pulsing status
/// dot, the gold gradient pill button, and the flat dark action button.
/// Kept together in one file because they are pure chrome - no game
/// state - and every redesigned screen draws from the same small kit.

/// 8x8 pixel head grid: H hair, S skin, E eye, M mouth/accent,
/// _ transparent. The "male" silhouette; [_femaleHeadGrid] is the same
/// face with hair extended past the jaw so gender reads at a glance
/// even at 8x8 resolution. Random/seeded avatars (opponents without a
/// saved [Character]) always use the male grid; a player's own
/// customized avatar picks whichever grid matches their chosen gender.
const List<String> _maleHeadGrid = [
  '__HHHH__',
  '_HHHHHH_',
  'HHSSSSHH',
  'HSSSSSSH',
  'HSESSESH',
  'HSSSSSSH',
  '_SSMMSS_',
  '__SSSS__',
];

const List<String> _femaleHeadGrid = [
  '__HHHH__',
  '_HHHHHH_',
  'HHSSSSHH',
  'HSSSSSSH',
  'HSESSESH',
  'HSSSSSSH',
  'HSSMMSSH',
  'HH_SS_HH',
];

/// Full avatar palette: hair/skin/eye/accent colors plus which grid
/// (gender silhouette) to draw. Seeded opponent avatars only vary
/// hair/skin/accent (see [_avatarPalettes]); a customized [Character]
/// supplies all four channels plus gender.
class AvatarPalette {
  final Color hair;
  final Color skin;
  final Color eye;
  final Color accent;
  final bool female;

  const AvatarPalette({
    required this.hair,
    required this.skin,
    this.eye = const Color(0xFF1A1410),
    required this.accent,
    this.female = false,
  });

  @override
  bool operator ==(Object other) =>
      other is AvatarPalette &&
      other.hair == hair &&
      other.skin == skin &&
      other.eye == eye &&
      other.accent == accent &&
      other.female == female;

  @override
  int get hashCode => Object.hash(hair, skin, eye, accent, female);

  /// Converts to the plain-Dart wire representation sent over LAN (see
  /// `LobbyAvatar` in `packages/net`, which can't depend on `dart:ui`'s
  /// `Color`).
  LobbyAvatar toLobbyAvatar() => LobbyAvatar(
        hair: hair.toARGB32(),
        skin: skin.toARGB32(),
        eye: eye.toARGB32(),
        accent: accent.toARGB32(),
        female: female,
      );

  static AvatarPalette fromLobbyAvatar(LobbyAvatar avatar) => AvatarPalette(
        hair: Color(avatar.hair),
        skin: Color(avatar.skin),
        eye: Color(avatar.eye),
        accent: Color(avatar.accent),
        female: avatar.female,
      );
}

const List<AvatarPalette> _avatarPalettes = [
  AvatarPalette(hair: Color(0xFF3B2A1A), skin: Color(0xFFE8B98A), accent: Color(0xFF9B4040)),
  AvatarPalette(hair: Color(0xFF1C1C22), skin: Color(0xFFC98A5B), accent: Color(0xFF78A8BA)),
  AvatarPalette(hair: Color(0xFFC9A24B), skin: Color(0xFFF0D4B0), accent: Color(0xFF8A56A0)),
  AvatarPalette(hair: Color(0xFF6B3D12), skin: Color(0xFFA8794F), accent: Color(0xFF989550)),
  AvatarPalette(hair: Color(0xFF8A8A90), skin: Color(0xFFE0B088), accent: Color(0xFFC97A2B)),
];

/// Tiny procedurally-drawn pixel-art head, used as a player avatar in
/// the board header and opponent chips. [seed] picks a palette
/// deterministically (pass a stable per-player value, e.g. the player's
/// index or name hash) so the same player always gets the same face.
/// Pass [palette] instead to render a specific customized [Character]
/// (e.g. the local player's own saved avatar) - it takes priority over
/// [seed]. [blinking] swaps the eye color to the skin color, for the
/// character picker's idle-blink animation.
class PixelAvatar extends StatelessWidget {
  final int seed;
  final AvatarPalette? palette;
  final double size;
  final Color borderColor;
  final double borderWidth;
  final bool blinking;

  const PixelAvatar({
    super.key,
    this.seed = 0,
    this.palette,
    this.size = 32,
    this.borderColor = ArmorUpColors.goldAccent,
    this.borderWidth = 2,
    this.blinking = false,
  });

  @override
  Widget build(BuildContext context) {
    final resolved = palette ?? _avatarPalettes[seed.abs() % _avatarPalettes.length];
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF0F1015),
        borderRadius: BorderRadius.circular(size * 0.19),
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(painter: _PixelHeadPainter(resolved, blinking)),
    );
  }
}

class _PixelHeadPainter extends CustomPainter {
  final AvatarPalette palette;
  final bool blinking;

  const _PixelHeadPainter(this.palette, this.blinking);

  @override
  void paint(Canvas canvas, Size size) {
    final grid = palette.female ? _femaleHeadGrid : _maleHeadGrid;
    final cell = Size(size.width / 8, size.height / 8);
    final paint = Paint();
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        final ch = grid[y][x];
        if (ch == '_') continue;
        paint.color = switch (ch) {
          'H' => palette.hair,
          'S' => palette.skin,
          'E' => blinking ? palette.skin : palette.eye,
          _ => palette.accent,
        };
        // +0.5 bleed so adjacent cells overlap and no hairline gaps
        // show between "pixels" at non-integer cell sizes.
        canvas.drawRect(
          Rect.fromLTWH(
            x * cell.width,
            y * cell.height,
            cell.width + 0.5,
            cell.height + 0.5,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PixelHeadPainter oldDelegate) =>
      oldDelegate.palette != palette || oldDelegate.blinking != blinking;
}

/// Small pulsing status dot (the "live" indicator next to ACTIVE /
/// BROADCASTING labels). Respects reduce-motion by holding steady.
class PulsingDot extends StatefulWidget {
  final Color color;
  final double size;

  const PulsingDot({
    super.key,
    this.color = ArmorUpColors.activeGreen,
    this.size = 7,
  });

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = reduceMotion ? 1.0 : _controller.value;
        return Opacity(
          opacity: 0.55 + 0.45 * t,
          child: Transform.scale(
            scale: 1 + 0.15 * t,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color,
                boxShadow: [
                  BoxShadow(color: widget.color, blurRadius: 6 * t),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The template's primary call-to-action: a rounded gold-gradient pill
/// with dark-bronze text. Falls back to a muted flat fill when disabled.
class GoldPillButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final double fontSize;
  final EdgeInsetsGeometry padding;

  const GoldPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.fontSize = 12.5,
    this.padding = const EdgeInsets.symmetric(vertical: 13),
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: enabled
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [ArmorUpColors.goldBright, ArmorUpColors.goldDeep],
              )
            : null,
        color: enabled ? null : const Color(0xFF2A2D38),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: enabled ? ArmorUpColors.goldEdge : ArmorUpColors.panelBorder,
          width: 2,
        ),
        boxShadow: enabled
            ? const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onPressed,
          child: Padding(
            padding: padding,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: fontSize,
                color: enabled ? ArmorUpColors.onGold : const Color(0xFF5B5F6E),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Flat dark action button (the DRAW / DISCARD boxes of the template's
/// bottom action bar). [primary] swaps it to the gold-gradient variant
/// used for PLAY CARD, with squarer corners than [GoldPillButton] so it
/// reads as part of the bar rather than a standalone pill.
class PixelActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  const PixelActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final Color textColor;
    if (primary && enabled) {
      textColor = ArmorUpColors.onGold;
    } else if (enabled) {
      textColor = ArmorUpColors.fontColor;
    } else {
      textColor = const Color(0xFF5B5F6E);
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: primary && enabled
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [ArmorUpColors.goldBright, ArmorUpColors.goldDeep],
              )
            : null,
        color: primary && enabled
            ? null
            : enabled
                ? ArmorUpColors.panelBackground
                : const Color(0xFF2A2D38),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: primary && enabled
              ? ArmorUpColors.goldEdge
              : const Color(0xFF3A3F4E),
          width: 2,
        ),
        boxShadow: primary && enabled
            ? const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 10.5,
                  color: textColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Stable avatar seed for a player: derived from the player's id so it
/// survives list reordering/elimination, matching "same player, same
/// face" across every screen that shows an avatar.
int avatarSeedFor(String playerId) => playerId.codeUnits.fold(0, (a, b) => a + b);
