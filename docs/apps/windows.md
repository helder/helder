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

<Reference to="os,ui"/>
