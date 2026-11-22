# Helder

Build apps and games with TypeScript or Haxe. Helder compiles to native code for
Windows, macOS, Linux, Android and iOS, and to WebAssembly for the web. The
toolkit includes a GPU-rendered UI, signals, 2D and 3D graphics, and a CLI that
builds, runs and packages your project. It uses [hxmc](https://github.com/benmerckx/hxmc)
as its compiler backend.

[Quickstart](https://helder.build/docs/start/install/) ·
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

See [TypeScript compatibility](https://helder.build/docs/start/typescript/)
for language features and project settings, and the
[publishing guide](https://helder.build/docs/ship/publishing/) for previews,
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

`examples/` has a program per folder, `apps/` whole apps, `docs/` the guide's
pages and `site/` the examples' site. An agent can check its own work
without a display: `helder run --headless` with a script, a snapshot and
the node tree ([cli](src/helder/cli/README.md), "Headless runs").

## Roadmap

**Lately**: [app services](src/helder/os/README.md#app-services): network
status, permissions, the share sheet, local notifications, the photo picker,
the camera, location, biometrics, the app's directories, device info, the
status bar's style and incoming deep links; [navigation](src/helder/ui/README.md#navigation);
gamepads on every platform; http, https and WebSockets on each platform's
own stack; [localization](src/helder/os/README.md#localization); the
platform's settings as signals; new [docs](https://helder.build/docs/).

**Now**: standard controls with a default look and forms; text input on
phones.

**Packages**, for what needs a library or glue the system lacks, built so
that their users need no Xcode or Android SDK: [in-app purchases](src/helder/store/README.md)
are done (StoreKit 2 on iOS and macOS, Play Billing fetched from Maven and
dexed by helder); next push notifications, Game Center and Play Games,
Steam, ads and analytics.

**Apps**
- Effects on nodes: blur, backdrop blur, filters, clip paths, shaders.
- Lazy layouts: horizontal and grid lists, collapsing headers, pull to refresh.
- Network images with a cache; long press and double tap; state restored
  after the system ends the app.

**Games**
- Physics: mesh and convex colliders, layers, triggers, contact events, stable stacks.
- Animation state machines and layers; tweens for any value.
- 3D audio, buses and effects; richer particles.
- 2D: animated sprites, tilemaps, a 2D camera and physics.
- Pathfinding, saves, ETC2 and KTX2 textures, a profiler.

**Parallel**: one function over a range or buffers that compiles to both
SIMD across jobs and a GPU compute pass, picked per call (as C++'s
parallel algorithms, ISPC and Taichi do); workgroup memory and subgroups
in `compute()`; GPU particles, cloth and soft bodies as its first users.

**Layers**, divided as browsers divide rendering:
- The program's thread runs signals and layout and records a display list
  per layer, in flat buffers outside the collector's heap; a layer is
  rastered in tiles, those near the view first, and only what changed is
  drawn again (damage rects).
- A compositor thread owns the GPU: it composites the layers and applies
  what needs no layout (scroll offsets, sticky boxes, transforms, opacity,
  filters, clips) and the declared springs and tweens, from the latest
  input each vsync, so scrolling and animations keep going while the
  program is busy. Scroll
  physics move there; scroll-linked effects (sticky and collapsing headers)
  are declared; a gesture that may claim a drag says so upfront.
- The system's compositor where there is one (CALayer, SurfaceControl,
  DirectComposition, Wayland subsurfaces): layers handed to it, native
  views and video between drawn layers in the same transaction as the
  frame, so they clip, stack and scroll with it. Ladybird's Compositor
  (LibCompositing, BSD-2-Clause) is this design, as a process of its own.
- Then Liquid Glass: the system's own on iOS and macOS 26 (UIGlassEffect,
  NSGlassEffectView) and a shader matching it elsewhere and in screenshots.

Also screen reader checks, and a low-end Android phone among the benchmarks.

**helder.run**: share and run links that update live: `helder share
--watch` sends each rebuild to the same address and open pages reload in
place, as `helder dev` does locally; sharing a project again keeps its link.

**120 Hz on the web**: iOS Safari holds requestAnimationFrame and touch
events to 60 Hz on a 120 Hz screen; the compositor in a worker drawing to
an OffscreenCanvas, the program in another, the page's thread only passing
input on (an invisible scroller's offsets: Safari's own momentum, at 120
Hz), the main thread's canvas where OffscreenCanvas is missing.

Also: Windows' touchpad scrolling, the web's scroll lag and Safari's rubber band.

**Later**: decals, volumetric fog, a lightmap baker, soft bodies, multiplayer,
a Vulkan back end (Android and Linux: async compute, timestamps, bindless),
io_uring for files and sockets on Linux.

## License

MIT (LICENSE). helder.pack's asset catalog and code signing are helder's own
code, written from the formats as
[viraptor/actool](https://github.com/viraptor/actool) (MIT) and
[rcodesign](https://github.com/indygreg/apple-platform-rs) (MPL-2.0, read
for the format only) document them.
