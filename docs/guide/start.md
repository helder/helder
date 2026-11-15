# Getting started

Install Helder, write a counter, and run it on your desktop, in a browser and on a phone.

## Install

You need Node.js. Helder is one npm package. It holds the `helder` command and the compiler, prebuilt for macOS, Linux and Windows (x64 and arm64).

```sh
mkdir counter
cd counter
npm init -y
npm i -D helder@next typescript@next
```

`helder@next` is the nightly build. Helder checks your code with your project's own TypeScript, which must be 7.1 or later. Today that is `typescript@next`.

## A first app

A project's entry is `src/main.tsx` (or `src/main.ts`). Create it:

```tsx src/main.tsx
import { signal } from "helder/view";
import { UiWindow, Surface } from "helder/ui";

const count = signal(0);

UiWindow.run(
  <Surface title="Counter" width={320} height={200}>
    <view grow={1} padding={24} row-gap={12} align-items="center" justify="center">
      <text font-size={32}>{count}</text>
      <view:button role="button" focusable padding="8 16" radius={6}
        background="#18181b" color="#fafafa" cursor="pointer"
        onPress={() => count(c => c + 1)}>+1</view:button>
    </view>
  </Surface>
);
```

- `signal(0)` holds the count. Call it to read, call it with a value or a function to change it.
- `<Surface>` is the window. On the web it fills the page.
- `<view>` is a box laid out with flexbox, `<text>` is text, and `<view:button>` is a box that can be pressed.
- `{count}` is bound to the signal. When the count changes, only that text updates.

[Building UI](ui.md) explains these.

### tsconfig.json

A `tsconfig.json` is optional. Without one, Helder uses its own defaults. If you add one, for your editor for example, it must be strict, use ES modules with bundler resolution and `"jsx": "preserve"`, and leave out the DOM library:

```json tsconfig.json
{
  "compilerOptions": {
    "target": "es2022",
    "lib": ["esnext"],
    "module": "esnext",
    "moduleResolution": "bundler",
    "jsx": "preserve",
    "strict": true
  }
}
```

Your code is compiled to machine code, not run as JavaScript. Typed arrays, `Map`, `Set`, `RegExp`, `Date`, `JSON`, promises and `async` functions work. `eval`, `Proxy` and the DOM globals do not exist.

## Run it

`helder dev` builds the app, runs it, and rebuilds it each time you save. The running app is updated in place, and signals keep their values.

### On your desktop

```sh
npx helder dev
```

A window opens. Change the text or a colour in `src/main.tsx` and save: the window updates and the count stays. Closing the window ends `helder dev`. If a build fails, the errors show in the terminal and the last good build keeps running.

### In a browser

```sh
npx helder dev --target web
```

This serves a page at `http://127.0.0.1:4321/`, or the next free port. `--port` picks another port, and `--host 0.0.0.0` listens on every network interface.

### On a phone

```sh
npx helder devices                 # what Helder can run on
npx helder dev --target android    # a connected Android device or a running emulator
npx helder dev --target ios        # the iOS simulator, on a Mac
```

Android needs `adb`: on your PATH, or in `$ANDROID_HOME/platform-tools`. The app is installed once, and each later build is swapped into it. iOS runs on the simulator, which needs a Mac with Xcode's simulators. Running on a real iPhone from `helder dev` is not supported yet.

With more than one device, pick one with `-d` and an id from `helder devices`:

```sh
npx helder dev --target android -d emulator-5554
```

## Build it

`helder build` makes a release build and prints its compile time and size. The output goes in `bin/<target>/`, named after your package.

| Command | Output |
|---|---|
| `helder build` | An executable for this machine: `bin/<target>/<name>` |
| `helder build --target web` | `bin/web/`: the WebAssembly module, its page and its runtime modules |
| `helder build --target android` | `bin/android/<name>.apk`, signed with your debug key. No Android SDK needed. |
| `helder build --target android --bundle` | `bin/android/<name>.aab` for Google Play, signed with your release key |
| `helder build --target ios` | `bin/ios/<name>.ipa`. No Xcode needed. It runs on devices only when signed for distribution. |
| `helder build --target ios-sim` | `bin/ios-sim/<name>.app` for the simulator |
| `helder build --target macos` | `bin/macos/<Label>.app`, a universal app bundle |
| `helder build --target windows-x86_64` | A build for another platform, by its exact target name |

`helder run` makes the same release build and runs it.

`--package` makes a desktop release in `bin/dist`: a zipped `.app` for `macos`, a zipped `.exe` for Windows targets, and a `.tar.gz` with a Flatpak manifest for Linux targets.

## Next

- [Building UI](ui.md): views, text, signals and layout.
- [Settings](settings.md): give the app a name, an icon and an id in helder.json.
- [Publishing](publishing.md): put it on the web with `helder share` or `helder publish`.
