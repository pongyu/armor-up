# Card art spec

Drop one PNG per card into this folder, named exactly `<card_id>.png` (ids
below, matching `CardDef.id` / the keys in
[`lib/widgets/card_display.dart`](../../lib/widgets/card_display.dart)).

## Format

- **File type**: PNG with transparency (no background fill - the parchment
  illustration box shows through).
- **Canvas size**: 64x64px, square. Render at this size natively; don't
  upscale from smaller source art. `CardWidget` displays it at ~54px tall
  inside a `BoxFit.contain` box, so anything under ~64px will look soft.
- **Filter quality**: the renderer forces `FilterQuality.none` (nearest
  neighbor, no smoothing) - this is a pixel-art hard constraint, not a
  style suggestion. Anti-aliased / soft-gradient art will look wrong
  (aliased edges instead of smooth ones). Draw actual pixel art: flat
  color fills, hard 1px edges, no gradients or blur.
- **Palette**: pull colors from `ArmorUpColors`
  ([lib/theme/armor_up_colors.dart](../../lib/theme/armor_up_colors.dart))
  where possible so art doesn't clash with the card frame. In particular
  avoid the exact card-background parchment tone (`0xFFE8DFD0`) as a fill
  color, since it'll blend into the frame.
- **Composition**: single centered icon/subject, not a scene. The box is
  small and square - think "app icon", not "illustration panel".

## Card IDs to fill in

### Attacks (Trials) - `ArmorUpColors.bannerAttack`
- `doubt.png`
- `deception.png`
- `pride.png`
- `discouragement.png`
- `strife.png`
- `confusion.png`
- `fiery_dart.png`
- `goliaths_taunt.png`

### Defenses - `ArmorUpColors.bannerDefense`
- `prayer.png`
- `it_is_written.png`
- `fellowship.png`

### Restores - `ArmorUpColors.bannerRestore`
- `fasting.png`
- `renewal.png`
- `armor_bearer.png`

### Events - `ArmorUpColors.bannerEvent`
- `jericho_march.png`
- `wilderness_season.png`
- `road_to_damascus.png`

## AI prompts

Shared style prefix - prepend this to every per-card subject line below:

```
retro 16-bit SNES-era pixelart sprite icon, low resolution 32x32 pixel
grid scaled up, blocky visible square pixels, jagged stair-step edges on
every curve and diagonal (no smooth curves anywhere), hard-edged flat
color fills with visible pixel blocks, no anti-aliasing, no smoothing,
no dithering, no gradients, no soft shading, no blur, no drop shadow, no
outer glow, 1-pixel-wide dark outline made of visible square pixels,
limited warm muted palette (parchment tan, dark brown, muted red, dusty
teal, olive gold, deep purple), single centered subject on a fully
transparent background, game icon style like a classic JRPG item icon or
tarot symbol, not a scene, no background elements, no text, no border,
no frame.
```

If the generator still returns smooth/anti-aliased art despite this
prompt (common - most image models default to smooth vector style),
add explicitly: "pixelated, low-res upscaled, 8-bit dithered sprite,
Minecraft/Terraria item icon style" and/or generate at a small native
resolution (e.g. 32x32 or 16x16) and upscale with **Nearest Neighbor**
resampling in Photoshop (`Image > Image Size`, resample: Nearest
Neighbor) to force hard pixel edges - this is the most reliable fix
since it's a deterministic post-process rather than hoping the model
gets it right.

Then append the subject for the specific card. Full prompt = prefix + subject.

### Attacks (Trials) - lean toward `bannerAttack` red/brown, ominous mood
- **doubt** - "a cracked round shield with a jagged fracture through the
  center, one shard falling away"
- **deception** - "a two-faced theater mask, one smiling side and one
  sneering side, split down the middle"
- **pride** - "an ornate gold crown tipping sideways about to fall, cracked
  jewel on top"
- **discouragement** - "a dented helmet with its visor drooping and a dark
  storm cloud looming behind it"
- **strife** - "two crossed broken swords clashing, sparks flying at the
  point of impact"
- **confusion** - "a tangled spiral maze of arrows pointing in every
  direction, chaotic knot shape"
- **fiery_dart** - "a single flaming arrow or dart mid-flight, orange-red
  flame trail behind it"
- **goliaths_taunt** - "a giant clenched fist wrapped in spiked bronze
  armor, slamming downward"

### Defenses - lean toward `bannerDefense` teal/blue, calm and protective mood
- **prayer** - "two hands clasped together in prayer, soft warm light
  glowing between the palms"
- **it_is_written** - "an open ancient book with glowing lines of text
  rising off the page like a ward"
- **fellowship** - "three simple linked figures standing shoulder to
  shoulder, arms interlocked, unified silhouette"

### Restores - lean toward `bannerRestore` olive/gold, hopeful mood
- **fasting** - "an hourglass with a small sprouting leaf growing from the
  sand at its base"
- **renewal** - "a single green sprout growing out of a cracked stone,
  spiral of new growth"
- **armor_bearer** - "a breastplate being lifted and re-fastened by a
  second pair of hands, glowing rivets"

### Events - lean toward `bannerEvent` purple, table-wide/dramatic mood
- **jericho_march** - "ancient stone city walls crumbling outward mid-
  collapse, cracks radiating from the base"
- **wilderness_season** - "a lone winding path through cracked desert
  ground under a sparse sun, no landmarks"
- **road_to_damascus** - "a blinding shaft of light striking down onto a
  dusty road, radiating beams"

## Wiring art in once a file lands here

Each card is a one-line change in
[`lib/widgets/card_display.dart`](../../lib/widgets/card_display.dart) -
add `illustrationAssetPath` to its entry:

```dart
'doubt': CardDisplaySpec(
  Icons.help_outline,
  illustrationAssetPath: 'assets/cards/doubt.png',
),
```

The `Icons.help_outline` placeholder can stay as a fallback (it's only
used if `illustrationAssetPath` is null) or be left as-is; either way,
once the path is set, `CardWidget` renders the PNG instead of the icon
automatically. No other code changes needed.
