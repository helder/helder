# Building UI

UI is written as TSX markup, bound to signals. This page covers the basics.

The snippets come from the [ts-counter](/examples/ts-counter) and [ts-todo](/examples/ts-todo) examples.

## Markup

Markup looks like JSX, but it is not React and not HTML. There is no virtual DOM. Each tag is compiled to a direct call that makes a node, and a value in braces that reads a signal is bound to it: when the signal changes, only that text or attribute updates.

Lowercase tags are elements. Capitalised tags are components: functions that return markup. A component function runs once, when it is mounted, not on every change.

`UiWindow.run` opens a window and runs the app. The window is a `<Surface>`:

```
import { UiWindow, Surface } from "helder/ui";

UiWindow.run(
  <Surface title="Todo" width={480} height={560}>
    <App/>
  </Surface>
);
```

On the web the surface fills the page.

## Elements

| Element | What it is |
|---|---|
| `<view>` | A box. It lays out its children with flexbox. |
| `<text>` | Text. |
| `<view:button>` | A box that can be pressed. |
| `<field>` | A text field. |
| `<scroll>` | A box that scrolls its content. |
| `<icon>` | An icon, by name: `<icon name="check"/>`. |

Attributes are styles and event handlers. Style names follow CSS: `padding`, `background`, `font-size`, `border-width`. Numbers are points.

## Layout

Layout is CSS flexbox. A view is a column by default.

```
<view grow={1} padding={24} row-gap={14}>
  <text font-size={28} font-weight={700}>todos</text>
  <view direction="row" align-items="center" justify="space-between">
    <text>2 items left</text>
    <text>all</text>
  </view>
</view>
```

| Attribute | What it does |
|---|---|
| `direction` | `"row"` lays children out side by side. The default is a column. |
| `grow` | Takes a share of the free space, as CSS `flex-grow`. |
| `width`, `height` | A fixed size. There are also `min-height` and the other minimums and maximums. |
| `padding` | Space inside the box: `padding={24}`, or `padding="8 16"` for vertical and horizontal. |
| `row-gap`, `column-gap` | Space between children. |
| `align-items` | Places children across the direction: `"center"`. |
| `justify` | Places children along the direction: `"center"`, `"space-between"`. |

As in CSS, a scrolling list inside a column needs `min-height={0}` next to `grow={1}`. Otherwise it grows to fit all of its content.

## Text

```
<text font-size={32}>{count}</text>
<text color="#a1a1aa" text-decoration="line-through">Buy milk</text>
```

Text styles are inherited, so you can set them once on a parent:

```
<view font-family="DejaVu Sans" font-size={14} color="#18181b">
  <text>Uses the view's font, size and colour.</text>
</view>
```

Colours are CSS colours: hex, `rgb()`, `hsl()` and the named colours.

## Buttons

A button is a `<view:button>` with an `onPress` handler. You style it yourself:

```
<view:button role="button" focusable padding="8 16" radius={6}
  background="#18181b" color="#fafafa" cursor="pointer"
  onPress={() => count(c => c + 1)}>+1</view:button>
```

`role="button"` tells assistive technology what it is. `focusable` lets the keyboard reach it. `radius` rounds the corners, and `border-width` and `border-color` draw a border.

## Signals

State lives in signals. A signal is a function: call it to read, call it with a value to write, call it with a function to update.

```
import { signal, memo } from "helder/view";

const count = signal(0);

count();            // read: 0
count(5);           // write
count(c => c + 1);  // update from the current value

const double = memo(() => count() * 2);  // derived, recomputed when count changes
```

In markup, put a signal or an expression that reads one in braces:

```
<text>{count}</text>
<text>{double()} is twice {count()}</text>
<view background={count() > 9 ? "#fee2e2" : "#ffffff"}/>
```

Writes are applied together at the end of the current event or frame. Until then, a read returns the previous value.

Under `helder dev`, a signal that holds plain data (numbers, strings, booleans, arrays and plain objects) keeps its value across a reload.

## Components

A component is a function that takes props and returns markup. A prop typed `Read<T>` accepts a constant, a signal or an expression. The component reads it by calling it, and stays bound to it.

```
import { Read } from "helder/view";

function Button(props: { label: string; onClick: () => void; outline?: Read<boolean> }) {
  return <view:button role="button" focusable cursor="pointer" padding="6 12" radius={6}
    background={props.outline?.() ? "#ffffff" : "#18181b"}
    color={props.outline?.() ? "#18181b" : "#fafafa"}
    onPress={() => props.onClick()}>{props.label}</view:button>;
}

<Button label="Add" onClick={() => add()}/>
<Button label="all" outline={filter() !== "all"} onClick={() => filter("all")}/>
```

## Lists and conditions

`<For>` keeps one row per item, matched by a key. `<Show>` mounts its content while a condition holds.

```
import { signal, For, Show } from "helder/view";

type Item = { id: number; title: string; done: boolean };
const todos = signal<Item[]>([]);

<scroll grow={1} min-height={0} row-gap={6}>
  <For each={todos} by={i => i.id}>{item =>
    <text>{item().title}</text>
  }</For>
  <Show when={todos().length === 0}>
    <text color="#a1a1aa">Nothing here.</text>
  </Show>
</scroll>
```

Inside `<For>`, `item` is a function. Call it to read the current item.

## Text fields

```
import { signal } from "helder/view";
import { Event, Key } from "helder/ui";

const draft = signal("");

<field value={draft} placeholder="What needs to be done?" padding="8 12" radius={6}
  border-width={1} border-color="#e4e4e7" background="#ffffff"
  onInput={(e: Event) => draft(e.text)}
  onKeyDown={(e: Event) => { if (e.key === Key.ENTER) add(); }}/>
```

## A complete example

[examples/ts-todo](/examples/ts-todo) is a small complete app: a text field, a keyed list, checkboxes, filters, keyboard shortcuts and tests. Run it from a checkout of the repository, or copy its files into your project.
