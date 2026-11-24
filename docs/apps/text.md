# Text and input

helder shapes and draws text itself: fonts are parsed, shaped and rasterized in helder's own code, so text looks the same on every platform and every script is handled the same way. Keyboards, input methods and screen readers still go through the system, so typing feels native.

<Example id="shaping"/>

Text styles inherit, so set them once on a parent. A `<field>` is a text field; its value is a signal you own.

```tsx
const draft = signal("");

<view font-size={14} color="#18181b" row-gap={8}>
  <text font-weight={700}>New task</text>
  <field value={draft} placeholder="What needs to be done?"
    padding="8 12" radius={6} onInput={e => draft(e.text)}
    onKeyDown={e => { if (e.key === Key.ENTER) add(); }}/>
</view>
```

```haxe
var draft = signal("");

<view font-size={14} color="#18181b" row-gap={8}>
  <text font-weight={700}>New task</text>
  <field value={draft} placeholder="What needs to be done?"
    padding="8 12" radius={6} onInput={e -> draft(e.text)}
    onKeyDown={e -> if (e.key == Key.ENTER) add()}/>
</view>
```

On a phone a field tells the keyboard what it takes, and the layout keeps clear of the keyboard: while it is up the safe area's bottom is its height, so a screen padded with `env(safe-area-inset-bottom)` moves above it, and the focused field scrolls into view.

```tsx
<view padding-bottom="env(safe-area-inset-bottom)">
  <field keyboard="email" enterkey="next" placeholder="Email"/>
  <field keyboard="number" enterkey="done" placeholder="Age" onSubmit={e => save(e.text)}/>
</view>
```

`keyboard` is `text`, `email`, `number`, `decimal`, `phone`, `url` or `search`; `enterkey` is `default`, `done`, `next`, `go`, `search` or `send` (next moves to the next field, done lets the keyboard go); `autocapitalize` and `autocorrect` say the rest. On iOS fields are UIKit's own, so marked text, the loupe and autocorrection are the system's; on Android helder draws them and talks to the keyboard itself. `Window.keyboard` is the keyboard's height, a signal.

## What else

- **Fonts:** OpenType and TrueType, variable fonts, colour emoji, and the system's fonts with fallback for every script. In the browser a page ships helder's Inter, its `sans-serif`.
- **Shaping:** kerning, ligatures, Arabic joining, right-to-left and mixed-direction text.
- **Typography:** line height, letter spacing, alignment and justification, ellipsis and line clamps, decorations and text shadows, OpenType features.
- **Input:** selection, the clipboard, undo, and input methods for Japanese, Chinese and Korean on every desktop, the web and phones.
- **Keymaps and actions:** named commands bound to keys in a JSON keymap, shown in menus, dispatched up from the focused view.
- **Accessibility:** roles and labels reach VoiceOver, TalkBack, Narrator and Orca.
- **A code editor:** highlighting, multiple cursors, find and replace ([Code editor](https://helder.build/examples/#code-editor)).
- **Markdown:** CommonMark and GitHub's tables, task lists and strikethrough, parsed into a tree and shown as nodes your look styles, long documents virtualized ([Markdown](https://helder.build/examples/#markdown)).

<Reference to="text,ui,markdown"/>
