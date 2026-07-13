# Card background texture

`parchment.png` (currently missing — see "Status" below) is the
background fill for the card face and description panel, wired in
`lib/widgets/card_widget.dart` via `_texturedFill()` and `_TypeTintedFill`.

If this file is missing, both fall back cleanly: `_texturedFill()`'s
`onError` lets the flat `tint` color show through with no crash and no
broken-image icon, and `_TypeTintedFill`'s `errorBuilder` falls back to a
flat `typeColor`-tinted `ColoredBox`. No code changes are needed either
way — dropping a file back in at this path is picked up automatically.

## Status

The previous `parchment.png` (a crop of the Tiny Swords "Regular Paper"
sheet) was removed. Cards currently render with flat tinted fills only.

## Format, if you make a replacement

- **Fit: `BoxFit.cover`, not tiled.** Despite the "texture" name, the
  image is stretched/cropped to cover the panel as a single image, not
  repeated (`ImageRepeat.repeat` was tried and rejected — a repeating
  tile made the crop's seams read as an obvious wallpaper pattern at
  card size). Draw one image sized close to its target panel, not a
  small seamless tile.
- **Resolution:** the card face is roughly 130x186px
  (`CardWidget.cardWidth`/`cardHeight` in `card_widget.dart`), with the
  description panel narrower. Since it's `cover`-fit rather than tiled,
  draw at something like 128x128–256x256px so it doesn't look soft when
  stretched, rather than a tiny tile.
- **Color: draw it light/neutral, near-white or light gray-tan.** Both
  call sites run the image through `BlendMode.modulate` against a tint
  color at render time (either the card's type color, or a panel's own
  dark tint) — modulate multiplies your pixel values against the tint,
  so a light/neutral source darkens correctly to match whatever tint is
  passed, while a saturated or dark source will multiply into muddy or
  near-black results. Grayscale paper grain (subtle noise/fiber texture,
  no strong color of its own) is the safest bet.
- **Current app palette is dark charcoal**, not light parchment — see
  `ArmorUpColors` in `lib/theme/armor_up_colors.dart`
  (`cardBackground = 0xFF262A35`, `descriptionBackground = 0xFF3A3F4E`).
  The texture's own base tone matters less than usual here since modulate
  will pull it toward whatever tint each panel passes, but avoid a source
  image so bright/washed-out that grain disappears after darkening.

## Wiring

Already wired in `lib/widgets/card_widget.dart` via `_texturedFill()` and
`_TypeTintedFill` — no code changes needed to swap the file itself, as
long as the replacement keeps the same path
(`assets/textures/parchment.png`) or `_parchmentTextureAssetPath` at the
top of that file is updated to match.
