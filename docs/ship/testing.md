# Testing and headless runs

Write tests in TypeScript or Haxe, run them natively and as WebAssembly, and drive the whole app without a display: `helder run --headless` plays a script of taps, typing and keys on a virtual clock and writes frames, videos and the UI's node tree. The same script gives the same pixels every time, which is what an AI agent or a CI job needs to check its own work.

<Image src="todo.webp" alt="A todo app with one item, Ship the docs, added by a script" caption="Every picture in these docs is a headless frame: here a script tapped the field, typed and pressed Enter."/>

```ts
import { describe, test, equals } from "helder/test";
import { added, left } from "./todos";

describe("todos", () => {
  test("left", () => equals(left(added([], 1, "Buy milk")), "1 item left"));
});
```

```haxe
import helder.test.Test;

function tests() {
  describe("todos", () -> {
    test("left", () -> equals(left(added([], 1, "Buy milk")), "1 item left"));
  });
}
```

Run the tests, then the app itself, headless:

```sh
npx helder test --target all                       # natively and as WebAssembly
npx helder run --headless --script demo.json --snap after.png --tree tree.json
npx helder run --headless --script demo.json --video demo.mp4 --keys --pointer
```

A script is a list of steps, aimed at nodes by their role or label:

```json demo.json
[
  {"t": 0.2, "type": "tap", "role": "textbox"},
  {"t": 0.3, "type": "type", "text": "Ship the docs"},
  {"t": 1.0, "type": "key", "name": "Enter"}
]
```

## What else

- **Assertions:** equality of any value, approximate numbers, throws and rejections, and snapshots.
- **Stories:** each screen of your app in each state, rendered for tests and for the stores' screenshots.
- **The node tree:** every node's place, text, role and state as JSON, and where in your source it was written.
- **Videos** with the keys and taps drawn over them, and frame times for performance work.
- **Inspect a running app:** `helder inspect` reads the tree, state and log of a `helder dev` session.

<Reference to="test,story,cli"/>
