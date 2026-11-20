# Standard controls and their look

Design proposal, November 2026. Research only: nothing here is implemented.

Scope: button, checkbox, switch, radio, select, tabs, dialog, menu,
progress and forms for helder.ui. These are already decided: one look on
every platform (no Material/Cupertino split), drawn by helder, with the
platform's own editor and menus where `Ui.policy` asks for them. The open
question is **how an app defines what the controls look like**.

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

## 4. Recommendation: five layers

```
behaviour   helder.ui.controls: Press, Toggle, Choice, Listbox, Disclosure, Modal, Range
            state as signals, keys, focus, the access tree. No look.
parts       each control's anatomy, a typed record: Switch = root, track, knob, label
            the part binder sets the slot ("switch-knob") and the state attributes
styling     a recipe per control: (tokens) -> {part: style, state: {…}, variants}
            plain Haxe or TS data, compiled once into a StyleSheet that Rules runs
defaults    Look.base: helder's tokens and one recipe per control
ownership   look.with({...}): one token, one variant, one part, or a whole render
```

**Tokens** are a typed record. A colour is a `Tone`, which holds a light
and a dark value (or one value for both). Everything else is a plain
value: fonts, sizes, radii, the control height, density. The token set is
semantic and small, shadcn's pairs plus studio's greys: `canvas bg well
hover active line edge fg fg2 fg3 accent accentFg accentInk accentSoft
focus danger dangerFg knob scrim`, and `font mono size small radius
radiusM control row pad`.

**A recipe** is a function of the tokens, called once when the look is
compiled. It receives colour references (`var(--accent)`, so light and
dark switch without running it again) and plain values for everything
else (so changing `radius` reruns the recipes). It returns, for each
part, a style whose keys may include states. Combined states nest:
`checked: {hover: {…}}`. There is one shared state vocabulary, each word
mapped to the Rules condition the behaviour keeps true:

| Recipe key | Rules condition | | Recipe key | Rules condition |
| --- | --- | --- | --- | --- |
| `hover` | `hover` | | `checked` / `mixed` | `data-state=checked` / `=mixed` |
| `pressed` | `active` | | `selected` / `open` | `data-selected` / `data-state=open` |
| `focus` | `focus-visible` | | `invalid` / `readonly` | `data-invalid` / `data-readonly` |
| `disabled` | `data-disabled` | | `dark`, `rtl`, `sm`…`2xl` | as they are |

`variants` holds two axes, matching the node's own `variant` and `size`:
`tone` (`primary secondary ghost danger`…) and `size` (`sm md lg`).
Defaults come from `defaults`. Compound variants can come later.

**Compilation.** `Look.sheet(look)` runs each recipe and emits `Rule`s:
the slot is `control-part` (the root is just `control`), the conditions
come from the table above, and `variant` and `size` come from the axes.
It also emits the light and dark token maps. The result is memoised per
look. `<Surface look={…}>`, or `look` on any node, installs it as the
`theme` and provides it as a context, which `render` overrides use.
Without a look, the controls fall back to `Look.base` through
`Rules.addBase`, so they look right with no setup. Hot reload produces a
new look value and calls `restyleTree`. There is nothing to compile
beyond that and nothing new per frame.

**Behaviour** is written once, in Haxe. helder.typescript generates the
TS declarations, so parity comes for free. Each behaviour returns typed
signals and part binders:

```haxe
final sw = Toggle.of(props, "switch"); // sw.checked(), sw.pressed(), sw.focusVisible(), sw.toggle()
<view ref={sw.root}>…<view ref={sw.part("knob")}/>…</view>
```

`root` sets the role, label and `checked`/`mixed` semantics, focus,
`onActivate`, keys, and the `data-*` attributes. `part(name)` sets the
slot and the same attributes. All of it is compiled; nothing is spread.

### Call sites

**1. Button and Switch with the defaults**

```tsx
import {signal} from 'helder/view'
import {UiWindow, Surface} from 'helder/ui'
import {Button, Switch} from 'helder/ui/controls'

const dark = signal(false)

UiWindow.run(
  <Surface title="Settings">
    <Switch label="Dark mode" checked={dark} onChange={dark}/>
    <Button tone="primary" onPress={save}>Save</Button>
  </Surface>
)
```

