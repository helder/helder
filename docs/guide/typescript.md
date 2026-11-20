# TypeScript compatibility

Helder checks the project with TypeScript, then compiles it to native code or WebAssembly. It provides a TypeScript runtime for supported language features and its own APIs for rendering, input, files and networking.

## What you can use

| Need | Use |
|---|---|
| Data and logic | Objects, arrays, classes, `Map`, `Set`, typed arrays, `Date`, `RegExp` and `JSON`. |
| Async work | Promises and `async` / `await`. See the [networking APIs](/src/helder/async/README.md) for HTTP and sockets. |
| Interface and events | Signals from `helder/view` and [TSX elements](ui.md) from `helder/ui`. |
| Embedded 3D | [`helder/scene`](../scene/typescript.md) for scenes, cameras, lights and materials. |

`UiWindow` uses Helder’s renderer on the web too. The TSX elements in [Building UI](ui.md) belong to Helder. To port a React front end, bring over portable logic and recreate the view with Helder’s elements and signals.

## Dependencies and platform APIs

Whether a TypeScript dependency works depends on what it imports and which language features and APIs it needs. Start with source modules you can compile and test on your target. Browser globals such as `document`, Node built-ins such as `node:fs`, and dynamic features such as `eval` and `Proxy` are unavailable to Helder’s TypeScript frontend.

For platform-specific work, check the API you need on your target. The [package index](/README.md#packages) links to the implementation and its notes. For instance, the [async package](/src/helder/async/README.md) describes the HTTP and socket implementations by platform.

## Project configuration

Helder uses the project’s installed TypeScript 7.1 or later. It looks for the nearest `tsconfig.json` between the entry file and the directory containing `package.json`. Without one, Helder uses built-in defaults.

Use strict checking, an ES2022 or later target, ESM with bundler resolution, and `"jsx": "preserve"`. Leave out the DOM library, ambient type packages and legacy decorators. The [starter configuration](start.md#tsconfigjson) is enough for a standalone app.

See the [frontend reference](/src/helder/typescript/README.md) for implementation details and the current language coverage.
