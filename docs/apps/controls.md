# Controls

Buttons, checkboxes and switches that look the same on every platform, behave as the platforms' own (keys, focus, screen readers), and take a look of your own: change a colour, add a variant, restyle one part, or replace how a control draws while it keeps its behaviour.

<Example id="signup"/>

Each control is drawn by the nearest look; `Look.base` is helder's, and `look.with` makes yours from it. A variant your look adds is checked where you write it.

```tsx
import {Button, Checkbox, Switch, Themed, Look} from 'helder/ui'

const look = Look.base.with({
  accent: 'violet',
  button: t => ({ variants: { variant: { soft: { root: {background: t.accentSoft, color: t.accentInk} } } } })
})

const controls = <Themed look={look}>
  <look.Button variant='soft' onPress={invite}>Invite</look.Button>
  <Checkbox label='Remember me' checked={remember} onChange={remember}/>
  <Switch label='Dark mode' checked={dark} onChange={dark}/>
</Themed>
```

```haxe
static final look = Look.base.with({
  accent: Violet,
  button: t -> {variants: {variant: {soft: {root: {background: t.accentSoft, color: t.accentInk}}}}}
});

<Standard.Themed look={look}>
  <look.Button variant='soft' onPress={invite}>Invite</look.Button>
  <Standard.Checkbox label='Remember me' checked={remember} onChange={v -> remember(v)}/>
  <Standard.Switch label='Dark mode' checked={dark} onChange={v -> dark(v)}/>
</Standard.Themed>
```

<Image src="controls.webp" alt="Buttons in five variants and three sizes, disabled, an icon button, checkboxes off, on and mixed, a switch" caption="docs/examples/controls: Look.base's variants and sizes."/>

## Keys

| Control | Keys | To a screen reader |
| --- | --- | --- |
| Button | Enter, Space, a click | a button |
| Checkbox | Space, a click | a checkbox, checked or mixed |
| Switch | Space, Enter, a click | a switch, on or off |
| Slider | the arrows (Shift: ten steps), Home, End, a press or a drag | a slider and its value |
| Segmented | the arrows, a click | a radio group |

## What else

- **Options:** a button's `variant` (`primary`, `secondary`, `outline`, `ghost`, `danger`), `size` (`sm`, `md`, `lg`), `icon`, `disabled`, `onPress`; a checkbox's and a switch's `label`, `checked`, `onChange`, `disabled`, and a checkbox's `indeterminate`.
- **More controls:** a `Slider` (a number as a field filled up to it), a `Segmented` choice (one of a few options) and a `Tooltip` (what a control does and its shortcut, once the pointer rests on it).
- **Your own parts:** a look's `parts` style an app's own slots from the same tokens (`parts: {panel: t => ({background: t.surface})}`), and `Look.ref.fg3` is a token's colour inline.
- **Looks:** colours in light and dark, a neutral accent and eight others, a compact density, a type scale and motion, all tokens; restyle one part (`switch: t => ({knob: {radius: 3}})`) or any state of it.
- **Your own rendering:** `render: {switch: Lamp}` draws every switch as your component, inside other widgets too; it keeps the switch's keys and accessibility.
- **Interactions:** [popups, keyboard shortcuts and drag and drop](interactions.md).
- **Motion:** hovers, presses and toggles ease, the focus ring fades in for the keyboard only, and reduced motion keeps the end states.
- **Cost:** a screen of controls draws in one pass, as plain views do.

<Reference to="ui"/>
