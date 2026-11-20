# Device services

One API for what the device offers, with each platform's own implementation underneath: settings and language, formatting for the user's locale, network status, the share sheet, permissions, local notifications, the photo picker, deep links, storage and the clipboard. Where a platform has no such thing, the call answers "unsupported" instead of failing, and an app only links the services it uses.

<Example id="services"/>

Status and settings are signals, so views follow the device; the rest are calls, awaited where the system answers later.

```ts
import { Network, Permissions, Share, Notifications, Photos, Settings }
  from "helder/os";

<text>{Network.online() ? "Online" : "Offline"}</text>
<view background={Settings.dark() ? "#18181b" : "#ffffff"}/>

if (await Permissions.request("notifications") === "granted")
  Notifications.schedule({ id: "tea", title: "Tea is ready", after: 180 });
await Share.share({ text: "A course", url: "https://example.com/c/3" });
const [photo] = await Photos.pick({ max: 1 });   // its file's bytes
```

```haxe
import helder.os.*;

<text>{Network.online() ? "Online" : "Offline"}</text>
<view background={Settings.dark() ? "#18181b" : "#ffffff"}/>

// in a coroutine: no await
if (Permissions.request(Notify) == Granted)
  Notifications.schedule({id: "tea", title: "Tea is ready", after: 180});
Share.share({text: "A course", url: "https://example.com/c/3"});
var photos = Photos.pick({max: 1});              // the files' bytes
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
| Deep links | Yes | Yes | Yes | — | — | The page's URL |

## What else

- **Locale:** the user's languages, numbers, percentages, currencies and dates in their format, and plural rules.
- **Strings:** one JSON catalogue per language, checked when you build, with typed messages and plurals.
- **Links:** open a page in the app (Safari's view on iOS) or in the browser.
- **Storage:** a small key-value store kept between runs, in the right place on each platform.
- **Files:** open dialogs, drops from the system, and downloads.
- **The clipboard, haptics and gamepads.**
- **Built for you:** the Android manifest entries and iOS usage strings a program's calls need come from the build and `helder.json`.
- **In progress:** the camera, location, biometrics, the app's directories, device info and the status bar's style.

<Reference to="os"/>
