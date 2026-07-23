import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/character_controller.dart';
import '../theme/armor_up_colors.dart';
import '../widgets/pixel_ui.dart';

/// Avatar customization (claude.ai/design "Armor Up Redesign", Character
/// tab): gender, hair/skin/eye/accent color, and display name, backed by
/// [characterControllerProvider]. Reachable from mode-select/setup/lobby
/// screens; on save, returns to whichever screen pushed it and the
/// player's own avatar everywhere in-game reflects the customized sprite
/// (see the `me.id`-keyed `PixelAvatar` in `game_screen.dart`).
class CharacterPickerScreen extends ConsumerStatefulWidget {
  const CharacterPickerScreen({super.key});

  @override
  ConsumerState<CharacterPickerScreen> createState() => _CharacterPickerScreenState();
}

class _CharacterPickerScreenState extends ConsumerState<CharacterPickerScreen> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: ref.read(characterControllerProvider).name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final character = ref.watch(characterControllerProvider);
    final controller = ref.read(characterControllerProvider.notifier);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _PixelTitle('CHARACTER'),
                  const SizedBox(height: 16),
                  Center(child: _AvatarPreview(character: character)),
                  const SizedBox(height: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'YOUR NAME',
                        style: TextStyle(
                          fontSize: 8.5,
                          letterSpacing: 0.5,
                          color: ArmorUpColors.mutedLabel,
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _nameController,
                        onChanged: controller.setName,
                        style: const TextStyle(
                          fontSize: 11,
                          color: ArmorUpColors.fontColor,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          filled: true,
                          fillColor: ArmorUpColors.boardBackground,
                          contentPadding: const EdgeInsets.all(12),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: const BorderSide(
                              color: ArmorUpColors.descriptionBackground,
                              width: 2,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: const BorderSide(
                              color: ArmorUpColors.goldAccent,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _SectionLabel('GENDER'),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: _GenderButton(
                          label: 'MALE',
                          selected: !character.female,
                          onTap: () => controller.setFemale(false),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _GenderButton(
                          label: 'FEMALE',
                          selected: character.female,
                          onTap: () => controller.setFemale(true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _SectionLabel('HAIR COLOR'),
                  const SizedBox(height: 6),
                  _SwatchRow(
                    presets: ArmorUpColors.characterHairPresets,
                    selected: character.hair,
                    onPick: controller.setHair,
                  ),
                  const SizedBox(height: 14),
                  _SectionLabel('SKIN TONE'),
                  const SizedBox(height: 6),
                  _SwatchRow(
                    presets: ArmorUpColors.characterSkinPresets,
                    selected: character.skin,
                    onPick: controller.setSkin,
                  ),
                  const SizedBox(height: 14),
                  _SectionLabel('EYE COLOR'),
                  const SizedBox(height: 6),
                  _SwatchRow(
                    presets: ArmorUpColors.characterEyePresets,
                    selected: character.eye,
                    onPick: controller.setEye,
                  ),
                  const SizedBox(height: 14),
                  _SectionLabel('MOUTH / ACCENT'),
                  const SizedBox(height: 6),
                  _SwatchRow(
                    presets: ArmorUpColors.characterAccentPresets,
                    selected: character.accent,
                    onPick: controller.setAccent,
                  ),
                  const SizedBox(height: 20),
                  GoldPillButton(
                    label: 'SAVE & CONTINUE',
                    fontSize: 12,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 8.5,
        letterSpacing: 1,
        color: ArmorUpColors.mutedLabel,
      ),
    );
  }
}

class _PixelTitle extends StatelessWidget {
  final String text;

  const _PixelTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: const TextStyle(
            fontSize: 18,
            color: ArmorUpColors.fontColor,
            shadows: ArmorUpColors.titleOutline,
          ),
        ),
        const SizedBox(height: 6),
        Container(width: 56, height: 3, color: ArmorUpColors.goldAccent),
      ],
    );
  }
}

/// The 112x112 avatar preview: continuous idle bob + periodic blink,
/// exactly as specced in the design handoff (2.2s bob loop, ~130ms blink
/// every ~3.2s).
class _AvatarPreview extends StatefulWidget {
  final Character character;

  const _AvatarPreview({required this.character});

  @override
  State<_AvatarPreview> createState() => _AvatarPreviewState();
}

class _AvatarPreviewState extends State<_AvatarPreview> with SingleTickerProviderStateMixin {
  late final AnimationController _bobController;
  Timer? _blinkTimer;
  bool _blinking = false;

  @override
  void initState() {
    super.initState();
    _bobController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 3200), (_) {
      if (!mounted) return;
      setState(() => _blinking = true);
      Timer(const Duration(milliseconds: 130), () {
        if (mounted) setState(() => _blinking = false);
      });
    });
  }

  @override
  void dispose() {
    _bobController.dispose();
    _blinkTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return AnimatedBuilder(
      animation: _bobController,
      builder: (context, child) {
        final t = reduceMotion ? 0.0 : (1 - (2 * _bobController.value - 1).abs());
        return Transform.translate(offset: Offset(0, -6 * t), child: child);
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(color: widget.character.accent.withValues(alpha: 0.4), blurRadius: 18),
          ],
        ),
        child: PixelAvatar(
          palette: widget.character.palette,
          size: 112,
          borderColor: widget.character.accent,
          borderWidth: 3,
          blinking: _blinking,
        ),
      ),
    );
  }
}

