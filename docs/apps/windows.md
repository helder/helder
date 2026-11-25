# Windows

A `<Surface>` is a window. Set its title, size, frame and background
in markup. With a transparent background an app can draw a window of
any shape. Clear pixels show the windows behind it and let clicks
through. Half-transparent pixels blend over what is behind them.

<Image src="windows.webp" alt="A round clock with 10:24 in white" caption="A round clock drawn in a transparent Surface, captured over black."/>

```tsx
<Surface title='Clock' titlebar='none' width={480} height={240} background='transparent'>
  <view grow={1} align-items='center' justify='center'>
    <view width={200} height={200} radius={100} background='#18181bdd'
      align-items='center' justify='center'>
      <text color='#ffffff' font-size={38}>10:24</text>
    </view>
  </view>
</Surface>
```

Transparency works on macOS, Windows through DirectComposition, Wayland,
X11 with a compositing manager, and the web through the canvas's alpha.
The window stays opaque where the system cannot make it transparent.

## A window at the edge

`titlebar='none'` removes the frame. `onTop` keeps the window over the
others and `taskbar={false}` hides it from the task bar and switcher.
`window.workArea()` gives the screen's usable rectangle, clear of the
menu bar, notch, Dock and task bar. On Wayland, the compositor controls
these settings apart from the title bar.

```haxe
var a = window.workArea();
window.resize(120, a.height);
window.moveTo(a.x + a.width - 120, a.y);
```

## What else

- **Backdrops:** set `backdrop='blur'` for macOS vibrancy, Windows 11 Acrylic or KDE blur. Use `'mica'` for Windows 11 Mica or `'glass'` for Liquid Glass on macOS 26. A backdrop makes the window transparent. `window.backdrop` reports what the system applied.
- **Input:** give drawn decorations `pointer-events='none'` to pass clicks through, or set `clickThrough={false}` on the surface to keep every click. From Haxe, `window.input(rects)` sets the hit regions in pixels.
- **Haxe windows:** pass `true` for transparency in `new Window(title, width, height, Standard, true)`. Read `window.transparent` to see if it worked. `window.shadow = false` removes the system shadow on macOS and Windows.

<Reference to="os,ui"/>
