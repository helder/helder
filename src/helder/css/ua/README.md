# User agent sheets

- `html.css`, `html-quirks.css`, `html-hints.css`: the HTML Standard's
  Rendering section and print's defaults, written by `ua.mjs`.
  `CssUserAgent` parses them when first asked; `CssUserAgentTheme` has
  them compiled at build time (CssTheme), so that a program styling
  documents with them and compiled sheets alone links no CSS parser.
- `app.css`: helder.ui's defaults for app trees, a draft for the port of
  helder.ui onto helder.dom, so that the port changes no app's look.
  `CssUserAgent.app()` parses it, `CssUserAgentTheme.app()` has it
  compiled. `bun run test css-app` compares it with helder.ui today.

## app.css: each default and its rule

| helder.ui today | Where | app.css |
| --- | --- | --- |
| `display = Flex` | Style.hx:36 | `* { display: flex }` |
| `flexDirection = Column` | Style.hx:41 | `* { flex-direction: column }` |
| `flexWrap = false` | Style.hx:44 | `* { flex-wrap: nowrap }` |
| `position = Relative`; absolute boxes placed in their parent's padding box | Style.hx:38, Position.hx:6 | `* { position: relative }` (every node a containing block) |
| sizes are border boxes, padding and border inside | Layout.hx:9-10 | `* { box-sizing: border-box }` |
| `margin`, `padding` 0; no margin collapsing | Style.hx:112-114 | `* { margin: 0; padding: 0 }` (flex items never collapse) |
| `borderWidth` 0, `borderStyle` null = solid, `borderColor` transparent | Style.hx:127-169 | `* { border: 0 solid transparent }` |
| `borderRadius` 0 | Style.hx:172 | `* { border-radius: 0 }` |
| `minWidth`/`minHeight` Auto: a flex item's automatic minimum | Layout.hx:372-410 | `* { min-width: auto; min-height: auto }` |
| `flexGrow` 0, `flexShrink` 1, `flexBasis` Auto | Style.hx:82-88 | `* { flex: 0 1 auto }` |
| `alignItems` Stretch, `justifyItems` Stretch | Style.hx:49, 78 | `* { align-items: stretch; justify-items: stretch }` |
| `rowGap`, `columnGap` 0 | Style.hx:136-139 | `* { gap: 0 }` |
| `textDecorationThickness` Auto = 1/10 of the font size | Style.hx:347 | `* { text-decoration-thickness: 0.1em }` |
| root text: sans-serif, 14, 400, line height 1.25 (a multiple), black | Style.hx:15-19 | `:root { font: 400 14px/1.25 sans-serif; color: #000 }` |
| `overflowWrap` BreakWord at the root | Node.hx:1007 | `:root { overflow-wrap: break-word }` |
| the root's cursor Default | Cursor.hx | `:root { cursor: default }` |
| the window's clear colour `#F4F4F5` | UiWindow.hx:130 | none: the window's, not the root's (ENGINE.md) |
| scrollbar thumb `0x59000000`, no track | Ui.hx:173 | `:root { scrollbar-color: rgb(0 0 0 / .35) transparent }` |
| `<text>` and the HTML names on it: a box, its runs one paragraph; inside a text, runs | TextNode.hx:84-104 | `text, p, h1... { display: block }`, nested `display: inline` |
| `<scroll>` | NodeRenderer.hx:117 | `scroll { overflow: scroll }` |
| `<image>`, `<icon>`: fill, centred | ImageNode.hx:16-23 | `object-fit: fill; object-position: 50% 50%` |
| `<field>`, `<textarea>`: clipped, a text cursor, fixed sizing | EditableText.hx:258-263 | `overflow: hidden; cursor: text; field-sizing: fixed` |
| `<glass>`: a capsule | Glass.hx:20 | `glass { border-radius: 10000px }` |
| `hidden` | NodeRenderer.hx:491 | `[hidden] { display: none }` |
| `outlineStyle` Auto: the window's focus ring, `#3B82F6`, 2 wide, offset 2 | Ui.hx:169-172 | `:focus-visible { outline: 2px solid #3b82f6; outline-offset: 2px }` |
| selection `rgba(59,130,246,.3)`, placeholder `rgba(0,0,0,.4)` | Ui.hx:2046, EditableText.hx:57 | `::selection`, `::placeholder` |