```haxe
UiWindow.run(<Surface title="Settings">
	<Switch label="Dark mode" checked={dark} onChange={dark}/>
	<Button tone={Primary} onPress={save}>Save</Button>
</Surface>);
```

**2. Brand tokens**

```ts
import {Look, tone} from 'helder/ui/controls'

export const look = Look.base.with({
  tokens: {accent: tone('#e11d48', '#fb7185'), font: 'Inter', radius: 8}
})
// <Surface look={look}>
```

```haxe
public static final look = Look.base.with({
	tokens: {accent: Tone.of("#e11d48", "#fb7185"), font: "Inter", radius: 8}
});
```

**3. A new variant**

```ts
const look = Look.base.with({
  button: t => ({
    variants: {tone: {soft: {
      root: {background: t.accentSoft, color: t.accentInk, hover: {background: t.hover}}
    }}}
  })
})
// <Button tone="soft">Invite</Button>
```

```haxe
final look = Look.base.with({
	button: t -> {
		variants: {tone: ["soft" => {
			root: {background: t.accentSoft, color: t.accentInk, hover: {background: t.hover}}
		}]}
	}
});
```

**4. Restyling one part: a square knob**

```ts
const look = Look.base.with({
  switch: t => ({
    knob: {radius: 3, shadow: '0 1 2 rgba(0,0,0,0.3)', checked: {background: t.accentFg}},
    track: {radius: 4}
  })
})
```

```haxe
final look = Look.base.with({
	"switch": t -> {
		knob: {radius: 3, shadow: "0 1 2 rgba(0,0,0,0.3)", checked: {background: t.accentFg}},
		track: {radius: 4}
	}
});
```

`with` merges by part and state. The base recipe runs first and the
patch's keys win, property by property. This works like Chakra's partial
recipes, with no specificity to fight.

**5. Replacing the rendering, keeping behaviour and accessibility**

```tsx
import {Toggle, type SwitchProps} from 'helder/ui/controls'

function Lamp(props: SwitchProps): View {
  const sw = Toggle.of(props, 'switch')
  return <view ref={sw.root} direction="row" align-items="center" column-gap={8}>
    <image ref={sw.part('icon')} src={() => (sw.checked() ? lit : unlit)} width={24} height={24}/>
    <text>{props.label}</text>
  </view>
}

// for one place: <Lamp label="Porch" checked={porch} onChange={porch}/>
// for every Switch, those inside other widgets too:
const look = Look.base.with({render: {switch: Lamp}})
```

```haxe
function Lamp(props:SwitchProps):View {
	final sw = Toggle.of(props, "switch");
	return <view ref={sw.root} direction="row" align-items="center" column-gap={8}>
		<image ref={sw.part("icon")} src={() -> sw.checked() ? lit : unlit} width={24} height={24}/>
		<text>{props.label}</text>
	</view>;
}
```

`Lamp` is still a switch to Narrator, VoiceOver, Orca and TalkBack, and
Space still toggles it. A recipe can still style its `switch-icon` part.

### Types, briefly

```ts
type State = 'hover' | 'pressed' | 'focus' | 'disabled' | 'checked' | 'mixed'
  | 'selected' | 'open' | 'invalid' | 'readonly' | 'dark' | 'rtl' | Breakpoint
type PartStyle = StyleProps & {[S in State]?: PartStyle}
type Recipe<Part extends string> = {[P in Part]?: PartStyle} & {
  variants?: {tone?: Record<string, {[P in Part]?: PartStyle}>, size?: Record<string, {[P in Part]?: PartStyle}>}
  defaults?: {tone?: string, size?: string}
}
type SwitchRecipe = (t: Refs) => Recipe<'root' | 'track' | 'knob' | 'label'>
```

In Haxe, `PartStyle` is `{> StyleProps, ?hover:PartStyle, …}` and each
control has a typedef with its parts. Variant names are open:
`enum abstract ButtonTone(String) from String` in Haxe, and in TS
`'primary' | 'secondary' | 'ghost' | 'danger' | (string & {})`. Autocomplete
offers the built-in ones and apps can add more. A tone missing from the
active look is a warning in debug builds. App-specific parts (`panel`,
`nav-item`) use the same recipe syntax under `parts: {…}`, so studio and
tables keep one mechanism.

