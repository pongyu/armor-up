# Card background texture

`parchment.png` is the tiled background fill for the card face and
description panel in `lib/widgets/card_widget.dart`. It's a 64x64px crop
of the center tile from the Tiny Swords "Regular Paper" nine-slice sheet
(`assets/cards/` art pack, credited in `CREDITS.md`) - not AI-generated.

If this file is ever missing, `CardWidget` falls back cleanly to the flat
`ArmorUpColors.cardBackground` fill with no error and no broken-image
icon (see `_texturedFill()` in `card_widget.dart`).

## Replacing it

If you want a different texture later, the format constraints that made
the current crop work:

- **Seamless tile**: it's rendered with `ImageRepeat.repeat` across the
  whole card face, so a slightly non-seamless tile (e.g. this crop, which
  keeps a hint of the source sheet's edge shading) still reads fine as
  paper grain when repeated - a perfectly flat/seamless tile actually
  looked worse here, since with only ~2x2 repeats across a card the grain
  needs to be visible to read as texture rather than a flat color.
- **Resolution**: keep it small (this one is 64x64px) - a card is only
  ~120-150px on a side, so a bigger tile just means fewer, more visible
  repeats or one static image stretched to fill the space, and looked
  identical to a flat color when tried at 128px.
- **Palette**: stay close to `ArmorUpColors.cardBackground`
  (`0xFFE8DFD0`) in `lib/theme/armor_up_colors.dart` - the texture sits
  under `cardStroke`-colored description text and the type-colored name
  banner, so it can't shift the overall card palette.

## Wiring

Already wired in `lib/widgets/card_widget.dart` via `_texturedFill()` -
no code changes needed to swap the file itself.