Not in app.css, on purpose: the controls' looks (Button, Checkbox,
Switch, PathBar..., `controls/Base.hx`) and the design tokens
(`Tokens.hx`). They are a theme (a `Look` compiled to a StyleSheet, set by
`<Themed>` or by a control on itself), not the user agent's: they port as
a theme sheet of their own, the tokens as custom properties, dark as
`prefers-color-scheme` (or `color-scheme`), the states as Compile.hx
maps them (hover, `:active`, `:focus-visible`, `[data-state=checked]`,
`[data-disabled]`, a part's `group/<control>:` as a descendant of the
control's state). `h1`-`h6`, `strong`, `em`, `code` have no default look
either: Look.base's slots style them.

## Properties of our own, and the rethinks (a design note)

What app trees need that CSS has no property for, each as helder.ui has
it today, so the port maps 1:1. All are `-helder-` properties in the
support table as ours.

- **`-helder-material: none | glass [ regular | clear ]?`**, not
  inherited, initial none, computed as keywords. Today the `<glass>`
  element (Glass.hx), `variant="clear"`. app.css gives `glass {
  -helder-material: glass }` beside its capsule radius. Its siblings:
  **`-helder-material-tint: <color>`** (initial transparent, a computed
  colour; today `tint`, its alpha how far) and
  **`-helder-material-spacing: none | <length [0,∞]>`** (initial none,
  an absolute length; today a view's `glassSpacing`, GlassGroup.hx:
  glass inside it nearer than this merge). `interactive` and `active`
  stay attributes: behaviour and window state, not style.
- **`-helder-backdrop: none | blur | mica | sidebar | glass`**, on the
  root, not inherited, computed as a keyword. Today `<Surface backdrop>`
  (UiWindow.hx:55, helder.os's WindowBackdrop): the window's material,
  seen through a transparent clear colour.
- **`-helder-scrollbar: system | overlay | always`**, inherited, initial
  system, computed as a keyword. Today `<Surface scrollbars>`
  (UiWindow.hx:77-81) choosing `Ui.scrollbarLook` (Plain, MacOverlay,
  MacLegacy) and `Ui.overlayBars`: system follows macOS's setting
  (always shown elsewhere), overlay shows them while scrolling. In app
  trees no bar takes room, as today (Layout reserves no gutter);
  `scrollbar-width` and `scrollbar-color` stay CSS's.
- **`text-overflow: -helder-middle`**, a keyword of our own in CSS's
  property (Overflow 4 has none for it): TextOverflow.Middle, the text's
  start and end with "…" between ("E07-uitzonderingen…ster.xlsx"),
  over the lines `line-clamp` allows.
- **Part shaders: `background-image: paint(<name>)`**, the CSS Painting
  API's function, so no property of our own: Recipe.hx's `draw:
  PartShader.of(shader)` registers the shader under a name, and the
  part's eased states and look reach it as its arguments and custom
  properties, as `paint()` passes them.

The rethinks, proposed:

- **Rings** (`ring*`, composed over `boxShadow`): drop them as
  properties. The codemod writes each ring as `box-shadow` layers (`0 0
  0 offset offsetColor, 0 0 0 offset+width color`, `inset` for
  ringInset) ahead of the shadow, per state, since it compiles the
  theme's states anyway. Shadows interpolate (CssInterpolate), so rings
  still ease.
- **A shadow's default colour** (`#00000040`, not currentcolor): drop
  it; the codemod writes the colour where a shadow leaves it out.
- **Sibling-only `zIndex`**: standard. app.css would add `* { isolation:
  isolate }` makes every node a stacking context, so z-index orders
  siblings only, as today.
- **`order` in paint and hit order**: standard already. Flexbox paints
  in order-modified document order, and hit testing follows paint; the
  engine has to implement that, nothing more.
- **`lineHeightPx` over `lineHeight`**: one `line-height` (a number or
  a length), the effective one per node written by the codemod. Markup's
  `"normal"` (today inherited, 1.25 at the root) is written as nothing,
  not CSS's `normal` (the font's metrics).
- **A default-valued own field counting as unset** (Rules.keep): drop
  it. The style attribute wins whatever its value, so the codemod drops
  an attribute equal to its default where a theme rule sets the same
  property and the node isn't under `Rules.keep`; the look stays.

Others the port keeps as they are: motion and layout animation, window
chrome (`dragRegion`, `titleHit`, `<WindowControls>`), `host="native"`,
`<icon name>` (elements and attributes, not style); safe areas and the
titlebar area are CSS's (`env(safe-area-inset-*)`,
`env(titlebar-area-*)`); `display: block` as a non-growing column
becomes CSS's block in the codemod only where it lays out alike.
