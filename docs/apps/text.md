# Text and input

helder shapes and draws text itself: fonts are parsed, shaped and rasterized in helder's own code, so text looks the same on every platform and every script is handled the same way. Keyboards, input methods and screen readers still go through the system, so typing feels native.

<Example id="shaping"/>

Text styles inherit, so set them once on a parent. A `<field>` is a text field; its value is a signal you own.

```tsx
const draft = signal("");

<view font-family="DejaVu Sans" font-size={14} color="#18181b" row-gap={8}>
  <text font-weight={700}>New task</text>
  <field value={draft} placeholder="What needs to be done?"
    padding="8 12" radius={6} onInput={e => draft(e.text)}
    onKeyDown={e => { if (e.key === Key.ENTER) add(); }}/>
</view>
```

```haxe
var draft = signal("");

<view font-family="DejaVu Sans" font-size={14} color="#18181b" row-gap={8}>
  <text font-weight={700}>New task</text>
  <field value={draft} placeholder="What needs to be done?"
    padding="8 12" radius={6} onInput={e -> draft(e.text)}
    onKeyDown={e -> if (e.key == Key.ENTER) add()}/>
</view>
```

## What else

- **Fonts:** OpenType and TrueType, variable fonts, colour emoji, and the system's fonts with fallback for every script.
- **Shaping:** kerning, ligatures, Arabic joining, right-to-left and mixed-direction text.
- **Typography:** line height, letter spacing, alignment and justification, ellipsis and line clamps, decorations and text shadows, OpenType features.
- **Input:** selection, the clipboard, undo, and input methods for Japanese, Chinese and Korean on every desktop and the web.
- **Keymaps and actions:** named commands bound to keys in a JSON keymap, shown in menus, dispatched up from the focused view.
- **Accessibility:** roles and labels reach VoiceOver, TalkBack, Narrator and Orca.
- **A code editor:** highlighting, multiple cursors, find and replace ([Code editor](https://helder.build/examples/#code-editor)).

<Reference to="text,ui"/>
