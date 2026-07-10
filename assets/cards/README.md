# Card art spec

Drop one PNG per card into this folder, named exactly `<card_id>.png` (ids
below, matching `CardDef.id` / the keys in
[`lib/widgets/card_display.dart`](../../lib/widgets/card_display.dart)).

## Card frame border (`card_frame.png`)

The pixelated card border/corners is a separate nine-slice asset, already
wired in `lib/widgets/card_widget.dart` (`_CardFrame`):

- **Canvas**: 48x48px.
- **Corners**: 12x12px each, drawn with pixelated stair-step edges (this
  is the only part where the actual corner shape lives - never stretched).
- **Edges**: the 24px-long strips between corners are straight border
  segments (no curve); Flutter stretches these to fit the card's real
  on-screen size via `centerSlice`.
- **Center**: the middle 24x24px must be fully transparent - the card's
  own parchment fill and content render underneath it.
- **Palette**: `ArmorUpColors.cardStroke` (outer, `#2A1C0F`) and
  `ArmorUpColors.goldAccent` (inner ring, `#C9A24B`), same as the rest of
  the card chrome.
- Border thickness must stay consistent between the corner tiles and the
  edge strips, or the stretched edges won't align with the fixed corners
  at the seam.

Selection state is *not* baked into this asset - it's a fixed single
frame; the colored glow shown when a card is selected is layered on
separately in Flutter (`_CardFrame`'s `boxShadow`), not part of the PNG.

## Name banner (`name_banner.png`)

The card name plaque - a notched-end shape (tapered left/right caps, not
a rounded pill), wired in `lib/widgets/card_widget.dart` (`_NameBanner`):

- **Canvas**: 64x24px.
- **End caps**: 0-6px and 58-64px (full canvas height), drawn with the
  tapered/notched silhouette - never stretched.
- **Middle**: 6-58px, flat top/bottom edges spanning the full height;
  Flutter stretches this horizontally via `centerSlice` to fit however
  long the card name needs. This is a *three*-slice (only stretches
  horizontally), not a full nine-slice like the card frame - the
  `centerSlice` rect spans the image's entire height so nothing distorts
  vertically.
- **Color**: draw it in a neutral/desaturated tone - it gets tinted
  toward the card's type color at render time via `BlendMode.modulate`
  (same approach as the card's type-tinted background), not drawn once
  per type.
- **Palette accents**: `ArmorUpColors.goldAccent` (`#C9A24B`) for the
  outline, matching the rest of the card chrome.

## Format

- **Style**: rich shaded pixel art, not flat 1-bit retro. Pixel-grid bones
  (blocky silhouette, visible pixel units, stair-step diagonals) but with
  gradients, ambient/rim lighting, glow on magic/metal highlights, and
  soft drop shadows allowed and expected - think Slay the Spire / Dead
  Cells UI, not classic flat-fill SNES item icons. This supersedes the
  "no gradients/no glow/no shading" language in the AI prompt prefix
  below (kept from an earlier flatter direction); when the two disagree,
  this section wins.
- **File type**: PNG with transparency (no background fill - the parchment
  illustration box shows through). Most generators can't output alpha
  directly - generate on a flat solid magenta (`#FF00FF`) background
  instead (a color that never appears in the actual palette below) and
  chroma-key it to transparent afterward, rather than fighting the
  generator for true transparency.
- **Canvas size**: 96x96px, square. Render at this size natively; don't
  upscale from smaller source art. `CardWidget` displays it inside a
  square `AspectRatio(1)` box sized off the card's own width (roughly
  100-110px on the default card size), using `BoxFit.contain`, so
  anything under ~96px will look soft.
- **Filter quality**: the renderer forces `FilterQuality.none` (nearest
  neighbor, no smoothing). This still matters for this richer style -
  it's why the pixel-grid bones (blocky edges, visible pixel units) need
  to stay crisp even though shading/gradients are now allowed within
  each pixel block.
- **Palette**: pull colors from `ArmorUpColors`
  ([lib/theme/armor_up_colors.dart](../../lib/theme/armor_up_colors.dart))
  where possible so art doesn't clash with the card frame. In particular
  avoid the exact card-background parchment tone (`0xFFE8DFD0`) as a fill
  color, since it'll blend into the frame, and avoid magenta/pink (the
  chroma-key color above).
- **Composition**: single centered icon/subject, not a scene. The box is
  small and square - think "app icon", not "illustration panel".

## Frame/banner redo (pending)

`card_frame.png` and `name_banner.png` currently exist but were drawn
flat (solid gold fill, no texture/shading) from the earlier flat-retro
direction. They need a redo pass to match the richer shaded style above
- e.g. carved stone or wood grain texture, a beveled edge (highlight on
one side, shadow on the other) rather than a single flat gold tone, and
a subtle ambient glow - while keeping their existing shapes/slicing
(48x48 nine-slice frame with 12x12 corners, 64x24 three-slice banner
with 6px end caps) unchanged, since those are load-bearing in
`lib/widgets/card_widget.dart`.

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
detailed pixel art game icon, painterly shaded pixel art style (like
Slay the Spire or Dead Cells item icons), visible pixel grid with
blocky silhouette and jagged stair-step edges on curves/diagonals, but
with rich shading within that grid: gradients, ambient light, soft rim
lighting, and glow on magic/metal highlights are all wanted, plus a
subtle soft drop shadow under the subject. 1-2px dark outline. limited
warm muted palette (parchment tan, dark brown, muted red, dusty teal,
olive gold, deep purple), single centered subject filling most of the
frame, flat solid magenta background color (#FF00FF, pure chroma-key
magenta, no gradient or texture on the background itself, no shadow
cast onto it, and don't use magenta/pink anywhere in the subject),
game icon style like a high-fidelity JRPG item icon or tarot symbol,
not a scene, no background elements, no text, no border, no frame.
```

If the generator returns fully smooth/vector art with no visible pixel
grid at all despite this prompt, add explicitly: "pixel art sprite,
Dead Cells/Hollow Knight item icon style, hand-placed pixels" and/or
generate at a small native resolution (e.g. 64x64) and upscale with
**Nearest Neighbor** resampling in Photoshop (`Image > Image Size`,
resample: Nearest Neighbor) to force a crisp pixel grid before
re-adding/cleaning up shading by hand - this is a deterministic
post-process rather than hoping the model gets it right.

To strip the magenta background in Photoshop: Select > Color Range,
sample the magenta, feather 0, then delete and clean up any leftover
fringe pixels by hand (soft/blended edge pixels won't key out cleanly
and need manual touch-up) before flattening to the final transparent
PNG.

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
