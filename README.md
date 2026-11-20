# Helder

Build apps and games with TypeScript or Haxe. Helder compiles to native code for
Windows, macOS, Linux, Android and iOS, and to WebAssembly for the web. The
toolkit includes a GPU-rendered UI, signals, 2D and 3D graphics, and a CLI that
builds, runs and packages your project. It uses [hxmc](https://github.com/benmerckx/hxmc)
as its compiler backend.

[Quickstart](https://helder.build/docs/guide/start/) ·
[Docs](https://helder.build/docs/) ·
[Playable examples](https://helder.build/examples/) ·
[Helder Studio](https://helder.build/studio/)

**Early preview.** Expect APIs and CLI behavior to change between nightlies.

## Try it locally

In an npm project with Node.js 24, install Helder and the TypeScript checker:

```sh
npm i -D helder@next typescript@next
```

Save this counter as `src/main.tsx`:

```tsx
import { signal } from "helder/view";
import { UiWindow, Surface } from "helder/ui";

const count = signal(0);

UiWindow.run(
	<Surface title="Counter" width={320} height={200}>
		<view grow={1} align-items="center" justify="center" row-gap={12}>
			<text font-size={32}>{count}</text>
			<view:button role="button" focusable padding="8 16" onPress={() => count(c => c + 1)}>+1</view:button>
		</view>
	</Surface>
);
```

```sh
npx helder dev                          # desktop, with reload on save
npx helder dev --target web             # browser preview
npx helder build --target android       # package a debug-signed APK
```

See [TypeScript compatibility](https://helder.build/docs/guide/typescript/)
for language features and project settings, and the
[publishing guide](https://helder.build/docs/guide/publishing/) for previews,
hosted web releases and store uploads.

## Packages

`src/helder/<name>`, each with its own README:

| | |
| --- | --- |
| [os](src/helder/os/README.md) | windows, input, the app loop, audio, on every platform |
| [gfx](src/helder/gfx/README.md) | a GPU API over GL/GLES, Metal, D3D11, WebGPU and WebGL2; shaders in Haxe |
| [view](src/helder/view/README.md) | signals and markup, compiled to direct calls |
| [ui](src/helder/ui/README.md) | CSS layout, text input, accessibility, keymaps, scrolling, drawn on gfx |
| [web](src/helder/web/README.md) | view in the browser's DOM: rendering, hydration, islands |
| [text](src/helder/text/README.md) | fonts, shaping, bidi and layout in Haxe; the platform's text where asked |
| [image](src/helder/image/README.md), [canvas](src/helder/canvas/README.md), [pdf](src/helder/pdf/README.md) | image codecs, 2D drawing, PDF rendering |
| [scene](src/helder/scene/README.md), [physics](src/helder/physics/README.md), [sprite](src/helder/sprite/README.md) | 3D (glTF, PBR, shadows, post effects), rigid bodies, 2D sprites |
| [asset](src/helder/asset/README.md) | files checked at compile time, bundled by use, hot reloaded |
| [async](src/helder/async/README.md), [jobs](src/helder/jobs/README.md) | coroutines, sockets, HTTP and WebSocket; work on other threads |
| [cli](src/helder/cli/README.md), [pack](src/helder/pack/README.md), [test](src/helder/test/README.md) | the `helder` command, APKs and app bundles without an SDK, tests |

## Working on helder

```sh
bun install
bun run test              # the lanes that need no GPU, display or browser (bun run test help: all)
bun run helder test       # the *.test.hx files
bun run helder examples/counter/Counter.hx   # an example, live
```

`examples/` has a program per folder, `apps/` whole apps, `docs/` the docs'
pages and `site/` the examples' site. An agent can check its own work
without a display: `helder run --headless` with a script, a snapshot and
the node tree ([cli](src/helder/cli/README.md), "Headless runs").

## Roadmap

**Now**: https and wss on every platform's own stack (#51); Windows'
touchpad scrolling; the web's scroll lag and Safari's rubber band.

**Foundations**
- [Localization](src/helder/os/README.md#localization): the device's locales, string catalogues, plurals, dates and numbers.
- The platform's settings as signals (text scale, reduced motion,
  contrast, orientation); Android's clipboard.

**App services**: one API each, the platform's implementation underneath
(as Capacitor's and Flutter's plugins), unavailable where a platform has none.
- In helder, on the system's own APIs: permissions, the share sheet, local
  notifications, network status, incoming deep links, the photo picker and
  camera, geolocation, biometrics, the app's directories, device info, the
  status bar's style.
- As packages, for what needs a library or glue the system lacks: in-app
  purchases first (StoreKit 2's Swift, Play Billing), then push
  notifications, Game Center and Play Games, Steam, ads and analytics. Such a
  package carries prebuilt native pieces (a static library, Android's DEX, a
  shared library) and what the build merges (entitlements, Info.plist,
  manifests), so that its users need no Xcode or Android SDK.

**Apps**
- Navigation: routes, a stack with the system's back, transitions, URLs, deep links.
- Text input on phones: iOS composition, keyboard types, the keyboard's insets.
- Standard controls (button, checkbox, select, tabs, dialog...) and forms.
- Effects on nodes: blur, backdrop blur, filters, clip paths, shaders.
- Lazy layouts: horizontal and grid lists, collapsing headers, pull to refresh.
- Network images with a cache; long press and double tap; state restored
  after the system ends the app.

**Games**
- Gamepads on Android, iOS and macOS.
- Physics: mesh and convex colliders, layers, triggers, contact events, stable stacks.
- Animation state machines and layers; tweens for any value.
- 3D audio, buses and effects; richer particles.
- 2D: animated sprites, tilemaps, a 2D camera and physics.
- Pathfinding, saves, ETC2 and KTX2 textures, a profiler.

**Later**: decals, volumetric fog, a lightmap baker, soft bodies, multiplayer.

## License

MIT (LICENSE). helder.pack's asset catalog and code signing are helder's own
code, written from the formats as
[viraptor/actool](https://github.com/viraptor/actool) (MIT) and
[rcodesign](https://github.com/indygreg/apple-platform-rs) (MPL-2.0, read
for the format only) document them.
