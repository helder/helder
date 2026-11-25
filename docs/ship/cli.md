# The CLI

One command does everything: `helder` builds, runs, reloads, tests, inspects and publishes, for every platform, from any machine. It brings its own compiler. See [Install and first app](../start/install.md) for the Node.js version and TypeScript checker.

<Terminal command="helder help" src="help.txt"/>

```sh
npx helder dev                          # this machine, reloaded on save
npx helder dev --target web             # a browser
npx helder dev --target android -d emulator-5554
npx helder build --target ios           # an IPA, no Xcode needed
npx helder build --target windows-x86_64   # cross-compiled from any machine
```

The entry is a TypeScript, TSX or Haxe file, or a project directory; it defaults to the current one. `helder <command> --help` lists a command's flags.

## What else

- **Targets:** `host`, `web`, `android`, `ios`, `ios-sim`, `macos` (universal), and exact ones such as `linux-arm64` or `windows-arm64`.
- **The dev loop:** a resident compiler rebuilds in a fraction of a second; a failed build leaves the last good one running, and signals keep their state.
- **Devices:** `helder devices` lists browsers, Android devices and emulators, and iOS simulators.
- **Studio:** `helder studio` opens your app's screens on a canvas with an inspector, and gives coding agents its tools over MCP.
- **Packaging without SDKs:** APKs, App Bundles and iPhone apps are assembled and signed by helder itself.

<Reference to="cli,compiler"/>
