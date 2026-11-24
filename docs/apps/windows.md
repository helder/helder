# Windows

`<Surface>` is a window. Its props set its title, size, theme, title bar and background.

## Transparent windows

A background that isn't opaque makes the window transparent: what is behind it shows through the pixels the app leaves clear, and half-transparent ones blend over it.

```tsx
<Surface title="Clock" width={240} height={240} background="transparent">
  <view width={200} height={200} radius={100} background="#18181bdd"/>
</Surface>
```

Works on macOS, Windows (through DirectComposition), Wayland, X11 with a compositing manager, and in the browser (the canvas's alpha). Where the system can't do it, the window stays opaque. From Haxe, `new Window(title, width, height, Standard, true)` asks for one, `window.transparent` tells whether it is, and `window.shadow = false` takes the system's shadow away (macOS, Windows).

## Materials

`backdrop` puts the system's material behind the window, seen through its clear and half-clear pixels: `"blur"` (macOS vibrancy, Windows 11 Acrylic, KDE's blur), `"mica"` (Windows 11 Mica, macOS's window vibrancy, KDE's blur) or `"glass"` (macOS 26). It makes the window transparent. Where the system has no such material, nothing is drawn behind; `window.backdrop` then reads `None`.

```tsx
<Surface title="Notes" width={320} height={400} backdrop="blur">
  <text padding={16}>Over a blur of what is behind</text>
</Surface>
```

## Clicks through

A transparent window takes clicks only where it draws something; elsewhere they go to whatever is behind it. Mark drawn content as click-through with `pointer-events="none"`, or keep every click with `<Surface clickThrough={false}>`.

```tsx
<Surface background="transparent">
  <view width={200} height={40} background="#18181bcc" pointer-events="none">
    <text color="#ffffff">A label the pointer goes through</text>
  </view>
</Surface>
```

From Haxe, `window.input(rects)` sets where the window takes the pointer, in pixels.

## A window at the edge

`titlebar="none"` takes the title bar and frame away. `onTop` keeps the window over the others, and `taskbar={false}` keeps it out of the task bar and the window switcher. `window.workArea()` gives the part of the screen windows go in, clear of the menu bar, a notch, the Dock and the task bar, so a window can sit at its edge:

```haxe
var a = window.workArea();
window.resize(120, a.height);
window.moveTo(a.x + a.width - 120, a.y);
```

Wayland has no way for a window to ask for any of these, except no title bar.

<Reference to="os,ui"/>
