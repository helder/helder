# Lists and scrolling

`<For>` keeps one row per item, matched by key, so adding, removing or reordering items moves rows instead of rebuilding them. For long lists, `VirtualList` lays out only the rows on screen: a million rows of different heights scroll as smoothly as ten.

<Example id="ts-million"/>

```tsx
import {signal, For, Show} from 'helder/view'

const todos = signal<Array<{id: number, title: string}>>([])

const list = <scroll flexGrow={1} minHeight={0} rowGap={6}>
  <For each={todos} by={t => t.id}>{item =>
    <text>{item().title}</text>
  }</For>
  <Show when={todos().length === 0}>
    <text color='#a1a1aa'>Nothing here.</text>
  </Show>
</scroll>
```

```haxe
import helder.view.Flow.*;
import helder.view.graph.Graph.*;

var todos = signal(new Array<Todo>());

<scroll flexGrow={1} minHeight={0} rowGap={6}>
  <For each={todos()}>{(item:Read<Todo>) ->
    <text>{item().title}</text>
  }</For>
  <Show when={todos().length == 0}>
    <text color='#a1a1aa'>Nothing here.</text>
  </Show>
</scroll>
```

Inside `<For>`, `item` is a function: call it to read the current item. A scroller's own minimum height is 0, as in CSS, but every box between it and the sized column that grows with `grow={1}` needs `min-height={0}` too, or that box grows to fit everything the scroller holds and nothing scrolls (browsers do the same).

## What else

- **VirtualList:** rows measured as they appear, jumps to any index, rows inserted above without the view moving, keyboard selection.
- **Scrolling that feels native:** flings with the platform's momentum on touch, precise touchpads and wheels on desktops, scroll bars in each platform's style.
- **Gestures:** pointers, fingers and pens with capture, drags and flings.
- **Motion:** rows animate in and out, and shared elements move between screens.

<Reference to="ui,view"/>
