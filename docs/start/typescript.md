# TypeScript or Haxe

Write helder apps in TypeScript or in Haxe: both compile to the same native code and WebAssembly, call the same packages, and mix the same markup. Pick TypeScript for a familiar language and its tooling; pick Haxe for macros and every package helder has. Shaders are written in either, as ordinary functions.

<Example id="motion"/>

The same component in both. Every sample in these docs with a TypeScript and a Haxe version has a switch, and your choice is remembered.

```tsx
import {signal} from 'helder/view'

function Toggle(props: {label: string}) {
  const on = signal(false)
  return <view:button role='switch' checked={on()} padding='6 12' radius={6}
    background={on() ? '#18181b' : '#e4e4e7'}
    color={on() ? '#fafafa' : '#18181b'}
    onPress={() => on(v => !v)}>{props.label}</view:button>
}
```

```haxe
import helder.view.*;
import helder.view.graph.Graph.*;

class Toggles implements Markup {
  static function Toggle(props:{label:String}):View {
    var on = signal(false);
    return <view:button role='switch' checked={on()} padding='6 12' radius={6}
      background={on() ? '#18181b' : '#e4e4e7'}
      color={on() ? '#fafafa' : '#18181b'}
      onPress={() -> on(v -> !v)}>{props.label}</view:button>;
  }
}
```

## How TypeScript runs

Your project's own TypeScript compiler (7.1 or later) checks the program. helder then compiles it straight to native code or WebAssembly: there is no JavaScript engine in the output and no Haxe source in between. Objects, classes, closures, `Map`, `Set`, typed arrays, `Date`, `RegExp`, `JSON`, promises and `async`/`await` all work.

## What else

- **TypeScript has:** `helder/view`, `helder/ui`, `helder/os`, `helder/gfx`, `helder/scene`, `helder/canvas`, `helder/async`, `helder/asset`, `helder/web` and `helder/test`, plus native calls into Objective-C, Java and COM through `helder/native`.
- **Haxe has, besides:** physics, 2D sprites, sound, image codecs and PDF rendering.
- **Not in TypeScript:** browser globals such as `document`, Node built-ins such as `node:fs`, `eval` and `Proxy`. A dependency works when its source compiles without them.
- Strict mode, ES2022 or later, ESM with bundler resolution and `"jsx": "preserve"`: the defaults when there is no `tsconfig.json`.

<Reference to="typescript,view"/>
