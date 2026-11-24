# helder.os

Windows, input, the app loop and audio output for hxmc in pure Haxe
(`helder.os`): raw OS bindings (X11, Wayland, the Objective-C runtime, AppKit and
UIKit, Win32, Android's NativeActivity, a canvas in the browser; ALSA, CoreAudio,
WASAPI, WebAudio) and a
portable layer over them. No C of its own: the system's C APIs through
externs, COM vtables, `objc_msgSend` and `dlopen`.

## One system's code per build

A build names its system, `-D helder.os=<linux|android|macos|ios|windows|web>`
(helder's compiler derives it from `hxmc.target`, or the host's; the CLI and
the tests pass it: `helder.compiler.Os`), and the shared classes keep each
system's branch under `#if (!helder.os || helder.os == "windows")` around
its `Platform` test. hxmc folds those tests only while lowering, after Haxe
has typed every branch and loaded the modules they name; under `#if` a
build loads, types and links its own system's code only. A type check without it
(`--no-output`, the declarations) types every system's. A branch that
names only shared types keeps its plain `Platform` test. (hxmc's own
`hxmc.os`, since hxmc #205, does not tell Android from Linux or iOS from
macOS, nor is it set for a build that names no target: helder keeps its own.)

## Windows and the loop

```haxe
var window = new Window("Hello", 640, 480);   // its size in points; window.surface for helder.gfx
App.run(() -> {
	// a frame (paced by the GPU's present)
}, e -> switch e.kind {
	case Close: window.close();               // the last window closed ends the loop
	case KeyDown if (e.key == 0xFF1B): App.quit();
	case _:
});
```