**What the foundation needs first:**
- **Typed StyleProps in TS:** `index.d.ts` must type `StyleProps` with
  literal unions and the markup's CSS strings (`direction?: 'row' | …`,
  `padding?: number | string`). They are parsed once, when the look
  compiles.
- **No allocation in `Rules.restyle`:** it builds a `StringBuf` key on
  every state change (each hover). Replace it with an integer key.
- **Typed tokens in inline markup:** `color={Look.ref.fg3}` should
  resolve against the nearest sheet, so `Theme.c()` and its global
  `appearance` can go. Today only rules resolve tokens (unverified for
  every property).

## 5. Behaviour, accessibility and forms

**The reference to follow is the [WAI-ARIA APG patterns][apg].** Map each
one onto helder's semantics and `Ui.accessAction`, not onto ARIA
attributes:

| Control | APG pattern | Keys (in the behaviour) | helder semantics |
| --- | --- | --- | --- |
| Button, toggle button | button | Enter and Space activate | `button`, `checked` when it toggles |
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

**Gaps to fill in the access tree:** `modal`, `invalid`, `required` and
checkbox `mixed`. AccessKit has all of them, but helder's semantics list
doesn't. Modal also needs focus trapping, restoring focus afterwards, and
an inert outside, built on `Popups`/`ui.overlay`.

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
<Button tone="primary" pending={signup.pending} onPress={() => signup.submit(v => api.signup(v))}>
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

## 6. Existing Theme, Controls and TextField

**Replace them, don't migrate them.** helder is an early preview, so
there is no API to keep.

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

## 7. Porting the Vercel UI SDK, or Zag

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

## 8. Plan

Each step is one small PR, with headless behaviour tests, access-tree
tests and a story per control.

1. **Foundation, Button, Checkbox and Switch:**
   - `helder.ui.controls` with `Tokens`, `Tone`, `Look`
     (`with`, `sheet`, `base`, `render`) and the recipe types.
   - The `look` attribute and `Surface` prop, and the base fallback.
   - `Press` and `Toggle` behaviours, and the access tree's `mixed`.
   - The Button, Checkbox and Switch components and recipes.
   - Typed StyleProps and tokens in `index.d.ts`, and the integer key in
     `Rules.restyle`.
   - `examples/controls` in both TSX and Haxe, and Signup moved onto it.
2. **Choice:** Radio group, Segmented (replacing `Controls.Segmented`)
   and Tabs, with roving focus.
3. **Field, Slider, Progress, Meter and Spinner:** `Field` gets
   `invalid`/`required` in the access tree; `Slider` moves onto `Range`.
4. **Forms:** `form`, `field`, validators, async validation and submit.
5. **Dialog, Alert dialog, Popover and Tooltip:** modal in the access
   tree, focus trapping and restoring; `Tip` is replaced.
6. **Menu, Menu button and Select:** the listbox engine and typeahead;
   drawn menus share `helder.ui.menu`'s model with the native ones.
7. **Migrate tables, then studio:** delete `widgets/Theme.hx`,
   `Controls.hx` and the app sheets; GridTheme and the code view read
   the look.
8. **Optional:** import DTCG `.tokens.json` into `Tokens` at build time
   (helder.asset), for designers' tools.

## 9. Decisions for you

1. **What is `Look.base`?** Either studio's dense, dark-first language
   (12-point type, 24-point rows), or a roomier neutral base that
   studio derives from. I suggest studio's language with a `density`
   token, roomier by default.
2. **Are variant names open or closed?** Open strings with a debug
   warning, as recommended above, or closed unions that an app declares
   through a typed wrapper of each control.
3. **Can a look replace a control's rendering for the whole app?** With
   `render: {switch: Lamp}`, it would also reach the switches inside
   other widgets. The alternative is to replace it only where the app
   uses its own component. I suggest allowing it.

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

Unverified beyond the notes in §7:
- the SwiftUI API details (Apple's pages need JavaScript; they come
  from memory)
- the M3 and Spectrum token-layer pages (not fetched)
- Flutter's `material_ui` 1.0 version and date (from search snippets)
- whether inline styles resolve token references for every property
  (§4)
