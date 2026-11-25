package helder.ui.controls;

import helder.gfx.Color;

// A colour token's values in light and dark: Look.tone("oklch(0.56 0.19
// 258)", "oklch(0.64 0.17 258)"), written as CSS writes a colour (one for
// both). A structure, not a class: a TypeScript program's are its objects.
typedef Tone = {light:Color, dark:Color}
