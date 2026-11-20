# Device services

One API for what the device offers, with each platform's own implementation underneath: the system's settings and language, formatting for the user's locale, links, storage and the clipboard. Where a platform has no such thing, the API says so instead of failing.

<Example id="services"/>

The settings are signals, so a view that reads them follows the device: switch to dark mode or a larger text size and the app updates.

```tsx
import { Settings, Locale, Format } from "helder/os";

<text font-size={14 * Settings.textScale()}>
  {Format.date(new Date(), { date: "long", locale: Locale.current() })}
</text>
<view background={Settings.dark() ? "#18181b" : "#ffffff"}/>
```

```haxe
import helder.os.*;

<text font-size={14 * Settings.textScale()}>
  {Format.date(Date.now(), {date: Long, locale: Locale.current()})}
</text>
<view background={Settings.dark() ? "#18181b" : "#ffffff"}/>
```

## What else

- **Settings:** dark mode, text size, reduced motion, contrast and orientation, as signals.
- **Locale:** the user's languages, numbers, percentages, currencies and dates in their format, and plural rules.
- **Strings:** one JSON catalogue per language, checked when you build, with typed messages and plurals.
- **Links:** open a page in the app (Safari's view on iOS) or in the browser.
- **Storage:** a small key-value store kept between runs, in the right place on each platform.
- **Files:** open dialogs, drops from the system, and downloads.
- **The clipboard, haptics and gamepads.**
- **Coming next:** permissions, the share sheet, local notifications, the photo picker and camera, and network status.

<Reference to="os"/>
