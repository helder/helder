# helder.ui

A UI toolkit for hxmc in pure Haxe: a node tree laid out with flexbox,
drawn with the GPU (`helder.gfx`), written in markup with fine-grained
signals, Solid's way (`helder.view`, which renders into its nodes).

```haxe
import helder.ui.draw.UiWindow;
import helder.ui.draw.UiWindow.Surface;
import helder.view.*;
import helder.view.graph.Graph.*;

class Counter implements Markup {
	static function main() {
		var count = signal(0);
		UiWindow.run(<Surface title="Counter" width={320} height={200}>
			<view grow={1} padding={24} row-gap={12} align-items="center" justify="center">
				<text font-size={32}>{count}</text>
				<view:button role="button" focusable padding="8 16" radius={6} background="#18181b" color="#fafafa" cursor="pointer"
					onPress={() -> count(c -> c + 1)}>+1</view:button>
			</view>
		</Surface>);
	}
}
```

```sh
bun run helder dev examples/counter/Counter.hx   # or build; --target web for a page
```

`Render.render(content, node)` mounts markup into a node of your own (a
`UiWindow`'s `root`, a test's `Ui`).

[GUIDE.md](GUIDE.md) walks through building an app: components, state,
lists, popups, your own nodes, each platform, tests.
`examples/todo/Todo.hx` is a complete app (a text field, a keyed
list, checkboxes, filters), `examples/mail/Mail.hx` a larger one (a
toolbar, folders, messages sorted by column, search, shortcuts, undo, dark
mode), both styled by a small `StyleSheet` of their own. They run natively on Linux, macOS and Windows, and in a browser
(wasm32-wasi on WebGPU or WebGL2).

## The parts

