# Install and first app

Install helder into an npm project, write a counter in a dozen lines, and run it on your desktop, in a browser and on a phone. This is the counter, running in this page:

<Example id="ts-counter"/>

## Install

You need Node.js 24. The CLI and compiler ship together for macOS, Linux and Windows on x64 and arm64.

```sh
mkdir counter && cd counter
npm init -y
npm i -D helder@next typescript@next
```

## The app

Save this as `src/main.tsx`. helder finds `src/main.tsx` or `src/main.ts` when you run it from the project's root.

```tsx
import {signal} from 'helder/view'
import {UiWindow, Surface} from 'helder/ui'

const count = signal(0)

UiWindow.run(
  <Surface title='Counter' width={320} height={200}>
    <view flexGrow={1} alignItems='center' justifyContent='center' rowGap={12}>
      <text fontSize={32}>{count}</text>
      <button padding='8 16' borderRadius={6} background='#18181b'
        color='#fafafa' onPress={() => count(c => c + 1)}>+1</button>
    </view>
  </Surface>
)
```

`signal(0)` holds the count, the `<text>` reads it, and the button updates it. `<Surface>` is the window; in a browser it fills the page.

## Run it

```sh
npx helder dev                    # a desktop window, reloaded on save
npx helder dev --target web       # in a browser, at http://127.0.0.1:4321/
npx helder dev --target android   # a device or an emulator; ios: the simulator
```

Change the button's colour and save: the window updates and the count keeps its value. When a build fails, the last good one keeps running.

## Build it

```sh
npx helder build                    # a native executable for this machine
npx helder build --target web       # a page and its WebAssembly module
npx helder build --target android   # an APK to install; ios: an IPA
```

## What else

- `npx helder devices` lists the phones, emulators and simulators to run on.
- A `tsconfig.json` is optional; helder uses the project's TypeScript 7.1 or later to check your code.
- Want to try without installing? The [examples](https://helder.build/examples/) play in your browser.

<Reference to="cli,ui"/>
