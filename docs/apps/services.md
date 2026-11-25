# Device services

One API for what the device offers, with each platform's own implementation underneath: settings and language, formatting for the user's locale, network status, the share sheet, permissions, local notifications, the photo picker and the camera, location, biometrics, deep links, the app's directories, device info, the status bar, storage and the clipboard. Where a platform has no such thing, the call answers "unsupported" instead of failing, and an app only links the services it uses.

<Example id="services"/>

Status and settings are signals, so views follow the device; the rest are calls, awaited where the system answers later.

```ts
import { Network, Permissions, Share, Notifications, Photos, Location,
  Biometrics, StatusBar, Settings } from 'helder/os'

const status = <text>{Network.online() ? 'Online' : 'Offline'}</text>
const panel = <view background={Settings.dark() ? '#18181b' : '#ffffff'}/>

if (await Permissions.request('notifications') === 'granted')
  Notifications.schedule({id: 'tea', title: 'Tea is ready', after: 180})
await Share.share({text: 'A course', url: 'https://example.com/c/3'})
const [photo] = await Photos.pick({max: 1})   // its file's bytes
const shot = await Photos.take()                 // the camera's JPEG, or null
const here = await Location.current()           // {latitude, longitude, ...} or null
if (Biometrics.kind() !== 'none' && await Biometrics.verify('Unlock your notes')) open()
StatusBar.style('light')                        // light icons over a dark app
```

```haxe
import helder.os.*;

<text>{Network.online() ? 'Online' : 'Offline'}</text>
<view background={Settings.dark() ? '#18181b' : '#ffffff'}/>

// in a coroutine: no await
if (Permissions.request(Notify) == Granted)
  Notifications.schedule({id: 'tea', title: 'Tea is ready', after: 180});
Share.share({text: 'A course', url: 'https://example.com/c/3'});
var photos = Photos.pick({max: 1});              // the files' bytes
var here = Location.current();                   // null when denied or unknown
var save = Paths.data() + '/save.json';          // the app's own directory
App.onOpen = urls -> nav.open(urls[0]);          // a deep link
```

## Where each works

| | iOS | Android | macOS | Windows | Linux | Web |
|---|---|---|---|---|---|---|
| Settings, locale, formatting | Yes | Yes | Yes | Yes | Yes | Yes |
| Network status | Yes | Yes | Yes | Yes | Yes | Yes |
| Share sheet | Yes | Yes | Yes | — | — | Yes |
| Permissions | Yes | Yes | Yes | Notifications | Notifications | Some |
| Local notifications | Yes | Yes | App bundles | — | — | While open |
| Photo picker | Yes | Yes | One, by dialog | One, by dialog | — | Yes |
| Camera (Photos.take) | Yes | Yes | — | — | — | A file input |
| Location | Yes | Yes | App bundles | — | — | Yes |
| Biometrics | Face ID, Touch ID | Yes | Touch ID | — | — | — |
| The app's directories | Yes | Yes | Yes | Yes | Yes | — |
| Device info | Yes | Yes | Yes | Yes | Yes | The browser's |
| Status bar style | Yes | Yes | — | — | — | — |
| Deep links | Yes | Yes | Yes | — | — | The page's URL |

## What else

- **Locale:** the user's languages, numbers, percentages, currencies and dates in their format, and plural rules.
- **Strings:** one JSON catalogue per language, checked when you build, with typed messages and plurals.
- **Links:** open a page in the app (Safari's view on iOS) or in the browser.
- **Storage:** a small key-value store kept between runs, in the right place on each platform.
- **Files:** open dialogs, drops from the system, and downloads.
- **The clipboard, haptics and gamepads.**
- **Built for you:** the Android manifest entries, Info.plist keys and iOS usage strings a program's calls need come from the build and `helder.json` (`targets.ios.usage`: `camera`, `location`, `faceid`...).

<Reference to="os"/>
