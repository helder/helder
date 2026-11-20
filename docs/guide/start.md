# Getting started

Run a TypeScript counter in this page, then build the same app on your desktop and in your browser.

## Try the counter

Select **Play** and press **+1**. This example compiles to WebAssembly and uses the same UI code as the desktop build. The full source is below it.

<Example id="ts-counter"/>

## Install

Use Node.js 24 and npm for this tutorial. The CLI and compiler ship together for macOS, Linux and Windows on x64 and arm64.

```sh
mkdir counter
cd counter
npm init -y
npm i -D helder@next typescript@next
```

`helder@next` installs the nightly. The project’s own TypeScript compiler checks your code. Use TypeScript 7.1 or later.

## A first app

Create a `src` folder and save the counter source above as `src/main.tsx`. Helder finds `src/main.tsx` or `src/main.ts` automatically when you run the CLI from the project root.

- `signal(0)` holds the count. Calling the signal reads it, and passing an update function changes it.
- `<Surface>` defines the window. In the browser it fills the page.
- `<view>` lays out its children. The `<text>` reads the signal, and the button’s `onPress` handler increments it.

Try changing the counter to count by five. In the button handler, replace `c + 1` with `c + 5`, then change the button label to `+5`. Run the app below and press it twice to reach 10.

### tsconfig.json

You can use Helder’s default settings for this app. If you create a `tsconfig.json` for your editor, start with this configuration:

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

See [TypeScript compatibility](typescript.md) for supported APIs and configuration.

## Run it

Run these commands from the directory containing your `package.json`.

### On your desktop

```sh
npx helder dev
```

Press the counter button a few times. Change the button’s `background` color in `src/main.tsx` and save. The running app updates and the count keeps its value. When a build fails, the terminal shows the error and the last successful build keeps running. Press **Ctrl+C** to stop the dev command.

### In a browser

```sh
npx helder dev --target web
```

Open the address printed in the terminal. The default is `http://127.0.0.1:4321/`. You can choose another port with `--port`.

If the CLI reports that the page ships no font, install [DejaVu Sans](https://dejavu-fonts.github.io/Download.html) and restart the command. Helder bundles that font from your machine so it can draw text in the browser. If you keep the font outside the system font folders, set `HELDER_FONT_DIRS` to the directory containing `DejaVuSans.ttf`.

### On a phone

```sh
npx helder devices
npx helder dev --target android
npx helder dev --target ios
```

For Android, connect a device with USB debugging enabled or start an emulator. Put `adb` on your PATH or install it under `$ANDROID_HOME/platform-tools`. To pick a device, pass `-d` and an ID from `helder devices`.

The iOS dev target runs on the simulator and needs a Mac with Xcode’s simulator tools. To test on a physical iPhone, use a signed distribution build such as [TestFlight](publishing.md#testflight).

## Build it

Use `npx helder build` for a release build. The command prints the output path and size. By default the output goes under `bin/<target>/`.

| Command | Output |
|---|---|
| `npx helder build` | A native executable for the current machine. |
| `npx helder build --target web` | A page, WebAssembly module and runtime files in `bin/web/`. |
| `npx helder build --target android` | A debug-signed APK you can install on a device. Building the APK does not need the Android SDK. |
| `npx helder build --target android --bundle` | An App Bundle for Google Play, signed with your release key. |
| `npx helder build --target ios` | An IPA. Building it does not need Xcode. Devices require valid signing and provisioning. |
| `npx helder build --target macos` | A universal macOS app bundle. |

For desktop archives, simulator builds and cross-compilation, see [build options](cli.md#helder-build) and the [target list](cli.md#targets).

## Next

- [Building UI](ui.md) covers layout, reusable components and reactive lists.
- [Palette study](https://helder.build/examples/#ts-palette) uses the same signal pattern to update a group of elements. Open the source and try adding a palette of your own.
- [Settings](settings.md) shows how to give the app a name, icon and ID.
- [Publishing](publishing.md) gives you a browser link you can send to someone.
