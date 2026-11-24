# Standard controls and their look

Design, November 2026. The proposal of the research branch with its
decisions made; PR 1 (the foundation, Button, Checkbox and Switch) is
implemented (src/helder/ui/README.md, "Controls", is the reference).

Scope: the standard controls of helder.ui and how an app defines what
they look like. Decided before: one look on every platform (no
Material/Cupertino split), drawn by helder, with the platform's own
editor and menus where `Ui.policy` asks for them.

## 1. Where helder is today

helder.ui already has a good engine. `Rules` matches a `StyleSheet`'s rules
by `slot`, `variant` and `size`, under states (`hover`, `active`,
`focus-visible`, `data-*`, `dark`, breakpoints, `starting`) and other
nodes' states (`group:`, `peer:`, `has:`). It merges the matches in order,
resolves colour tokens against the sheet's light and dark maps, and runs
again only when a state changes. `States.of(node)` gives those states as
signals, which is how React Aria's render props work. The access tree
already maps roles and states onto UI Automation, NSAccessibility,
UIAccessibility, AT-SPI, Android and ARIA.

What hurts is `helder.ui.widgets.Theme` and the API on top of the engine:

1. **It is one app's look, copied.** `widgets/Theme.hx` is a near copy of
   `apps/studio/src/studio/Theme.hx`, which keeps its own copy. The two
   will drift apart.
2. **Every name is a string.** Slots (`"nav-item"`), tokens
   (`c("accent-ink")`) and states (`data-on="true"`) are all strings. A
   typo styles nothing and raises no error. TypeScript sees even less:
   `StyleSheet.light?: unknown`, `Theme.c(): number`, and `StyleProps`
   typed as `direction?: number` and `padding?: unknown`. A TS app can
   hardly write a sheet, so tables only names slots and calls `c()`.
3. **The theme styles parts, but nothing makes them.** There is no
   Button, Checkbox or Switch. Each call site assembles `view:button`,
   `slot`, `role`, `focusable`, `label` and `data-on` by hand. There are
   114 hand-built buttons in studio and tables, and each one's keyboard
   and accessibility handling is its own.
4. **State leaks out of the sheet.** Icons are coloured at the call site
   by state, as in `color={on() ? c("accent-ink") : c("fg3")}`. Studio
   and tables do this 168 times. `c()` follows a global
   `Theme.appearance`, not the window it is drawn in.
5. **Only colours and radii are tokens.** Sizes, fonts and weights are
   `inline var` constants, compiled into their callers. An app can't
   change the control height or the font without forking the sheet.
6. **Overriding means winning the cascade.** An app appends rules after
   Theme's, using the internal slot and state spellings. That is MUI's
   problem ([styleOverrides fighting specificity][mui-pit]). There is no
   unit to replace, such as one variant or one part. The engine supports
   variants, but the default look doesn't use them: `"primary"` is a
   separate slot rather than a variant of `"button"`.
7. **Unrelated concerns share one list.** App layout parts (`panel`,
   `section`, `nav-item`) sit next to other widgets' tokens (`grid-*`,
   `code-*`). `GridTheme` resolves the same tokens a second way.

So the fix belongs in the layer above Rules, not in Rules itself. Keep
the engine and replace the content and the API.

## 2. What the survey says