class _GenderButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _GenderButton({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? ArmorUpColors.goldBright.withValues(alpha: 0.15)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? ArmorUpColors.goldBright : const Color(0xFF3A3F4E),
              width: 2,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              color: selected ? ArmorUpColors.goldBright : ArmorUpColors.mutedLabel,
            ),
          ),
        ),
      ),
    );
  }
}

/// One color-channel row: preset circular swatches plus a rainbow
/// "custom" swatch that opens [_CustomColorDialog]. The custom swatch
/// gets the same gold selected-ring treatment whenever [selected] isn't
/// one of [presets].
class _SwatchRow extends StatelessWidget {
  final List<Color> presets;
  final Color selected;
  final ValueChanged<Color> onPick;

  const _SwatchRow({required this.presets, required this.selected, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final isCustom = !presets.any((c) => c.toARGB32() == selected.toARGB32());
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final color in presets)
          _Swatch(
            color: color,
            selected: color.toARGB32() == selected.toARGB32(),
            onTap: () => onPick(color),
          ),
        _CustomSwatch(
          selected: isCustom,
          currentColor: selected,
          onPick: onPick,
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _Swatch({required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: selected ? ArmorUpColors.goldBright : Colors.transparent,
            width: 3,
          ),
          boxShadow: selected
              ? [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 10)]
              : null,
        ),
      ),
    );
  }
}

class _CustomSwatch extends StatelessWidget {
  final bool selected;
  final Color currentColor;
  final ValueChanged<Color> onPick;

  const _CustomSwatch({
    required this.selected,
    required this.currentColor,
    required this.onPick,
  });

  Future<void> _openPicker(BuildContext context) async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (context) => _CustomColorDialog(initialColor: currentColor),
    );
    if (picked != null) onPick(picked);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openPicker(context),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const SweepGradient(
            colors: [
              Colors.red,
              Colors.yellow,
              Colors.green,
              Colors.cyan,
              Colors.blue,
              Colors.pink,
              Colors.red,
            ],
          ),
          border: Border.all(
            color: selected ? ArmorUpColors.goldBright : const Color(0xFF3A3F4E),
            width: 3,
          ),
        ),
      ),
    );
  }
}

/// Stand-in for the design's native `<input type="color">`: Flutter has
/// no built-in color-wheel widget, so this is a minimal HSV picker (hue
/// strip + saturation/value pad) that previews live and returns the
/// chosen color on confirm.
class _CustomColorDialog extends StatefulWidget {
  final Color initialColor;

  const _CustomColorDialog({required this.initialColor});

  @override
  State<_CustomColorDialog> createState() => _CustomColorDialogState();
}

class _CustomColorDialogState extends State<_CustomColorDialog> {
  late HSVColor _hsv;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initialColor);
  }

  @override
  Widget build(BuildContext context) {
    final color = _hsv.toColor();
    return AlertDialog(
      backgroundColor: ArmorUpColors.panelBackground,
      title: const Text(
        'CUSTOM COLOR',
        style: TextStyle(fontSize: 12, color: ArmorUpColors.fontColor),
      ),
      content: SizedBox(
        width: 260,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: ArmorUpColors.goldAccent, width: 2),
              ),
            ),
            const SizedBox(height: 16),
            _GradientSlider(
              gradientColors: const [
                Colors.red,
                Colors.yellow,
                Colors.green,
                Colors.cyan,
                Colors.blue,
                Colors.pink,
                Colors.red,
              ],
              value: _hsv.hue / 360,
              onChanged: (v) => setState(() => _hsv = _hsv.withHue(v * 360)),
            ),
            const SizedBox(height: 8),
            _GradientSlider(
              gradientColors: [Colors.white, _hsv.withSaturation(1).toColor()],
              value: _hsv.saturation,
              onChanged: (v) => setState(() => _hsv = _hsv.withSaturation(v)),
            ),
            const SizedBox(height: 8),
            _GradientSlider(
              gradientColors: [Colors.black, _hsv.withValue(1).toColor()],
              value: _hsv.value,
              onChanged: (v) => setState(() => _hsv = _hsv.withValue(v)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('CANCEL', style: TextStyle(fontSize: 9.5)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(color),
          child: const Text('USE COLOR', style: TextStyle(fontSize: 9.5)),
        ),
      ],
    );
  }
}

class _GradientSlider extends StatelessWidget {
  final List<Color> gradientColors;
  final double value;
  final ValueChanged<double> onChanged;

  const _GradientSlider({
    required this.gradientColors,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 14,
        activeTrackColor: Colors.transparent,
        inactiveTrackColor: Colors.transparent,
        thumbColor: Colors.white,
        overlayColor: Colors.transparent,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: 14,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              gradient: LinearGradient(colors: gradientColors),
            ),
          ),
          Slider(
            value: value.clamp(0, 1),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
