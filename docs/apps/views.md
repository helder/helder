# Views and signals

A helder interface is markup bound to signals. A signal holds a value; markup that reads it updates when it changes, and nothing else is redrawn. There is no virtual DOM and no diffing: each binding is a direct call, compiled from your TSX or Haxe markup.

<Example id="ts-todo"/>

A signal is a function: call it to read, call it with a value to write, or with a function to update. `memo` derives a value from others.

```tsx
import {signal, memo} from 'helder/view'

const count = signal(0)
const double = memo(() => count() * 2)

count(5)                // write
count(c => c + 1)       // update

const label = <text>{double()} is twice {count()}</text>
```

```haxe
import helder.view.graph.Graph.*;

var count = signal(0);
var double = memo(() -> count() * 2);

count(5);                // write
count(c -> c + 1);       // update

<text>{double()} is twice {count()}</text>
```

## Components

A component is a function that takes props and returns markup. It runs once when it mounts; after that, only the bindings inside it run. A prop typed `Read<T>` takes a constant, a signal or an expression, and stays bound to it.

```tsx
import {Read} from 'helder/view'

function Badge(props: {label: string, on: Read<boolean>}) {
  return <view padding='2 8' radius={9}
    background={props.on() ? '#16a34a' : '#a1a1aa'}>
    <text color='#ffffff'>{props.label}</text>
  </view>
}

<Badge label='Online' on={connected() && !paused()}/>
```

## What else

- `<Show when={...}>` mounts content while a condition holds; `<For each={...}>` keeps a row per item ([Lists and scrolling](lists.md)).
- `effect` runs code when what it reads changes; writes land together at the end of each event or frame.
- Under `helder dev`, signals holding plain data keep their values across a reload.
- **Context:** make a key with `context`, give a subtree a value with `provide` and read the nearest value with `use`. Pass a signal for a value the subtree should follow.
- **Lifetime:** `onCleanup` runs when the owning computation reruns or is removed. `isPending` and `latest` let a view keep showing a value while new work is pending.
- **Mounting:** `UiWindow.run` takes one or more `<Surface>` windows. Use `Render.render(markup, node)` to mount into an existing node.
- **Setup:** [Install and first app](../start/install.md) shows how to install and run a counter.
- The same components render to HTML and the DOM in a web page ([Pages, hydration and islands](../web/pages.md)).

<Reference to="view,ui"/>
