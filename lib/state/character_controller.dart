import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/pixel_ui.dart';

/// The local player's customized avatar, set from [CharacterPickerScreen]
/// and applied to their own pixel-head avatar everywhere it's shown
/// in-game (see `PixelAvatar` usages keyed off `me.id` in
/// `game_screen.dart`). Not persisted across app launches - like the rest
/// of the app's Riverpod state, this lives only for the current process.
@immutable
class Character {
  final bool female;
  final Color hair;
  final Color skin;
  final Color eye;
  final Color accent;
  final String name;

  // Defaults mirror characterHairPresets[0] / characterSkinPresets[0] /
  // characterEyePresets[0] / characterAccentPresets[0] - indexing into
  // those const lists isn't itself a const expression, so the literal
  // values are duplicated here.
  const Character({
    this.female = false,
    this.hair = const Color(0xFF3B2A1A),
    this.skin = const Color(0xFFE8B98A),
    this.eye = const Color(0xFF1A1410),
    this.accent = const Color(0xFF9B4040),
    this.name = 'Player',
  });

  Character copyWith({
    bool? female,
    Color? hair,
    Color? skin,
    Color? eye,
    Color? accent,
    String? name,
  }) =>
      Character(
        female: female ?? this.female,
        hair: hair ?? this.hair,
        skin: skin ?? this.skin,
        eye: eye ?? this.eye,
        accent: accent ?? this.accent,
        name: name ?? this.name,
      );

  AvatarPalette get palette => AvatarPalette(
        hair: hair,
        skin: skin,
        eye: eye,
        accent: accent,
        female: female,
      );
}

class CharacterController extends StateNotifier<Character> {
  CharacterController() : super(const Character());

  void setFemale(bool female) => state = state.copyWith(female: female);
  void setHair(Color color) => state = state.copyWith(hair: color);
  void setSkin(Color color) => state = state.copyWith(skin: color);
  void setEye(Color color) => state = state.copyWith(eye: color);
  void setAccent(Color color) => state = state.copyWith(accent: color);

  void setName(String name) =>
      state = state.copyWith(name: name.trim().isEmpty ? 'Player' : name);
}

final characterControllerProvider =
    StateNotifierProvider<CharacterController, Character>((ref) => CharacterController());