X11 or Wayland on Linux (the glibc mode, `-D hxmc.libc=glibc`; Wayland
when `WAYLAND_DISPLAY` is set and it connects, `HELDER_X11=1` X11's), Cocoa on macOS,
Win32 on Windows, a canvas in the browser (wasm32-wasi: `App.run` returns
and `requestAnimationFrame` runs the loop). `Event` is one object, refilled
for each event: keys as X11 KeySyms, `TextInput` characters (and an input
method's `TextEditing`), the mouse in
pixels from the top left, `Scroll` in pixels, `Resize`, `ScaleChange`,
and every pointer's events (below).

In the browser the program runs in a Web Worker where it fits (the page
`helder build --target web` writes, and WebAssembly islands:
`browser.mjs`'s option `worker`, `'auto'`; `?thread=page` on the page,
`worker: false` to `run`, keep it on the page's thread). The first window's
canvas gives its control to the worker (`transferControlToOffscreen`), the
program draws on it there, and the page keeps the element: its listeners
post input to the worker, the calls only a page can make (text fields, the
accessibility mirror, history, the clipboard, the cursor) are made there
in order, and what the program reads at once (the pixel ratio, the soft
keyboard, media queries, `localStorage`) is the page's as it last told it.
Each of the worker's frames waits for the page's frame that delivered its
input, 4 ms at most, so input reaches the same frame as on the page's
thread, and a page busy with its own scripts holds no frame back. It fits
in a browser with module workers and OffscreenCanvas, when the module
imports nothing only a page has (audio's AudioContext, helder.web's DOM,
helder.media's `<video>`, helder.canvas's Canvas 2D) and with one window;
`helder dev`'s builds, swapped in place, stay on the page's thread. The
details are in `src/helder/os/thread.mjs`; `bun run test thread-web`
compares both threads in Chromium, Firefox and WebKit.

On Android (`helder build --target android`: an APK, helder.pack.android)
the window is the activity's (full screen, one per app; `new Window` waits
for it): the program runs on a thread of its own, `App.run` draws while the
activity has its window, a touch is as in the browser (below: a tap a
click, a drag `Scroll`s that glide), `Suspend` and `Resume` come when the system takes the window and
gives one back (`Surface.lost`: the GPU back end lets go of it), and what
the program prints goes to logcat (`adb logcat -s hxmc`). Text input
(`startTextInput`, once `helder.os.android.TextInput.enable()` was called:
helder.ui's drawn windows do) shows the soft keyboard and brings the input
method's compositions and commits through a hidden `EditText`; a
`ChildSurface` is a GPU view among Android's views. No clipboard there yet. Java from Haxe: `helder.os.android.Jni` (JNI's function tables,
bound like COM's by `helder.os.VTable`), `MainThread` (Java's main
thread, where views live: work handed to it, Choreographer's frames
there) and `Glue` (Java's listeners calling Haxe: helder then writes a
`classes.dex` into the APK).

On iOS (`helder build --target ios` or `ios-sim`: an app bundle,
helder.pack.ios) the window is a `UIWindow` on the whole screen (one per app),
backed by a `CAMetalLayer`: the program's main runs inside UIKit's loop
(`UIApplicationMain` comes first: `helder.os.uikit.UIKitApp`), `App.run`
draws while the app is active, a touch is as in the browser
and on Android, `Suspend` and `Resume` come when
the app goes to the background and back. No keys or text input there yet.

### Threads

On macOS, iOS, Windows and Linux (X11, Wayland) `App.run` runs the
program's loop on a thread of its own, as on Android: the main thread is
the system's, where AppKit and UIKit have to be called and Win32's
windows live (a window is its maker thread's), and the program's is free of it (Layers'
compositor reads the input there while the program is busy: the
README's roadmap). The main thread runs what the program hands it
(`helder.os.OsThread.run`: windows, events polled, the clipboard,
dialogs, menus, native views, accessibility) and waits otherwise; what
the system calls back into the program comes back to its thread
(`OsThread.back`: events, a live resize's frames, files opened). One of
the two runs at a time, each serving the other while it waits, so the
program sees what it saw on one thread, and code after `App.run`
runs on the main thread again. Code of the app's own that calls AppKit
from a frame or an event (`helder/native`, Objective-C) goes through
`OsThread.run`.

While the program runs on and calls nothing, the main thread reads the
system's input itself (`OsThread.waitMain`), so that a window's
compositor (helder.ui's README, "Performance") gets each event as it
comes, before the program: macOS's input events in the default run loop
mode (a call handed to it posts an event that wakes it); X11's
connection; Wayland's pointer, keyboard and touch, on an event queue of
their own (the rest, the windows' configures among them, the program's as
before; a touch's shared slot, `Pointers`, written as the program takes
its event). Android's UI thread routes each motion event as it copies it
(`Activity.router`: pointers of its own by the system's ids, the answers
kept in the event's record for the program's; not under a dev host). Each event is routed then (`Window.route`, `Event.routed`)
and kept for the program's next poll, in order. `OsThread.post` hands
the main thread a call from any thread without waiting (the compositor's
native views moved with its frame; on macOS and iOS, a frame's Core
Animation transaction where a native view moves with it, an NSView's and
a UIView's being the main thread's; one without commits on the render
thread, flushed, as it has no run loop). A system's callback into the
program's state meanwhile (NSAccessibility, a native field's delegate,
WKWebView's) is handed to the program's thread (`OsThread.hold`).
Window calls stay where they were (macOS's on the main thread, X11's and
Wayland's on the program's, their libraries locking).

Windows: the windows, TSF, the clipboard, the file dialog, the EDITs and
menus and UI Automation are the main thread's, in its COM apartment.
While the program runs on, the main thread takes only the input messages
from its queue (`PM_QS_INPUT`: no sent or posted message, nor a COM call,
is served behind the program's back), routes them, translates the keys
and keeps them for the program's poll, which dispatches them first; a
press on the frame or a system key stops the reading until then, so that
the modal loop (moving, sizing, the menu) gets what follows. During that
loop the window procedure hands the program its events and the sizing
timer's frames, as before. A Win32 call of the app's own that may send
its window a message goes through `OsThread.run`: the main thread does
not serve one sent from elsewhere while it waits. A window of system
layers (helder.ui.draw.DcLayers) has its DirectComposition target made
there with its swap chain; its visuals are the render thread's, which
commits them.

iOS: the program's thread starts once UIKit has launched; while it runs
on, the main thread turns the run loop (UIKit's touches, layout, scroll
views and animations, the keyboard). What UIKit tells meanwhile that
needs no answer (touches, read at once; the layout; text typed; a
UIScrollView's offset; the foreground, a memory warning, a URL opened)
waits for the program's next call to the main thread (`OsThread.soon`),
so the main thread never waits for a busy program; what needs an answer
(VoiceOver's actions, a pan's start over the tree, going to the
background, after which no GPU work may come) waits for it
(`OsThread.hold`).

`HELDER_THREAD=0` keeps the program on the main thread; the browser and
headless runs keep it there.

`HELDER_BACKGROUND=1` keeps macOS's windows in the background (no Dock
icon, never key nor active, shown on screen so that frames present): for
window tests run while someone uses the machine.

### Files dropped, full screen, a window's place

```haxe
App.run(frame, e -> switch e.kind {
	case Drop: open(e.files[0]);           // paths, at e.x, e.y (pixels)
	case _:
});
window.fullscreen = true;                   // the whole screen, no frame
var p = window.position();                  // the content's top left on the screen (points); null in a browser
window.moveTo(p.x, p.y);                    // put back (a setting kept across runs)
```

A drop of files is a `Drop` event with their paths (`Event.files`) and
where they fell, by each system's own means: Windows' `DragAcceptFiles`
and `WM_DROPFILES` (`DragQueryFileW`, UTF-16), macOS's dragging
destination (the window registered for `public.file-url`, its delegate
answering `draggingEntered:` with a copy when the pasteboard has file
URLs and reading them at `performDragOperation:`), X11's XDND 5 (the
window `XdndAware`; an `XdndEnter` offering `text/uri-list`, each
`XdndPosition` answered by an `XdndStatus`, the drop's
`XdndSelection` converted, the URIs' paths decoded by `UriList`, then
`XdndFinished`). Not yet in the browser, on Android or iOS, nor Wayland
(which helder does not speak yet). `fullscreen`: X11's
`_NET_WM_STATE_FULLSCREEN` asked of the window manager, Windows' borderless
window over its monitor (the frame and place given back after), macOS's
full-screen space (`toggleFullScreen:`; the getter follows once there).
`position` and `moveTo`: the content's top left, in points (X11: pixels;
the frame's extents, `_NET_FRAME_EXTENTS`, taken off when moving; macOS:
from the main screen's top left). A trackpad's pinch on macOS is a
`Scroll` with `Mods.CONTROL` (`deltaY` -180 ln(scale): as browsers send
one, as Control and the wheel; Windows' precision touchpads send it so
themselves). In the browser the canvas's wheel listener is not passive:
a wheel with Control (Chrome's and Firefox's pinch, Control and the wheel)
is prevented, the program's and not the page's zoom, other wheels left to
scroll a page around it; Safari's pinch, its `gesturestart` and
`gesturechange` (prevented too), comes as the same `Scroll` with
`Mods.CONTROL` (-100 ln of the scale's step, in CSS pixels, as Chrome makes
it). Tests: `bun run test window` (tests/os/WindowTest.hx: on X11
a second connection drags two files over the window speaking XDND, on
Windows an HDROP posted as `WM_DROPFILES`, under Wine too
(`GFX_TARGET=windows-x86_64`), on macOS a dragging info of the test's
own class given to the window's dragging destination; then moveTo and
position, fullscreen asked); `src/helder/os/UriList.test.hx`.

### Dragging files out

```haxe
// from a pointer move with the button down: the system's drag from here
window.dragFiles(paths, thumb, 16, 16, [Copy, Move], op -> if (op == Move) refresh());
ui.dragFiles(paths, thumb, 16, 16, [Copy], op -> {});  // helder.ui: through its window
```

`dragFiles` hands the press to the system as a drag of files (absolute
paths) to other apps: file managers, mail, chat, a browser's upload. The
image (straight RGBA, a pixel a point) has its top left at the pointer
less the offsets; `done` comes once with the target's operation (`None`:
cancelled with Escape, dropped where nothing took it). The press is the
system's from then on: no release follows (helder.ui lets its pressed node,
its capture and a drag of its own go). macOS: a dragging session
(`beginDraggingSessionWithItems:event:source:`) from the last mouse-down
or -dragged event, an `NSDraggingItem` per file URL, the source a class
made at run time (its operation mask from `allowed`, its
`draggingSession:endedAtPoint:operation:` the completion); events keep
flowing. Windows: OLE's modal `DoDragDrop` (`OleInitialize` on the
windows' thread; frames drawn from a timer meanwhile, as while sizing),
the Shell's data object (`CF_HDROP`, the Shell IDList Array: a shell item
array's `BHID_DataObject` handler, else the parent folder's
`GetUIObjectOf`, which is what Wine has), a native `IDropSource` (Escape
cancels, the button's release drops) and the image through
`IDragSourceHelper::InitializeFromBitmap`; the left button only. X11: an
XDND 5 source: the pointer and keyboard grabbed, the `XdndAware` window
under the pointer found (an `XdndProxy` followed), `XdndEnter` with
`text/uri-list`, `XdndPosition` (the action from `allowed` and the
modifiers: Shift move, Control and Shift link) and its `XdndStatus`,
`XdndLeave` on leaving it, `XdndDrop` on the release when accepted, the
`XdndSelection` answered with the paths as percent-encoded `file://` URIs
(`UriList.encode`), then `XdndFinished` (or 5 s); no image, the drag's
cursor instead. False on Wayland, in the browser, on Android and iOS.
Tests: `bun run test window` (on X11 a second connection's window is the
target, answering and converting the selection; on Windows the Shell's
data object read back as `CF_HDROP`; on macOS the dragging items and the
source's mask and end), `src/helder/ui/DragFiles.test.hx`.

### An inset title bar

```haxe
var window = new Window("Studio", 1180, 740, Inset);  // helder.os.TitleBar: the content under the title bar
window.titlebarAt = (x, y) -> y < 40 * window.scale ? Drag : Content;  // the app's answer at a press (pixels)
window.titlebarArea();                      // the bar's area free of the buttons (pixels; null: not inset, full screen)
window.systemControls();                    // macOS's own buttons over the content (null where the app draws its own)
window.placeControls(x, y);                 // ... moved there (macOS)
window.minimize(); window.maximized = !window.maximized;
```

`Inset` runs the content under the title bar, the window's buttons in the
app's own layout (helder.ui's `<WindowControls/>`, `drag-region` and
`env(titlebar-area-*)`), what a press is the app's answer
(`titlebarAt`: `TitleHit`'s Drag, Minimize, Maximize, Close or Content;
`TitleBars.hit` adds the window's edges, 6 points, unless maximised or full
screen). macOS: a full-size content view (`NSWindowStyleMaskFullSizeContentView`),
the bar transparent, no title; the system's buttons kept and placed where
the app asks (Electron's way: the title bar's container made as tall as
the buttons and twice the top margin, each button's origin set in it;
AppKit lays its title bar out again after a title is set, a resize and a
change of key status, so in those the layout is done at once and the
buttons moved again in the same turn of the main thread, before the
window is drawn: never seen at AppKit's place for a frame); a press on the bar but the buttons is the app's,
a drag region's `performWindowDragWithEvent:` (a double click what the
user set: `AppleActionOnDoubleClick`, zoom by default). Windows:
WM_NCCALCSIZE takes the caption off (the sides and bottom kept: their
resize borders and shadow; maximised, the frame the monitor hides too),
WM_NCHITTEST answers the top edge (HTTOP), the drag regions (HTCAPTION:
Windows' own moves, snaps and double clicks) and the maximise button
(HTMAXBUTTON: Windows 11's snap layouts; its presses taken by the window,
its hover passed on as a move); `TitleBars.button` and `HEIGHT` are the
drawn buttons' sizes. Wayland: neither the compositor's decorations nor
helder's bar; a drag region's press `xdg_toplevel.move` (a double press
maximises, the right button the window menu), an edge's `resize`. X11:
undecorated (`_MOTIF_WM_HINTS`), `_NET_WM_MOVERESIZE` for a drag region
or an edge (the pointer's grab let go first), maximised through
`_NET_WM_STATE`. A headless run of a macOS build has the buttons where
macOS puts them (7, 6 points, 54 by 16): `<WindowControls/>` draws
stand-ins. Tests: `TitleBar.test.hx` (the edges, each system's codes;
natively, as wasm32-wasi and on Eval) and the window lane's
`tests/os/TitleBarTest.hx` (macOS: the window's style, the buttons
measured, placed and kept through a resize, the bar's presses the app's
and the buttons' AppKit's; Windows: no caption, WM_NCHITTEST's answers;
X11: Motif's hints). Not yet: the edges' cursors on Wayland and X11 (the
compositor's or the window manager's), the maximised state followed on X11
(the window's own requests only).

### Windows of any shape

```haxe
var window = new Window("Clock", 320, 320, Standard, true);  // transparent: what is behind shows through
window.transparent;   // composed so here (false where the system can't)
window.shadow = false;  // no system shadow (macOS, Windows)
```

```tsx
<Surface background="transparent">…</Surface>  // or any colour with alpha: a transparent window
```

A transparent window's pixels are premultiplied, its clear pixels show
what is behind it. macOS: the NSWindow not opaque, its background clear,
the CAMetalLayer not opaque; its shadow follows the window's pixels, made
again after its first frame. Windows: `WS_EX_NOREDIRECTIONBITMAP` and a
swap chain for composition, `DXGI_ALPHA_MODE_PREMULTIPLIED`, the content
of a DirectComposition visual (not a layered window); `shadow = false`
turns DWM's frame off (`DWMWA_NCRENDERING_POLICY`). Wayland: EGL's
ARGB8888 buffers, no opaque region (the system layers' base layer sets
none either). X11: a 32-bit TrueColor visual and its colormap, the EGL
config of that visual, where a compositing manager owns `_NET_WM_CM_S0`;
else the window is opaque and says so. The browser: the canvas's alpha
(WebGPU's `alphaMode: 'premultiplied'`, WebGL's `alpha`). helder.ui
clears the frame to its background premultiplied (a transparent window's
frames drawn whole: no damage rectangles) and an opaque window's
background keeps alpha 1. Tests: `tests/ui/ShapeWindow.hx` (the frame
read back; macOS's capture of the window, Windows' screen over an opaque
window behind, X11's 32-bit pixels and the composed screen, weston's
screenshot over its background; `tests/ui/shape.sh` on Linux).

### Dialogs, file types, the files the system opens

```haxe
var path = FileDialog.open(window, "Open an image", [{name: "Images", extensions: ["jpg", "png"]}]); // null: cancelled
FileTypes.register("helder-viewer", "Viewer", exe, [{mime: "image/jpeg", extensions: ["jpg"]}]);   // "Open with", this user's
App.onOpen = paths -> open(paths[0]);       // macOS: Finder's Open With, the Dock's icon (application:openURLs:)
window.raise();                              // to the front (a second launch handing its file over)
```

`FileDialog`: Windows' IFileOpenDialog (COM's vtables: filters, title,
the result's IShellItem path), macOS's NSOpenPanel (runModal), Linux's
xdg-desktop-portal FileChooser (OpenFile over the session bus with
`helder.os.linux.DBus`, a small blocking client of its own: SASL
EXTERNAL, the marshalling of the portals' types, calls, replies, signals,
a match rule; the request's Response signal, its URI as the path);
`available()` says whether there is one (no portal: the caller's own
picker). `FileTypes.register`: Windows' HKCU\Software\Classes (a ProgID
and its open command, each extension's OpenWithProgids, the
application's SupportedTypes; SHChangeNotify), Linux's
~/.local/share/applications/<id>.desktop (MimeType, Exec with %F); a
macOS bundle's are its Info.plist's (`helder build --target macos`, from
helder.webmanifest's `file_handlers`). Tests: the window lane
(IFileOpenDialog and NSOpenPanel made; FileTypes' registry values and
.desktop file read back; application:openURLs: reaching App.onOpen), the
dbus lane (tests/os/DBusTest.hx: a real dbus-daemon, the portal's
OpenFile against a stand-in portal).

### The system's image decoders

`SystemImages.decode(path, side)`: what helder.image does not read,
through the system: Windows' WIC (COM: the factory's decoder from the
file, its first frame converted to 32bppRGBA, its EXIF orientation from
the metadata query reader applied), macOS's ImageIO (an image
source, its size from its properties, then a thumbnail of at most `side`
with its EXIF orientation applied, drawn into an sRGB bitmap,
unpremultiplied). TIFF, HEIC and HEIF, AVIF and the cameras' RAW files
where the system has their codecs (Windows: its HEIF, AV1 and Raw Image
extensions). ImageLimits is checked on the size the system reports,
before any pixel; errors are ImageErrors (Unsupported: no codec for it).
Linux (`linux/LinuxImages`): libtiff, libheif (HEIC, HEIF, and AVIF with
its AV1 decoder), libavif and libraw where installed, each loaded at run
time (none: `supports` false for its formats; `available()` whether any
is); the limits first on each one's size (HEIF's and AVIF's from their
ispe boxes). Tests: `bun run test system-images`
(tests/os/SystemImagesTest.hx: a TIFF of a known gradient, plain and LZW,
its pixels and straight alpha; one with EXIF's orientation 6, upright; an
AVIF where the system reads it; macOS: a HEIC made by sips, whole and at
a side; the limits first; Linux natively, Windows under Wine with
GFX_TARGET=windows-x86_64).

### A phone's screen and the display's frames

```haxe
var w = new Window("Game", 0, 0);          // a phone's: the whole screen, its size the system's
w.safeTop; w.safeBottom;                    // the safe area, pixels from each edge (a Resize when it changes)
w.scale;                                    // pixels per point: Android's density / 160, iOS's nativeScale
w.immersive = true;                         // the system's bars hidden (a game's)
App.run(() -> {
	var dt = App.frame.delta;               // since the last frame: the display's vsyncs on a phone
}, e -> {});
```

`Window.safeTop`, `safeLeft`, `safeBottom` and `safeRight` are the
insets, in pixels, that the system's bars, a notch, the island, a
display cutout or the home indicator leave clear, as CSS's
`env(safe-area-inset-*)`: iOS's view's `safeAreaInsets` (measured in
`layoutSubviews` and `safeAreaInsetsDidChange`), Android's window insets
(`helder.os.android.Insets`, JNI on the main thread: the decor view's
root `WindowInsets`, on API 30 `getInsets(systemBars | displayCutout)`,
on 29 the system window insets and the cutout's safe insets), measured
again when the window, its size, its content rect or the configuration
changes; 0 elsewhere. A change is a `Resize` (a rotation is one anyway: a
new size). helder.ui takes them as `Ui.safeArea` and markup's
`env(safe-area-inset-*)` (src/helder/ui/README.md). `Window.scale` is
Android's density over 160 (`AConfiguration`, a `ScaleChange` when the
configuration changes it) and iOS's screen's `nativeScale` (the view's
`contentScaleFactor` and the layer's `contentsScale` set to it).
`Window.immersive` hides the system's bars: Android's immersive mode
(API 30: `WindowInsetsController.hide(systemBars)`, a swipe shows them for
a while; API 29: the immersive sticky flags; the window into a cutout's
edges), iOS's status bar and home indicator (the controller's
`prefersStatusBarHidden`, `prefersHomeIndicatorAutoHidden`); nothing
elsewhere. The app's options in package.json (`"helder": {"orientation":
"portrait" | "landscape" | "any", "fullscreen": true}`: the manifest's
`screenOrientation` and the plist's `UISupportedInterfaceOrientations`,
`-D helder.fullscreen` making every window immersive from the start;
src/helder/cli/README.md).

On Android and iOS the frames are the display's: a turn of `App.run` that
may draw asks for the next vsync and sleeps until it comes (or an event
does), and the next turn draws it. Android: Choreographer
(`AChoreographer_postFrameCallback64`, the NDK's, on the program's own
thread and looper: `helder.os.android.Vsync`); iOS: a `CADisplayLink` on
the main run loop, whose callback stops the run loop's wait. `App.frame`
(a `FrameClock`) is the frame's time: on a phone the vsync's timestamp
(Choreographer's `CLOCK_MONOTONIC` time, the link's `timestamp`) moved
into `haxe.Timer.stamp()`'s seconds, elsewhere when the turn began;
`delta`, the time since the last frame, and `period`, the display's
refresh interval learnt from the deltas. A frame that sleeps (`App.wait`:
nothing to draw) asks for no vsync until it has slept, so an idle app
sleeps; the background, a lost window (Android's `onPause`, the window
destroyed) and an inactive app (iOS's `willResignActive`,
`didEnterBackground`) ask for none, and the first frame after them has a
delta of one period, not the time away. Nothing is allocated a frame.

Tests: `src/helder/os/FrameClock.test.hx` (the deltas, the period at 60
and 120 Hz, a missed frame, a pause, no allocation; natively and as
wasm32-wasi); on CI's emulator and simulator `tests/pack/Screen.hx`
(`tests/pack/android.sh`, `ios.sh`, checked by `tests/pack/screen.mjs`):
the window's size, scale and safe area, the display's frames (vsyncs at a
display's pace, nothing allocated over 120), the bars hidden, a rotation
(Android), the background and back.

A touch is its pointer's events alone, in the browser, on Android and on
iOS (`Pointers`, below): no mouse events or scrolls are made of it, so one
touch drives one thing; a program taps, drags, flings and pinches from the
pointers (helder.ui does: a tap clicks, the first finger's drag scrolls and
glides; the examples drag with any pointer, the mouse's left button too;
`helder.os.Glide` is a fling's glide). In the browser `browser.mjs`'s option
`touchAction` is the canvas's CSS `touch-action`: `'none'` by default
(every drag the program's); with `'pan-y'` a drag that starts vertical asks
the program first, once, at its first move: `Window.scrollsAt(x, y, dx,
dy)`, whether something where it started scrolls that way (helder.ui
answers from its scrollers, innermost first, and from what follows the
pointer's moves there: an `onPointerMove`; the cube takes only sideways
drags). Yes: the drag is the program's, the page held still (its
touchmoves cancelled); no, or no answer: the page scrolls instead, as at a
scroller's end (a canvas as wide as a phone's screen that the page must
scroll past), and the pointer is cancelled (`PointerCancel`). A tap
focuses the canvas. A mouse's press is captured by the canvas: a drag that
leaves it still moves, and its release still comes. On Android and iOS
the window sees the touches itself: no page to pan, every drag the
program's.

## Platform settings and clipboard

`helder.os.Settings` exposes read-only `helder.view` signals. Read them in
markup or an effect as `Settings.textScale()`, `Settings.reducedMotion()`,
`Settings.contrast()`, `Settings.dark()`, and `Settings.orientation()`.
In TypeScript, import `Settings` from `helder/os`.

Text scale is a multiplier, defaulting to 1. Contrast is `normal`, `more`,
`less`, or `custom` (a forced palette in the browser). Orientation is
`portrait`, `landscape`, or null before a viewport is known. It follows the
phone app, the browser viewport, or the first desktop window. The signals
update while `App.run` runs, within a second of a change, or from media
query events in JavaScript. Headless runs use the requested theme and
motion preference. Apps decide how to use the values.

iOS text scale is Dynamic Type at the body size. Android reads the font
scale and animation setting, with contrast on API 34 and later. Windows
reads the system text size, animation, and high-contrast settings.
Linux reads GNOME's preferences where its GSettings schemas are installed.
macOS exposes motion and contrast through AppKit. macOS and the web
report 1 for text scale.

`Clipboard.write(window, text)` and `Clipboard.read(window, callback)`
use the system's text clipboard. On Android, the activity must have focus
for reads. The callback receives null when Android supplies no text.

## App services

One API for each, the system's own underneath; where a system has none
the call answers its "unsupported" value (false, `Unsupported`, nothing)
and never throws. All of it is in TypeScript's `helder/os` too. Each is
linked only when used: an APK gets the Java classes (helder.pack.android.Glue)
and manifest entries a program's calls need, nothing else.

```haxe
Network.online();                                  // a signal, like Settings'
var s = Permissions.request(Camera);               // in a coroutine: Granted, Denied, Prompt, Unsupported
Share.share({text: "A course", url: "https://example.com/c/3"});
App.onOpen = urls -> route(urls[0]);               // a deep link (helder.json's "links"), or a file's path
var photo = Photos.take();                         // the camera's JPEG, null when cancelled
var here = Location.current({precise: false});     // null when denied or unknown
if (Biometrics.kind() != None && Biometrics.verify("Unlock your notes")) open();
var save = Paths.data() + "/save.json";            // the app's own directory, made
StatusBar.style(Light);                            // light icons over a dark app
```

| | iOS | Android | macOS | Windows | Linux | Web |
| --- | --- | --- | --- | --- | --- | --- |
| Network | yes | yes | yes | online only | yes | yes |
| Share | yes | yes | yes | false | false | yes |
| Permissions | yes | yes | yes | notifications | notifications | some |
| Notifications | yes | yes | app bundles | false | false | while open |
| Photos (pick) | yes | yes | open dialog | open dialog | none | file input |
| Photos (take) | yes | yes | null | null | null | file input |
| Location | yes | yes | app bundles | null | null | yes |
| Biometrics | yes | yes | yes | none | none | none |
| Paths | yes | yes | yes | yes | yes | null |
| DeviceInfo | yes | yes | yes | yes | yes | the browser's |
| StatusBar | yes | yes | nothing | nothing | nothing | nothing |
| Deep links | yes | yes | yes | none | none | the page's URL |

**Network**: `online` and `kind` (`none`, `wifi`, `cellular`, `wired`,
`other`), signals sampled as Settings are (about once a second while
`App.run` runs, and on coming back to the foreground).

| | |
| --- | --- |
| iOS, macOS | Network.framework's path monitor (its first path waited for, half a second at most) |
| Android | ConnectivityManager's active network and its capabilities (ACCESS_NETWORK_STATE and INTERNET added to the manifest) |
| Windows | `GetNetworkConnectivityHint` (Windows 10 2004 on; online, `other`, before); no kind but `other` |
| Linux | the default route (`/proc/net/route`, else IPv6's), Wi-Fi when its interface is wireless |
| Web | `navigator.onLine`, `navigator.connection.type` where there is one |

**Share**: `share({?text, ?url, ?files})`, a coroutine: whether the user
shared where the system tells, else whether the sheet was shown.

| | |
| --- | --- |
| iOS | UIActivityViewController over the window (an iPad's a popover at its centre); the user's answer. "Save Image" only with Info.plist's `NSPhotoLibraryAddUsageDescription` (`infoPlist`) |
| macOS | NSSharingServicePicker at the first window's centre: whether a service was chosen |
| Android | ACTION_SEND (SEND_MULTIPLE) in the chooser; files through org.hxmc.Files, a provider of the app's own (`<package>.hxmc.files`) serving this share's files alone, read-granted; true once shown |
| Web | `navigator.share` (files where `canShare` takes them); false without it |
| Windows, Linux | false (Windows' DataTransferManager is not used) |

**Permissions**: `status(p)` and the coroutine `request(p)` of `Camera`,
`Microphone`, `PhotoLibrary`, `Location` (while in use), `Notify` (their
strings, TypeScript's: `camera`, `microphone`, `photos`, `location`,
`notifications`): `granted`, `denied`, `prompt` (asking would show the
system's dialog), `unsupported`. A request only asks where the status is `prompt`. What a
program requests is declared by the build: Android's manifest entries,
and iOS's usage strings from helder.json's `targets.ios.usage`, a missing
one an error at the call.

| | |
| --- | --- |
| iOS | AVCaptureDevice, PHPhotoLibrary (read and write; limited is granted), CLLocationManager (when in use), UNUserNotificationCenter |
| macOS | the same; notifications only for an app bundle (unsupported for a bare executable) |
| Android | checkSelfPermission; asked through org.hxmc.Request, a transparent activity of the app's own (NativeActivity gets no answers); denied once asked and the system would not ask again. Photos: READ_MEDIA_IMAGES from 13, READ_EXTERNAL_STORAGE before; notifications: POST_NOTIFICATIONS from 13, granted before (unless turned off) |
| Web | `navigator.permissions` and `Notification.permission` for the status; requests by `getUserMedia` (camera, microphone) and `Notification.requestPermission`, unsupported for the others; photos unsupported |
| Windows, Linux | notifications granted, the others unsupported |

**Notifications**, local: `schedule({id, title, ?body, ?at, ?after})`
(at a `Date`, after seconds, or now; false where the system has none for
the app), `cancel(id)`, and `onOpen`, the id of the one tapped (the app
opened by it; queued until set, as `App.onOpen`). Asking to show them is
`Permissions.request(Notify)`'s. TypeScript programs give `after`
(seconds): `at`, a Haxe `Date`, has no TypeScript counterpart in the
API's bridge yet.

| | |
| --- | --- |
| iOS, macOS | UNUserNotificationCenter: a time interval's trigger (after), the calendar's (at); shown in front too (a delegate made at run time). macOS: an app bundle's only |
| Android | AlarmManager (exact while idle where the app may, else inexact) aimed at org.hxmc.Alarm, a receiver of the app's own that posts it in the channel "default" with the app's icon (the system's when it has none), the process running or not; a tap opens the app (org.hxmc.Main, singleTop) with the id. POST_NOTIFICATIONS and SCHEDULE_EXACT_ALARM added to the manifest |
| Web | the Notification API by a timer, while the page is open; a click focuses the page |
| Windows, Linux | false: Windows' toasts need an AppUserModelID and an installer's shortcut, Linux's a desktop file and D-Bus' notifications service; neither is helder's yet |

**Photos**: the coroutine `pick(?{max})`, the images picked as their
files' bytes (JPEG, PNG, HEIC...), at most `max` (1); none when cancelled.
No permission is asked.

| | |
| --- | --- |
| iOS | PHPickerViewController, images only, each result's image data |
| Android | MediaStore's ACTION_PICK_IMAGES (Android 13 on), else ACTION_GET_CONTENT of image/*, for a result through org.hxmc.Request; the content URIs read through the ContentResolver on a thread attached to the VM |
| macOS, Windows | the open dialog (FileDialog) filtered to images: one |
| Web | a hidden `<input type=file accept=image/*>` (multiple for more than one): call it from a user's gesture, or within a few seconds of one |
| Linux | none |

**Photos.take**, the camera: the coroutine `take(?{front})`, a photo the user takes as a
JPEG, null when cancelled or where there is no camera. iOS needs
helder.json's usage string `camera` (a build that calls it without one
fails at the call); Android's camera app takes the photo and needs no
permission (unless the manifest has CAMERA for another of the program's
requests: then it is asked for first).

| | |
| --- | --- |
| iOS | UIImagePickerController, its source the camera (front: the front camera where there is one), a delegate made at run time; UIImageJPEGRepresentation of the photo (0.9). The simulator has no camera: null at once |
| Android | MediaStore's ACTION_IMAGE_CAPTURE through org.hxmc.Request, EXTRA_OUTPUT a file of the app's cache served by org.hxmc.Files (write-granted to the camera app while it takes it); read on a thread of its own, then deleted. Front: the extras camera apps read (no standard one) |
| Web | the photo picker's file input with `capture` (`user` for front, else `environment`): a phone's camera, a desktop's file picker |
| macOS, Windows, Linux | null |

**Location**: the coroutine `current(?{precise})`, one fix, and
`watch(f, ?{precise})`, each fix on the app's loop until the function it
returns is called. A `GeoPosition` is `latitude`, `longitude`, `accuracy`
(metres), `altitude`, `heading`, `speed` (null where unknown) and `time`
(ms since 1970). The permission is `Permissions`' `Location`, asked for
while it is `Prompt`; null when denied or there is no fix. `precise:
false` asks for coarse accuracy.

| | |
| --- | --- |
| iOS, macOS | CLLocationManager, a delegate made at run time: requestLocation, or startUpdatingLocation while a watch lasts; coarse: kCLLocationAccuracyThreeKilometers. macOS: an app bundle's (a bare executable's request is never answered: null) |
| Android | LocationManager from the best provider enabled that the app may use (gps when precise and ACCESS_FINE_LOCATION is granted, else network): getCurrentLocation (API 30), else the last known fix under a minute old or requestSingleUpdate; a watch by requestLocationUpdates; their answers to org.hxmc.Locator. ACCESS_COARSE_LOCATION and ACCESS_FINE_LOCATION added to the manifest; coarse asks for COARSE alone |
| Web | `navigator.geolocation` (getCurrentPosition, watchPosition), which asks by itself |
| Windows, Linux | null |

**Biometrics**: `kind()`, `None`, `Face`, `Fingerprint` or `Other` (none
where nothing is enrolled), and the coroutine `verify(reason)`: whether
the user is verified, the system's prompt showing the reason. iOS needs
the usage string `faceid` (NSFaceIDUsageDescription).

| | |
| --- | --- |
| iOS, macOS | LocalAuthentication's LAContext: canEvaluatePolicy and biometryType, evaluatePolicy (LAPolicyDeviceOwnerAuthenticationWithBiometrics) |
| Android | the framework's BiometricPrompt (no androidx), the reason its title, the system's cancel; org.hxmc.Biometric its callback; BiometricManager.canAuthenticate (BIOMETRIC_WEAK from API 30) and the system's features for the kind. USE_BIOMETRIC added to the manifest |
| Windows, Linux, Web | `None`, false |

**Paths**: `data()` (persistent, the app's own), `cache()` (the system may
empty it), `temp()` and `documents()` (the user's: where they see the
app's files), each absolute and made when missing; null on the web. The
desktop's data and cache are under the app's name: macOS's bundle id,
else the executable's name. `Store` keeps its files under `data`'s place.

| | |
| --- | --- |
| iOS | NSFileManager's Application Support, Caches, Documents and temporaryDirectory of the app's container; Documents in the Files app (Info.plist's UIFileSharingEnabled and LSSupportsOpeningDocumentsInPlace, set by a build that calls `documents()`) |
| macOS | the same under ~/Library, data and cache in `<id>/`; ~/Documents |
| Android | the files directory (ANativeActivity's internalDataPath), getCacheDir (temp too), getExternalFilesDir(DIRECTORY_DOCUMENTS) |
| Windows | SHGetKnownFolderPath: `RoamingAppData\<name>`, `LocalAppData\<name>`, Documents; GetTempPathW |
| Linux | `$XDG_DATA_HOME/<name>` (~/.local/share), `$XDG_CACHE_HOME/<name>` (~/.cache), `$TMPDIR` (/tmp), user-dirs.dirs' XDG_DOCUMENTS_DIR (~/Documents) |

**DeviceInfo**: `get()`, `{model, manufacturer, os, osVersion, kind}`, kind
`Phone`, `Tablet`, `Desktop` or `Web`; "" where the system does not tell.

| | |
| --- | --- |
| iOS | hw.machine (the simulator's SIMULATOR_MODEL_IDENTIFIER), UIDevice's systemName, systemVersion and idiom |
| macOS | hw.model, kern.osproductversion |
| Android | android.os.Build's MODEL and MANUFACTURER, Build.VERSION.RELEASE; a tablet from a smallest width of 600 dp |
| Windows | RtlGetVersion; the registry's BIOS SystemProductName and SystemManufacturer |
| Linux | /sys/class/dmi/id's product_name and sys_vendor; /etc/os-release's NAME and VERSION_ID as the version |
| Web | `navigator.userAgentData`'s brand and platform, else the userAgent's; the vendor |

**StatusBar**: `style(s)`, `Light` (light icons, over a dark app), `Dark`
or `Auto` (the system's appearance, `Settings.dark`), and `hidden(h)`.
Nothing on the desktop and the web.

| | |
| --- | --- |
| iOS | the root view controller's preferredStatusBarStyle and prefersStatusBarHidden (methods added to its class at run time), setNeedsStatusBarAppearanceUpdate |
| Android | WindowInsetsController's APPEARANCE_LIGHT_STATUS_BARS and _NAVIGATION_BARS, statusBars() hidden or shown (API 30), else the decor view's SYSTEM_UI_FLAG_LIGHT_STATUS_BAR, _LIGHT_NAVIGATION_BAR and _FULLSCREEN; `Auto` follows `Settings.dark` |

**Deep links**: helder.json's `"links": {"schemes", "domains"}`
(helder.cli's README), each URL to `App.onOpen`, at launch too (kept until
it is set). Android: the VIEW intent the activity was started or brought
back with (org.hxmc.Main: NativeActivity, its onNewIntent the activity's
intent, read on resume). iOS: `application:openURL:options:` and a
universal link's `continueUserActivity`. macOS: the GetURL Apple event
(an app bundle's `CFBundleURLTypes`). Windows and Linux: none (a URL
handler is an installer's registration); the web: the page's own URL.

## Wayland

`helder.os.wayland`: libwayland-client, libwayland-egl, libxkbcommon and
libwayland-cursor loaded at run time (`Dl`: a machine without them runs
X11's). The protocols' bindings are generated by helder's own scanner from
their XML (`Scanner.hx`, run on Eval: `haxe -cp src --run
helder.os.wayland.Scanner src/helder/os/wayland/protocol <xml>...`; checked
in, `bun run test wayland` makes them again from the system's XML and
compares): core, xdg-shell, xdg-decoration, viewporter, fractional-scale,
cursor-shape, text-input-v3, presentation-time, single-pixel-buffer and
linux-dmabuf (the last three helder.ui's system layers', WlLayers), each interface an abstract over its proxy with a method
per request (`wl_proxy_marshal_array_flags`, the arguments as wl_argument
slots) and an events class of handlers (one C dispatcher,
`wl_proxy_add_dispatcher`), the wl_interface and wl_message structs made
at run time (`Interfaces`). `WaylandWindow`: an xdg_toplevel on a
wl_surface, GL's EGL on a wl_egl_window (`SurfaceKind.Wayland`; its swap
interval 0, the loop pacing itself), the buffer at the compositor's scale
(fractional-scale and the viewport's destination, else wl_surface's
preferred_buffer_scale or the outputs' integer scale), the compositor's
decorations where xdg-decoration agrees, else helder's own bar above the
content (a wl_shm subsurface: minimise, maximise, close; a press moves the
window, a double press maximises; no title text in it yet), fullscreen
and back to the windowed size; the seat's keyboard (xkbcommon's keymap,
KeySyms as X11's, its text, repeat), pointer (value120 wheel notches, a
touchpad's pixels; cursor-shape's shapes, else the theme's images) and
touch (Pointers); wl_data_device's clipboard text and file drops
(text/uri-list). Not yet: an input method (text-input-v3), xdg_popup
(helder's menus are drawn in the window), edge resizing of helder's
decorations. Tests: `src/helder/os/wayland/Wayland.test.hx` (the structs,
requests and events against a recorder: no compositor), and the wayland
lane under a headless weston at scale 1 and 2 (tests/os/WaylandTest.hx, the
viewer, a screenshot; helder.ui's system layers under its kiosk shell,
tests/ui/WaylandLayersWindow.hx).

## Pointers: the mouse, fingers and pens

One stream for every pointer, as the DOM's Pointer Events: `PointerDown`,
`PointerMove`, `PointerUp` and `PointerCancel` events carry `e.pointer`, a
`Pointer` (one per slot of `Pointers`, preallocated: nothing is allocated
per event or per frame), already updated: its `id` (the slot: 0 the
mouse, fingers and pens the lowest free one from 1, stable while it is
down), `type` (`Mouse`, `Touch`, `Pen`), `window` (and its `scale`), `phase`, `down`,
`primary` (the first finger down while no other was, or the mouse), `x`,
`y` (window pixels, sub-pixel where the system has them), `startX`,
`startY`, `dx`, `dy` (its motion this frame), `pressure`, `tiltX`, `tiltY`,
`buttons`, `time`, `press` (its press's number: a press and its release
within one step still count), `owner` (who took it: nobody, ui, a game
control), and the samples the system batched before the event
(`samples`, `sampleX(i)`, `sampleY(i)`: Android's
history, iOS's coalesced touches, the browser's coalesced events and the
moves between two frames).

```haxe
App.run(() -> {
	for (i in 0...Pointers.count) {         // in a frame: the pointers down, in down order
		var p = Pointers.at(i);
		if (Pointers.justDown(p)) grab(p.id);
		look(p.dx, p.dy);
	}
}, e -> switch e.kind {
	case PointerDown if (e.pointer.type == Touch): ...;
	case PointerCancel: release(e.pointer.id);  // the system took it: no tap, let go
	case _:
});
```

`App.run`'s turns begin a frame of `Pointers` (`Pointers.step`: `dx`,
`dy`, `justDown`, `justUp` start again) before their events. A cancel is a
real ending: the system took the pointer (a call, a system gesture, the
browser panning the page), it must not tap and what it held lets go.

The back ends: Android's `MotionEvent`s (every pointer, its tool: a
finger, a stylus or a mouse; `ACTION_CANCEL` and a palm's
`FLAG_CANCELED` cancel), iOS's `UITouch`es (`multipleTouchEnabled`; a
pencil is a pen; the background cancels), the browser's Pointer Events
for touches and pens (captured by the canvas, without the browser's
mouse events: a pen is no longer the mouse there), the mouse everywhere
as slot 0 after its own `Mouse*` events (a move without a button too).
Touch screens on Windows and X11 (`WM_POINTER`, XInput2) come later.

A finger or a pen has its pointer's events alone: no `MouseMove`,
`MouseDown`, `MouseUp` or `Scroll` is made of it (the mouse emulation and
`TouchDrag` before pointers are gone). helder.ui's arena taps, scrolls and
pinches from the pointers; helder.scene's `InputMap` makes the first finger
or pen down that no control took the left button while it is down
(`Mouse(1)`, `Region`).

Tests: `src/helder/os/Pointers.test.hx` (slots, frames, samples, cancels,
no allocation: natively and as wasm32-wasi, the test lane),
`bun run test touch-web` (`tests/os/PointersWeb.hx` in headless
Chromium: two fingers, a pen and the mouse through the DevTools
protocol, samples, a cancel, a tap and a drag without mouse events or
scrolls, a wheel with Control prevented and a plain one not, Safari's
gesture events made by hand), `src/helder/os/Glide.test.hx` (a fling's glide). Android's and
iOS's on CI's emulator and simulator: `tests/gfx/android.sh` and `ios.sh`
(the cube's Spin on a finger's pointer: a tap's PointerDown and PointerUp,
a drag held turning the cube and holding it still while it rests, a
fling's flick, never a mouse event or a scroll from a touch) and
`tests/os/android-touch.sh` (a drawn ui's fling: the box following the
finger, gliding on).

## Gamepads

`Gamepads` (polled once a step, after `enable()`: helder.scene's
`InputMap` reads them) has up to four pads in the browser's standard
layout. The back ends: the browser's Gamepad API, Linux's
`/dev/input/js*`, XInput on Windows, GameController on macOS and iOS
(loaded at the first poll; on macOS read while the window is not key
too), and on Android the input queue's gamepad and joystick events, a
slot for each device (a pad's keys are then no UI keys: B is not Back).
`Gamepads.set` feeds a pad from the program (an on-screen stick).

## Localization

Read `Locale.current()` for the device's BCP 47 language tag and
`Locale.preferred()` for its ordered list. The current tag is a read-only
signal. Native apps refresh it with the other system settings, including
after foregrounding. Browsers also follow `languagechange`. Linux reads
`LANGUAGE` and the message locale from `LC_ALL`, `LC_MESSAGES` or `LANG`.
An empty list falls back to `en-US`.

`Format.number(value, options)` formats a decimal, a percentage of a
ratio (`percent: true`), or an amount in an ISO currency code
(`currency: "EUR"`). Set `decimals` to fix the number of fractional digits.
`Format.date(date, options)` formats a local date, time or both. Set
`date` and `time` to `Short`, `Medium`, `Long` or `Full` in Haxe,
and to their lowercase strings in TypeScript. Omit both for a medium
date. Both functions accept a `locale` override and otherwise use
`Locale.current.peek()`. The Linux fallback uses decimal points,
comma grouping and ISO-like dates and times. To track a formatted
value in a view, pass `{locale: Locale.current()}`.

`Plural.category(locale, n)` returns one of `zero`, `one`, `two`, `few`,
`many` or `other` using the same [CLDR cardinal rules](https://unicode.org/reports/tr35/tr35-numbers.html#Language_Plural_Rules)
on all targets. The built-in rules cover common languages, with `other`
for languages outside the table. Counts are numbers, so `1.0` and `1`
have the same category.

### String catalogues

Put one UTF-8 JSON file per tag in a folder such as `locales/`. Each
file is a flat object of message IDs to strings. Dots in a key become
fields in the Haxe accessor. For example, `locales/en.json` can contain:

```json
{
  "title": "Messages",
  "hello": "Hello, {name}!",
  "cart.items": "{count, plural, =0 {Empty cart} one {# item} other {# items}}"
}
```

```haxe
import helder.asset.Asset;

var t = Asset.strings("locales");
t.title();
t.hello({name: "Ada"});
t.cart.items({count: 3});
```

```ts
import { strings } from "helder/asset";

const t = strings("locales");
t.get("title");
t.get("hello", {name: "Ada"});
t.get("cart.items", {count: 3});
```

The first filename alphabetically defines the keys and parameter types.
Set `"locale": "en"` in `helder.json` to choose the default explicitly.
Missing translations emit a compile-time warning. Inconsistent
placeholder names or types are errors. The supported syntax is
`{name}` for strings and a cardinal plural with a numeric argument.
Plural cases require `other`, can include exact integers such as `=0`,
and replace `#` with the formatted count.

A message looks for its key in the exact tag, then its language, then
the default. When the locale changes, views that read a message update.
The JSON files use [helder's asset bundling](../asset/README.md), with
catalogues preloaded on the web and a message's readers updated on
reload under `helder dev`. TypeScript uses `get` with named parameters.

## Fast refresh: `helder.dev.Hot`

Under `helder dev` (`-D hxmc.dev`) a
reload is a fresh start of the new build with the old one's state carried
over by key. `helder.dev.Hot` is the public layer state libraries use for it
(helder.view's signals included): `onSnapshot` and `onDispose`, `save` and
`load` by key with the type's hash (`typeOf((_ : T))`), `here()` and
`scope(name, f)` for keys, `keep(key, init)`, `reloading`. The app loop
reads the dev server's messages (`App.run`'s turns; an idle loop wakes
every 50 ms) and reports the first frame. Without `-D hxmc.dev` every call
compiles to nothing.

## Downloads

`Downloads.save(name, bytes, type)`: a file handed to the user where a
browser puts what it downloads: in the browser the page's own download
(a Blob's URL on a link clicked), on macOS, Linux and Windows the user's
Downloads folder under a name not taken yet ("Font 2.ttf"); it answers
the path (the name in a browser), null on phones or when it could not be
written. A save dialog is for later.

## Places

`Places.user()`: the user's existing Home, Desktop, Documents, Downloads,
Pictures, Movies (Videos on Windows) and Music folders, in that order.
Each has a `kind`, a display `name` and its `path`. macOS and Windows ask
the system for localized names. Linux reads XDG's `user-dirs.dirs` and
uses the folder's name.

`Places.volumes()`: the mounted volumes a user can browse, with `name`,
`path`, `total` and `free` in bytes (zero when unknown), and `removable`,
`network` and `root` flags. The system volume comes first. macOS uses
Finder's browsable volumes, Windows its logical drives, and Linux the
root filesystem and mounts under `/media`, `/run/media` or `/mnt`, plus
network mounts under `/home`.

## Trash

`Trash.available()` is true on macOS, Windows and Linux. `Trash.move(path)`
moves a file or folder to the system trash and throws if the move fails.
It returns the item's new path on macOS and Linux. Windows' Recycle Bin
answers null. Linux uses the freedesktop trash, keeping the original path
and local deletion time in a `.trashinfo` file and renaming the item on
its own filesystem.

On the web, phones and headless runs, Places gives empty arrays and Trash
is unavailable. Both APIs are also exported from `helder/os` in TypeScript.

## Store

`Store.open(name)`: a small key-value store of strings kept between runs
(settings, a save), read when opened and written through at each `set`,
`remove` or `clear` (a temporary file renamed over the old one): a JSON
file in the app's data directory (Linux `$XDG_DATA_HOME/<name>/store.json`,
macOS `~/Library/Application Support/<name>/`, Windows `%APPDATA%\<name>\`,
Android the app's files directory, iOS its `Library/Application Support`),
localStorage on the web (the item `helder.store/<name>`). A damaged or
missing file opens empty; `written` says whether the last change was
kept. `Store.test.hx` (natively and as wasm32-wasi).

## Audio

A pull model: the system asks for samples and a callback fills them.

```haxe
var out = Audio.open({sampleRate: 48000, channels: 2, frames: 512}, (buffer:Ptr<Float32>, frames:Int) -> {
	for (i in 0...frames) {                   // interleaved, zeroed before the call
		var v = 0.25 * Math.sin(phase);
		buffer[i * 2] = v;
		buffer[i * 2 + 1] = v;
		phase += step;
	}
});
out.start();          // the callback runs on the audio thread from now on
out.stop();           // what the system queued is dropped; start plays again
out.close();
out.sampleRate; out.channels; out.frames; out.latency; // as the system gave them
```

`examples/tone/Tone.hx` plays a 440 Hz sine for two seconds. Effects and
music: `Sfx.open()` mixes sounds made up front (`add(samples)`, mono at
`Sfx.RATE`; a file decoded whole by `Sound.decode`: WAV or Ogg Vorbis) on
a few voices, `play(id, gain, rate, pan)` once or `loop(...)` until
`stop(handle)` (`gain(handle, g)`, `pan(handle, p)` meanwhile), and music:
`music(bytes, fade, gain, loop)` streams an Ogg Vorbis file, decoded a
packet at a time on the audio thread from its compressed bytes, resampled
to the output's rate, crossfading from what played over `fade` seconds
(`stopMusic(fade)`; `volume` the effects', `musicVolume` the music's).
Nothing is allocated on the audio thread (`Sfx.test.hx`, `Vorbis.test.hx`;
Little Skies' sounds, helder/little-skies).

Vorbis (`Vorbis.hx`, the Vorbis I specification, some 900 lines): floor 1,
residues 0 to 2, any channels; floor 0, unused by encoders since 2002, is
refused. `open` parses the headers and allocates every buffer; `next()`
decodes a packet (the IMDCT through an n/4-point FFT) into `out`,
`rewind()` loops; a container's stream (helder.media's Matroska) is
`Vorbis.headers(config)` (its three headers, Xiph-laced), then
`feed(packet)` a packet at a time. Ogg Vorbis rather than a simpler codec: music is
distributed in it, at a quarter of the bytes of ADPCM or QOA for the same
quality. Its samples match ffmpeg's decoder within a float's rounding
(about 1e-7; the tests' files are ffmpeg's libvorbis), some 300 times
faster than real time natively. `frames` is a hint:
`out.frames` is the most frames a callback is asked for (the system's
period or buffer), `out.latency` the seconds from a callback's samples to
the output, as the system reports them.

| Target | Back end | The audio thread |
| --- | --- | --- |
| Linux | ALSA (`libasound.so.2`, loaded with `dlopen` when an output opens: the glibc mode), the `default` PCM (PipeWire's or PulseAudio's plugin on most desktops), floats through ALSA's plug layer | ours: pulls a period, `snd_pcm_writei` (blocks while ALSA's buffer is full) |
| macOS | CoreAudio's default output unit (AudioToolbox) | ours: fills a ring in native memory; CoreAudio's I/O thread runs a `@:hxmc.noGc` render callback that copies from it |
| iOS | RemoteIO (an AudioUnit of AudioToolbox), after AVAudioSession's category (`session`: `"ambient"` by default, which the silent switch silences; `"playback"`), its preferred buffer a period | as macOS's: the ring, RemoteIO's render callback copying from it |
| Android | AAudio (`libaaudio.so`, loaded with `dlopen` when an output opens; API 26+), low-latency, shared, usage game, two bursts of buffer | as macOS's: the ring, AAudio's `@:hxmc.noGc` data callback copying from it and posting a semaphore |
| Windows | WASAPI, shared mode, event driven (COM through vtables), floats converted by the audio engine | ours: waits for WASAPI's event, fills what the buffer has free |
| Browser | WebAudio: an AudioWorklet node fed chunks the page posts it | none: the main thread, when the worklet has played a chunk |

Phones: the app's lifecycle holds the outputs (`helder.os.AppAudio`):
Android's activity paused, or iOS's app in the background, stops the running
ones, and coming back starts them again (`Audio.held`). On Android a stream
disconnected (headphones unplugged, a Bluetooth device gone: AAudio's error
callback) is closed by the audio thread and another opened where the system
routes now. On iOS an interruption (a call, an alarm:
AVAudioSessionInterruptionNotification) holds them the same way, and its
end makes the session active and starts them again. In the browser a hidden
page suspends its contexts until it shows again.

The callback is ordinary Haxe on one of the runtime's threads, but it runs
against a deadline: preallocate, do not allocate (that can start a
collection, and any thread's collection pauses this one), lock, block or
print there, and never stop or close the output from it (both wait for
the audio thread). CoreAudio calls back on a thread the runtime does not
know, where only `@:hxmc.noGc` code may run (hxmc's docs/plans/lowlevel.md,
"Callbacks"): that is why it only copies from the ring. In the browser the
module's memory is not shared with the worklet's thread, so each chunk is
copied and posted, keeping about 50 ms queued; the callback may close the
output there. AudioWorklet rather than ScriptProcessorNode: the latter is
deprecated and runs its callback on the main thread with the output
waiting on it, where a busy main thread is a glitch either way, but the
worklet keeps playing what it has. Browsers start audio after a user
gesture: a context made before resumes on the page's next click or key.

The device: `null` is the system's default; `"file:PATH"` (Linux and
macOS) plays to no device, what the system's API renders written to PATH
as raw interleaved floats (ALSA's file plugin over its null device;
CoreAudio's generic output unit rendered at the clock's pace); on Linux
any other name is ALSA's (`"null"`, `"hw:0"`). In the browser,
`browser.mjs`'s option `audioContext` gives the context (an
`OfflineAudioContext` in tests). An output that has no device throws
`helder.os.audio: no output device (...)`.

Tests (`tests/os/AudioTest.hx`): a known signal through each back end's real
API, the samples that reach it compared with the signal, the callbacks'
count and rate. `bun run test audio` (`tests/os/audio.sh`): ALSA's null and file
devices; CoreAudio's file device, then the default output where there is
one; WASAPI on the default endpoint where there is one, or under Wine
(`AUDIO_TARGET=windows-x86_64`) through winealsa to an ALSA file.
`bun run test audio-web` (`tests/os/web.mjs`): headless Chromium, realtime (the
rate) and an `OfflineAudioContext` (the rendered samples, exact).
Phones (`tests/pack/AudioCheck.hx`, in CI's emulator and simulator jobs:
tests/pack/android.sh, ios.sh): an output on AAudio or RemoteIO for two
seconds, its line counting the callbacks, "audio: started" once the
device pulled half a second's worth.