| Source | What helder should take | What to avoid |
| --- | --- | --- |
| **Vercel UI SDK** ([vercel-labs/ui], [ui-sdk.dev]) | Behaviour defined once, split into `state`, `api` and `slots`. Each part carries `data-slot` and state attributes. Change events carry reasons. Tokens are few and named `--ui-*`. | It is DOM-bound (§6) |
| **React Aria** ([styling][ra-styling], [interactions][ra-quality]) | Typed state per control (`isPressed`, `isFocusVisible`…). Press is cleared when the pointer drags off, hover never sticks on touch, focus-visible shows only after keyboard input. The [Spectrum 2 `style` macro][s2] is a typed object of conditions, compiled at build time, with values limited to tokens. | Prop bags spread onto elements |
| **Radix** ([parts][radix-switch], [Themes colour][radix-color]) | Anatomy: `Switch.Root` and `Switch.Thumb`, with `data-state`. A 12-step colour scale where each step has a fixed meaning, so a new brand only changes step 9. | `asChild` prop merging |
| **Base UI** ([styling][base-styling]) | `className`, `style` and `render` each accept a function of state. Version 1.0 has been stable since December 2025. | |
| **Zag / Ark** ([machines][zag-machines]) | One state machine per control, framework-agnostic, with `connect()` returning the api. Each control declares its anatomy. A switch takes 173 + 133 lines; a select takes 818 + 503. MIT. | DOM effects inside the machines |
| **shadcn/ui** ([docs][shadcn], [button.tsx][shadcn-btn]) | Tokens in pairs (`--primary` and `--primary-foreground`) and one `--radius`. Variants and sizes through cva. The app owns the code. | Forks that never receive fixes |
| **cva / tailwind-variants / vanilla-extract / Panda / Chakra 3** ([tv slots][tv], [Panda slot recipes][panda-slot], [Chakra recipes][chakra-recipes]) | `base`, `variants`, `defaultVariants` and `compoundVariants`, with slots per recipe. Chakra overrides by merging a partial recipe into the default. Panda types the slots; vanilla-extract produces everything at build time. | Codegen steps (`chakra typegen`, Panda `staticCss`) |
| **MUI** ([theme components][mui-theme]) | Defaults per component in the theme. | String slot names and overrides that fight specificity; new variants need module augmentation |
| **Flutter** ([WidgetStateProperty][flutter-wsp], [theme design doc][flutter-doc], [decoupling][flutter-decouple]) | A style resolved from a set of states, with a clear lookup order (widget, then component theme, then scheme). | A 64-field `ThemeData` whose defaults depend on each other, and variants with no theme of their own (`FilledButton.tonal`). Flutter has since moved Material and Cupertino out of the core. |
| **Compose** ([custom design systems][compose]) | Tokens as typed immutable objects in CompositionLocals, `XDefaults.colors()` for partial overrides, and slot content. | Wrapping every component just to restyle it |
| **SwiftUI** ([ButtonStyle][swiftui-bs], [ToggleStyle][swiftui-ts]) | `makeBody(configuration)`: the style owns all the visuals and the control keeps behaviour and accessibility. It is set on a container and inherited below. | Built-in styles are all or nothing |
| **Iced 0.13+** ([#2312][iced-2312], [Catalog][iced-catalog]) | `style(theme, status) -> Style` as one plain function. Presets are plain functions. It replaced per-state StyleSheet traits, which the PR called "painful and confusing". | |
| **Zed GPUI ui** ([button_like.rs][zed-btn], [theme schema][zed-schema]) | A small, closed `ButtonStyle` enum, flat semantic colour keys a JSON theme fills, and Tailwind-like layout methods. | Focus styles left unused (`#[allow(unused)]`) |
| **egui** ([Widgets][egui]) | One serialisable record of visuals per state, which makes a live style editor easy. | The same five buckets for every widget |
| **Slint** ([styles][slint-styles], [blog][slint-blog]) | Moving to a single default style: "maintaining five parallel implementations of every widget has a cost". This confirms helder's one-look decision. | |
| **DTCG 2025.10** ([format][dtcg]) | `$value`, `$type` and `{alias}`, groups and composite types; reference, system and component layers ([M3][m3-tokens]). | |

All of these libraries end up with the same three pieces: a behaviour
layer that exposes typed state, a named anatomy of parts, and a variant
function that maps state and props to a style per part. The open
question is whether the style is data (recipes) or code (a function of
state). For helder, data wins as the default, for the reasons in §3.

## 3. The models compared

The columns are what matters to helder:
- **Nodes:** fits drawn nodes
- **Signals:** fits signals
- **Parity:** Haxe and TS parity
- **Typing:** static typing
- **No CSS:** needs no runtime CSS engine
- **Reload:** hot reload
- **Alloc:** no per-frame allocation

| Model | Nodes | Signals | Parity | Typing | No CSS | Reload | Alloc | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **Tokens only** (Radix Themes props, egui, Zed JSON) | ✓ | ✓ | ✓ plain records | ✓ | ✓ | ✓ | ✓ | Needed, not enough: it can't give the knob another shape or add a variant |
| **Variants and recipes** (cva, Panda, Chakra, vanilla-extract) | ✓ compile to Rules | ✓ states are the conditions | ✓ plain object literals | ✓ parts and states typed | ✓ Rules is the resolver | ✓ data, recompiled | ✓ compiled once per look | **The core** |
| **Style as a function of state** (SwiftUI, Iced, Flutter, React Aria render props) | ✓ | ✓ already `states={s -> …}` | ✓ closures in both | ✓ | ✓ | ~ code reload | ✗ a fresh StyleProps on each change, per node | Escape hatch per instance, and inside custom renders |
| **Slot/part styling** (Radix, Ark `data-part`, UI SDK `data-slot`, MUI) | ✓ slots exist | ✓ | ✓ | ✗ today (strings); ✓ if the parts are a typed record per control | ✓ | ✓ | ✓ | Yes, as keys inside each recipe, never typed by hand |
| **Copy-in components** (shadcn) | ✓ | ✓ | ✗ two sources, plus a CLI | ✓ | ✓ | ✓ | ✓ | Not the main path. Maybe later as `helder add switch` to eject one control |
| **Full render replacement** (SwiftUI `makeBody`, Base UI `render`, Compose) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | Yes, as the top escape, on the behaviour layer |

The deciding constraint is in helder.view itself: **a spread
(`{...props}`) falls back to looking names up at run time and links every
attribute parser.** React Aria, Zag and the UI SDK all hand out prop bags
to spread onto elements, and that pattern costs helder size and
speed. Behaviour should attach to a node through a typed `ref` instead.

## 4. Five layers

```
behaviour   helder.ui.controls: Press, Toggle (then Choice, Listbox, Disclosure, Modal, Range)
            state as signals, keys, focus, the access tree. No look.
parts       each control's anatomy, bound by ref: Switch = root, track, knob, label
            the binder sets the slot ("switch-knob"), the root its role and data-* attributes
styling     a recipe per control: (tokens) -> {part: style, state: {...}, variants}
            plain Haxe or TS data, compiled once per look into a StyleSheet that Rules runs
defaults    Look.base: helder's tokens and one recipe per control (section 5)
ownership   look.with({...}): one token, one variant, one part, or a whole rendering
```

Behaviour attaches by a typed `ref`, never a prop bag (section 3). A
recipe is a function of the tokens' references (colours as token
references, so light and dark switch without running it again; other
values plain, so a new radius reruns it). Its keys are parts; a style's
keys may be states, nested (`checked: {hover: {...}}`), one vocabulary
for every control, each word the Rules condition its behaviour keeps
true:

| Recipe key | Rules condition | | Recipe key | Rules condition |
| --- | --- | --- | --- | --- |
| `hover` | `hover` | | `checked` / `mixed` | `data-state=checked` / `=mixed` |
| `pressed` | `active` | | `selected` / `open` | `data-selected` / `data-state=open` |
| `focus` | `focus-visible` | | `invalid` / `readonly` | `data-invalid` / `data-readonly` |
| `disabled` | `data-disabled` | | `dark` | `dark` |

A part's states are its root's: the root is a group of its slot (the
sheet's `markers`), a part's rule `group/switch:hover`, and a variant's
`group/switch:variant=x`; parts carry only their slot. `with` merges by
part and state, property by property, the patch's keys winning (Chakra's
partial recipes, no specificity to fight). Compiling memoises per look;
nothing is made a frame, and `Rules.restyle` allocates nothing (a slot's
merges kept by an integer hash of the rules that hold).

```tsx
import { Button, Switch, Themed, Look, Toggle, tone, type SwitchProps } from "helder/ui";

const look = Look.base.with({
  tokens: { accent: tone("#e11d48", "#fb7185"), radius: 6 },
  button: t => ({ variants: { variant: { soft: { root: { background: t.accentSoft, color: t.accentInk } } } } }),
  switch: () => ({ knob: { radius: 3 } }),
  render: { switch: Lamp }  // every Switch, those inside other widgets too
});

function Lamp(props: SwitchProps<any>) {
  const sw = Toggle.of(props, "switch");  // behaviour, keys and access kept
  return <view ref={n => sw.root(n)} direction="row" column-gap={8}>
    <image ref={sw.part("icon")} src={() => (sw.checked() ? lit : unlit)} width={24} height={24}/>
    <text>{props.label}</text>
  </view>;
}

<Themed look={look}>
  <look.Button variant="soft">Invite</look.Button>
  <Switch label="Porch" checked={porch} onChange={porch}/>
</Themed>
```

Haxe writes the same (`Look.base.with({...})`, `"switch": t -> ...`,
`Look.tone`), checked where it is written.

## 5. The default look

`Look.base` follows [CUI][cui] (MIT, a C99 immediate-mode drawn UI: its
`docs/design.md`, `docs/theming.md` and its controls). Taken from it:
semantic OKLCH colour tokens in light and dark, pure grays, a neutral
accent and a table of others (its values, under its MIT licence);
soft rectangles on a radius ladder (controls, panels, surfaces) and a
density token; a hairline of shadow under solid controls; an opaque blue
focus ring for the keyboard alone, fading in; a press that darkens and
barely gives; spring motion, and disabled controls faded, not
recoloured. Not taken: its names, structure and code. helder's tokens
and recipes are its own, tuned by eye in the gallery's snapshots
(tests/ui/controls).

| Tokens | comfortable (the default) | compact |
| --- | --- | --- |
| Neutrals, OKLCH (light / dark) | canvas 1 / 0.18, surface 1 / 0.21, raised 1 / 0.24, well 0.975 / 0.26; fill 0.945 / 0.26 (hover, press a step each); a switch's rail 0.895 / 0.33; line 0.915 / 0.29, edge 0.84 / 0.29, edgeStrong 0.665 / 0.515; washes fg at 5% and 7.5%; chroma 0 | the same |
| Text | fg 0.15 / 0.96, fg2 0.46 / 0.77, fg3 0.565 / 0.64 | the same |
| Accent | graphite, the default: 0.23 / 0.93 (its hover 0.3 / 0.85, text on it white / 0.19); blue, violet, teal, green, amber, orange, red, pink after CUI's table; the focus ring one blue, 0.58 / 0.73 at chroma 0.15 | the same |
| Danger | oklch(0.55 0.19 27) / oklch(0.7 0.16 24), white / dark text | the same |
| Type | Inter 14 (12, 16, 20), Inter Display, Geist Mono; medium 500 | 13 (11, 14, 17) |
| Radii | 10, 14, 18 (a button 8, 10, 12 by size) | 8, 12, 16 (6, 8, 10) |
| Control heights, padding | 30, 36, 44; 12, 16, 20 | 26, 30, 36; 10, 12, 16 |
| Checkbox, switch | box 18 (radius 5, edge 1.5); track 36 by 20, thumb 16 | 16; 30 by 16, 12 |
| Motion (s) | hover 0.12, toggle 0.18, disclosure 0.26, floating 0.22, dialog 0.3, exit 0.15; press scale 0.98 | the same |
| Disabled | opacity 0.42 | the same |

`font` is helder's Inter (src/helder/text/fonts: a web page ships it,
and Look.base adds it where the system has none). Inter Display and
Geist Mono are named, not bundled: an app adds them. The theme change
blended in OKLab that CUI does is not taken yet.

