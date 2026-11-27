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
| the window's clear colour `#F4F4F5` | UiWindow.hx:130 | `:root { background-color: #f4f4f5 }` |
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

## What CSS can't say (a property of our own, `-helder-...`, or a rethink)

| helder.ui | Where | Note |
| --- | --- | --- |
| Liquid Glass `<glass>` (`tint`, `interactive`, `variant`, glass merging by `glassSpacing`) | Glass.hx, GlassGroup.hx | a system material; `backdrop-filter` only approximates it: `-helder-material` |
| window backdrops (blur, mica, sidebar, glass) | UiWindow.hx:52-55 | the window's, not a box's: `-helder-backdrop` on the root |
| scrollbar art (Plain, MacOverlay, MacLegacy), overlay bars that fade and take no room | ScrollbarLook.hx, Scrolling.hx | CSS's bars take room (`scrollbar-gutter`); `-helder-scrollbar-look` |
| the focus ring the window draws (`outlineStyle` Auto) | Ui.hx:1356-1367 | `outline-style: auto` is the nearest; the ring's colour and offset are the window's |
| rings (`ring*`: width, colour, offset, inset) composed over the box shadow | Style.hx:218-228 | box-shadow layers, or custom properties as Tailwind's `--tw-ring-*` |
| a box shadow without a colour is `#00000040`, not currentcolor | Shadow.hx:12-22 | a rule can't change a shadow's default colour |
| `textOverflow` Middle (an ellipsis in the middle) | TextOverflow.hx | `-helder-text-overflow: middle` |
| `zIndex` among siblings only, no stacking contexts | Style.hx:269-271 | CSS's z-index makes stacking contexts; `isolation`/contexts differ |
| `order` changes paint and hit order too | Style.hx:267 | CSS's order is layout only |
| `display: block` as a column whose items neither grow nor shrink | Display.hx | CSS's block is flow layout |
| `lineHeightPx` over `lineHeight` on one node; `"normal"` as inherited 1.25 | StyleAttrs.hx:83-93 | CSS has one line-height; normal is the font's |
| an own value equal to its default counts as unset (`Rules.keep`) | Rules.hx:12-14 | CSS's style attribute wins whatever its value |
| motion, layout animation (`motion`, `matched`, `ride`), function-valued states | NodeRenderer.hx:339-400 | transitions and animations only in part |
| window chrome (`dragRegion`, `titleHit`, `<WindowControls>`) | NodeRenderer.hx:286, WindowButtons.hx | `app-region` (non-standard) is the nearest |
| `host="native"` controls | Host.hx | ours |
| part shaders (`PartShader`) | Recipe.hx | ours |
| `<icon name>` | Icons.hx | ours (an element, not a style) |
| the spellcheck wave's colour | EditableText.hx:87 | `::spelling-error` with `text-decoration-color` comes close |
| `fontSize` default 14 (CSS's medium is 16) | Style.hx:17 | said in app.css (`:root`) |
| safe areas, titlebar area | SafeArea.hx | CSS has them: `env(safe-area-inset-*)`, `env(titlebar-area-*)` |
