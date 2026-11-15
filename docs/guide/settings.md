# Settings

helder.json holds the app's name, icon, colours and id, each target's settings, and where `helder publish` sends it.

Put `helder.json` at the project's root, beside `package.json`. Every member is optional, and so is the file: an app builds and runs without it.

## Example

```json helder.json
{
  "$schema": "https://helder.build/schema/helder.json",
  "name": "Little Skies",
  "label": "Greens",
  "description": "Mini golf on little islands in the sky.",
  "id": "build.helder.littleskies",
  "version": "1.2",
  "build": 3,
  "entry": "src/main.tsx",
  "icon": "icon.svg",
  "colors": {"theme": "#9fd0ff", "background": "#fbdfea"},
  "splash": {"image": "splash.svg", "background": "#fbdfea",
             "dark": {"image": "splash-dark.svg", "background": "#000000"}},
  "display": "fullscreen",
  "orientation": "landscape",
  "run": {
    "name": "little-skies",
    "listed": true,
    "kind": "game",
    "tags": ["golf"],
    "source": "https://github.com/helder/little-skies",
    "screenshots": ["shots/hole-4.png", "shots/hole-9.png"]
  },
  "targets": {
    "android": {
      "minSdk": 31,
      "permissions": ["VIBRATE"],
      "publish": [{"to": "play", "track": "internal"}],
      "store": "https://play.google.com/..."
    },
    "ios": {
      "bundleId": "build.helder.littleskies",
      "publish": ["testflight"],
      "store": "https://apps.apple.com/..."
    },
    "macos": {"publish": ["notarize"]}
  }
}
```

The `$schema` line gives editors completion and checks. A mistake in the file stops the command with an error that names the member, such as `targets.android.minSdk`.

## The app

| Member | Type | What it is |
|---|---|---|
| `name` | string | The app's name: the page's title and the name in the stores. |
| `label` | string | The short name under the icon on a launcher or home screen. Default: `name`. |
| `description` | string | A description of the app. |
| `id` | string | The app's id on both phones, such as `org.example.app`. Default: `org.helder.<name>`. |
| `version` | string | The version people see. Default: `1.0`. |
| `build` | integer | The build number, 1 or higher. Default: `1`. The stores need a higher one for each upload. |
| `entry` | string | The file to build: a `.ts` or `.tsx` file. Default: the project's main file. |
| `icon` | string or object | The icon's file: an SVG, or a PNG of 1024 px. Or one file for each purpose: `{"any", "maskable", "monochrome"}`. |
| `colors.theme` | colour | The colour of the browser's and the system's bars. |
| `colors.background` | colour | The background of the splash screen and the page. |
| `splash.image` | string | The image on the splash screen. Default: the icon. |
| `splash.background` | colour | The splash screen's background. Default: `colors.background`. |
| `splash.dark` | object | `image` and `background` for the dark appearance. |
| `display` | string | `fullscreen`, `standalone`, `minimal-ui` or `browser`. `fullscreen` hides the system's bars on phones. |
| `orientation` | string | `portrait` or `landscape` locks the screen on phones. `any` and `natural` do not. The `-primary` and `-secondary` forms are accepted too. |
| `lang` | string | The app's language. |
| `dir` | string | `ltr`, `rtl` or `auto`. |
| `categories` | array of strings | The app's categories. |
| `fileHandlers` | array | The file types the app opens, as the web manifest's `file_handlers`. |

Colours are CSS colours. Paths are relative to helder.json.

One icon is enough. Helder makes every size each target needs from it when it builds: Android's adaptive icon, iOS's app icons, the web page's icons, and the desktop packages' icons. A `maskable` icon is used full bleed where the platform crops icons. A `monochrome` icon is used for Android's themed icons.

## run

The `run` block is for [helder.run](publishing.md#helderrun). With it, `helder publish` puts the web build on helder.run.

| Member | Type | What it is |
|---|---|---|
| `run.name` | string | The address: `<name>.helder.run`. 3 to 40 lowercase letters, digits and hyphens. Default: the app's name, made into one. |
| `run.listed` | boolean | List the project on [Explore](https://helder.build/explore). Default: `false`. |
| `run.kind` | string | `game`, `app` or `tool`. |
| `run.tags` | array of strings | Up to 5 tags, each lowercase letters, digits and hyphens. |
| `run.source` | string | Where the source is, an https URL. A GitHub repository of the owner's gives the project page its verified mark. |
| `run.screenshots` | array of strings | Up to 8 images for the project page. Default: one screenshot, taken of the running program. |

## targets

`targets` has a block for each of `web`, `windows`, `linux`, `macos`, `android` and `ios`. Every block takes `store`. The `macos`, `android` and `ios` blocks also take a `publish` list, and the phones have settings of their own.

| Member | Type | What it is |
|---|---|---|
| `targets.<target>.store` | string | The app's page in that target's store, an https URL. The project page on helder.build links to it. |
| `targets.android.publish` | array | Where `helder publish` sends the Android build: `"play"`, or `{"to": "play", "track": "beta", "draft": true}`. Tracks: `internal`, `alpha`, `beta`, `production`. |
| `targets.ios.publish` | array | `["testflight"]` |
| `targets.macos.publish` | array | `["notarize"]` |

### targets.android

| Member | Type | What it is |
|---|---|---|
| `package` | string | The Android package name. Default: `id`. |
| `minSdk` | integer | The lowest Android API level. Default and minimum: `29`. |
| `targetSdk` | integer | Default: `36`. |
| `permissions` | array of strings | `"VIBRATE"` means `android.permission.VIBRATE`. A name with a dot is used as it is. |
| `key` | string | The debug key's file. Default: a key Helder makes on first use and keeps. |
| `signing` | object | The release key: `certificate` and `key`, PEM files. |
| `serviceAccount` | string | A Google service account's JSON key, for publishing to Google Play. |

### targets.ios

| Member | Type | What it is |
|---|---|---|
| `bundleId` | string | The bundle id. Default: `id`. |
| `minVersion` | string | The lowest iOS version. Default: `15.0`. |
| `entitlements` | string | An entitlements file, an XML plist. |
| `signing` | object | The distribution identity: `certificate`, `key` and `profile`. |
| `sdk` | object | The SDK and Xcode versions the build reports to the App Store. |
| `nonExemptEncryption` | boolean | The answer to App Store Connect's export compliance question. |
| `privacy` | object | Required-reason APIs for the privacy manifest: each category's reasons. |

Keys and certificates can also come from environment variables, which suits CI. See [Publishing](publishing.md#the-stores).

## helder migrate

Older projects keep these settings in `helder.webmanifest`. `helder migrate` writes that file as `helder.json` and removes it.

```sh
npx helder migrate          # the project here
npx helder migrate my-app   # the project in my-app
```

A project with both files reads `helder.json`.