- **`helder.ui`**, the core, plain Haxe (it runs on any target; its tests
  run on Eval): `Node` and `TextNode`, `Style`, `Layout`, `Ui`.
  - Layout is CSS flexbox, column by default: `direction`, `wrap`,
    `justify`, `alignItems`, `alignSelf` (`Baseline`: a row's items on their
    first baselines, a text's first line's, a box without one on its bottom
    edge; a column's on their start edges), `alignContent`, `grow`,
    `shrink`, `basis`, `width`, `height`, min and max (widths also
    `min-content`, `max-content`, `fit-content`: CSS's intrinsic sizes;
    `"calc(100% - 2px)"`, `Calc(100, -2)`: a percentage plus pixels),
    `aspectRatio`,
    `padding`, `margin` (`auto`, `Edges.AUTO`: CSS's auto margins, along and
    across flex lines, in grid areas, on absolute boxes), `borderWidth`,
    `rowGap`, `columnGap` (`gap` both; `flex`, `inset`: CSS's shorthands,
    `flex="none"`, `inset="0 10"` in markup), `position`
    (Absolute with `left`, `top`, `right`, `bottom`; both offsets and a
    size on an axis: placed between them by `justifySelf` and `alignSelf`;
    an auto width shrinks to fit), `overflow` (Hidden,
    Scroll), `dir` (Rtl: rows from the right, columns' items across
    from the right, grids' columns from the right, text aligned right by
    default, paragraphs in that direction; inherited; margins and padding
    stay physical; a scroller's content overflowing to the left scrolled to
    by negative `scrollX` from 0 at its right end, as Chromium's
    scrollLeft, its vertical bar on the left), `order` (laid out,
    painted and hit in it; Tab keeps the tree's order), `zIndex` (painted
    and hit over or under siblings; no stacking contexts across levels).
    Sizes are border boxes. Items get CSS's automatic minimum
    size, so content is not squashed (their content's, not their own
    `height`: an empty box of a fixed height shrinks in a column it
    overflows, as in CSS; `shrink: 0` keeps it; a scroll container's is 0,
    in grid tracks too). A column's auto height is its content's, however tall: a
    flex item holding a scroller wants `minHeight: 0`, as in CSS, else it
    grows to all of the scroller's content. `display: Block` is CSS's block
    layout: a column whose children neither grow nor shrink (a row
    direction given makes it a flex row). `display: Grid` lays children out
    on CSS grid tracks instead: `gridTemplateColumns` and
    `gridTemplateRows` (px, %, fr, auto, min-content, max-content,
    minmax(), repeat()), `gridAutoRows`, `gridAutoColumns`,
    `gridAutoFlow`, `gridTemplateAreas` ("'head head' 'side main'"), items
    placed by `gridColumn` and `gridRow` ("1 / 3", "span 2", negative
    lines, an area's name) or `gridArea`, or auto-placed (`gridAutoFlow`:
    by rows or columns, sparse or dense), aligned by `justifyItems`,
    `justifySelf`, `alignItems`, `alignSelf`, the tracks by `justify` and
    `alignContent` (no other named lines, no subgrid). Checked against
    Chromium on 143 cases, 39 of them grids, 8 right to left. Taffy's fixtures make a
    conformance suite of their own (Chrome's boxes, 1,308 of them, each left
    to right and right to left: [tests/layout-conformance](../../../tests/layout-conformance/README.md),
    its manifest the cases that pass and why the others do not yet).
  - Text properties inherit: `color`, `fontFamily`, `fontSize`,
    `fontWeight`, `italic`, `lineHeight` (a multiple of the font size;
    `lineHeightPx`: pixels, inherited as pixels), `letterSpacing`
    (`letterSpacingEm`: a multiple of the node's font size, inherited as
    the pixels it comes to), `wordSpacing`,
    `textAlign` (left, center, right, justify: the room shared among the
    spaces as Chromium shares it; spacing added as Chromium adds it),
    `textWrap` (`NoWrap`, CSS's text-wrap-mode: each line kept whole, past
    its box, its min-content width that wide), `overflowWrap` (`BreakWord`
    by default, where CSS's is `Normal`: a word too wide is cut, not
    overflowing; `Anywhere`: its min-content width too), `wordBreak`
    (`BreakAll`, `KeepAll`; soft hyphens break as in CSS: lines as
    Chromium breaks them), `textTransform` (`Uppercase`,
    `Lowercase`, `Capitalize`: letter for letter; a span its own; a text
    field's text as typed), `textOverflow` (`Ellipsis`, not inherited: a
    line too wide for its box ends in one within it). `textDecoration`
    (underline, line-through, overline) draws its lines with the text inside
    the node, in its colour (`textDecorationColor`: another), as thick as
    `textDecorationThickness` says (a tenth of the font size by default), an
    underline `textUnderlineOffset` below the baseline, where Chromium
    draws them. `textShadow`
    (`"1px 2px 4px #0006"`, several, inherited, `none`) draws the text's
    and its lines' shadows under them (a text field's and its placeholder's
    too), blurred as Chromium blurs them
    (BoxTest compares them). `fontFeatureSettings` (`"'tnum'"`,
    `"'liga' 0, 'ss01'"`, inherited) asks for OpenType features as CSS's
    font-feature-settings does; `fontVariantNumeric` (`"tabular-nums"`,
    `"oldstyle-nums slashed-zero"`) as font-variant-numeric does, under it.
    `maxLines` cuts a
    text to so many lines, the last ending in an ellipsis where Chromium's
    line-clamp puts it.
  - Paint: `background`, `borderColor`, `radius` (`corners`, or markup
    `radius="12 12 0 0"`: each corner's, as CSS's border-radius; `borders`,
    or `border-width="0 0 2 0"`: each side's width, laid out and drawn, the
    inner corners quarter ellipses as Chromium draws them), `borderStyle`
    (`border-style="dashed"`: `Solid`, `Dashed` or `Dotted`, each side's
    dashes or dots fitted to it from a corner to the next, around rounded
    corners too, the background in their gaps), `opacity` (of the node and
    its subtree as one, as CSS's: a node with children, or content over its
    box, drawn into a texture of its bounds and that faded, so that what
    overlaps in it is not seen through; a lone box or text each quad's), `shadow`
    (CSS's box-shadow: `"0 2px 8px rgba(0, 0, 0, 0.25)"`, x, y, blur, spread,
    colour; `inset`; several, comma-separated; blurred by a Gaussian as
    Chromium blurs them, within a few levels of its pixels), `outlineWidth`,
    `outlineOffset`, `outlineColor` (or markup `outline="2px solid red"`: a
    solid line around the border box over the content, its corners the
    box's grown, as Chromium draws it; BoxTest compares them), `outlineStyle`
    (`Auto`, the default: the window's focus ring while focused by the
    keyboard; `Solid`: only the outline; `Dashed`, `Dotted`: it drawn so;
    `None`: neither, as CSS's `outline-style: none`), `ringWidth`, `ringColor`, `ringOffsetWidth`,
    `ringOffsetColor`, `ringInset` (Tailwind's ring: spread shadows of no
    blur over the node's own `shadow`, the offset over the ring, each from
    its own property or rule), `paddingTop`...`paddingLeft`, `marginTop`...
    `marginLeft` (one side each, a margin's may be `Edges.AUTO`: rules for
    `pt-2` and `px-4` combine), `userSelect` (inherited: `None`, `Text`, `All`:
    whether a drag selects its text, as CSS's user-select), `overflowX` and
    `overflowY` (both clip when either does, as CSS's; an axis scrolls by the
    wheel, keys and scrollbar only where it is `Scroll`), `fieldSizing`
    (`Content`: a text area as tall as its lines, as CSS's field-sizing), `scrollbarWidth` (`Thin`, `None`:
    CSS's scrollbar-width), `scrollbarColor` and `scrollbarTrackColor` (inherited,
    CSS's scrollbar-color), corner radii scaled down together where a side's
    two add up to more than it (as CSS: `9999` a pill), `cursor`,
    `visibility` (inherited; `Hidden` keeps the node's place but draws,
    hits, focuses and shows it to assistive technology no more, while a
    `Visible` descendant still is), `pointerEvents` (inherited; `None` lets
    the pointer through to what is under it, an `Auto` descendant still
    found). Colours are
    CSS's (`Color.parse`: hex, `rgb()`, `hsl()`, the 148 names, as Chromium
    computes them); `backgroundImage` (markup: `background="linear-gradient(...)"`)
    is a CSS gradient, linear or radial, repeating or not (`Gradient`: within
    two levels of Chromium's pixels on 19 cases), under the border.
  - `position: Sticky` (Style only for now, markup to come with helder.view):
    laid out in the flow, then kept its `top`, `left`, `right` or `bottom`
    inside its nearest scroller's content box as it scrolls, within its
    parent's content box, drawn and hit over its siblings, where Chromium
    sticks it.
  - Transforms: `transform` (CSS's: `translate`, `scale`, `rotate`,
    `skew`, `matrix`, composed left to right; `Transform.parse`, or
    `Transform.rotate(45)`) about `transformOrigin` (`"left top"`, `"50% 0"`;
    the centre by default) moves how a node and its subtree are drawn and
    hit, not their layout; pointer events' `localX`/`localY` and
    `Node.localX` go through it. The renderer turns quads on the GPU,
    their edges anti-aliased over a pixel, and rasterizes glyphs at the
    scaled size (on the pixel grid when the transform only moves and
    scales evenly), within half a level of Chromium's pixels on average.
    Under a turning transform a clip is its bounds.
  - Transitions: `transition` (CSS's shorthand, `"background-color
    150ms ease-in-out, opacity 0.2s"`; `Transition.parse`): once a node
    has been drawn, a change of a property it names (colours, opacity,
    transform, box-shadow; `all`) eases on the `Clock` from where it is,
    along CSS's timing functions (cubic Béziers), colours with their
    alphas premultiplied, transforms function by function, shadows shadow
    by shadow, as Chromium interpolates them; `style.target(name)` is
    where it goes. A theme's rules set it as any property.
  - Images: `helder.image`'s (`Image`, RGBA8 pixels; `Image.decode`: PNG,
    JPEG, GIF and WebP, [its README](../image/README.md); an
    `AnimatedImage` played on the `Clock`), shown by an `ImageNode` at its own
    size or the style's (keeping its aspect ratio), fitted as `Fill`,
    `Contain`, `Cover` or `None`, placed by `position` (CSS's object-position:
    `"right 10px top"`, markup `object-position`; centred by default, the
    part outside cut), its corners rounded with the node's.
  - SVG: `Svg.parse` (helder.canvas's `Svg`) reads the static subset icon sets use (shapes, all of
    path data, fills and strokes with their joins, caps and dashes, linear
    and radial gradients, opacities, transforms, use and symbol, clip-path,
    nested viewports, CSS colours, currentColor); `render` draws it at any
    size, checked against Chromium's pixels on 30 cases. An `ImageNode`'s
    `svg` (markup: `src={svg}`) is drawn at the window's pixel size in the
    node's colour. Not drawn: text, images, patterns, masks, filters, markers.
    Markup's `<svg>` is such an image, its drawing read when compiled (as
    `Svg.parse` of a constant: `SvgBuild`), so the program links no parser;
    `Svg.read` reads a string made when the program runs.
  - A `TextNode` that is `selectable` takes a selection from the pointer (a
    drag, a double click: a word, a triple: all), painted under its text
    (`Ui.textSelection`, `Ui.selectionColor`) and copied by Mod+C.
  - `Ui` dispatches pointer, wheel, key and text events to nodes (bubbling
    to ancestors), tracks hover and press, moves the focus (click, Tab,
    Shift+Tab; a ring shows when the keyboard moved it) and scrolls
    `Overflow Scroll` nodes (the wheel or a trackpad, by the pixels it
    moved, Shift turning a wheel sideways; a finger's drag (below),
    gliding on when let go moving, a tap a click; their scrollbars'
    thumbs; or the keys a browser scrolls with, when the focus took none of
    them: the arrows by 40 pixels, Page Up, Page Down and Space by seven
    eighths of the view, Home and End, eased over `Ui.scrollDuration`;
    `Ui.scrollBy` eases the same way). A node's key handler calls
    `preventDefault` (or `stop`) on the keys it takes.
  - Fingers and pens are pointers of their own, as the DOM's Pointer
    Events (`UiWindow` feeds helder.os's `Pointers`:
    `Ui.pointerDown(x, y, 1, id, type)` with the slot as the
    id, 0 the mouse): `e.pointerId`, `e.pointerType`, `e.pressure`,
    `e.isPrimary` on their events; each captured by the node it went down
    on (`capture()` in a handler moves it there, `releaseCapture()` lets
    it go: `onLostPointerCapture`); `onPointerCancel` when the system takes
    it, when its node leaves the tree, or when a scroll takes the press;
    a press released within 8 points on its node clicks. The first
    finger's drag scrolls what is under where it started (Wheel events at
    that point, as the wheel's, then a glide when let go moving:
    `helder.os.Glide`), unless a recogniser inside wins it first
    (below). `pointerDown` answers whether the press is the ui's (not the
    root's, the body's, nor a world drawn under the ui: `Node.ownsPointer`,
    a `<Scene>`'s box says no); `UiWindow` marks the pointer `owner = Ui`
    then, so that a game's touch controls leave it alone.
  - Where the platform has scroll views of its own, they drive the
    scrollers instead (`Ui.nativeScroll`; iOS: a clear `UIScrollView` per
    scroller that overflows, its pan on the window's view, as WebKit
    does; the browser: a clear `overflow: auto` element per scroller over
    the canvas, nested as the scrollers are, the pointer's events still
    the program's): their deceleration, bounce (`scrollX`/`scrollY` past
    the ends meanwhile, as Safari's scrollTop), scrollbars or indicators,
    the browser's wheel, trackpad and scroll chaining, iOS's status bar
    tap. A finger's drag elsewhere is still helder's own. Android has no
    scroll views under the tree: there helder's drag glides by Android's
    physics, ported as Chromium and Flutter port them (`AndroidFling`:
    a least-squares speed, OverScroller's spline), and stretches past an
    end as Android 12's (`Stretch`, `Ui.stretch`: Flutter's curve and
    spring, a scale anchored at that end). On Linux's Wayland a
    touchpad's scrolls are a gesture (`Ui.kinetic`: `axis_source` finger,
    `axis_stop` its end) gliding on once the fingers lift as GTK's
    kinetic scrolling (its speed over the last 150 ms, `v / 4 (1 -
    e^(-4t))`, a bounce at an end). A wheel's scrolls stay with the
    scroller they moved until the wheel rests half a second (Chromium's
    latching). On macOS
    (`Ui.elastic`, `Trackpad`) a trackpad's gesture goes to one scroller,
    stretches past its ends by AppKit's measured curve and springs back,
    its momentum the system's replayed at the frames' times; the
    scrollbars are AppKit's own scrollers drawn into the tree
    (`ScrollbarArt`: `MacScrollbarArt`), overlay ones fading as macOS's,
    as the system's "Show scroll bars" says. The
    tree still decides whose drag it is (`Ui.nativeBegins`: none while a
    recogniser of the tree holds a pointer or a node there follows the
    pointer's moves; else the nearest scroller that can move that way,
    as the wheel's) and draws at the offsets they report
    (`Ui.nativeScrolled`); a touch stops one gliding without a click.
    `<Surface scrolling="helder">`, or `UiWindow.scrolling = false` for
    every window, keeps helder's own drag and glide.
  - Gestures (`helder.ui.gesture`): recognisers on nodes competing for
    each pointer in an arena (Flutter's model): at a press the recognisers
    from the node pressed up to the root join, the innermost first (the
    first finger's scroll last); the first to accept (past its 8-point
    slop, a second finger for a pinch) wins the pointer, the others lose
    it; at the release a `Tap` still in it wins. A recogniser that wins
    other than a `Tap` takes the click (`onClick` is a tap that won, as on
    iOS: a button inside a pannable list). `Tap` (once, `Ended`, at the
    release), `Pan` (`axis` `X` or `Y`: a drag along the other is left to a
    scroller; `minPointers`), `Scale` (pan, pinch and turn at once: `scale`,
    `dscale`, `angle`, `dangle`; `minPointers` 2 for a pinch); a finger put
    down or lifted makes no jump. Their handler gets the recogniser itself,
    reused: `state` (`Possible`, `Began`, `Changed`, `Ended`, `Cancelled`),
    the focus `x`, `y` (node-local), `dx`, `dy` since the last call, `tx`,
    `ty` since it began, `vx`, `vy` (points a second), `pointers`,
    `pointerType`, `button`, `taps`; `cancel()` gives its pointers back.
    The mouse's presses feed the arena too. `Node.addGesture`,
    `removeGesture`, `gesture(Class)`; a recogniser of a node that leaves
    the tree is cancelled.
- **`helder.ui.draw`**: the GPU renderer. One instanced shader (after
  Rune's uber-quad) draws rounded rectangles with borders, soft shadows
  (outer and inset), glyphs from an atlas and images, each an instance of
  one quad, every fragment clipped by a rounded rectangle carried by its
  instance; small images (paths, SVGs, gradients, colour glyphs) share
  atlas pages, so that a frame is one draw call (a texture of its own, a
  large image or a `<Scene>`'s, a draw more where it is bound), its
  instances in a ring of buffers written where they changed; `UiWindow` puts a
  `Ui` in an `helder.os` window, shows the hovered node's cursor and runs
  the loop. In markup the window is `<Surface>` (`UiWindow.Surface`, a
  root): `UiWindow.run(<Surface title="Todo" width={480} height={560}
  theme={sheet}>...</Surface>)` opens it and runs the loop; its props
  (title, size, theme, background, dark) are values or reactive, several
  make several windows; on the web it fills the page, or takes the canvas
  the page gives (a helder.web `<Surface>`'s) at its styles' size. The GPU
  renderer also draws a render target (`gpuTexture`) and records passes
  before the frame's (`beforePass`): a `<Scene>`'s box. Text under a
  transform (a canvas zoomed) is culled per glyph before it is
  rasterized; while the transform's scale moves (a pinch, a zoom's
  flight) its glyphs are drawn at the nearest quarter octave, stretched,
  and at their own size once the scale has rested for 6 frames (the
  window draws that frame: `Renderer.steps`, `again`); glyphs past 256 device
  pixels (`Renderer.LARGE`) are images of their own, not in the atlas,
  freed once a frame does not draw them. The atlas grows to the GPU's
  largest texture (`Device.maxTextureSize`, at most 4096) and is never
  changed under a frame that drew from it (helder.text's GlyphAtlas). On macOS the app has the usual menu bar (Hide, Quit, the Window
  menu); Quit asks each window to close, as its close button does.
- **`helder.ui.view`**: `helder.view`'s renderer for these nodes
  (`NodeRenderer`, named by `Node`'s `@:rendered`; `UiView`, its markup:
  a `<Surface>`'s children, a component returning one pinned to ui), the markup's attributes (`StyleAttrs`, generated
  from `Style`'s properties: a property added to `Style` is an
  attribute), and what is ui's own: the control flow components
  `VirtualList` (a `VirtualScroll`: only the rows in view made, each of
  its own height in a `HeightIndex`; a million rows scroll as twenty, below),
  `Popover` (`UiFlow`), and `Motion`:
  `transition`, `spring` and `color` are signals moving toward a target
  as the `Clock` ticks (a window ticks it each frame and keeps drawing
  while anything moves; `Clock.finish()` ends every animation, for tests). Signals (`signal`,
  `memo`, `effect`, `flush`, `untrack`, contexts: `helder.view.graph`),
  `Render` and the control flow components `For`, `Repeat`, `Show`,
  `Switch`, `Errored`, `Loading` are `helder.view`'s ([its
  README](../view/README.md)). The graph's writes land at the end of each
  event (`Ui`'s pointer, key and text entry points, a native control's
  callbacks) and frame (`Ui.update`, `Clock.tick`, `App.run`'s turns).
- **`helder.ui.motion`**: motion as property tracks, declared on nodes
  (examples/motion, in Haxe and TSX). A `Track` is one value moving: an
  analytic spring by duration and bounce (SwiftUI's
  `Spring(duration:bounce:)`, closed form in each damping regime), a tween
  (a duration on a cubic Bézier) or a decay (a fling's), evaluated at the
  `Clock`'s time (a headless run's virtual one), retargeted from exactly
  where it is and how fast it moves, settled once within its epsilon for
  good; sampling allocates nothing. A node's `Present` keeps a track per
  property that moves, `Motions` changes them:
  - `motion` (Node.motion, markup's `motion="snappy|default|calm"`,
    `motion="0.3 0.15"`, `motion={{duration: 0.3, bounce: 0.2}}`, a
    `MotionSpec`) for a node and its subtree, per property class over it
    (`motion-layout`, `motion-opacity`, `motion-color`,
    `motion-transform`, `motion-radius`, `motion-presence`); the palette's
    tokens (snappy .25/0, default .3/0, calm .4/0, lead .2/0, fade .15,
    bouncy, morph, glide, drift: `Curve.TOKENS`), a theme's own over them
    (`StyleSheet.motion`).
  - Layout: a node laid out elsewhere after it was drawn moves there edge
    by edge in its parent's space, from where its edges are drawn: an edge
    that stays put never moves, children ride their parent's leading
    (top left) edges, or its trailing ones (`ride="trailing"`, `"x"`,
    `"y"`); `lead` and `trail`: the edge in the direction of travel on one
    curve, the other on another, the box stretching as it goes. Drawn
    where the tracks are (the renderer's translation, the presented size;
    text and children keep their layout); `windowBounds`, the inspector
    and `--trace` say where it is drawn. Hit testing stays on the layout.
  - Properties: `opacity`, `radius`, `background`, `borderColor` and
    `color` (premultiplied OKLab; a text colour in half the time, so a
    theme switch keeps its contrast: `textLeads`) spring as they are set;
    the style reads where they are, `style.target(name)` where they go;
    `transform` moves as translation, scale and rotation lanes.
  - Presence: a transition's presence words (`transition="fade"`,
    `"scale"`, `"slide-up"`, `"slide-left(24)"`, `"pop"`, combined: `"fade
    scale"`; with CSS's parts: `"fade, background-color 150ms"`) play as a
    node is inserted into a drawn parent and as it is removed: kept drawn
    where it was, out of the tree and its layout (its old parent's
    `exits`), until its exit settles, revived from where it is if it is
    inserted again; helder.view's keyed `For` keeps such a row and takes
    it back when its key returns (Renders' `leaving`). Nothing enters on
    the first frame. `blur` is a fade (the renderer has no blur).
  - Matched elements (`matched="id"`): one removed and another of that id
    laid out within an update: the new one flies from where the old one
    was seen, its rect, velocity, radius and fill, drawn over everything,
    its content scaled to cover its frame as it goes.
  - `instant` (a node's subtree; `Motions.instant(f)`): its changes without
    motion, its own entrance and exit kept. `Clock.reducedMotion`: travel,
    size, transforms and matched flights snap; opacity, presence and
    colours fade over 0.15 s.
  - A change between frames moves from the next frame on (the Clock may
    have been idle); a layout's within the frame it is laid out.
  1,000 boxes moving at once: a frame's work the same as drawing them still
  (0.82 ms against 0.85 ms median, headless on llvmpipe), retargeting all
  of them 3.7 ms, 152 GC bytes a frame either way (the motion-bench lane).
- **`helder.ui.widgets`**: text editing, `TextField` (caret, selection,
  keyboard editing, `cut`, `copy`, `paste`, `selectAll`) and `TextArea`
  (lines: wrapping, Up and Down, scrolling), both on `EditableText`, with
  an input method's composition shown at the caret (markup's `<field/>`
  and `<field:textarea/>`); `Icons`, lucide's icons by name (markup's
  `<icon/>`); `Theme`, the studio's look for any app (its sheet's
  parts by slot: panels, sections, buttons, fields, menus; light and dark
  from the same tokens, `Theme.c` for a colour given inline; superseded
  by `helder.ui.controls`' looks, "Controls" below, and going once the
  apps move); `Controls`,
  styled by it: `Slider` (a number as a field filled up to it, set by a
  press, a drag or the keys), `Segmented` (one of a few options, a radio
  group) and `Tip` (a tooltip: what a control does and its shortcut, under
  it once the pointer rests there, for a button that shows only an icon).
- **`helder.ui.controls`**: the standard controls, `Button`, `Checkbox`
  and `Switch` so far, their behaviour (`Press`, `Toggle`) and their
  looks (`Look`): "Controls" below. Others (menus, tabs) are still views
  with a role, `focusable` and `onPress`, as in the examples and
  `GUIDE.md`. A
  `UiWindow`'s `Ui.dark` follows the system's appearance
  (`helder.os.App.prefersDark`: the browser's colour scheme, macOS's,
  Windows', GTK's settings).
- **`helder.ui.code`**: a code editor. `CodeModel` is its document: a
  rope (`Rope`: chunks of at most 1 KB with their lengths, UTF-8 lengths
  and line breaks; line and offset lookups and UTF-16/UTF-8 mapping by
  binary search), multi-cursor selections, undo grouped by runs of
  typing, highlighting read again from an edited line until a line's
  state is the one it had (`CodeLanguage`; TypeScript, TSX and Haxe are
  `helder.syntax.Lexer`'s, by extension in `CodeLanguages`, more
  registered), and the commands (brackets paired, Enter's indentation,
  words, indent, comments, duplicated and moved lines, cursors above,
  below and at the next occurrence, find and replace). `CodeView` draws
  it virtualised (only the lines in view highlighted, laid out and
  drawn; a line laid out kept until it changes, and shared by content)
  in the bundled JetBrains Mono (OFL, ligatures off unless asked): a
  gutter of line numbers and diagnostics, the current line, selections,
  cursors that blink and spring, indentation guides, whitespace in
  selections, decorations, squiggles with their message on hover; keys
  are `CodeAction`'s through the keymap (context `CodeEditor`), an input
  method composes at the primary caret (its context the caret's line),
  and assistive technology reads a multi-line text input
  (`Node.accessValue`). `CodeEditor` adds find and replace and go to
  line, and the studio's hooks: `revealRange`, `setSelection(s)`,
  `addDecoration`, `setDiagnostics` (helder.compiler.service's),
  `onChange` with each edit's changes (helder.syntax's: a
  `Transaction`'s). examples/code-editor hosts it; tests: `CodeModel.test.hx`,
  `CodeEditor.test.hx`, the headless-run lane (a scripted 2,000-line TSX
  file), the code-bench lane (tests/bench/results/code-editor.md). Not
  yet: soft wrap, folding, completion, bidi text on its column grid.
- **Popups**: `Popup` nodes are layers over the tree (`Ui.open`, `Ui.close`:
  children of `Ui.overlay`, drawn and hit after the tree, not clipped by
  it), anchored to a node (below, above, beside; flipped and kept in the
  window), in a corner of the window (notifications), at a point (a context menu) or modal (a backdrop, the focus kept inside); a press outside or
  Escape asks them to close. In markup, `UiFlow.Popover` puts its children
  in one while `open` is true.
- **Long lists**: `VirtualScroll` (markup's `VirtualList`, `UiFlow`)
  makes only the rows in view and an overscan more, in the flow between
  two spacers; a `HeightIndex` (a sum tree over leaves of 128 rows: 4
  bytes a measured row, under one for the rest) holds every row's height,
  estimated until the row is shown and measured (whole pixels: a row's
  height taken up to the next, so rows above changing move no edge), the
  estimate following the measured mean. Each layout ends with the rows
  shown measured and the window moved (`Ui.update` settles its settlers,
  laid out again while one changes), so no frame shows a gap. The scroll
  is anchored to the row at its top: measures, the estimate, rows put in
  or taken out above it (`splice`; VirtualList diffs its list by key into
  them) move nothing in view. Rows leaving the window are hidden and kept
  by key (`keep`, the farthest let go), coming back made already;
  `scrollToIndex` and `focusIndex` reach rows not made, the arrows, Page
  Up and Down, Home and End move the focus (and `selected`, a key that
  outlives its row's node) onto them; a listbox to assistive technology,
  each made row's place among all (`Semantics.posInSet`, `setSize`).
  examples/million and ts-million (a million messages); tests: MarkupTest,
  `HeightIndex.test.hx`, the headless-run lane, the million-bench lane
  (tests/bench/results/million.md). Not yet: sticky headers across rows
  (a header sticks within its own row), horizontal lists, the code
  editor's lines on the index (fixed height: a multiplication is all it needs).
- **Shortcuts**: the keymap's bindings to actions (below), run when the
  focused node does not take the key; menu items show them.

## Navigation

`Router` (helder.ui) holds screens by path as a stack, `Stack` shows it
(examples/navigation):

```haxe
final nav = new Router();
nav.route("/", _ -> <Home/>)
	.route("/product/:id", p -> <Product id={p.id}/>)   // p:{id:String}
	.fallback(path -> <NotFound path={path}/>);
<Stack router={nav}/>                                  // transition={Slide | Fade | None}

nav.go("/product/3");  nav.back();  nav.replace("/cart");  nav.reset("/");
nav.open(url);         // myapp://host/product/3, https://..., a path: the root and the match
nav.path(); nav.depth(); nav.query();                  // Reads of the top
```

- Routes match in order; `:name` takes one segment (decoded), its
  params typed from the path literal (Haxe: `route` is a macro; TS: a
  template-literal type, `RouteParams<P>`). No optional segments or
  wildcards. A path none matches is the fallback's, else `go` throws.
- Each entry is mounted once, when pushed, and kept below the top
  (hidden once covered: its state and scroll kept); a popped one is
  disposed after its exit. During a transition the entering and leaving
  screens take no pointer input. After a push or pop the new top's first
  focusable node takes the focus, and its first text is announced (a
  polite live region).
- The system's back: while `depth > 0` the Stack is `App.onBack` (a pop)
  with `App.backDepth = depth`: Android's back, Escape on the desktop and
  in the browser. At the root, and once unmounted, the app's own onBack
  and backDepth are back.
- In a browser the Stack owns the page's history (`helder.os.History`,
  App.backDepth's single entry set aside): a push is an entry with its
  path, the history's back pops, and at start the Stack opens
  `location`'s path and query, so a reload or a shared URL shows that
  screen over the root. Deep links are the app's to wire:
  `App.onOpen = urls -> nav.open(urls[0])`.
- Transitions, the platform's by default: iOS's and macOS's slide (the
  new screen from the right edge over 350 ms, critically damped; the one
  below to -30% and dimmed by 10%; a drag from within 20 points of the
  left edge pops as it goes, done past half the width or 500 pt/s, else
  springing back), Android's (a 10% slide and a fade in over 300 ms, the
  one below to 90%), and elsewhere a fade (150 ms with an 8 px slide).
  An explicit `Slide` is iOS's off Android. Reduced motion
  (`Settings.reducedMotion`, `Clock.reducedMotion`): a 150 ms fade
  for a slide or a fade (`None` stays none). Screens are see-through unless their content
  has a background: give a screen's root one under a slide.

## Actions and keymaps

`helder.ui.actions`, modelled on Zed's GPUI. An action is a value of an
enum an app or a library declares (`enum ViewerAction { Next; ZoomTo(percent:Float); }`),
its namespace given by a definition (src/helder/compiler/DESIGN.md 4):
`actions("viewer", ViewerAction)`, `viewer::ZoomTo` in a keymap. Its
handler (`ActionsDefinition`, TypeScript's the same) checks it when the
program is built: the namespace an identifier, a string literal, declared
once in the program; every argument one a JSON keymap can give (numbers,
strings, booleans, and arrays and structures of these). It generates the
actions' names and their arguments' readers and comparisons (an
`ActionSpace`, registered where the call is evaluated), so nothing is
looked up by reflection at run time (`-dce full` keeps it working).
`StandardAction` is declared as `standard` (`standard::Quit`).
`Ui.dispatchAction(a)` sends it from the focused node up its
ancestors (a popup's: on to the node it is anchored to, else where the
focus was when it opened) to the root, then to the window's handlers
(`Ui.on`), then the app's (`Actions.on`): each handler (`Node.on(ViewerAction,
a -> ..., ?state)`) takes it (true) or lets it bubble (false); its state
(`Enabled`, `Disabled`, `Checked`, `Unchecked`, `Unhandled`) is what a
menu shows. `StandardAction` is every app's (Quit, CloseWindow,
ToggleFullscreen: the window's; Copy: the selection's; About, Undo, Cut,
Paste...: the menus' roles).

In TypeScript (`helder/ui/actions`, src/helder/ui/actions/index.ts) the
definition takes an object of methods, their parameters the arguments; a
method with arguments returns them as an object, which is what TypeScript
types the action as (a type has no parameter names), and the bodies never
run. It is plain TypeScript, checked by tsgo as it is written:

```tsx
import { actions, type ActionOf, handle, Keymap } from "helder/ui/actions";

export const Viewer = actions("viewer", {
	next() {},
	zoomTo(percent: number) { return { percent }; },
});
export type ViewerAction = ActionOf<typeof Viewer>;   // {type: "next"} | {type: "zoomTo", percent: number}

Keymap.global.bind("1", Viewer.zoomTo(100), "Viewer");
<view key-context="Viewer" actions={handle(Viewer, a => {
	switch (a.type) {
		case "next": next(); return true;
		case "zoomTo": zoom(a.percent); return true;
	}
}, a => a.type === "next" && last() ? Disabled : Enabled)}>...</view>
```

`Viewer.zoomTo(100)` makes a value, `{type: "zoomTo", percent: 100}`; a
handler is a `switch (a.type)`, narrowed by the checker. The same
machinery dispatches it (`on(node, ...)`, `onWindow`, `onApp`, a JSON
keymap's `["viewer::ZoomTo", 100]`, menus' `item(label, action)`,
`resolve`, `popup`, `MenuBar`); `Standard` is StandardAction's
(`Standard.quit()`), its values given to a TypeScript handler as the
program's objects. tests/typescript/definitions/shortcuts.tsx and
Shortcuts.hx print the same; examples/ts-todo binds its filters.

A node's key context (`Node.keyContext`, `KeyContext.parse("Editor mode=full read_only")`)
joins the context stack of the focus (root first). A binding
(`Keymap.bind("secondary-k secondary-s", ZoomIn, "Viewer && !picker")`)
matches by GPUI's predicates: names, `key == value`, `!=`, `!`, `&&`,
`||`, parentheses and `a > b` (b inside a). Keystrokes as GPUI writes
them: `ctrl-shift-s`, `alt-enter`, `f11`, `ctrl--`, `secondary-o`
(Command on macOS, Control elsewhere); several separated by spaces are a
chord, which waits `Keymap.timeout` (1 s) for its next keystroke
(`Ui.pendingKeys`), then runs what its keys alone are bound to. Of the
bindings that match, the one whose context holds deepest wins, then the
later; one whose action no handler on the path takes is passed over.
`Keymap.global` is the app's default keymap; `loadUser(path)` adds a JSON
file over it (`[{"context": "Viewer", "bindings": {"secondary-k z": "viewer::ZoomIn", "1": ["viewer::ZoomTo", 100], "f11": null}}]`:
null unbinds), read again when it changes (a window polls it each
second; a bad file keeps the last good bindings, `error` says why).
`keysFor(action, ?stack)` and `label(action)` (`"Ctrl+O"`, `"⌘K ⌘S"`)
are what a menu or a tooltip shows. Keys a typing field takes (no
Control, Alt or Command) stay its own; the keymap runs after the focus's
`onKeyDown` handlers.

Focus: `FocusHandle` (made before its node, tied by `track-focus`):
`focus()`, `blur()`, `isFocused()`, `containsFocus()` and the signals
`focused` and `within`; `Node.focusWithin()`; `Node.tabIndex` orders Tab
and Shift+Tab as the DOM's tabindex does (above 0 first, below 0 left
out). A popup gives the focus back to where it was when it closes. In
markup:

```haxe
<view key-context="Viewer" actions={[Actions.handle(ViewerAction, a -> switch a {
	case ZoomIn: camera.zoomIn(); true;
	case _: false;
}, a -> a == ZoomIn && camera.canZoom() ? Enabled : Disabled)]}>
	<view track-focus={handle} tab-index={1}/>
</view>
```

## Menus

`helder.ui.menu`: one model for the menu bar and context menus. A
`MenuItem` is `Item(label, action)`, `Separator`, `Submenu(label, items)`
or `Role(role)` (About, Quit, Hide, Undo, Redo, Cut, Copy, Paste,
SelectAll, Minimize, Zoom, Fullscreen, CloseWindow: `StandardAction`'s);
a `Menu` is a title and its items (`role: Window`: the window menu).
`Menus.resolve` turns it into the platform's items: each action's
shortcut from the keymap (the first binding where the context stack of
the node it is for holds), enabled and checked from its handler's state.
`Menus.popup(ui, items, x, y, ?from)` shows a context menu, its choice
dispatched from `from`; `MenuBar` (markup's `<MenuBarView menus={...}/>`)
the window's bar, set again when a label or a state changes (checked
before each update, `Ui.beforeUpdate`). Where `Ui.hostOf` says native
(`"context-menu"`, `"menubar"`) and the window has them: macOS's NSMenu
(the bar's menus after the application's, About moved to the top of the
application's menu, Quit and Hide left to its own, a window menu's items
in Window; an editing role's `copy:`, `paste:`... sent to a native text
editor first; context menus by popUpMenuPositioningItem), Windows' HMENU
(SetMenu; the accelerator after a tab, `Open…\tCtrl+O`; TrackPopupMenuEx).
Elsewhere (Linux) helder draws them (`DrawnMenu`, GTK's look loosely, in
the window's light or dark colours): a bar of titles (F10 opens the
first; Left and Right move along it; a hover moves while one is open) and
popups with check marks, shortcuts at the right and submenus; Up, Down,
Home, End, a letter, Right and Left into and out of submenus, Enter or
Space chooses, Escape closes the innermost, a press outside all; the
focus given back when they close. `tests/os/MenuTest.hx` reads each
platform's back (the window lane); `src/helder/ui/menu/Menus.test.hx` the
model and the drawn menus.

## Markup

Intrinsic elements: `view` (a box), `text` (a run of text), `scroll` (a box
that scrolls), `image` (an `ImageNode`: `src={image}` or `src={svg}`, `fit="cover"`, `object-position="left top"`).
Inside a `text`, elements are spans of rich text: `span`, `b`, `i` or
`text` again, each with its own style (colour, weight, size...) and
handlers (a link: `<span color="#2563eb" onClick={...}>`); lines are as
high as CSS makes them, their spans on one baseline.
Attributes:

- any Style property, in camelCase or kebab-case, with values as CSS
  writes them: `direction="row"`, `justify="space-between"`,
  `padding="8 12"`, `width="50%"`, `background="#3b82f6"`, `radius={6}`;
  `style={...}` takes a typed `StyleProps` object;
- events: `onClick`, `onPointerDown`, `onPointerUp`, `onPointerMove`,
  `onPointerEnter`, `onPointerLeave`, `onPointerCancel`,
  `onLostPointerCapture`, `onWheel`, `onKeyDown`, `onKeyUp`,
  `onTextInput`, `onFocus`, `onBlur`, `onFocusIn`, `onFocusOut` (bubbling) (an `Event -> Void`);
  `onPress` (`Node.onActivate`: a click, or Enter or Space unless `onKeyDown`
  took it, as a DOM button's click); the gestures `onTap`, `onPan`
  (`pan-axis="x"`, `pan-min-pointers`), `onPinch`, `onScale` (a
  recogniser made on the node, given to its handler: a `Tap`, a `Pan`, a
  `Scale`). `helder.ui.view.NodeEvents` declares them (NodeRenderer's
  `@:events`, the neutral elements' in every renderer), and markup checks
  each handler against it: a function of its event or of none
  (`onPress={() -> ...}`), an untyped parameter typed as it
  (`onPan={g -> x(g.tx)}`, `onInput={e -> name(e.text)}`); another type, a
  Dynamic value or a name not there is a compile error at the attribute
  (helder.view's README);
- `key-context="Viewer zoomed"` (what the node is to the keymap),
  `actions={[Actions.handle(ViewerAction, a -> ...)]}` (its action
  handlers), `track-focus={handle}` (a `FocusHandle` tied to it),
  `tab-index={1}` (Tab's order): see Actions and keymaps below;
- `focusable`, `ref={n -> ...}` (the node), `tag="name"` (for `Node.find`);
  `id` none here (a page's element's, where a page's renderer realises
  the element).

The elements are also the neutral ones of single-source components
(`@:neutral`, src/helder/view/README.md): `view:button`, `view:label`... and
`text:p`, `text:h2`... are a view and a text here, the element of that name
in a page; `<icon name="check"/>` draws lucide's icon of that name
(`helder.ui.widgets.Icons`, an inline SVG in a page; `mirrored` flips it
right to left, `data-mirrored` in a page); `<field/>` and
`<field:textarea/>` are a text field (`TextField`, `TextArea`: native
where `Ui.policy` says; a page's `<input>`, `<textarea>`): `value`,
`placeholder`, `type` (`password`: dots), `rows`, `readonly`,
`maxlength`, `spellcheck` (the platform's checker on its words: a text
area's by default, a field's asked; misspelled words underlined with a red
wave, their corrections and Add to Dictionary in a right click's menu;
`helder.text.Spell`, off in the deterministic modes), its soft keyboard
(`helder.os.TextKind`, Text input below): `keyboard` (`text`, `email`,
`number`, `decimal`, `phone`, `url`, `search`), `enterkey` (`default`,
`done`, `next`, `go`, `search`, `send`), `autocapitalize` (`none`,
`words`, `sentences`, `characters`), `autocorrect`, `autocomplete`
(`new-password`: iOS suggests one), `inputmode` (a page's), `onInput` (its
text changed by its user: `e.text`), `onSubmit` (Enter, the keyboard's
Enter key whatever its label: `e.text`), its own editing after the markup's
`onKeyDown`... unless that prevented the default; a ref of theirs gets an `helder.ui.Part` (Node is one: `focus`,
`rect`, `scrollIntoView`, `contains`, `attr`, `rtl`, `capture`: a press's
moves and release to it (in a handler, that event's pointer: a finger's too); `select`: a field's selection).
- drag and drop: `drag-data={value}` makes a node draggable; `onDragStart`,
  `onDragEnd` (`e.dropped`) on the source, `onDragOver` (`e.preventDefault()`
  accepts), `onDragLeave` and `onDrop` (`e.data`) on targets; Escape cancels.

A phone's safe area (the insets its bars, notch, island, cutout or home
indicator leave clear) is CSS's `env()`: a literal attribute naming
`env(safe-area-inset-top)` (`-right`, `-bottom`, `-left`; a fallback after
a comma for a name it does not know) is bound to the main window's insets
in UI pixels (`SafeArea.insets`, a signal; UiWindow sets it from
`helder.os.Window.safeTop`... over the scale) and set again when they
change (a rotation, the bars hidden): `padding-top="env(safe-area-inset-top)"`,
`padding="calc(env(safe-area-inset-top) + 8px) 16px"`,
`margin-bottom="max(12px, env(safe-area-inset-bottom))"` (`calc()`,
`max()` and `min()` of pixels fold to one length). Each Ui has its own as
`ui.safeArea` (0 on the desktop and the web); a `<Scene>`'s box gives the
part over it (`SceneBox.safeArea()`), for a game's HUD over a scene on the
whole screen.

A desktop window's title bar can be inset into the app
(`<Surface titlebar="inset">`, helder.os's `TitleBar`): the content runs
under it and the app lays out the window's buttons with
`<WindowControls/>` (`helder.ui.widgets.WindowButtons`: on macOS a box of
the system's own buttons' size, the buttons placed at it after each
layout; on Windows minimise, maximise and close drawn, 46 by 32, the close
button red when hovered; on Linux round ones; nothing in the browser, on a
phone or with the system's title bar). A node with `drag-region` moves the
window when pressed (what takes presses inside it, a button or a field,
stays the content's: `Ui.titleHit`, which each system's code asks at a
press, Windows at each WM_NCHITTEST); `env(titlebar-area-x)`, `-y`,
`-width` and `-height` are the bar's area free of the buttons (the Window
Controls Overlay's names, bound as the safe area's; without an inset
title bar the fallback). A layout whose top left and top right are
different bars (a sidebar's, an inspector's) puts one at each end,
`<WindowControls side="start"/>` and `<WindowControls side="end"/>`: only
the one at the system's side is drawn (`WindowButtons.side()`, reactive:
`"start"` on macOS, `"end"` on Windows and Linux, null without an inset
title bar), which a bar's padding at that end can follow too. Tests:
`TitlebarArea.test.hx`.

```haxe
<Surface title="Studio" titlebar="inset">
	<view direction="row" drag-region height="env(titlebar-area-height, 40px)" padding-left="env(titlebar-area-x)">
		<text>Studio</text><view grow={1}/><WindowControls/>
	</view>
</Surface>
```

```haxe
<view direction="row">
	<view tag="sidebar" drag-region><WindowControls side="start"/><text>Project</text></view>
	<view grow={1}/>
	<view tag="inspector" drag-region padding-right={WindowButtons.side() == "end" ? 0 : 12}>
		<text>Inspector</text><view grow={1}/><WindowControls side="end"/>
	</view>
</view>
```

A value that is a signal, a memo or a function is reactive: the attribute,
text or region follows it. In a `view`, text and text-valued holes next to
each other become one `TextNode`.

Tags and attribute names are resolved at compile time, so a program links
only the nodes, attributes and value parsers its markup names (a gradient
parser only with a gradient, image nodes only with `image`). A name none of
them has, a spread (`{...props}`) or `NodeRenderer.setAttribute` looks the
name up at run time and links them all.

## Controls

`helder.ui.controls` holds the standard controls, drawn by helder in one
look on every platform: `Button`, `Checkbox` (`indeterminate` too),
`Switch` and `PathBar`. The rest of the set and its design are in
[docs/design/controls.md](/docs/design/controls.md). Each control is its
behaviour (`Press`, `Toggle`), its parts (nodes bound by `ref`), and a
look's recipe for it (`Look`).

```haxe
import helder.ui.controls.Look;
import helder.ui.controls.Standard;

<Standard.Themed look={Look.base}>
  <Standard.Button variant="primary" onPress={save}>Save</Standard.Button>
  <Standard.Checkbox label="Remember me" checked={remember} onChange={v -> remember(v)}/>
  <Standard.Switch label="Dark mode" checked={dark} onChange={v -> dark(v)}/>
</Standard.Themed>
```

```tsx
import { Button, Checkbox, Switch, Themed, Look } from "helder/ui";

<Themed look={Look.base}>
  <Button variant="primary" onPress={save}>Save</Button>
  <Checkbox label="Remember me" checked={remember} onChange={remember}/>
  <Switch label="Dark mode" checked={dark} onChange={dark}/>
</Themed>
```

- **Props.** `Button`: `children` (text or views), `label` (its name for
  assistive technology: an `icon` alone's), `icon` (an `Svg`; alone: a
  square button), `variant`, `size`, `disabled` and `selected` (each a
  `Read<Bool>`), and `onPress`. Give `selected` to expose a toggle
  button's pressed state and update its value from `onPress`.
  `Checkbox` and `Switch`: `label`, `checked` (a
  `Read<Bool>`), `onChange`, `disabled`, `variant`, `size`;
  `indeterminate` (a checkbox's mixed). `checked` with no `onChange`: the
  caller's alone; neither: the control's own state. Each takes `tag`.
- **Keys and states** (WAI-ARIA's patterns, on helder's access tree):

  | Control | Keys | To assistive technology | Attributes a recipe reads |
  | --- | --- | --- | --- |
  | Button | a click, Enter, Space | button, disabled, pressed if a toggle | `data-disabled`, `data-selected` |
  | Checkbox | a click, Space (not Enter) | checkbox, checked or mixed | `data-state=checked\|unchecked\|mixed` |
  | Switch | a click, Space, Enter | switch, checked | `data-state` |

  Disabled: no press, not focusable. Pressed holds while the pointer is
  down on it and over it (leaving cancels it); hover is never a touch's;
  the focus ring is the keyboard's alone (`ui.focusVisible`).
- **Behaviour without the look**: `Press.of(props, "button")` and
  `Toggle.of(props, "switch")` (a checkbox for any other name) bind a
  control's root and parts by `ref` (`p.root`, `p.part("knob")`: in
  TypeScript `ref={n => p.root(n)}`): the root's slot (the name), role,
  label, focus, keys, `data-*`, variant and size; a part's slot
  (`switch-knob`). Their states are signals (`hovered`, `pressed`,
  `focusVisible`, `checked`, `mixed`) and eased amounts (`eased`).
  Neither sets a style. `invalid`, `required` and `modal` are in the
  access tree too (markup's attributes; UI Automation's
  IsDataValidForForm and IsRequiredForForm, AT-SPI's INVALID_ENTRY,
  REQUIRED and MODAL, macOS's required and modal, Android's
  contentInvalid, ARIA's).

**PathBar** takes `segments` (a `Read<Array<PathSegment>>`, each with a
`label` and optional `icon`) and calls `onNavigate(index)` for an ancestor,
including one picked from the overflow menu. Give `onSeparator(index, anchor)`
to open a folder menu from its chevron. Clicking the current segment or
empty space starts editing. Pass an `editing` signal to start it from a
shortcut. The editor selects `text` (the labels joined with `/` by
default), calls `onSubmit(text)` on Enter, and closes on Escape or blur.
`editable={false}` disables the editor. The bar takes `size` (`sm` or
`md`), `tag`, and an accessible `label` (defaults to “Path”).

### Looks

A look is tokens, a recipe per control, the renderings an app replaced
and its own parts, compiled once into a `StyleSheet` that `Rules` runs:
a control's states only change which rules hold. `Look.base` is helder's;
`<Themed look={look}>` installs one for a subtree (its sheet, and the
look its controls take); a control under none takes `Look.base` for
itself.

**Tokens.** Colours are tones (`Look.tone(light, dark)`, as CSS writes a
colour: `oklch()`, `#hex`), the rest plain values; a recipe reads them
as `Refs` (colours as token references, light or dark by the window,
`Ui.dark`). `Look.ref` gives the references for inline markup
(`color={Look.ref.fg3}`).

| Group | Tokens |
| --- | --- |
| Surfaces | `canvas` (the window), `surface` (what rests on it), `raised` (what floats), `well` (fields), `hover`, `press` (washes), `fill`, `fillHover`, `fillPress` (a filled control's gray), `rail`, `railHover` (a switch's track off), `line`, `edge`, `edgeStrong` |
| Text | `fg`, `fg2`, `fg3` |
| Accent | `accent`, `accentStrong` (its hover), `accentSoft`, `accentFg` (text on it), `accentInk` (accent text), `focus` (the ring: one blue for every accent) |
| Status | `danger`, `dangerStrong`, `dangerSoft`, `dangerFg`, `success`, `warning`, `info` |
| Other colours | `knob`, `scrim`, `shadow` |
| Type | `font` (Inter), `display` (Inter Display), `mono` (Geist Mono), `size` 14, `small` 12, `large` 16, `title` 20, `medium` 500 |
| Shape | `radius` 10, `radiusPanel` 14, `radiusSurface` 18; `controlSm` 30, `control` 36, `controlLg` 44; `padSm` 12, `pad` 16, `padLg` 20; `gap` 8, `icon` 16; `box` 18; `track` 36 by `trackHeight` 20, `thumb` 16 |
| Motion | `hoverTime` 0.12, `toggleTime` 0.18, `openTime` 0.26, `floatTime` 0.22, `dialogTime` 0.3, `exitTime` 0.15 (seconds); `pressScale` 0.98; `disabledOpacity` 0.42 |

The neutrals are pure grays (white in light, 0.18 to 0.26 in dark, as
OKLCH's lightness). A button is a soft rectangle (radius 10, 8 small, 12
large): `primary` the accent, `secondary` a filled gray (the default),
`outline` the surface in a hairline edge, `ghost` a wash on hover,
`danger` red; a solid one rests on a hairline of shadow, lightens under
the pointer and settles back when pressed. `density: Compact` gives
13-point type, controls of 26, 30 and 36 and radii of 8, 12 and 16;
`accent` one of `Graphite` (the default: neutral, near black in light
and near white in dark), `Blue`, `Violet`, `Teal`, `Green`, `Amber`,
`Orange`, `Red`, `Pink` (after CUI's table). A token given alone,
`accent`, brings its shade, tint and ink. `font` is helder's Inter
(src/helder/text/fonts): a web page ships it, and on a system without
one `Look.base` adds it when first used; the other fonts are named, not
bundled: an app adds them (`Asset.font`), else the system's stand in.

**Recipes.** A control's recipe is a function of the tokens giving each
part's style; a style's keys may be states, nested (`checked: {hover:
{...}}`), and a part's states are its control's:

| Recipe key | While | | Recipe key | While |
| --- | --- | --- | --- | --- |
| `hover` | hovered | | `checked`, `mixed` | `data-state=checked`, `=mixed` |
| `pressed` | pressed | | `selected`, `open` | `data-selected`, `data-state=open` |
| `focus` | the keyboard's focus | | `invalid`, `readonly` | `data-invalid`, `data-readonly` |
| `disabled` | `data-disabled` | | `dark` | the dark appearance |

`variants: {variant: {...}, size: {...}}` gives each value's parts,
`defaults: {variant, size}` what a control takes when its props give
none. Parts: a button's `root`, `icon`, `label`; a checkbox's `root`,
`box`, `mark`, `label`; a switch's `root`, `track`, `knob`, `label`.
Slots are `button`, `button-icon`, ...: the rules a sheet gets are
ordinary ones, a part's states its root's (`group/switch:hover`).
TypeScript's styles are written as markup's attributes are (`'row'`,
`'0 12'`, `'#e11d48'`, `'scale(0.97)'`: `StyleProps`, typed in
`style.d.ts`), parsed once when the look compiles.

**`look.with({...})`** gives a new look, the patch's keys over the
look's by part and state, property by property:

```haxe
static final look = Look.base.with({
  accent: Violet,
  tokens: {radius: 6},
  button: t -> {variants: {variant: {soft: {root: {background: t.accentSoft, color: t.accentInk}}}}},
  "switch": t -> {knob: {radius: 3}},
  render: {"switch": Lamp},
  parts: {card: t -> {padding: 24, radius: t.radiusSurface, background: t.surface}}
});
```

```ts
const look = Look.base.with({
  accent: "violet",
  tokens: { radius: 6 },
  button: t => ({ variants: { variant: { soft: { root: { background: t.accentSoft, color: t.accentInk } } } } }),
  switch: () => ({ knob: { radius: 3 } }),
  render: { switch: Lamp }
});
```

- **Typed variants.** A look's type names its variants and sizes, the
  patch's added (Haxe: `with`'s macro reads them from the recipe's
  literal; TypeScript: `Look<V>`, inferred from the patch). `look.Button`
  takes the look's: `<look.Button variant="soft">`; `Button` takes
  `Look.base`'s, and `variant="soft"` there is a compile-time error, at
  the attribute in Haxe (`"soft" is no button variant of this look`), the
  TypeScript checker's in TypeScript. A variant is a literal.
- **A rendering replaced** (`render`): every `Switch` under the look, those
  inside other widgets too, is the app's component, given the switch's
  props; it binds `Toggle.of(props, "switch")`, so its behaviour, keys
  and accessibility stay the switch's, and the recipe still styles its
  parts:

  ```haxe
  function Lamp(props:SwitchProps<Dynamic>):View {
    final sw = Toggle.of(props, "switch");
    return <view ref={sw.root} direction="row" column-gap={8}>
      <image ref={sw.part("icon")} src={() -> sw.checked() ? lit : unlit} width={24} height={24}/>
      <text>{props.label}</text>
    </view>;
  }
  ```
- **App parts** (`parts`, Haxe's for now): a slot each, styled as a
  control's root (its states its own), so an app's panels and cards share
  the look's tokens (`examples/signup`).

**Animated states.** A recipe's states are amounts that ease from 0 to
1 over the look's time for them (a hover's, a toggle's), and what they
change blends: colours, opacity, transforms, shadows and rings, through
the transition compile gives each part (unless the part gives its own),
on the quad every part already draws as. A press gives 2%; a switch's
knob travels with `checked` over the toggle's time, springing (a
Bézier's overshoot); the keyboard's ring fades in. Under reduced motion
travel jumps to its end and colours still fade. `Press.eased`
(`Eased`: `hover`, `pressed`, `checked`, `focus`, `open`) has the amounts
for what draws itself.

**A part's shader** (the escape hatch): `draw:
PartShader.of(shader)` (`helder.ui.draw.PartShader`, a helder.gfx
shader taking `DrawParams`: the part's size, the look's accent, text and
surface colours, the eased states) draws the part's content into a
texture of its own, in a pass before the window's, shown under the
part's children. Each such part costs a pass and splits the window's one
draw (a texture bound between quads), so the default look has none: 500
buttons draw in one pass, one pipeline and one draw, as 500 plain views
do (`tests/ui/ControlsBench.hx`, the ui-draw lane, which checks both).

The controls' gallery, every state in light and dark at both densities,
is `tests/ui/ControlsGallery.hx` against `tests/ui/controls/`.
`widgets.Theme` is the studio's look from before; it goes once the apps
move onto looks.

## Themes

A node's look is its style, or a theme's: a `StyleSheet` of `rules`, each
a `Rule` `{slot, ?variant, ?size, ?when, style}`, and the colours its
token references name, `light` and `dark`. A node takes the rules of its
`slot` (the name of the part it is: `"button"`, `"switch-thumb"`),
`variant` and `size` whose states all hold: `hover`, `active`,
`focus`, `focus-visible`, `disabled`, `dark`, `rtl` and `ltr` (its direction), `starting` (until it is first drawn, as CSS's `@starting-style`: its transition then eases from there), `sm`, `md`, `lg`, `xl`, `2xl` (the window at least Tailwind's breakpoint wide), `placeholder` (an
input's placeholder colour), `selection` (its selection's background), attributes (`data-state=checked`, a bare
`data-disabled`; `node.setAttr`, markup `data-state="checked"`;
`data-slot=x` is the slot), and other nodes' states, as Tailwind's
variants: `group:hover` (an ancestor with a `group` attribute hovered;
`group/item:` one whose attribute names `item`), `peer:data-state=checked`
(an earlier sibling with a `peer` attribute), `has:focus` (a descendant;
`has:>x` a child), `first`, `last`, `not:x`, nested as
`group:has:focus`. Later
rules win, property by property; the node's own style wins over them
(a value still its default counts as none: `Rules.keep(node, ["padding"])`
holds its own at any value, as an instance's `p-0` over its slot's `p-4`).
Lengths may be token references too: `Length.token("radius", -4)` is
`calc(var(--radius) - 4px)`, resolved with the sheet's `lengths` (radii).
Colours may be token references, `Color.parse("var(--primary)")`,
`"var(--ring)/50"`, resolved with the sheet's colours when applied;
`oklch()` and `oklab()` parse as CSS converts them (Chromium's pixels).
A TypeScript program's styles are written as markup's attributes are
(`StyleProps` in `style.d.ts`) and parsed once: a look's when it is made,
a sheet's own rules once a look has been made with `with` (a TypeScript
program styles through looks; a sheet alone keeps its values as given).
A node's own colour may be one too (`color={Look.ref.fg3}`,
`background="var(--canvas)"`): resolved with its nearest sheet's colours,
light or dark, whenever they change; one it is given since is its own.
`ui.theme = sheet` installs one for a window, `node.theme` for a subtree,
`ui.dark` picks the dark colours and the `dark` rules; every change of a
state, attribute, variant, sheet or of dark applies them again, at the
window's next update (several changes, one restyle). Without a sheet a
node has no look but its own style, unless a program adds base rules
(`Rules.addBase`: where no sheet applies). The examples' sheets are their
own (`Todo.sheet`, `Mail.sheet`). A part's states are signals (`helder.ui.view.States.of(node)`:
`hovered`, `pressed`, `focused`, `focusVisible`, `disabled`,
`attr("data-state")`...), and a node's `states` attribute is a function of
them, as React Aria's render props: `<view:button states={(s:States) ->
(s.pressed() ? {opacity: 0.8} : {} : StyleProps)}>` (typed: a function
literal markup cannot type is a reactive value; over the theme's rules;
what it stops giving, the theme's again). The system colours `Canvas` and `CanvasText` are a sheet's colours of those
names, else Chromium's, light or dark; a page's slot `"body"` takes them
(a page's background and text colour), and the layers
(popups, dialogs: `ui.overlay`) inherit its text, as a page's popups in
its body do (`ui.body`).

## Fonts

Text is shaped and rasterized by `helder.text` with the system's fonts
(`sans-serif` by default). `HELDER_NO_SYSTEM_FONTS=1` makes
`helder.text.SystemFonts` look for none (only the fonts added: a
program's fallback tested as on a bare system); `HELDER_FONT_DIRS`
(directories, `:`-separated) looks in those alone, the platform's lookups
off: the same faces on every machine. Colour emoji come from the system's emoji font,
drawn from its bitmaps (scaled down as a browser does) or colour layers. In a browser, give the page's fonts to `run`
(`fonts: [...]` with `src/helder/text/imports.mjs`).

## Platform views

`helder.ui.platform` is a small layer for the platform's own views
embedded in a drawn window, each in a rectangle the layout gives it:
the native menus (a context menu, the menu bar), the platform's text
editors where `Ui.policy` or a node says native (on the desktop helder
draws its own by default), the system's web view (`WebView`, below),
and later other heavy views (video) when an app needs one. A window's `Ui.platform` is its
`PlatformViews` (`MacViews` on macOS, `IosViews` on iOS, `WinViews` on
Windows, `WebViews` in a browser; none on Linux and Android, where
everything is drawn); a
`PlatformEditor` is one text editor, `PlatformMenuItem` a menu's item as
the platform takes it. The AppKit and Win32 calls they make beside
helder.os's are theirs (`AkMsg`, `UkMsg`, `Win32`).

### The web view

`<webview>` (`helder.ui.platform.WebView`, a node) is the system's web
view placed where it is laid out, over the drawn surface: on iOS and
macOS a WKWebView (`AppleWebView`: a subview of the window's view,
its UiWindow's surface's), on Android an `android.webkit.WebView` (`AndroidWebView`:
a panel window of the activity's, since NativeActivity's own window draws
no views, made and driven on Java's main thread); elsewhere nothing yet
(its box is drawn). `WebShell.run` is an app that is a web view alone, on
the whole screen (iOS: its window's root view; Android: the activity's
content, `org.hxmc.Activity`; the desktop: a window with one WebView):
the thin native shell around a web app (helder studio's web build on a
phone, where only the system's web view runs wasm compiled at run time).

```haxe
var content = WebContent.bundle("web/");          // Asset.bytes("web/index.html") etc.: the bundle's files
<webview src="index.html" content={content} flex-grow={1}
	onMessage={e -> reply(e.text)} onTitle={e -> title(e.text)} onLoadError={e -> trace(e.text)}/>

web.post("hello");                                 // the page's helder.onmessage (e.data)
web.postJson({kind: "open", path: p});
web.postBytes(bytes);                              // an ArrayBuffer there
web.eval("document.title");
web.snapshot(shot -> ...);                         // {width, height, pixels}: RGBA8, straight alpha

WebShell.run({content: content, src: "index.html"}, (shell, e) -> if (e.kind == Message) shell.post("pong"));
```

- **Its own origin**: a `WebContent` serves the bundle's files
  (`bundle(prefix)`: helder.asset's keys, which the program names), a
  directory's (`directory(dir)`) or a function's (`handler(path ->
  WebResponse)`). On iOS and macOS by a server of the app's own on the
  loopback address (`WebServer`: `http://127.0.0.1:<port>/`, a potentially
  trustworthy origin; WebKit isolates HTTP origins only, never a custom
  scheme's page, as CI's simulator shows), or with `local = false` by
  WKURLSchemeHandler for `app://localhost/`; on Android by
  `shouldInterceptRequest` for `https://appassets.androidplatform.net/` (as
  WebViewAssetLoader). The page is a secure context. Every response has
  COOP `same-origin`, COEP `require-corp` and CORP `same-origin` (its
  `headers`), and a MIME type by extension (`.wasm`: `application/wasm`):
  `crossOriginIsolated`, SharedArrayBuffer and wasm threads on Apple's;
  Android's WebView (Chrome 113 on CI's emulator) isolates no page, the
  headers notwithstanding. The loopback server answers its own web view
  alone (below: its threat model): its URLs are
  `http://127.0.0.1:<port>/<secret>/...` (`content.url(path)`; `src` may be
  a path of it), so a page's own URLs are relative ones, never from the
  root.
- **The loopback's threat model**: any process of the device can connect
  to a port on 127.0.0.1 (another app on a Mac, a local service, a script),
  and the bridge will carry privileged calls (the stores, the keychain).
  So such a process must neither read what the server serves nor post to
  the bridge, nor tie it up. `WebServer`:
  - binds 127.0.0.1 alone (never every address: nothing off the machine);
  - takes only requests whose path starts with `/<secret>/`, 256 random
    bits of the session's from the system's CSPRNG (`helder.pack.Entropy`:
    /dev/urandom), given to no one but the web view (in the URLs it loads).
    The origin is `http://127.0.0.1:<port>` with or without it, so the
    page's origin, its storage and its cross-origin isolation are as they
    were. The request line is read alone, its path compared with the secret
    in constant time (every byte, whatever differs), and without it the
    answer is a 403 before a header is read;
  - takes a Host of its own only (`127.0.0.1:<port>`: a name rebound to the
    loopback by DNS is refused);
  - takes the bridge (`/<secret>/__helder/post`, macOS's messages) as a POST
    whose `Origin` is the page's own origin only (no other page in the web
    view, which would not know the secret either, posts to it), with a
    `Content-Length` (no chunks);
  - is bounded: the request line within 5 s (a connection that says
    nothing goes), the whole request within 30 s, its line and headers
    within 16 KB (100 headers), a bridge message within 64 MB
    (`WebServer.MAX_*`, `TIMEOUT`), at most 32 connections served at once,
    the next ones waiting in the system's queue.

  Not covered: a process running as the same user that can read the app's
  memory or attach a debugger has the secret anyway (the system's own
  boundaries are those), and the page's own scripts are trusted with the
  bridge as before. Android's origin is intercepted in process
  (`shouldInterceptRequest`) and the custom scheme (`local = false`) is
  WKURLSchemeHandler's: neither has a port. Tests: the test lane's
  `WebServer.test.hx` (raw sockets: no secret, a wrong one, refused before
  the headers, a foreign Host, the bridge from another origin, its method,
  the limits, a timed out connection, the cap), and on CI's simulator and
  macOS runner `WebViewCheck` from a socket of the app's own and the
  scripts' curl from outside, while the page stays cross-origin isolated.
- **The bridge** (`WebBridge`): the page has `window.helder` before its own
  scripts (Apple: a WKUserScript at the document's start; Android: put in
  the HTML its content serves, and evaluated at each other page's start):
  `helder.post(x)` a string, a value as JSON or bytes (an ArrayBuffer or
  typed array, as base64) to `onMessage` (`WebViewEvent`: `text`,
  `isJson`/`json()`, `bytes`), over WKScriptMessageHandler or a
  `@JavascriptInterface` object (`org.hxmc.WebBridge`, on its JavaBridge
  thread); native to the page by evaluating its `helder.__receive`, and
  bytes fetched by the page from its own origin
  (`/__helder/bytes/<id>`: an ArrayBuffer, no base64) where it has one.
  What native code gives the page that a browser cannot (the stores' APIs
  without a CORS relay, the keychain, files, the share sheet) goes through it.
- **Its life**: `onNavigate`, `onUrlChange`, `onLoad`, `onTitle`,
  `onProgress`, `onLoadError`, `onConsole` (Android's console; Apple's
  console.* through the bridge), `onCrash` (the content process gone);
  `url`, `title`, `progress`, `loading`; `goBack`, `goForward`, `reload`,
  `stop`. The back gesture (iOS's edge swipe, Android's Back key) goes
  back in its history (`backGesture`); the keyboard and the page's safe
  area (`env(safe-area-inset-*)`) are the system's; pinch zoom off unless
  `zoom`; `transparent`; the inspector (`isInspectable`,
  `setWebContentsDebuggingEnabled`) in debug builds or with `inspectable`.
- **A still** (`snapshot`): WKWebView's takeSnapshot (a block made by
  hand: a global one, its invoke a callback), Android's View.draw into a
  bitmap; RGBA8, for helder to composite a frame of it.

Tests: CI's simulator and emulator (`tests/platform/webview-ios.sh`,
`webview-android.sh`: `tests/platform/WebViewCheck.hx` in a drawn window
and `WebShellCheck.hx` on the whole screen; a bundled page that reports
`crossOriginIsolated`, instantiates a wasm module streamed as
`application/wasm` and posts the result, native's string and bytes
answered by the page and checked, a snapshot, then examples/todo's web
build run in the same web view). Not yet: Windows' WebView2 and Linux's
WebKitGTK (nothing is drawn there), the web view in a browser (an
iframe), ArrayBuffers from the page without base64.

### Native or drawn, per widget

In a drawn window a widget can also be the platform's own control:
`host` on a node (`Auto`, `Native`,
`Drawn`; markup's `host="native"`) holds for its subtree, and where the
tree leaves it `Auto` the window's `Ui.policy` decides per kind of widget
(`"text-field"`, `"text-area"`, `"context-menu"` and `"menubar"`;
`Ui.defaultPolicy()`: on the desktop, Windows, macOS and Linux, text
fields and areas drawn, as Zed's GPUI draws its editor: helder's own
composes with popups, scrolling and clipping and keeps screenshots the
same, and the platform still gives input methods (TSF, NSTextInputClient,
XIM, text-input-v3), spellcheck (`helder.text.Spell`) and accessibility
(the access tree); in a browser and on phones the platform's editor; the
menus native everywhere). Native
needs the window's `Ui.platform` (`helder.ui.platform.PlatformViews`); without one, or for a
kind it lacks, the widget is drawn. `host="native"` on a field, or
`ui.policy["text-field"] = Native`, asks for the platform's editor on the
desktop too: the
platform's editor sits over the field's content box, borderless and
transparent in the field's font, colour and alignment, the theme drawing
the box, ring and placeholder's colour; its text, selection and focus
follow the node's both ways, the keys it leaves to the program (Tab,
Escape; Enter, Up and Down on one line) go to the window, and the field is
drawn again while a popup covers it or a scroller clips it. In the
browser the editors are the page's input and textarea over the canvas
(`WebViews`; `web-field.mjs` drives them in Chromium); on Windows EDIT
controls, children of the window, coloured through WM_CTLCOLOREDIT with the
background behind them (`WinViews`; `WinAccessTest`); on macOS
NSTextFields over the window's content view (a password's an
NSSecureTextField) in the field's font, colour and alignment, a text area an
NSTextView in a borderless NSScrollView (`MacViews`; `MacAccessTest`); on
iOS UITextFields and UITextViews over the window's view, so that UIKit's
own editing is the app's: marked text (Japanese, Chinese, Korean,
dictation), the selection's handles and loupe, autocorrection; their text,
selection and focus synced both ways, the node getting the text once
marked text is committed, Return on one line the program's Enter (`IosViews`;
`tests/platform/TextInputCheck.hx`). Linux (X11, no toolkit) and Android
draw them still (Android's input method through an InputConnection of
helder's own: Text input below). The platform's menus are there for a
program's own (`helder.ui.menu` is the model over them, Menus below): `PlatformViews.menu` shows a context menu (its items,
separators, checked and disabled ones, submenus and shortcuts' labels):
Windows' popup menu, macOS's NSMenu; `PlatformViews.menuBar` a menu bar,
the system's on macOS (its menus after the application's) and the
window's own on Windows (SetMenu: its items' commands the window's
WM_COMMAND).

## Accessibility

`helder.ui.access` builds the tree assistive technology sees (AccessKit's
model: roles, names, states, actions) from the nodes: each node's
`semantics` (in markup: `role`, `label`, `description`, `checked`,
`selected`, `expanded`, `disabled`, `value-now`, `value-min`,
`value-max`, `value-text`, `multiselectable`, `live`, `current`,
`invalid`, `required`, `modal`), text as labels,
focusable nodes as groups; the text fields declare theirs. An `id`
(`Semantics.identifier`) is what UI tests find a node by, and puts it in
the tree (a group when it has no role): iOS's and macOS's
accessibilityIdentifier (XCUITest's `app.descendants(matching: .any)["cart"]`;
on iOS an identified group is a container of the elements below it, with
its frame), Android's view id resource name (UiAutomator's `By.res`),
UI Automation's AutomationId, AT-SPI's accessible id, the browser
mirror's `data-testid` (Playwright's `getByTestId`). A node without one
is `helder-<n>`, stable while it lives. A `navigation`
role is a landmark (ARIA's navigation, AT-SPI's landmark, UI Automation's
navigation landmark type, macOS's AXLandmarkNavigation); `current` marks
the current one of a set (aria-current="page"; AT-SPI's current
attribute, UI Automation's AriaProperties; macOS has no property for it). A live region
(`live="polite"` or `"assertive"`) has its changes announced
(`AccessTree.announcements`: its new text): ARIA's aria-live, AT-SPI's
Announcement, UI Automation's LiveRegionChanged, macOS's announcement
request. `Ui.accessTree()` gives it, `AccessTree.changes`
the incremental update, `Ui.accessAction` does what a screen reader asks
(click, focus, increment, decrement, set a value: a text's, or a range's,
stepped there; expand, collapse, select an item, scroll into view, set a
text input's selection). The tree counts what assistive technology
announces as "2 of 3": an item's place in its set (a list's items, tabs,
radios, menu items, a tree's items of a level), a table's rows and
columns and each cell's row and column; a text input's node has its
caret, its selection and whether it is read only. In a browser the window
mirrors it as ARIA elements inside its canvas (the canvas's fallback
content: in the page's accessibility tree, not drawn; a set's place,
a table's rows and columns and a cell's, read-only as ARIA's attributes):
load `src/helder/ui/imports.mjs` with the others (a page without helder.ui
loads none of it; the ui-web lane reads the fixture's mirror through
Chromium's own tree, `tests/ui/web-access.mjs`). On macOS the window gives it to
NSAccessibility (`MacAccess`: an element per node, its role, label, value
and frame; a text input's characters, selection and lines; a table's
rows, columns and headers, a row's and an item's index; press,
increment and decrement come back as actions, as do a value, the focus,
expanded and selected set; the notifications of what changed), which
VoiceOver reads (the window lane on macOS: `MacAccessTest`,
`MacPatternsTest`, in process); on iOS to UIAccessibility (`IosAccess`:
the window's view a container of a UIAccessibilityElement per node
VoiceOver stops at, its label, value, hint, traits and frame; activate,
increment and decrement come back as actions; layout changes and
announcements posted; `tests/ui/IosAccessCheck.hx` on CI's simulator); on Android to an
AccessibilityNodeProvider on NativeActivity's content view
(`AndroidAccess`, its Java classes.dex's `org.hxmc.AccessProvider` and
`AccessDelegate`, natives: a virtual view per node, its class, text,
bounds, states, range, collection and item info and actions, the
accessibility focus its own, TalkBack's order the tree's; the content
changed, the focus and announcements sent; `tests/ui/AndroidAccessCheck.hx`
read by `uiautomator dump` on CI's emulator); on Windows to UI Automation (`WinAccess`: a COM
provider per node, made here: navigation, properties (an item's place in
its set, a heading's level, off screen), bounds, the Invoke, Toggle,
RangeValue, Value, ExpandCollapse, SelectionItem, Selection, ScrollItem,
Grid, GridItem, Table, TableItem and Text patterns, a text's ranges by
characters, words, lines and the whole (`TextUnits`); the focus,
structure, property, selection, text and live region events of what
changed), which Narrator reads (the window lane: in process,
`WinAccessTest`, `WinPatternsTest`; from another process through
IUIAutomation, `WinAccessProbe`, on the fixture and the screens Linux's
probe reads; under Wine, whose IUIAutomation has no patterns, the tree
and its properties); on
Linux to AT-SPI over D-Bus (`LinuxAccess`, through helder's own D-Bus
client, `helder.os.linux.DBus`: Accessible, Component, Action, Value,
Text by characters, words, sentences and lines with the caret and the
selection, EditableText, Selection, Table and TableCell; the events of
what changed since the last frame: children added and removed, names,
values, states, the text's edits and caret, a selection's change), which
Orca reads (the ui-draw lane reads the fixture, the todo and mail
examples and the guide's widgets through libatspi, the viewer lane the
viewer's main screen: `tests/ui/AtspiProbe.hx`). On macOS, Windows
and Linux the tree is built only once a client first asks for it, so a
program nobody reads pays nothing for it.

## Hosts, canvases and documents

A `Ui` is a tree's host: its size and scale (the display's pixels per UI
pixel), its text engine and fonts, the events it is given, the clock,
the focus, the accessibility tree (`ui.accessTree()`: roles, names, states,
a link's `href`, each node's box). A `UiWindow` feeds it a window's
events; without one (`new Ui(engine, width, height)`, `update`, `paint`) it
is a host of a fixed size and no events, first-class: headless tests,
thumbnails, documents.
`ui.paint(canvas)` draws through a `Canvas`: the GPU renderer's, or a
writer's. What a writer gets: rectangles with their borders and corners,
shadows and inset shadows (calls of their own, not pixels), opacity groups,
clips, transforms, images (`Image.source`: the file decoded, to embed as it
is; `Image.drawing`: the SVG an icon was rendered from, to draw as vectors),
vector paths (`canvas.path(path, fill, ?stroke)`: `Path`'s moves, lines,
curves, arcs, even-odd; a `Paint`, a colour or a CSS gradient; a `Stroke`'s
width, caps, joins, miter and dashes), and text as paragraphs whose
`runs(width, align)` give the glyphs as placed: the face's file, the size,
the glyph ids and each glyph's source text. `breakBefore`, `breakAfter`,
`breakInside` and `page` are kept for a paged layout; a window has none.

### On the CPU

`helder.ui.draw.soft.SoftCanvas` is the GPU renderer's Canvas with no GPU:
it draws into a helder.canvas `Bitmap` (RGBA8, premultiplied) what the
Renderer draws, placed by the same rules (its snapping to the pixel grid,
clips' radii, transforms' scale and turn, a glyph's pen and phase), each
quad shaded by UiShader's own functions (`UiShapes`: the rounded box, the
border's inner ellipse, dashes and dots, the Gaussian shadow) and blended
as a GPU blends into RGBA8; glyphs from the same `GlyphAtlas`, paths and
SVGs rasterized by helder.canvas (`Path.render`, as the Renderer's), images
read bilinearly, opacity groups into buffers of their own. Unturned
rectangles, borders and shadows are shaded four pixels at a time
(hxmc.simd), only near their edges: a run a rectangle covers whole is its
fill, an outer shadow under its box is skipped, a blur's terms that hold
along a row are kept. What draws with the GPU (a part's shader, a
`<Scene>`, a sprite box, a GPU texture) is a grey box (`GpuPlaceholder`).

Headless runs draw on it with `--soft` (`-D helder.soft`: no GPU code
linked, a static executable on Linux), `HELDER_SOFT=1`, or where no GPU
device can be made; a build without `helder.headless` links none of it.
Its frames are the GPU's within a level (Metal's and llvmpipe's, every
golden scene, below) and the same bytes on every machine given the same
fonts (`HELDER_FONT_DIRS`: those directories alone, e.g. DejaVu on a Mac),
so the image tests' goldens are its (`bun run test ui-soft`).

Against the GPU (tests/ui/SoftBench.hx: a frame painted and read back, the
least of 20; first frame in brackets; ms):

| scene | Metal (M4) | CPU (M4) | llvmpipe, Docker | CPU, Docker |
|---|---|---|---|---|
| sample 480x320 | 0.5 (6) | 2.0 (3.5) | 3.3 (357) | 6.2 (28) |
| todo 480x560 | 0.6 (5) | 0.8 (1.1) | 3.0 (21) | 2.0 (4.4) |
| controls 760x660 | 1.6 (6) | 3.7 (4.8) | 25.1 (147) | 9.5 (20) |
| controls 1520x1320 | 4.1 (9) | 14.0 (15.5) | 88.4 (227) | 32.6 (41) |
| 5,000 rows 800x600 | 1.0 (6) | 3.0 (4.2) | 10.1 (30) | 8.4 (13) |

(Docker: helder-llvmpipe-dejavu, linux-x86_64 emulated on the same M4;
llvmpipe on 10 threads, the CPU canvas on one.) It beats llvmpipe on
every scene but the shadow-heavy sample, and its first frame by 10 to 40
times (llvmpipe compiles its shaders). Not yet: bands in parallel (its
buffers are the collector's), glyphs and images in SIMD.

## Text input

Keys come as `KeyDown` and characters as `TextInput` (Shift, the
keyboard layout, dead keys and compose sequences applied: on X11 through
the input method, `XMODIFIERS`'s or Xlib's own). While a text field has
the focus the window takes text at its caret (`helder.os.Window.startTextInput`):
an input method's composition (Japanese, Chinese, Korean) shows in the
field, underlined, until committed. In the browser keys then go through a
transparent textarea at the caret, which input methods compose in
(`TextEditing` events), on macOS through a text view at the caret
(`NSTextInputClient`: input methods and dead keys); on Windows through
the Text Services Framework (`helder.os.win32.Tsf`: a text store whose
document is the field's text and selection, `Window.textContext`; the
composition drawn in the field, the candidate window placed below the
caret through `GetTextExt`; where TSF is not there, IMM32's own windows at
the caret); on Wayland through text-input-unstable-v3 (`WaylandTextInput`:
enabled while the field has the focus, its surrounding text, content type
and caret's rectangle sent, the preedit drawn in the field, commits typed,
`delete_surrounding_text` applied); X11's input method draws its
composition itself. An input
method's edit of the text around the caret (TSF's `SetText`, Wayland's
`delete_surrounding_text`, Android's `deleteSurroundingText`) comes as
`TextReplace` (`Node.replaceText`), its selection as `TextSelect`.

On phones and in a browser a field tells the soft keyboard what it takes
(`EditableText.keyboard`, `enterkey`, `autocapitalize`, `autocorrect`; a
`TextKind`, `Window.textKind`): on iOS its UITextField's traits
(UIKeyboardType, UIReturnKeyType, autocapitalisation, autocorrection,
secure entry, a textContentType for AutoFill: email, phone, URL, a password,
a new one), on Android its EditorInfo (inputType's class, variation and
flags, imeOptions' action), in a browser its input's `inputmode`,
`enterkeyhint`, `autocapitalize`, `autocorrect` and `spellcheck`; the
desktop has none of it but a password's. An email's, a URL's and a
password's are neither capitalised nor corrected unless asked. Enter (or
that key) fires `onSubmit`, then `next` moves the focus to the next field
and `done` lets go of it, the keyboard with it. Android's fields stay drawn:
the input method talks to an `org.hxmc.Editor` (classes.dex, only in a
program that takes text) whose InputConnection is helder's
(`helder.os.android.TextInput`): the field's text and selection mirrored
on the main thread, so the keyboard reads what is around the caret
(capitalisation, suggestions) and edits it; its composition shown in the
field, underlined (Gboard's, a CJK keyboard's).

The soft keyboard's height over the window is `Window.keyboard` (a
signal, points; `SafeArea.keyboard` the main window's in UI pixels, both
in TypeScript; `Ui.keyboard` each window's): iOS's keyboard frame
(UIKeyboardWillChangeFrame, with its animation's duration), Android's IME
insets (adjustResize; the visible frame below API 30), a browser's visual
viewport against the window, 0 on the desktop. While it is up the safe
area's bottom is at least its height, so a layout that keeps clear of the
safe area (`padding-bottom="env(safe-area-inset-bottom)"`) moves above it,
and the focused field is kept in its nearest scroller's view, 16 points
clear of the keyboard (`Ui.KEYBOARD_MARGIN`), scrolled with the keyboard's
animation where the system gives its duration.

## Performance

A frame does the work of what changed and what is seen. `Ui.update` lays
out nothing on a clean tree; after a change it lays out again the dirty
path (a node's measures are cached per constraints) and rounds only the
subtrees that moved. A changed node whose parent's measures of it come out
as they were (a checkbox toggled, a field typed into: its size its own) is
laid out again in place, its ancestors not (`Layout.inPlace`; UiTest checks
it against layouts from scratch of random trees changed at random). Paint and hit tests skip subtrees whose bounds
(their ink: the box, overflowing text, children unless clipped, widened
by shadows and the focus ring) miss the window or their scrollers. The
accessibility tree is built again only when something it reads changed.
Paint is split into layers (`helder.ui.draw.Layer`): the root, each
scroller's content (below its clip, above its scroll translation) and each
node whose transform or opacity changes in paints one after another (until
it has been still for 60). Each records into a display list of its own
(`DisplayList`: each Canvas call an opcode and its numbers in flat arrays,
what it takes by reference in a table of resources with their versions),
kept from frame to frame while nothing it paints changed. A change to a
node's style, text, image, layout or children, to motion's tracks, the
focus ring, the selection or the theme marks the layer it is painted in
(what children inherit, the layers inside it too) and stamps the node and
its ancestors: recorded again, a layer copies the entries of the nodes
whose subtree did not change (their calls, resources and cull tests, as
recorded under the same rect seen) and walks only the others, so a row
toggled among 5000 records that row; what reads more than its nodes as
it records (asks for frames, sticky, a pass, a GPU texture) is walked. A layer holding a node
of its own drawing (a subclass's `paintContent`, unless it overrides
`paintsLive`), anything that asks for frames as it paints, a leaving node
or an overscroll's stretch is recorded again each frame. A scroller's
content is recorded over what is seen and a viewport each way (a quarter
after a change), again once a scroll leaves that or a sticky node in it
moves. The layers are then walked onto the canvas, each where its scroller
and transform put it now, culled to what is seen: the calls painting
directly gives, in its order (UiTest checks it on random trees changed at
random over frames: scrollers and sticky rows, transforms and opacity
moving, motion's entering and leaving rows), and a frame that only scrolls
or moves a transform records nothing. Passes (`beforePass`) are entries of
the lists, run in their place. A window's renderer (`Renderer.tiles`: not
headless, X11's or a browser's) draws a layer that holds no other and
draws nothing anew from tiles of its own, textures of 512 device pixels
kept while it paints the same and moves by whole device pixels (snapped
while it moves by fractions of one, drawn again where it rests), not in
the paint that recorded it (what changed may change again). A scroller's
tiles are drawn over its opaque background (one without is replayed), so
that its content blends over what it does in place; under a rounded clip
the tiles fill all but the corners, the list replayed into each corner's
box; and UiShader measures each fragment from its pixel's centre (an
unturned quad's from its own centre's whole part and fraction), not an
interpolated position a rasterizer places a little apart in a target of
another size. So the tiles give the pixels replaying gives, at whole
pixels, on Metal and Mesa alike. A scroll draws no new tile once those
around the view are drawn. Screenshots, story renders and golden images
replay every layer (`LayerTest` checks the two pixel for pixel, on
rounded scrollers at scales 1 and 2). The renderer draws a quad as four
vertices and six indices, batched by texture.

A window keeps its frame (`Renderer.keep`) and draws only what changed:
the walk that marks finds the damage (at most 8 rectangles, merged where
they meet): where a layer recorded again differs from its last record,
each node compared with its old entry (only the boxes of the calls that
differ where only their numbers do: a caret moved damages the caret; else
its old and new bounds), a layer moved, scrolled, faded or come to rest
(its old and new place, within its clip), scrollbars that draw otherwise,
a GPU texture each frame, popups (the overlay's entries), all of it at a
scale or theme change or a match flying. Each rectangle is walked culled
to it and drawn straight into the frame kept (a texture of the window's
size, single-sampled: each quad is grown past its anti-aliased edge, so a
multisampled window's samples change none of its pixels), its background first, every unturned quad cut to it and a turned
one's fragments outside it left as they were, then the frame is copied
to the drawable (Metal's and a browser's are not kept), and the system
told what changed (EGL's swap with damage on Wayland and Android, DXGI's
Present1). Where 40% or more of it changed (a scroll of a scroller filling
the window), the frame is drawn whole straight to the drawable, as copying
it in and out would draw more. UiShader measures every fragment from its
pixel's centre, a turned quad's solved from its corners, so what is drawn
into the frame kept is what drawing whole gives, on GL too, which draws
textures the other way up (`DamageTest`: random trees changed at random
over 80 frames, pixel for pixel against drawing whole, at scales 1 and 2,
replayed and from tiles, on Metal and Mesa; `DamageTest --window` in a
multisampled window). Headless runs, screenshots,
golden images and X11 draw every frame whole; `HELDER_DAMAGE=full` draws
a window's so, `HELDER_DAMAGE=flash` shows each frame's rectangles.

On macOS, iOS, Windows, Linux (X11, Wayland) and Android a window has a compositor
(`helder.ui.draw.Compositor`), so that scrolling keeps the display's pace
while the program is busy. The main thread hands it each input event as
it reads it (helder.os's README, "Threads"), before the program. Its
mirror of the scrollers (`ScrollMirror`: each program frame's
`ScrollShot`) runs the program's own physics (`ScrollHost`: the wheel and
its latch, Trackpad's gestures, momentum and stretch, TouchScroll's drag
and fling, ScrollGlide's eased notches and keys, a thumb dragged, nested
scrollers chaining) on scrolls that are its own; on the render thread it
draws a frame each vsync the program misses (it did not take the
offsets within 0.6 of a period), from the program's last
(`CompositeFrame`: the tree walked whole once more, each quad tagged with
the scrollers it moves with, a tiled scroller's tiles kept as tiles over
what its layer was recorded over, cut to its clip where they fall),
drawn whole. Content past what was recorded shows the scroller's
background until the program records it. The program takes the offsets
at its next turn (`Ui.mirrored`: onScroll, scrollX and scrollY, its
frame drawn from them; a stretch held past the ends not clamped), and an
offset it set itself wins (setting scrollX or scrollY asks for a frame:
once the overlay bars had faded, nothing else did, and the mirror kept
the last offset). A gesture whose first step lands under a node
that may claim it (a pointer's, wheel or gesture handler, selectable
text, a drag's data; a key the focus, its handlers or the keymap take)
asks the program first (`Event.routed`: ASK; Ladybird's wheel listener
gate) and waits; let through, the compositor runs it from its start and
the rest never waits; kept, it is the program's. The program does with
an event all but the scroll the compositor took.

What moves on its own moves in the compositor's frames too, sampled at
the time each is drawn (`helder.ui.Mover`, taken with each program
frame): a node with a layer of its own, its transform and opacity under
a transition, a spring or a tween (the same closed forms the program
samples: the transition's run, each Track's segment, copied; a part whose
start is its next tick waits for it, as the program's does; one
retargeted hands over its new segment with the next frame). A transition
or a motion of transform or opacity gives its node a layer as it is
declared, and one declared in a frame's update (a rule's restyle: a
hover, a press) starts at that frame's time, as motion's tracks do, so
the frame declaring it hands it over running and the program may block
at once (tap, animate, heavy work: animated from the first vsync it
misses; `AsyncScrollTest`); sticky nodes,
placed by the compositor's offsets as Layout places them; overlay
scrollbars, drawn shown and faded as `Ui`'s are. Its quads are turned
and faded in the target's pixels (a clip inside it bounded as a turned
one is); a fading layer of more than one thing is drawn into a group of
the compositor's frame's own (a render target, at 1) and that faded
whole, as the program's group is. Not the compositor's: a layout moving
(edges' tracks), colours, a layer that holds a scroller (drawn as it
was). The native views
over a scroller (a macOS or iOS field, a Windows EDIT, a web view) are moved on the main thread
as each of its frames is drawn (`OsThread.post`), hidden once they leave
their scroller's view. On iOS the scrollers are UIScrollViews (IosScroll):
their offsets come to the compositor on the main thread as UIKit moves
them (`Compositor.nativeScrolled`), so their deceleration and bounce are
drawn at the display's pace while the program is busy; the program has
them at its next turn.

On macOS and iOS the frames go to the system's compositor
(`helder.ui.draw.CaLayers`): each frame, the program's and the
compositor's, is composed from the compositor's state and split in paint
order into Core Animation layers: the window's CAMetalLayer at the
bottom; a CAMetalLayer of their own for each top-level scroller's content
(over what it recorded, under a CALayer clipping to the scroller's clip on
whole pixels) and each top-level layer that moves on its own (nothing
nested moving, its clips its own); over each, a CAMetalLayer of what
overlaps it, the rest staying below. A rounded scroller's clip has a mask:
its coverage drawn once by UiShader itself (a white quad under that clip,
only its corners and a pixel between them, stretched by `contentsCenter`),
so its corners are the reference's (within a level where translucent) and
scrolling it is a layer move, as a square one's. A layer is drawn again
only where its quads, size or what they sample changed
(`CompositeFrame.fresh`: tiles rastered, groups, images, a scene); a
scroll moves its content's layer and a mover's transform and opacity are
its layer's, so neither draws (a scrollbar's thumb, a layer of its size,
does). On Apple a changed layer is drawn again whole: Core Animation keeps
no drawable's contents, and copying the last one forward to draw only what
changed measured slower on an M-series GPU (0.09–0.13 ms a frame against
0.04–0.09 for a header's label over a list).

A node can own a system layer between what is drawn (`LayerSlot`, Node's
`systemLayer`: a CALayer, helder.media's `<Video>`'s
AVSampleBufferDisplayLayer): it goes in the tree at
its paint position, placed at its box, clipped by its scrollers (rounded
too), under what is drawn over it, moved with its scroller and its
transform. Native views (the text fields, the web view) are slots too:
AppKit and UIKit keep a view's layer in its superview's tree, so each is
a view in a host view (its clip, and the mask's copy) and what is drawn
over it goes in a view over it (`CaViews`), which takes a press only
where something is drawn over a host. They are never hidden for a popup
or a scroller cutting them, so their focus and editing stay the
system's.

A frame is one transaction where something of the tree changes: its
drawables presented with it (`presentsWithTransaction`), the layers and
views placed, on the main thread where views are in it. A frame that only
draws (a scene that changes every frame) presents its drawables at once,
as the textured compositor does, and a frame split into the window's layer
alone (a full-window scene and its overlay) is drawn by the program onto
it, as before: Little Skies' title on the iPhone 16 Pro simulator, 5.56 ms
a frame before system layers, 18.0 with them in their first version (a
commit a display period, a transaction waited for), 5.6 now. Core
Animation is never handed a NaN or an infinity (a layout gone wrong):
such a layer keeps its last place for the frame. Pixels: the textured
compositor's where the layers are opaque; a translucent layer (an edge, a
fade) is blended by the window server in the display's colours, a few
levels off UiShader's sRGB blending (12 at most on a P3 panel, in
`SystemLayersWindow`). Memory: the layers' drawables beside the tiles
(7.4 MB for `SystemLayersWindow`'s scene at scale 2, 11.1 before a
scroller's layer was bounded to what its clip shows, beside 6.3 MB of
tiles). A steady scroll at scale 2 on an M-series Mac: 0.05–0.07 ms of
GPU a frame, a rounded list as a square one (drawn, before: 0.8–1.1).
`HELDER_SYSTEM_LAYERS=0` keeps one CAMetalLayer and the textured
compositor (`=flat`: the same split, all on the window's layer, native
views over it as before); a frame read back (a window's capture) is drawn
as before, the layers hidden for it. `SystemLayersWindow` (ui-draw,
macOS) runs one scene on a clock of its own three ways (Core Animation's
layers, `flat`, `0`) and compares window captures
(`CGWindowListCreateImage`, a process's own windows): a rounded list
scrolled by the program with a native field, a web view and a system
layer in it and a popup over them, a rounded scroller, a layer moving
and a card of overlapping children fading on their own, then the
compositor's frames while the program is blocked; then a layout of NaN;
`--time s [anim] [round]` times a scroll or an animation. The split
itself is shared (`LayerSplit`); keyed by node, a moving layer is made
once, not again with each program frame (on Apple a layer moving had
gone unpaced: 5,600 frames in 4 s at 110% of a core on an M-series Mac,
now the display's 119 a second at 21–28%).

On Android (API 33 on) the frames go to SurfaceFlinger
(`helder.ui.draw.ScLayers`): the same split as SurfaceControls, under one
of Java's put under the window (a view's root surface has no handle for
the NDK's `ASurfaceControl_createFromWindow`), each with buffers of its
own (AHardwareBuffers drawn by GLES through an EGLImage, fenced, two a
layer, three for a small one), a scroll and a mover's translation, scale
and opacity set in the frame's one transaction, which waits until the
last one was presented (`setOnComplete`: the display's pace, the release
fences); none where nothing changed. A frame split into the window's
layer alone is drawn onto the window as before, the stack hidden once
that frame is queued; a new window's first frame is drawn onto it too
(Android routes no input to a window whose surface never had a buffer).
SurfaceControl has no rounded clip, turn or fraction of a pixel: rounded
scrollers and movers that turn, skew or flip stay drawn, and layers sit
on whole pixels. A node's `LayerSlot` is a SurfaceControl (`surface()`:
one under ours), placed, cropped and stacked in the transaction, square
under a rounded clip. On the API 33 emulator, with the program blocked:
a fling 18 frames in 300 ms, an animation 17, a swipe read on the UI
thread 98 in 3 s, all at 16–17 ms, the list's layer moved and not drawn
(1 quad a frame: the thumb); the textured compositor there keeps 4 in
300 ms and 27 in 3 s, 62–85 ms apart. An animation timed: 102 frames in
3.9 s, 9.7 ms of CPU a frame, against 28 frames at 18 ms. Screencaps
against `HELDER_SYSTEM_LAYERS=0`: within 6 levels (glyphs' edges in the
list's layer) but for a moving box's anti-aliased edge (0.03% of the
pixels, as the compositor composes a mover against the program's own
paint); the box, at 0.6 over the header, is that blend within a level in
every mode. A layer drawn again is drawn only where it changed (`LayerPlane`:
its quads against those it drew last, the same from the start and from
the end, the rest's old and new bounds, and those sampling what was drawn
into since; past 40% of it, drawn whole): its buffers are its own, so each
is brought up to date from what it missed since it was drawn (a history of
the last draws: buffer age), those rectangles cleared without blending,
then each quad that meets one, cut to it by UiShader's region, over the
rest as it was (`DamageTest`: two stacks, a header's label, a badge, its
colour, the list scrolled and rows toggled over 60 frames, the window's
layer drawn in part against drawn whole, 0 pixels differ at scales 1 and
2); the transaction tells SurfaceFlinger which (`setDamageRegion`, API
29); a buffer not let go in time leaves its layer drawn the next frame,
what it missed kept. A header's
label changed each frame over a full-window list (`AndroidLayersTest`,
API 33 emulator): 1,260–44,800 pixels a frame drawn against 2,243,000
drawn whole, 120 changes in 5.5–6.5 s against 9.5, 22–28 ms of CPU a
change against 52. A scroller's content layer covers what its clip shows at an
offset in its range, not all its quads do (its tiles' 512-pixel columns:
a 1080×2400 list's layer was 1600 wide): the test's layers take 77 MB,
103 before; recording half a view each way rather than one made it 64 MB,
but its stills then differed from the textured compositor's at glyphs'
edges past the tolerance (a frame replayed where the textured one drew
its tiles), so the recorded range is as before; a cap on phones (the
content's layer tiled, or its range by the device's memory) is to come. Below 33, or where a call or a buffer fails, the textured
compositor; and while running, where the system misbehaves (no
transaction reported presented for 1.5 s, a layer kept 1.5 s from a
buffer: one not let go of within a display period is drawn the next
frame, the frame's moves not held back by it), the layers turn off for good and the program
draws its next frame onto the window (`LayerSplit.fell`).
`tests/ui/android-layers.sh` (CI's android job) runs `AndroidLayersTest`
three ways: system layers, the textured compositor, and the layers
stalled (`HELDER_SYSTEM_LAYERS=stall`: no presentation reported), which
must fall back while running (pixel for pixel the textured compositor's
after).

On Windows the frames go to DirectComposition
(`helder.ui.draw.DcLayers`): the window's swap chain is made for
composition, a visual of a target on the window (under its child
windows: an EDIT stays over what is drawn and moves as before; the web
view too), the same split as visuals over it, each layer's pixels an
`IDCompositionSurface` drawn by Direct3D 11 into BeginDraw's texture at
its offset (never cleared whole: it may be an atlas). A scroll is a
visual's offset, on whole pixels, a mover's 2D transform its visual's
(turns too) and its opacity an effect group's. A rounded scroller stays
drawn: a rectangle clip's corners are not UiShader's coverage (54 corner
pixels over 8 levels, up to 119, on CI's runner). A surface keeps what it showed and its
update lands with the commit, so a layer drawn again is drawn in one
rectangle around what changed since its last draw (`LayerPlane.cut`). A
frame that changes anything is one commit, each frame on its own
composition: one that comes before the composition showing the last
waits until then, once (the frame statistics' next estimate, a
high-resolution timer: `Sleep`'s tick is 15.6 ms), as a swap chain's
present would; nothing else paces them, the program's frames presenting
nothing (700 frames a second on CI's runner without it, 32 ms apart
when every frame waited for DWM's next composition after it); one that
changes nothing commits nothing; one split into the window's layer alone
is drawn onto the swap chain and presented as before, the stack taken out
of the tree once that frame is queued. A node's `LayerSlot` is a visual
(`DcLayers.visualFor`), cut to its box in its clip. No commit processed
for 1.5 s, a call that fails or a lost device turn the layers off for
good: every visual but the window's own out of the tree in one commit,
the next frame the window's own; `HELDER_SYSTEM_LAYERS=0`, or no
DirectComposition, keeps a swap chain of the window's own.
`WinLayersWindow` (the window lane, CI's desktop-windows job) runs a list
with a system layer, a rounded scroller and a moving box three ways
(layers, `0`, `stall`).
Wayland's subsurfaces come later; X11 and headless stay on the textured
compositor.

`AsyncScrollTest` scripts the wheel, eased notches, a trackpad's gesture
and momentum past an end, a finger's fling, the keys, a thumb and a
nested chain through both paths with an injected clock, the program held
for vsyncs: the same offsets at every vsync, the same end, and the
compositor's frames pixel for pixel the program's at those offsets; then
transitions of transform and opacity, a spring retargeted mid-flight, a
tween and sticky headers in a scrolled list, the same values at every
vsync, and frames of a layer turning and fading, a card with overlapping
children fading while the program is held, sticky headers and
overlay bars shown and fading against the program's (a turned layer's
within a level: its corners rounded to 32-bit floats once more).
`AsyncScrollWindow` blocks the program 300 ms in a window while input
comes, `--anim` while a layer animates (`--anim --pace s [--work ms]`:
its frames' pacing; Windows: SendInput's wheel; the window lane there).
On the iPhone simulator `IosTest scroll` (tests/gfx/ios.sh) has UIKit
animate a UIScrollView while the program blocks 500 ms: the compositor's
frames at its offsets meanwhile, the program at them after.
`HELDER_ASYNC_SCROLL=0` turns it off; headless runs,
screenshots and golden images are the program's alone.

A window's GPU work runs on the render thread (helder.gfx's README,
"Render thread"; macOS, iOS, Windows, Linux and Android): the frame is
recorded here and handed over at its passes' and its end, and the loop
waits for it to be presented before it takes the next events (`settle`),
so a frame shows the input it was drawn for, as without the thread, while
the driver's encoding overlaps the rest of the turn: the frame's
accessibility tree, the text input, other windows' frames, the app's own
work. `RenderThreadTest` (ui-draw) checks its frames against the
synchronous path's, pixel for pixel, in a window; `--time n [--work ms]`
times it. A list of 400 rows scrolled a pixel a frame with 4 ms of the
program's work after each: 13.1 ms a frame synchronously, 10.8 on the
thread (Mesa's llvmpipe in Docker, not paced by a display); at a 60 Hz
display's pace (Metal) 16.7 either way, the start of a frame to its
present the same. `HELDER_RENDER_THREAD=0` turns it off.

Memory per node is kept small: leaves share one empty children array; event
handlers and the rarely set style properties (grid, transforms, shadows,
offsets...) are allocated when first set; paragraphs share their font sets.

`StressTest [rows]` (`bun run test ui-draw` runs it) prints the times of the
first layout, of the frames after a change, a scroll and an append, and of
a steady frame; `RT_STATS=1` adds the collector's figures and the RSS, and
a build with `-D hxmc.census` run with `RT_CENSUS=1` lists the live heap by
type. At 5000 rows (35000 nodes, an M-series Mac) a steady frame paints in
about 0.02 ms and allocates about 300 bytes (the scrollbars'; 14 KB before
layers, the text in view painted again), a frame of a scroll going on paints
in 0.01 (0.1 before) and draws 26 quads (509), and a change to one row is
laid out in about 0.1 and painted in 0.13, drawing that row's 24,500 of
the frame's 480,000 pixels (its GPU part 0.8 ms, 1.5 before, readPixels
included); a caret moved draws about 190; the tiles take about 14 MB.
The first layout of 1000 rows (8000 nodes) takes about 30 ms, 60% of it
laying out text and nearly half of that the collector copying the
paragraphs' glyphs, which all survive: a compact glyph store in
`helder.text` (arrays, not an object per glyph) is what would cut it next.

## Tests

`bun run test ui` (Eval: layout against Chromium, events, markup rendered into nodes, the guide),
`bun run test ui-draw` (natively, golden images), `bun run test ui-soft` (the
image tests on the CPU, no GPU linked: the goldens' reference, BLESS=1),
`bun run test ui-web`
(Chromium, WebGPU and WebGL2, real input events), from tests/ui (`bun run test help`: every lane).
The `*.test.hx` beside the sources run natively and as wasm32-wasi (the
test lane): pointers, gestures, and the safe area (`SafeArea.test.hx`:
`env()` resolved, markup's attributes following the insets, laid out
again).
