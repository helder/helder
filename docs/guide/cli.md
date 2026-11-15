# CLI reference

The `helder` command builds, runs, tests and publishes an app.

```sh
helder <command> [entry] [options]
helder <entry>                       # the same as: helder dev <entry>
```

The entry is what to build: a `.ts` or `.tsx` file, a directory, or a project. The default is the current directory. Where it runs is always a flag, never the entry.

`helder help` lists the commands, and `helder <command> --help` lists a command's flags. Installed in a project, run it as `npx helder`.

## Common flags

| Flag | What it does |
|---|---|
| `--target <t>` | Where it runs or what it is built for. See [Targets](#targets). Default: `host`, this machine. |
| `-d, --device <d>` | Which phone, emulator or simulator, with `--target android` or `ios`. `helder devices` lists them. |
| `-o, --out <path>` | The output of the build. |
| `-- <args>` | Arguments for the program itself (`dev`, `run`). |
| `-h, --help` | Help. |

### Targets

| Target | What it is |
|---|---|
| `host` | This machine. The default. |
| `web` | WebAssembly with its page. |
| `android` | Android: arm64 for `build`, the device's own architecture for `run` and `dev`. |
| `ios` | An iPhone for `build`, the simulator for `run` and `dev`. |
| `ios-sim` | The iOS simulator. |
| `macos` | A universal macOS app bundle. |
| An exact target | `linux-x86_64`, `linux-arm64`, `macos-x86_64`, `macos-arm64`, `windows-x86_64`, `windows-arm64`, `wasm32-wasi`, `android-arm64`, `android-x86_64`, `ios-arm64`, `ios-sim-arm64`. |

## helder dev

Builds, runs and reloads on every change. State is kept across a reload.

```sh
helder dev [entry] [options] [-- <args>]
```

| Flag | What it does |
|---|---|
| `--target <t>` | Where it runs. |
| `-d, --device <d>` | Which phone, emulator or simulator. |
| `--port <n>` | The HTTP port, for the web page and the devtools. Default: `4321`, or the next free one. |
| `--host <address>` | The address it listens on. Default: `127.0.0.1`. `0.0.0.0` is every interface. |

## helder run

Makes a release build and runs it.

```sh
helder run [entry] [options] [-- <args>]
```

| Flag | What it does |
|---|---|
| `--target <t>` | Where it runs. |
| `-d, --device <d>` | Which phone, emulator or simulator. |
| `-o, --out <path>` | The output of the build. |
| `--headless` | Run with no window: offscreen, on a virtual clock. The flags below need it. |

### Headless runs

With `--headless`, the app runs on this machine without a display, on the real renderer. A script can drive it, and the run writes what you ask for. The same script gives the same output every time. This is how tests and coding agents see the app.

```sh
helder run --headless --snap out.png --tree tree.json
helder run --headless --script demo.json --snap added.png --at mark:added
helder run --headless --script demo.json --video demo.mp4
```

| Flag | What it does |
|---|---|
| `--snap <png>` | Write a frame as a PNG, at `--at`. |
| `--tree <json>` | Write every node as JSON: its tag, role, label, text, rect, colours and state. |
| `--at <t>` | When the `--snap` or `--tree` before it is taken: seconds, `end`, `mark:<name>` or `mark:<name>+0.5`. Default: `end`. |
| `--script <json>` | Timestamped input steps: taps, drags, keys, typing, resizes, marks. |
| `--frames <n>` | Write n frames as PNGs into `-o`, from `--start`. `--every <k>` writes every k-th frame. |
| `--video <file>` | Write a video: `.mp4`, `.webm` or `.mov`. Needs ffmpeg. `--duration <s\|auto>` sets its length. |
| `--start <t>` | Where `--frames` and `--video` begin. Default: `0`. |
| `--fps <n>` | Frames a second of the virtual clock. Default: `60`. |
| `--size <WxH>` | The window's size in points. Default: the program's. |
| `--scale <n>` | Pixels per point. Default: `1`. |
| `--theme <t>` | The system's appearance: `light` (default) or `dark`. |
| `--reduced-motion` | The system asks for reduced motion. |
| `--seed <n>` | The seed of `Math.random`. Default: `1`. |
| `--keys` | Draw the script's keys over the frames, as keycaps. `--keys-at <corner>` and `--keys-theme <t>` place and colour them. |
| `--pointer` | Draw a ripple at each press. |
| `--trace <jsonl>` | Write each tagged node's rect and opacity, one JSON line per frame. |
| `--stats <json>` | Write each frame's work time, GC bytes and input events. |

## helder build

Makes a release build in `bin/<target>/<name>`, and prints its compile time and size.

```sh
helder build [entry] [options]
```

| Flag | What it does |
|---|---|
| `--target <t>` | What it is built for. |
| `-o, --out <path>` | The output. |
| `--bundle` | Android: an App Bundle (.aab) for Google Play, signed with the release key. |
| `--package` | A desktop release in `bin/dist`, or the directory `-o` names. `macos`: a signed .app in a zip. Windows targets: the signed .exe in a zip. Linux targets: a .tar.gz and a Flatpak manifest. |
| `--release` | A release build. This is what build makes anyway. |

## helder test

Builds and runs the project's test files: `*.test.ts` and `*.test.tsx`. They import from `helder/test`.

```sh
helder test [file or name filter...] [options]
```

A filter that is part of a test file's path picks those files. Any other filter picks the tests whose name contains it.

| Flag | What it does |
|---|---|
| `--target <t>` | `host` (default), `wasm`, or `all` for both. |
| `-t, --test-name-pattern <text>` | Only the tests whose name contains the text. `/text/` is a regular expression. |
| `-w, --watch` | Run again on every change. |
| `-u, --update-snapshots` | Rewrite the snapshots that differ. |
| `--timeout <s>` | Seconds an async test may take. Default: `5`. |

## helder inspect

Reads from the program a running `helder dev` has: its UI tree, state, log or frame stats.

```sh
helder inspect [dir] [options]
```

| Flag | What it does |
|---|---|
| `--log` | The log, then each entry as it comes. The default. |
| `--tree` | The UI tree, once. Each node has the place in the source that wrote it. |
| `--at <file:line[:col]>` | The nodes made from that place in the source, once. |
| `--state` | The state kept across reloads, once. |
| `--frames` | The frames' stats, a line per batch. |
| `--port <n>` | The HTTP port of `helder dev`. Default: found from the project. |

## helder publish

Builds a release, signs it and uploads it. With no destination, it publishes to every one helder.json names. See [Publishing](publishing.md).

```sh
helder publish [entry] [--run | --play | --testflight | --notarize | --screenshots | --listing | --pull] [options]
```

| Flag | What it does |
|---|---|
| `--run` | To helder.run: `<run.name>.helder.run`. |
| `--play` | To Google Play: the App Bundle. |
| `--testflight` | To TestFlight: the .ipa. |
| `--notarize` | macOS: the packaged release notarized by Apple and stapled. |
| `--track <t>` | Google Play's track: `internal` (default), `alpha`, `beta` or `production`. |
| `--draft` | Google Play: a draft release, for an app never published. |
| `--dry-run` | Build and sign, read what is there, print what would change. Nothing is uploaded. |
| `--no-screenshot` | With `--run`: take no screenshot of the program when `run.screenshots` names none. |
| `--screenshots` | Render the stories marked for the stores at the stores' sizes, with a review sheet, in `bin/store`. |
| `--listing` | Send helder.json's `listing` and the screenshots to the stores' pages. With `--play` or `--testflight`: that store only. Never a build. |
| `--submit` | With `--testflight`: once processed, the build on its App Store version, `listing.notes` its what's new, sent for App Review. |
| `--create-version` | With `--listing` or `--submit`: make the App Store version when helder.json's is not being prepared. |
| `--pull` | Print the stores' listing text as helder.json's `listing`. |
| `--locale <l>` | The listing's language. Default: `en-US`. |
| `-o, --out <path>` | The output of the build. |

## helder share

Puts the web build on helder.run for a week, without an account, and prints a link to send. The project is unlisted.

```sh
helder share [entry] [options]
```

| Flag | What it does |
|---|---|
| `--no-screenshot` | Take no screenshot of the program for its page. |
| `--dry-run` | Build, and print what would be uploaded. Nothing is uploaded. |

## helder login, helder logout

`helder login` signs in to helder.build with GitHub, for `helder publish --run`. The token is kept in Helder's config directory. `helder logout` forgets it.

## helder migrate

Writes a project's `helder.webmanifest` as [helder.json](settings.md) and removes the old file.

```sh
helder migrate [dir]
```

## helder studio

Opens Helder's studio on a project: its screens on a canvas, its code, an inspector, and tools for a coding agent over MCP. The screens are the project's stories, the `*.story.tsx` files.

```sh
helder studio [project] [options]
```

| Flag | What it does |
|---|---|
| `--mcp-port <n>` | The MCP server's port on 127.0.0.1. Default: `HELDER_STUDIO_MCP_PORT`, or a free one. |

## helder devices

Lists where the app can run: this machine, a browser, Android devices and emulators, and iOS simulators. Each has an id for `-d`.

## helder help

`helder help` prints the commands and the common flags. `helder help <command>` prints one command's help.
