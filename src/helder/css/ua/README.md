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
| `<glass>`: a capsule of glass | Glass.hx:20 | `glass { border-radius: 10000px; -helder-material: glass }` |
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
  -helder-material: glass }` beside its capsule radius. The host
  chooses how it renders: the system's glass where the host has it
  (macOS 26), helder's shader glass on the GPU elsewhere, and a blur
  or a plain tint as the last fallback (PDF and print: the tint over
  the background). Its siblings:
  **`-helder-material-tint: <color>`** (initial transparent, a computed
  colour; today `tint`, its alpha how far) and
  **`-helder-material-spacing: none | <length [0,∞]>`** (initial none,
  an absolute length; today a view's `glassSpacing`, GlassGroup.hx:
  glass inside it nearer than this merge). `interactive` and `active`
  stay attributes: behaviour and window state, not style.
- **`-helder-backdrop: none | auto | sidebar | popover`**, on the root,
  not inherited, computed as a keyword. Today `<Surface backdrop>`
  (UiWindow.hx:55, helder.os's WindowBackdrop): the window's material,
  seen through a transparent clear colour. The values say what the
  surface is; the host picks the material, and no platform's name
  (mica, glass, blur) is in CSS:
  - `auto`, the host's standard window material: Liquid Glass on
    macOS 26 and later, under-window vibrancy before; Mica on Windows
    11; KDE's blur; none elsewhere.
  - `sidebar`, the sidebar's: macOS's sidebar vibrancy; Mica Alt on
    Windows, else Mica; KDE's blur.
  - `popover`, a transient surface's: macOS's menu and popover
    material (glass on 26); Acrylic on Windows; KDE's blur.

  Where the host has none, the element's `background-color` alone
  shows. The port maps today's values: blur to popover, mica and
  glass to auto, sidebar to sidebar.
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

The rethinks, as decided:

- **Rings** (`ring*`, composed over `boxShadow`): drop them as
  properties. The port writes each ring as `box-shadow` layers (`0 0
  0 offset offsetColor, 0 0 0 offset+width color`, `inset` for
  ringInset) ahead of the shadow, per state, since it compiles the
  theme's states anyway. Shadows interpolate (CssInterpolate), so rings
  still ease.
- **A shadow's default colour** (`#00000040`, not currentcolor): drop
  it; the port writes the colour where a shadow leaves it out.
- **Sibling-only `zIndex`**: CSS's stacking, as standard; app.css adds
  no `isolation`. The port writes `isolation: isolate` only where an
  app relies on z-index ordering siblings alone: on a node whose
  descendants set z-index, so they stay inside it as today.
- **`order` in paint and hit order**: standard already. Flexbox paints
  in order-modified document order, and hit testing follows paint; the
  engine has to implement that, nothing more.
- **`lineHeightPx` over `lineHeight`**: one `line-height` (a number or
  a length), the effective one per node written by the port. Markup's
  `"normal"` (today inherited, 1.25 at the root) is written as nothing,
  not CSS's `normal` (the font's metrics).
- **A default-valued own field counting as unset** (Rules.keep): drop
  it. The style attribute wins whatever its value.

Others the port keeps as they are: motion and layout animation, window
chrome (`dragRegion`, `titleHit`, `<WindowControls>`), `host="native"`,
`<icon name>` (elements and attributes, not style); safe areas and the
titlebar area are CSS's (`env(safe-area-inset-*)`,
`env(titlebar-area-*)`); `display: block` as a non-growing column
becomes CSS's block in the port only where it lays out alike.

## The port (a plan)

No codemod: the repo's examples and apps are ported by hand (#553's
design). helder.ui's API was never released, so nothing is kept for
parity. A node's style becomes a fast Style (`style={...}`,
`node.set`). A `Look` becomes CSS modules (StyleModule, compiled to
fast Styles) over a theme of typed tokens, which are registered custom
properties shared with documents. A feature with no typed equivalent
moves to a CSS module or a DOM island where an app needs it, and is
dropped where none does. The elements' defaults are app.css.

Where a CSS module or a document writes a helder.ui property, the name
or the value changes:

| helder.ui | CSS |
| --- | --- |
| `background`, `backgroundImage` (a Gradient) | `background-color`, `background-image: linear-gradient(...)` |
| `borderWidth`, `borders`, `borderColor`, `borderStyle` (null: solid) | `border-width` per side, `border-color`; `border-style: solid` where a width is set and no style |
| `corners` | the four `border-*-radius` |
| `ring*` | `box-shadow` layers ahead of the shadow's, per state: `0 0 0 offset offsetColor` (white unless set), then `0 0 0 calc(offset + width) color` (currentcolor when null), both `inset` for `ringInset` |
| `boxShadow`, `textShadow` without a colour | the colour written: `#00000040` |
| `lineHeight` (a multiple), `lineHeightPx` | one `line-height`: the px where the node sets `lineHeightPx`, else the number; markup's `"normal"` written as nothing (inherited, 1.25 from app.css's `:root`) |
| `letterSpacing` (px), `letterSpacingEm` | `letter-spacing` in px or em |
| `scrollbarColor`, `scrollbarTrackColor` | `scrollbar-color: thumb track` |
| `textOverflow` Middle, `lineClamp` | `text-overflow: -helder-middle`, `line-clamp` |
| `textDecoration` (flags), `textWrap` | `text-decoration-line`, `text-wrap-mode` and `text-wrap-style` |
| `outlineStyle` null (Auto) | `outline-style: auto`; the ring is app.css's `:focus-visible` |
| `display` Block | `display: block` where its children lay out alike (no grow, shrink or row direction on them); else `display: flex; flex-direction: column`, its children `flex: none` |
| `zIndex` | `z-index`; and `isolation: isolate` on the parent of each node with a z-index, unless the parent already makes a stacking context (opacity, a transform, its own z-index), so siblings stay ordered among themselves as today |
| `<glass tint>`, `variant="clear"`, a view's `glassSpacing` | `-helder-material-tint`, `-helder-material: glass clear`, `-helder-material-spacing` |
| `<Surface backdrop>` | `-helder-backdrop` on the root: blur to popover, mica and glass to auto, sidebar to sidebar |
| `<Surface scrollbars>` | `-helder-scrollbar` on the root |
| `objectFit`, `objectPosition` (`<image>`, `<video>`) | `object-fit`, `object-position` |

The rest of Style's fields keep their name in kebab case (`flexGrow` to
`flex-grow`, `gridTemplateColumns` to `grid-template-columns`).

**Rules.keep** is dropped: a node's own style wins, whatever its
value.

**What stays an attribute.** Behaviour, state and content, not style:
`id`, `class`, `role`, `hidden` (app.css's `[hidden]`), `disabled`,
`required`, `tabIndex`, `autoFocus`, `focusable`, `selectable`, `slot`,
`variant`, `size`, `host`, `group`, `peer`, `tag`, `states`,
`keyContext`, `actions`, `trackFocus`, `dragRegion`, `dragData`,
`panAxis`, `panMinPointers`, the `motion*` attributes, `lead`, `trail`,
`instant`, `matched`, `ride`, `lang`, `aria-*`, `data-*`, `key`, `ref`,
the events; and each element's own: `<text text>`, `<image src
mirrored>`, `<icon name mirrored>`, a field's and a textarea's inputs
(`value`, `placeholder`, `type`, `rows`...), `<webview>`'s, `<glass
interactive>`, `<video>`'s but `objectFit`, `<a href>`, `<label for>`.