## 6. Typed variants

A look declares its variants by its recipes (`variants: {variant:
{soft: ...}}`), and its type carries them: `Look<V>`, V naming each
control's axis's values (`{button_variant: {primary, secondary, outline,
ghost, danger}, ...}`). In Haxe, `with` is a macro that reads the patch's
recipe literals and returns the look typed with their variants added,
and a variant prop's `@:from` macro checks a literal against the
expected type's V (an unknown one: `"soft" is no button variant of this
look`, at the attribute). In TypeScript, `with`'s type infers them from
the patch (`Look<V & PatchVariants<P>>`). Either way the call site has
no annotation: `look.Button` takes the look's variants, `Button`
`Look.base`'s. Each control has two axes, `variant` and `size`, as
`Rules` matches them.

## 7. Animated states, and a part's own shader

After Makepad: each state of a recipe is an amount that eases from 0 to
1 over the look's time for it, and what it changes blends. The blend
rides on what helder already has: compile gives each part a transition
of the look's timings (a hover's for a button, a toggle's for a
checkbox's and a switch's parts, a toggle's travel springing), and the
renderer's quad draws the eased colours, opacity, transforms, shadows and
rings: no new shader, still one pipeline. A switch's knob follows
`checked` over the toggle's time. Under reduced motion travel jumps and
colours fade. The amounts themselves (`Eased`: hover, pressed, checked,
focus, open) are the machines', for what draws itself.

That is the escape hatch: a recipe may give a part `draw:
PartShader.of(shader)`, a helder.gfx shader given the part's size, the
look's accent, text and surface colours and the eased states, drawn into
a texture of its own before the window's pass and shown under the part's
children. Each such part costs a pass and splits the window's single
draw (a texture bound between quads), so `Look.base` uses none.
Measured (ControlsBench, the ui-draw lane): 500 buttons, 1 pass, 1
pipeline, 1 draw, as 500 plain views; one shaded button, 2, 2, 2.

## 8. Behaviour, accessibility and forms

**The reference to follow is the [WAI-ARIA APG patterns][apg].** Map each
one onto helder's semantics and `Ui.accessAction`, not onto ARIA
attributes:

| Control | APG pattern | Keys (in the behaviour) | helder semantics |
| --- | --- | --- | --- |
| Button, toggle button (`selected`) | button | Enter and Space activate | `button`, pressed via `checked` when it toggles |
| Checkbox | checkbox | Space toggles; mixed is allowed | `checkbox`, checked / mixed |
| Switch | switch | Space (and Enter) toggles; never mixed | `switch`, checked |
| Radio group, segmented | radio group | Tab goes to the checked one; arrows move and check, wrapping | `radiogroup` / `radio`, place in its set |
| Tabs | tabs | arrows move, automatic or manual activation, Home and End | `tablist`, `tab` selected, `tabpanel` |
| Select | select-only combobox and listbox | Down, Enter or Space opens; typeahead; Escape keeps the value | `combobox` expanded, `listbox`, `option` selected |
| Menu, menu button | menu button, menubar | Enter, Space or Down opens; arrows; Escape returns focus | `menu`, `menuitem`; native menus where the policy says |
| Dialog, alert dialog | dialog (modal) | focus moves in and is trapped, Escape closes, focus returns | `dialog`, **modal** |
| Progress, meter | (ARIA role only) | none | `progressbar` / `meter`, value-now/min/max |

Interaction details come from React Aria's
[interaction notes][ra-quality]: a press is cancelled when the pointer
leaves, hover doesn't apply to touch, and focus-visible follows only
keyboard input (helder's `ui.focusVisible` does this already). Each
machine keeps them in one place, so every control inherits them.

**The access tree:** `mixed` was there; `modal`, `invalid` and
`required` are added in PR 1 (UI Automation, NSAccessibility, AT-SPI,
Android, ARIA). Modal still needs focus trapping, restoring focus
afterwards, and an inert outside, built on `Popups`/`ui.overlay` (PR 5).

**Behaviour stays out of styling.** A machine never sets a style
property. It sets semantics and `data-*` attributes and exposes signals.
A recipe only reads them. Tests can then check behaviour and the access
tree headlessly, with no look installed.

**Forms.** The values live in signals. A form is a record of fields, and
a field can wrap an existing signal of the app's (`field(user.email)`),
so the form never becomes a second store.

```ts
const signup = form({
  email: field('', [required(), email()]),
  name: field('', [required(), unique(name => api.free(name))]),  // async: an async memo
  agree: field(false, [checked('Please accept the terms')])
})

