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
import {signal} from 'helder/view'
import {UiWindow, Surface} from 'helder/ui'

const count = signal(0)

UiWindow.run(
  <Surface title='Counter' width={320} height={200}>
    <view flexGrow={1} alignItems='center' justifyContent='center' rowGap={12}>
      <text fontSize={32}>{count}</text>
      <button padding='8 16' onPress={() => count(c => c + 1)}>+1</button>
    </view>
  </Surface>
)
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
| [gfx](src/helder/gfx/README.md), [math](src/helder/math/README.md) | a GPU API over GL/GLES, Metal, D3D11, WebGPU, WebGL2 and the CPU; shaders in Haxe and TypeScript; the vectors, matrices and quaternions they share |
| [view](src/helder/view/README.md) | signals and markup, compiled to direct calls |
| [ui](src/helder/ui/README.md) | CSS layout, text input, accessibility, keymaps, scrolling, drawn on gfx |
| [web](src/helder/web/README.md) | view in the browser's DOM: rendering, hydration, islands |
| [text](src/helder/text/README.md) | fonts, shaping, bidi and layout in Haxe; the platform's text where asked |
| [image](src/helder/image/README.md), [canvas](src/helder/canvas/README.md), [pdf](src/helder/pdf/README.md) | image codecs, 2D drawing, PDF rendering |
| [media](src/helder/media/README.md) | MP4 and Matroska read in Haxe, exact seeking, the playback clock |
| [markdown](src/helder/markdown/README.md) | CommonMark and GFM parsed into a tree, shown as nodes |
| [scene](src/helder/scene/README.md), [physics](src/helder/physics/README.md), [sprite](src/helder/sprite/README.md) | 3D (glTF, PBR, shadows, post effects), rigid bodies, 2D sprites |
| [asset](src/helder/asset/README.md) | files checked at compile time, bundled by use, hot reloaded |
| [async](src/helder/async/README.md), [jobs](src/helder/jobs/README.md) | coroutines, sockets, HTTP and WebSocket; work on other threads |
| [cli](src/helder/cli/README.md), [pack](src/helder/pack/README.md), [test](src/helder/test/README.md) | the `helder` command, APKs and app bundles without an SDK, tests |
| [store](src/helder/store/README.md) | in-app purchases on Apple platforms and Android |
| [story](src/helder/story/README.md), [headless](src/helder/headless/README.md) | screens in isolation, scripted runs and snapshots |
| [dev](src/helder/dev/README.md) | live reload, preserved state, logs and inspection |
| [typescript](src/helder/typescript/README.md), [compiler](src/helder/compiler/README.md), [syntax](src/helder/syntax/README.md) | TypeScript and Haxe builds, source parsing and edits |
| [native](src/helder/native/README.md) | native calls and compile-time target checks from TypeScript |

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

**Lately**: [video](src/helder/media/README.md) on every platform; layers
on macOS, iOS, Android, Windows, Wayland and the web, with Liquid Glass;
[software rendering](src/helder/gfx/README.md#on-the-cpu) for drawing,
compute and windows; [windows of any shape](docs/apps/windows.md),
with transparent backgrounds, click-through, backdrops, borderless and
on-top modes, taskbar control and work areas; [files](src/helder/os/README.md#dialogs-file-types-the-files-the-system-opens),
from folder grids to trash, thumbnails and dragging out of the viewer.

### Now

- **Software rendering:** TypeScript shaders and per-pixel speed at 1024×768.
- **Time tracker:** an example along the screen's edge, inside the work
  area, scrolling through days. Hairline hours, a stroke per project and
  ticks for switches and activity. An OS service reads the frontmost app
  and window, idle time and input counts, with the system's permission.

### Next

- **Packages:** push notifications, Game Center and Play Games, ads and
  analytics, with no Xcode or Android SDK needed.
- **Games:** more physics (mesh and convex colliders, layers, triggers,
  contact events, stable stacks), animation state machines and tweens,
  3D audio, richer particles, tilemaps and 2D physics, pathfinding, saves,
  ETC2 and KTX2 textures, and a profiler.
- **Parallel:** one function over a range or buffers, compiled to SIMD
  across jobs and GPU compute, picked per call. Workgroup memory and
  subgroups in `compute()`, with particles, cloth and soft bodies first.
- **helder.run:** `helder share --watch` sends each rebuild to the same
  address and open pages reload in place. Sharing again keeps the link.
- **Later:** decals, volumetric fog, a lightmap baker, soft bodies,
  multiplayer, Vulkan on Android and Linux, and io_uring for files and
  sockets on Linux.

## License

[MIT](LICENSE). helder.pack's asset catalog and code signing are helder's own
code, written from the formats as
[viraptor/actool](https://github.com/viraptor/actool) (MIT) and
[rcodesign](https://github.com/indygreg/apple-platform-rs) (MPL-2.0, read
for the format only) document them.
