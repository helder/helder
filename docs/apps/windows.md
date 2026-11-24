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

<Reference to="os,ui"/>