<Field field={signup.email} label="Email"/>
<Checkbox field={signup.agree} label="I accept the terms"/>
<Button variant="primary" pending={signup.pending} onPress={() => signup.submit(v => api.signup(v))}>
  Sign up
</Button>
```

- **Timing:** "reward early, punish late." A field shows its error
  after its first blur or after a submit, then validates on every
  change. `validate: 'change' | 'blur' | 'submit'` overrides that per
  field.
- **Async validators** are async memos, so `isPending` drives a spinner
  and a stale answer is dropped.
- **Submit** validates every field and focuses the first invalid one
  (as the UI SDK does). It sets `pending` and awaits the handler, a
  helder.async `Awaitable` or a Promise in TS. Errors the handler
  returns per field (`{email: 'Taken'}`) are shown on those fields;
  a form-level error goes in a polite live region.
- **Each field gives its control** a label, a description (the hint or
  the error), `invalid` and `required`, so the access tree reads them.

## 9. Existing Theme, Controls and TextField

**Replace them, don't migrate them.** helder is an early preview, so
there is no API to keep. PR 1 keeps `widgets/Theme.hx`, marked
superseded, until the apps move (PR 9).

- **`widgets/Theme.hx`:** its tokens become `Look.base`'s tokens. Its
  control rules become recipes (`button` with tones in place of the
  separate `primary` slot, plus `field`, `slider`, `tip`, `menu-item`,
  `kbd` and `badge`). `panel`, `section` and `nav-item` move out to the
  apps' own `parts`. `grid-*` and `code-*` become recipes of DataGrid
  and the code view, derived from the same tokens. That leaves
  `GridTheme` with a single path.
- **`Controls.hx`:** `Slider` moves onto `Range`, `Segmented` onto
  `Choice` (radio-group semantics, as now), and `Tip` becomes `Tooltip`.
  The old names go.
- **`TextField`:** the node class stays as it is: it is the editor, and
  it is native where the policy says. A new `Field` control wraps it
  with `label`, `input`, `hint` and `error` parts and binds to forms.
- **Studio:** delete its `Theme.hx` sheet and use
  `Look.base.with({tokens, parts})` with studio's density. About 64
  hand-built buttons and 99 `c()` reads become controls or
  `currentColor`.
- **Tables:** it is TS only, so the TS gaps (typed StyleProps, tokens)
  get fixed in helder first. Then its 50 `view:button`s, `seg` tabs and
  `field` boxes become `Button`, `Tabs` and `Field`, and its 69 `c()`
  reads mostly disappear, because icons follow their part's
  `currentColor`.
- **Foundry and examples:** Foundry imports `Slider`, `Segmented` and
  `Tip` and moves to the new names. Signup's hand-made Checkbox and
  Switch become the controls, which makes a good before-and-after test.

## 10. Porting the Vercel UI SDK, or Zag

**What the "UI SDK" is.** It is most likely **UI SDK from Vercel Labs**
([vercel-labs/ui], [ui-sdk.dev]): "a library of behaviors for agents to
build the next generation of user interfaces." It is unstyled, has its
own kernel, and depends on nothing: not Radix, not React Aria. It
includes an "agent bridge" that lets coding agents inspect and drive
component state.
- **Packages:** `@ui-sdk/core` at `0.1.0-beta.13`, with React, Vue,
  Svelte, Solid and Web Components adapters.
- **Licence:** Apache-2.0.
- **Size:** 51 components; the core is about 117k lines of TS in 392
  files. I checked these against a clone at `855bc7f`, 2026-11-20.
- **Its model:** `definePrimitive({options, state, sync, api, slots,
  agent})`. Every slot gets `data-slot` and state attributes. There is
  an optional 3.5k-line `web.css` themed by `--ui-*` tokens, and change
  events carry a reason.

**Not verified:**
- the launch date, reported only by news sites as a public beta around
  12–13 November 2026 ([InfoQ][infoq], [MarkTechPost][mtp])
- a vercel.com blog or changelog post, which I didn't find
- whether this is the SDK the user meant (I'd put it at about 90%)
- what the agent bridge can actually do

**Is it portable?** Not as a package. In 192 of its 392 core files, the
code touches `HTMLElement`, `document` or listeners. Its forms rest on
hidden `<input>`s and `ElementInternals`, and its positioning, layers,
live regions and CSS are all web-only. helder would end up rewriting the
DOM half against its own nodes and keeping a fork of the rest.

**What is worth taking, by reading and rewriting in Haxe** (Apache-2.0
allows it; add attribution where code is translated closely):
1. The shape: `state`, `api` and `slots` split, plus change reasons and
   controllers. This proposal's behaviour and part binders already
   follow it.
2. Keyboard tables and edge cases: the listbox engine, typeahead,
   selection model, roving focus and focus recovery.
3. The DOM-free models, later: calendar, date and number input, colour
   and spring motion.
4. Its tests, as specifications.

**Zag** (MIT): the statecharts are the clearest spec for each control,
but their effects touch the DOM. Port them by hand, one control at a
time. Estimated Haxe size: about 150 lines each for Toggle and Press,
about 400 for Choice and Tabs, about 250 for Dialog, and 800 to 1,000
each for Listbox/Select and Menu. That makes roughly 4,000 lines for the
set, plus the recipes. Don't add a statechart runtime: a machine is a
small class of signals and methods, which suits helder better than an
interpreter.

## 11. The set and the plan

A lean set, not CUI's 175 or so: Button, IconButton, Checkbox, Switch,
PathBar, Radios, Segmented, Slider, Field (wrapping TextField), Select and
Combobox, Tabs, Menu, Popover and Tooltip, Dialog, Sheet, Toast,
Progress, Spinner, Badge, Card, Alert. DataGrid stays as it is for now.

Each step is one PR, with headless behaviour and access-tree tests, the
gallery's snapshots, and both languages.

1. **Foundation, Button, Checkbox and Switch** (this PR): typed
   StyleProps for TypeScript (`style.d.ts`, parsed once); no allocation
   in `Rules.restyle`; token references in inline markup; `modal`,
   `invalid` and `required` in the access tree; `Press` and `Toggle`;
   recipes, looks, `Look.base`, `look.with`, typed variants, animated
   states, the `draw` escape; the gallery (light, dark, both densities,
   every state) and ControlsBench; signup on the controls.
2. **IconButton, Badge, Card, Alert**: the simple ones, on Press and the
   recipe syntax.
3. **Choice: Radios, Segmented (migrated), Tabs**: roving focus.
4. **Field, Slider (migrated), Progress, Spinner**: `Range`; `invalid`
   and `required` driven by Field.
5. **Popover and Tooltip (Tip migrated), Dialog, Sheet**: Modal, focus
   trapping and restoring; floating layers' shadows and motion.
6. **Menu, Select and Combobox**: Listbox, typeahead; drawn menus share
   `helder.ui.menu`'s model with the native ones.
7. **Toast**: a polite live region and a stack.
8. **Forms**: `form`, `field`, validators, async validation and submit
   (section 8).
9. **Tables, then studio**: their sheets become looks with `parts`
   (studio's from `density: Compact`); `widgets/Theme.hx`, `Controls.hx`
   and `GridTheme`'s second path go. Then "Standard controls and forms"
   moves to the roadmap's "Lately".

## 12. Decisions, and what the build changed

Decided: `Look.base` after CUI's principles with a density token
(comfortable by default, compact for studio); variants typed at compile
time in both languages; a look may replace a control's rendering
app-wide; animated states; a shader per part as an escape hatch only;
the lean set above.

What PR 1 changed from the proposal:
- **`<Themed look={look}>`** installs a look (its sheet and context), not
  a `look` prop on `<Surface>`: a window would otherwise link the
  controls whether or not it uses them.
- **TypeScript imports from `helder/ui`**, not `helder/ui/controls`; the
  components are `Standard`'s statics (`Button`, `Checkbox`, `Switch`,
  `Themed`), as the widgets are `Controls`'.
- **`look.Button`** carries a look's own variants (the typed
  alternative to open strings with a debug warning); `Button` takes
  `Look.base`'s. A look's components are values (TSX takes a member read
  as a component only when it is a value).
- **A tone is a structure** (`Look.tone(light, dark)`), not a class, and
  TypeScript's `with` takes a typed patch: in a TypeScript build a value
  read from `Dynamic` as a class, a field read by a computed name, or a
  JavaScript function called through `Dynamic` pulls in the whole
  dynamic runtime, and with it EGL, which a static musl executable
  cannot link. The `parts` of a look are Haxe's for now for the same
  reason.
- **`PartShader` lives in `helder.ui.draw`**, a function of the shader
  (`PartShader.of`): a program without one links no GPU code, a
  TypeScript one either.
- **Parts follow their root through `group:`** rather than mirrored
  attributes, and **animated states blend through transitions** rather
  than a per-frame blend: both reuse what Rules and Style already do.

## Sources

[vercel-labs/ui]: https://github.com/vercel-labs/ui
[ui-sdk.dev]: https://ui-sdk.dev
[infoq]: https://infoq.com/news/2026/11/vercel-ui-sdk
[mtp]: https://www.marktechpost.com/2026/11/13/vercel-ui-sdk-agent-ui-behaviors/
[ra-styling]: https://react-aria.adobe.com/styling
[ra-quality]: https://react-aria.adobe.com/quality#interactions
[s2]: https://react-spectrum.adobe.com/styling
[radix-switch]: https://www.radix-ui.com/primitives/docs/components/switch
[radix-color]: https://www.radix-ui.com/themes/docs/theme/color
[base-styling]: https://base-ui.com/react/handbook/styling
[zag-machines]: https://zagjs.com/guides/building-machines
[shadcn]: https://ui.shadcn.com/docs
[shadcn-btn]: https://github.com/shadcn-ui/ui/blob/main/apps/v4/registry/new-york-v4/ui/button.tsx
[tv]: https://www.tailwind-variants.org/docs/slots
[panda-slot]: https://panda-css.com/docs/concepts/slot-recipes
[chakra-recipes]: https://chakra-ui.com/docs/theming/customization/recipes
[mui-theme]: https://mui.com/material-ui/customization/theme-components/
[mui-pit]: https://www.dmcinfo.com/blog/17372/3-common-pitfalls-of-theme-customization-with-material-ui/
[flutter-wsp]: https://api.flutter.dev/flutter/widgets/WidgetStateProperty-class.html
[flutter-doc]: https://docs.google.com/document/d/1kzIOQN4QYfVsc5lMZgy_A-FWGXBAJBMySGqZqsJytcE/mobilebasic
[flutter-decouple]: https://flutter.dev/blog/decoupling-material-cupertino
[compose]: https://developer.android.com/develop/ui/compose/designsystems/custom
[swiftui-bs]: https://developer.apple.com/documentation/swiftui/buttonstyle
[swiftui-ts]: https://developer.apple.com/documentation/swiftui/togglestyle
[iced-2312]: https://github.com/iced-rs/iced/pull/2312
[iced-catalog]: https://docs.rs/iced/latest/iced/widget/button/trait.Catalog.html
[zed-btn]: https://github.com/zed-industries/zed/blob/main/crates/ui/src/components/button/button_like.rs
[zed-schema]: https://zed.dev/schema/themes/v0.2.0.json
[egui]: https://docs.rs/egui/latest/egui/style/struct.Widgets.html
[slint-styles]: https://docs.slint.dev/latest/docs/slint/reference/std-widgets/style/
[slint-blog]: https://slint.dev/blog/default-native-style-change
[dtcg]: https://www.designtokens.org/tr/2025.10/format/
[m3-tokens]: https://m3.material.io/foundations/design-tokens
[apg]: https://www.w3.org/WAI/ARIA/apg/patterns/
[cui]: https://github.com/yappologistic/CUI

Unverified beyond the notes in §7:
- the SwiftUI API details (Apple's pages need JavaScript; they come
  from memory)
- the M3 and Spectrum token-layer pages (not fetched)
- Flutter's `material_ui` 1.0 version and date (from search snippets)
- whether inline styles resolve token references for every property
  (§4)
