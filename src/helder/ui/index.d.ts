// helder.ui for TypeScript programs (helder.typescript): windows and their
// markup (see helder/view), the events handlers are given, the keys. Each
// class is the Haxe class `__haxe` names. The neutral elements (view, text,
// button...) take any attribute, their handlers given ui's events.
//
// Generated from helder's Haxe types (helder.typescript.api.Declarations: node
// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.
import type {Image} from "helder/asset";
import type {Cursor, Edges, PointerType, Rect} from "helder/os";
import type {Read, RootView, Signal, View} from "helder/view";

declare const __haxe: {UiWindow: "helder.ui.UiWindow", Event: "helder.ui.Event", Key: "helder.ui.Key", VirtualScroll: "helder.ui.VirtualScroll", Selection: "helder.ui.Selection", GridScroll: "helder.ui.GridScroll", Clock: "helder.ui.Clock", WebViewEvent: "helder.ui.platform.WebViewEvent", WebContent: "helder.ui.platform.WebContent", WebResponse: "helder.ui.platform.WebResponse", Node: "helder.ui.Node", TextNode: "helder.ui.TextNode", UiFlow: "helder.ui.view.UiFlow", SafeArea: "helder.ui.SafeArea", Router: "helder.ui.nav.Router", DataGrid: "helder.ui.controls.DataGrid", EditableText: "helder.ui.controls.EditableText", GridColumn: "helder.ui.controls.GridColumn", GridTheme: "helder.ui.controls.GridTheme", Icons: "helder.ui.controls.Icons", Pager: "helder.ui.controls.Pager", TextArea: "helder.ui.controls.TextArea", TextField: "helder.ui.controls.TextField", WindowButtons: "helder.ui.controls.WindowButtons", Eased: "helder.ui.controls.Eased", Look: "helder.ui.controls.Look", Press: "helder.ui.controls.Press", Standard: "helder.ui.controls.Standard", Toggle: "helder.ui.controls.Toggle", CodeActions: "helder.ui.code.CodeAction.CodeActions", CodeCompletion: "helder.ui.code.CodeCompletion", CodeEditor: "helder.ui.code.CodeEditor", CodeLanguage: "helder.ui.code.CodeLanguage", SyntaxLanguage: "helder.ui.code.CodeLanguage.SyntaxLanguage", CodeLanguages: "helder.ui.code.CodeLanguage.CodeLanguages", Sel: "helder.ui.code.CodeModel.Sel", Decoration: "helder.ui.code.CodeModel.Decoration", CodeDiagnostic: "helder.ui.code.CodeModel.CodeDiagnostic", CodeModel: "helder.ui.code.CodeModel", CodeTheme: "helder.ui.code.CodeTheme", CodeView: "helder.ui.code.CodeView", Rope: "helder.ui.code.Rope", SqlLanguage: "helder.ui.code.SqlLanguage", tone: "helder.ui.controls.Look.tone", Surface: "helder.ui.UiWindow.Surface", VirtualList: "helder.ui.view.UiFlow.VirtualList", VirtualGrid: "helder.ui.view.UiFlow.VirtualGrid", Stack: "helder.ui.nav.Screens.Stack", NavScreen: "helder.ui.nav.Bar.NavScreen", NavButton: "helder.ui.nav.Bar.NavButton", Sheet: "helder.ui.nav.Sheets.Sheet", pager: "helder.ui.controls.Pager.create", windowControlsSide: "helder.ui.controls.WindowButtons.side", item: "helder.ui.menu.Menus.menuItem", separator: "helder.ui.menu.Menus.menuSeparator", submenu: "helder.ui.menu.Menus.menuSubmenu", role: "helder.ui.menu.Menus.menuRole", popup: "helder.ui.menu.Menus.popup", resolve: "helder.ui.menu.Menus.menuResolve", Popover: "helder.ui.view.UiFlow.Popover", MenuBarView: "helder.ui.view.UiFlow.MenuBarView", Pages: "helder.ui.controls.Pager.Pages", WindowControls: "helder.ui.controls.WindowButtons.WindowControls", Button: "helder.ui.controls.Standard.Button", PathBar: "helder.ui.controls.Standard.PathBar", Checkbox: "helder.ui.controls.Standard.Checkbox", Switch: "helder.ui.controls.Standard.Switch", Slider: "helder.ui.controls.Standard.Slider", Segmented: "helder.ui.controls.Standard.Segmented", Tooltip: "helder.ui.controls.Standard.Tooltip", Themed: "helder.ui.controls.Standard.Themed", __module: "helder.ui.TypeScript"};

// A colour as 0xAARRGGBB (straight alpha), helder's one colour: ui's,
// canvas' and sprite's (TypeScript's Color: a number or a CSS string).
// From an Int literal written 0xRRGGBB it is opaque only through rgb():
// `Color.rgb(0x3366ff)`; `Color.rgba(0x3366ff, 0.5)`; TRANSPARENT is 0. A
// CSS string converts too, a literal's parsed when compiled (`var c:Color
// = '#3366ff'`), another's when run (parse). A token reference
// (Color.token, "var(--primary)", "var(--ring)/50") stands for a style
// sheet's colour of that name (StyleSheet), resolved when a rule using it
// is applied: drawn as it is, it is transparent (its alpha is 0; its other
// bytes name the token and its alpha, so a transparent colour with any
// other byte set is one); "currentColor" is one, the text's colour where
// it is applied, and so are the system colours "Canvas" and "CanvasText"
// (a sheet's colours of those names, else the browser's, light or dark).
// A shader's colour is a Vec4 (toVec4).
export type Color = number | string;

export type EventType = "pointer-down" | "pointer-up" | "pointer-move" | "pointer-enter" | "pointer-leave" | "click" | "wheel" | "key-down" | "key-up" | "text-input" | "composition" | "focus" | "blur" | "drag-start" | "drag-over" | "drag-leave" | "drop" | "drag-end" | "focus-in" | "focus-out" | "input" | "pointer-cancel" | "lost-pointer-capture" | "resize" | "submit";

export type TextAlign = "left" | "center" | "right" | "justify";

// How an ImageNode's image fills its content box (CSS's object-fit)
export type ImageFit = "fill" | "contain" | "cover" | "none";

// whether the pointer finds a node (CSS's pointer-events): None lets it
// through to what is under it; inherited, so a descendant can be Auto again
export type PointerEvents = "auto" | "none";

// what a menu shows an action as, from the handler that would take it
export type ActionState = "unhandled" | "disabled" | "enabled" | "checked" | "unchecked";

export type Placement = "below" | "above" | "right" | "left" | "center" | "manual" | "point" | "top-left" | "top-right" | "bottom-left" | "bottom-right";

// One menu model for the menu bar and context menus (Menus): items bound
// to actions (helder.ui.actions), each shown with the keys the keymap binds
// to it and enabled or checked as the handler that would take it says
// (Ui.actionState, from the focus, or the node a context menu is for);
// separators, submenus, and roles: the standard items each platform has
// (StandardAction's, in the platform's place where it has one: macOS's
// application menu for About and Quit, its Window menu; its text editors'
// copy: and paste:).
export declare class MenuItem {
	private readonly menuItem: never;
}

// An SVG document for icons and drawings: parsed once (Svg.parse), drawn
// into an Image at any size (the Image's drawing: this, for a writer's vectors; render: the viewBox fitted as
// preserveAspectRatio says, xMidYMid meet by default). The static subset
// icon sets use: svg, g, path (all of its data, arcs as cubic curves), rect
// (rounded), circle, ellipse, line, polyline, polygon; fill and stroke (a
// colour: hex, rgb(), rgba(), CSS's names, currentColor: render's color;
// none; linear and radial gradients: their units, transform, spread and
// stops, href'd ones), their opacities, opacity (a group's composited as
// one), fill-rule, stroke-width, stroke-linecap, stroke-linejoin,
// stroke-miterlimit, stroke-dasharray, stroke-dashoffset, transform; use
// (of an element or a symbol, its viewBox fitted, clipped to its
// viewport, as a nested svg is); clip-path (a clipPath's shapes, in user
// units); presentation attributes, style="" and the inherited ones passed
// down; lengths in percentages of the viewport. Not drawn: text, images,
// patterns (a pattern paint draws nothing), masks, filters, markers, a
// <style> element's rules; defs, title and the like are skipped. paint
// draws it into any Painter as paths (a PDF's vectors), sized as CSS
// sizes an image (naturalWidth, naturalHeight, ratio).
export declare class Svg {
	private readonly svg: never;
}

export type VirtualListProps<T, K> = { each: Read<T[]>; children: (arg0: Read<T>, arg1: number) => unknown; by?: (arg0: T) => K; keyed?: boolean; estimate?: number; itemHeight?: number; height?: number; overscan?: number; keep?: number; selected?: Signal<K | null>; onActivate?: (arg0: number[]) => void; label?: string; ref?: (arg0: VirtualScroll) => void; tag?: string; selection?: Selection; selectMode?: Read<boolean>; onContextMenu?: (arg0: number, arg1: number, arg2: number) => void; textOf?: (arg0: T) => string };

// (a route's params as its path names them: "/product/:id" gives {id: string})
export type RouteParams<P> = P extends `${string}:${infer K}/${infer R}` ? {[k in K]: string} & RouteParams<`/${R}`> : P extends `${string}:${infer K}` ? {[k in K]: string} : {};

// how a Stack's screens come and go: the platform's slide (iOS's and
// macOS's from the right edge over the one below; Android's a short slide
// and a fade), a fade (the desktop's and the web's), or none
export type StackTransition = "slide" | "fade" | "none";

// How much room a screen has, by its width in points (UI pixels), as
// iOS's and Android's window size classes: Compact under 600 (a phone, a
// narrow browser tab), Medium to 1024 (a tablet upright, a foldable, split
// view, a narrow desktop window), Expanded from 1024 (a tablet on its side,
// a desktop). current is the current screen's (ScreenContext.sizeClass: its
// surface's, the Ui made last in it as it resizes, a window's, a story's),
// a signal: markup that reads it follows it.
//
//   <Switch>
//     <Match when={SizeClass.current() == Compact}><PhoneShell/></Match>
//     <Match when={true}><DesktopShell/></Match>
//   </Switch>
export type SizeClass = "compact" | "medium" | "expanded";

// where a sheet rests: about half the window's height (Medium), or all of
// it but a strip at the top (Large)
export type Detent = "medium" | "large";

export type NavScreenProps = { title: Read<string>; large?: boolean; subtitle?: Read<string>; leading?: unknown; trailing?: unknown; header?: unknown; bottom?: unknown; scrolls?: boolean; bars?: Read<boolean>; tag?: string; children?: unknown };

export type SheetProps = { open: Read<boolean>; onDismiss?: () => void; detents?: Detent[]; detent?: Signal<Detent>; anchor?: () => Node | null; popover?: boolean; label?: string; tag?: string; children?: unknown };

// the default look's variants
export type BaseVariants = { button_variant: { primary: boolean; secondary: boolean; outline: boolean; ghost: boolean; danger: boolean }; button_size: { sm: boolean; md: boolean; lg: boolean }; checkbox_variant: {}; checkbox_size: {}; switch_variant: {}; switch_size: {} };

// The controls' props, V the look whose variants and sizes they take
// (Look<V>: Look.base's for Standard's, a look's own for look.Button).
// children: what a button shows (text, or views); label: its name for
// assistive technology (an icon alone's), a checkbox's and a switch's
// text beside it. checked with onChange: the caller's state; neither: the
// control's own.
export type ButtonProps<V> = { children?: unknown; label?: string; icon?: Svg; variant?: import('./style').Axis<V, 'button_variant'>; size?: import('./style').Axis<V, 'button_size'>; disabled?: Read<boolean>; selected?: Read<boolean>; onPress?: () => void; tag?: string };

export type CheckboxProps<V> = { label: string; checked?: Read<boolean>; indeterminate?: Read<boolean>; onChange?: (arg0: boolean) => void; disabled?: Read<boolean>; variant?: import('./style').Axis<V, 'checkbox_variant'>; size?: import('./style').Axis<V, 'checkbox_size'>; tag?: string };

// a suggestion: what it shows, a quieter detail (a kind, a type), what it puts in (else its label)
export type Completion = { label: string; detail?: string; insert?: string };

// suggestions for the word that starts at from and ends at the caret
export type Completions = { from: number; items: Completion[] };

// The pointer's shape over a node (Style.cursor): helder.os's, whose Auto
// takes the parent's (the root's: Default); a window shows the hovered
// node's (Ui.cursor).
export type Cursor = Cursor;

// a menu of the menu bar; role Window: the window menu (macOS's: its own
// items after Minimize, Zoom and Close)
export type Menu = { label: string; items: MenuItem[]; role?: "about" | "quit" | "hide" | "undo" | "redo" | "cut" | "copy" | "paste" | "select-all" | "minimize" | "zoom" | "fullscreen" | "close" | "window" };

export type PathBarProps = { segments: Read<PathSegment[]>; onNavigate: (arg0: number) => void; onSubmit: (arg0: string) => void; onSeparator?: (index: number, anchor: Node) => void; editable?: boolean; text?: Read<string>; editing?: Signal<boolean>; size?: 'sm' | 'md'; tag?: string; label?: string };

export type PathSegment = { label: string; icon?: Svg };

// An item of a native menu (PlatformViews.menu): its label, its shortcut
// as shown ("Ctrl+C", "⌘C") and as keys (a menu that takes its keys
// itself: macOS's key equivalents), whether it is disabled or checked; a
// separator; a submenu's items. id: what the menu reports when it is chosen.
// role: a standard item's (helder.ui.menu.MenuRole: "about", "quit",
// "copy", "window" for a menu bar's window menu...), which a platform puts
// in its own place or gives its own behaviour (macOS).
export type PlatformMenuItem = { id: number; label: string; shortcut?: string; keys?: unknown; disabled?: boolean; checked?: boolean; separator?: boolean; items?: PlatformMenuItem[]; role?: string };

export type Refs = { canvas?: Color; surface?: Color; raised?: Color; well?: Color; hover?: Color; press?: Color; fill?: Color; fillHover?: Color; fillPress?: Color; rail?: Color; railHover?: Color; line?: Color; edge?: Color; edgeStrong?: Color; fg?: Color; fg2?: Color; fg3?: Color; accent?: Color; accentStrong?: Color; accentSoft?: Color; accentFg?: Color; accentInk?: Color; focus?: Color; focusSoft?: Color; danger?: Color; dangerStrong?: Color; dangerSoft?: Color; dangerFg?: Color; success?: Color; warning?: Color; info?: Color; knob?: Color; scrim?: Color; shadow?: Color; density?: "comfortable" | "compact"; font?: string; display?: string; mono?: string; size?: number; small?: number; large?: number; title?: number; medium?: number; radius?: number; radiusPanel?: number; radiusSurface?: number; controlSm?: number; control?: number; controlLg?: number; padSm?: number; pad?: number; padLg?: number; gap?: number; icon?: number; box?: number; track?: number; trackHeight?: number; thumb?: number; hoverTime?: number; toggleTime?: number; openTime?: number; floatTime?: number; dialogTime?: number; exitTime?: number; pressScale?: number; disabledOpacity?: number };

// A theme's rule (StyleSheet): the style a node with this slot (Node.slot,
// the name of the part it is: "button", "switch-thumb"), variant and size
// (when given) takes while every state in when holds ("hover", "active",
// "focus", "focus-visible", "disabled", "placeholder", "dark", an
// attribute "data-state=checked" or a bare "data-disabled", another node's:
// "group:hover", "peer:checked", "has:data-state=open", "first", "last",
// "not:x", as Rules reads them). Later rules
// win, property by property, as CSS's source order; the node's own style
// wins over all of them. Colours may be token references (Color.token,
// "var(--primary)", "var(--ring)/50"), resolved with the sheet's colours.
export type Rule = { slot: string; variant?: string; size?: string; when?: string[]; style: import('./style').StyleProps };

// A theme: its rules (Rule) and the colours their token references name,
// light and dark (names without the dashes: "primary", "ring"). Installed
// per window (Ui.theme) or for a subtree (Node.theme, the nearest
// winning); Ui.dark picks the dark colours and makes "dark" hold. Its
// lengths are what Length.token references name ("radius"), light or dark.
// Its markers are the group and peer markers its slots carry, "group/item
// peer" ("group" unnamed), as an element's class: a rule's group: and peer:
// states find them as they find a node's group and peer attributes. Its
// motion is its palette of motion tokens (helder.ui.motion.Curve: "snappy",
// "default", "calm", "lead", "fade", or names of its own), over the
// built-in ones, for the nodes it themes (motion="calm").
export type StyleSheet = { rules: Rule[]; light?: unknown; dark?: unknown; lengths?: unknown; markers?: unknown; motion?: unknown };

// <Surface>'s props (UiWindow.Surface)
export type SurfaceProps = { title?: Read<string>; width?: Read<number>; height?: Read<number>; theme?: Read<StyleSheet>; background?: Read<Color>; backdrop?: Read<"none" | "blur" | "mica" | "sidebar" | "glass">; clickThrough?: Read<boolean>; shadow?: Read<boolean>; dark?: Read<boolean>; onClose?: () => void; onDrop?: (files: string[], x: number, y: number) => void; ref?: (arg0: UiWindow) => void; antialias?: boolean; titlebar?: "standard" | "inset" | "none"; scrollbars?: string; onTop?: Read<boolean>; taskbar?: Read<boolean>; children?: UiView };

export type SwitchProps<V> = { label: string; checked?: Read<boolean>; onChange?: (arg0: boolean) => void; disabled?: Read<boolean>; variant?: import('./style').Axis<V, 'switch_variant'>; size?: import('./style').Axis<V, 'switch_size'>; tag?: string };

// A colour token's values in light and dark: Look.tone("oklch(0.56 0.19
// 258)", "oklch(0.64 0.17 258)"), written as CSS writes a colour (one for
// both). A structure, not a class: a TypeScript program's are its objects.
export type Tone = { light: Color; dark: Color };

// helder.ui's markup (helder.view.ViewOf): a component returning one is
// pinned to ui, a children prop typed so makes its content ui's (a
// boundary's: <Surface>, <Ui> in a scene)
export type UiView = unknown;

export type VirtualGridProps<T> = { each: Read<T[]>; children: (arg0: Read<T>, arg1: number) => unknown; by: (arg0: T) => string; cellWidth: number; cellHeight: number; gap?: number; padding?: number; selection?: Selection; selectMode?: Read<boolean>; textOf?: (arg0: T) => string; onActivate?: (arg0: number[]) => void; onContextMenu?: (index: number, x: number, y: number) => void; label?: string; ref?: (arg0: GridScroll) => void; tag?: string };

// A window showing a UI tree drawn with the GPU: an helder.os Window, its
// gfx Device, a helder.ui.draw.Renderer and the Ui (root: the tree's root node, in the
// window's points). The window's events become the Ui's (pointer, wheel,
// keys, text); a frame lays the tree out and draws it, when there is
// something new to draw (needsFrame: the Ui asked for one, the window was
// resized or lost its pixels). run() is the app loop for every UiWindow
// open, which sleeps while none has a frame to draw. In the browser each
// frame's accessibility tree goes to the mirror in the canvas (helder.ui.access.web.Access:
// load src/helder/ui/imports.mjs), on macOS to NSAccessibility (helder.ui.access.apple.MacAccess), on
// iOS to UIAccessibility (helder.ui.access.apple.IosAccess), on Android to its AccessibilityNodeProvider (helder.ui.access.android.Access),
// on Windows to UI Automation (helder.ui.access.windows.Access), on Linux to AT-SPI (helder.ui.access.linux.Access),
// and the actions asked for come back.
//
// In markup (helder.view) <Surface> is the root ui draws into: a UiWindow,
// its children ui's markup rendered into its root; several make several
// windows; run(content) opens them (Render.open) and runs the loop:
//
//   UiWindow.run(<Surface title="Todo" width={480} height={560} theme={sheet}>
//     <Todo/>
//   </Surface>);
//
// In a page's markup (helder.web's DOM or static renderer) a <Surface> is
// helder.web's: a canvas running a wasm program whose root is this one.
export declare class UiWindow {
	// the app loop: every UiWindow's frames and events until the last closes
	// (on the web it returns, the frames going on); content, when given, opened first
	static run(content?: RootView): void;
	// (a background as Surface takes it: a Color, or a string Color.parse
	// reads, markup's background="#333333", which taken as the Int it is not
	// was 0: transparent black)
	// <Surface>: a window (a canvas on the web), its children rendered into its ui's root; closed with its owner
	static Surface(props: SurfaceProps): View;
	// (once: a <Surface>'s owner closes it too)
	close(): void;
}

// (a background as Surface takes it: a Color, or a string Color.parse
// reads, markup's background="#333333", which taken as the Int it is not
// was 0: transparent black)
// <Surface>: a window (a canvas on the web), its children rendered into its ui's root; closed with its owner
export declare function Surface(props: SurfaceProps): View;

// An event as Ui dispatches it: to the target, then (unless stopped) to
// each ancestor (current), except PointerEnter, PointerLeave, Focus and
// Blur, which each node gets for itself.
export declare class Event {
	// an event of type at target, the pointer at x, y in the window's coordinates
	static of(type: EventType, target: Node, x: number, y: number): Event;
	readonly type: EventType;
	readonly target: Node;
	// the node whose handler runs
	readonly current: Node;
	// the pointer in window pixels (pointer events; else where it was last)
	readonly x: number;
	readonly y: number;
	// pointer buttons: 1 left, 2 middle, 3 right (a finger, a pen: 1)
	button: number;
	// pointer events: which pointer (0 the mouse, else helder.os's slot of a
	// finger or a pen: Pointer.id), its type, its pressure (0 to 1), and
	// whether it is the primary one (the mouse, the first finger down)
	pointerId: number;
	pointerType: PointerType;
	pressure: number;
	isPrimary: boolean;
	// KeyDown, KeyUp: the key (Key) and the modifiers (helder.os.Mods)
	key: number;
	mods: Array<import("helder/os").Mod>;
	// TextInput: the characters typed (an IME's composed text, too); Input: the field's text;
	// Composition: an input method's text not committed yet (empty: none)
	text: string;
	// Composition: the caret in text (UTF-16)
	caret: number;
	// Wheel: the scroll in pixels (down and right positive)
	// drag and drop: what is dragged (the source's dragData); DragEnd: whether it was dropped
	data: any;
	dropped: boolean;
	deltaX: number;
	deltaY: number;
	// a wheel's deltas to ease rather than jump to (a mouse's notches on macOS)
	eased: boolean;
	readonly stopped: boolean;
	// the default action (Tab moving the focus, the wheel scrolling) is not taken
	readonly defaultPrevented: boolean;
	// the pointer relative to current's border box (Node.localX: through
	// scrolling and transforms; fields, so that a handler's untyped event
	// reads them too)
	readonly localX: number;
	readonly localY: number;
	stop(): void;
	preventDefault(): void;
}

// Key codes: X11 KeySyms, as helder.os.Event.key gives them on every
// platform (Latin-1 keys are their unshifted character code: 'a' is 0x61)
export declare class Key {
	static readonly BACKSPACE: number;
	static readonly TAB: number;
	static readonly ENTER: number;
	static readonly ESCAPE: number;
	static readonly HOME: number;
	static readonly LEFT: number;
	static readonly UP: number;
	static readonly RIGHT: number;
	static readonly DOWN: number;
	static readonly PAGE_UP: number;
	static readonly PAGE_DOWN: number;
	static readonly END: number;
	static readonly INSERT: number;
	// the context menu key
	static readonly MENU: number;
	static readonly F1: number;
	static readonly F10: number;
	static readonly F12: number;
	static readonly DELETE: number;
	static readonly SHIFT: number;
	static readonly CONTROL: number;
	static readonly ALT: number;
	static readonly META: number;
	static readonly SPACE: number;
}

// A scroller over a long list's rows, only those in view made
// (UiFlow.VirtualList's; usable alone): count rows, their heights in a
// HeightIndex (estimated until measured), the rows of the window (the view
// and overscan more on each side) made by onMakeRow into a row node each and
// shown in the flow between two spacers as tall as the rows before and
// after them; rows that leave the window are hidden and kept (keep of them,
// the farthest from the window let go first, onDropRow), shown again as they
// were when they come back. After each layout (Ui.update: settle) the rows
// shown are measured and the window moved, laid out again while that
// changes it, so a frame never shows a gap or the estimates.
//
// The scroll is anchored to a row: the first in view and how far into it,
// kept through measures, a new estimate and rows put in or taken out
// before it (splice), so the content does not move; at the very top it
// stays at the top (rows put in above the first come into view). scrollToIndex (start,
// center, end or the nearest edge: auto) goes to a row made or not, held
// there while its rows are measured, within the insets (a bar over the
// top, a padding: the row shown with their room); focusIndex makes the row, scrolls to
// it and focuses it. The rows are a listbox's options to assistive
// technology (rowRole), each its place among all (posInSet, setSize). The
// keyboard on a row (its focus within the list): Up and Down, Page Up and
// Down, Home and End move the focus onto that row (made if need be, onRowActive
// told: a selection follows it); Enter and Space are onRowActivate's; the row
// focused or last moved to is the one Tab stops on (the others -1).
// Rows should not have margins: their measure is their border box.
export declare class VirtualScroll extends Node {
	// the first and last rows in view (-1: none)
	firstVisible(): number;
	lastVisible(): number;
	// scrolls to row index ("start", "center", "end"; "auto": as little as
	// shows it), made or not, held there while the rows are measured
	scrollToIndex(index: number, align?: string): void;
	// focuses row index (made, scrolled into view first), the focus ring shown
	focusIndex(index: number): void;
}

// A list's selection by key. The range of a Shift gesture is replaced
// as it grows or shrinks, over the selection made before that gesture.
export declare class Selection {
	constructor(keyOf: (arg0: number) => string, count: () => number);
	readonly anchor: string | null;
	readonly focus: string | null;
	readonly version: Signal<number>;
	has(key: string): boolean;
	size(): number;
	// The keys present in the list, in its current order.
	keys(): string[];
	focusIndex(): number;
	select(i: number): void;
	toggle(i: number): void;
	extend(i: number): void;
	selectAll(): void;
	clear(): void;
	setKeys(keys: string[], additive?: boolean): void;
	prune(): void;
}

// A VirtualScroll over rows of fixed-size cells (UiFlow.VirtualGrid's): as
// many columns of at least cellWidth as fit, widened to fill the row, each
// grid row one of the scroller's. Items are indices into the source (keyOf,
// count); a reflow keeps the first item in view where it was, a refresh
// remakes only the rows whose keys changed. The selection and the focus
// are held by key.
export declare class GridScroll extends VirtualScroll {
	readonly selection: Selection;
	readonly columns: number;
	// select mode (a phone's Select): a press toggles its item, a drag sideways selects a run
	selectMode: boolean;
	// scrolls to item index ("start", "center", "end"; "auto": as little as shows it)
	scrollToIndex(index: number, align?: string): void;
	// focuses item index, scrolled into view, the focus ring shown
	focusIndex(index: number): void;
}

// The animation clock: what animates adds a step, called with the time (in
// seconds) at each tick until it returns false. A window ticks it before
// each frame and keeps drawing while anything animates (active); a test
// ticks it by hand.
export declare class Clock {
	// the last tick's time
	static readonly now: number;
	// the system asks for reduced motion (a headless run's --reduced-motion):
	// what moves a node's place, size or shape jumps to its end (Style's
	// transitions of transform and shadow, Motion's transition and spring,
	// helder.ui.motion's travel, sizes, radii and matched flights), fades,
	// presence and colours still ease (motion's over 0.15 s)
	static reducedMotion: boolean;
	static add(step: (arg0: number) => boolean): void;
	static readonly active: boolean;
	// runs the steps to their ends (tests, a screenshot): ticks a tenth of a
	// second apart, from now on, until none is left
	static finish(): void;
	// runs the steps at time t (the ones done are dropped): whether any is left
	static tick(t: number): boolean;
}

// A web view's event (WebView's handlers, WebViewListener): what each kind
// has is in WebViewEventKind
export declare class WebViewEvent {
	constructor(kind: number);
	// a message from the bridge's wire form (WebBridge: s text, j JSON, b base64, c a console line)
	static message(wire: string): WebViewEvent;
	readonly kind: number;
	url: string;
	text: string;
	// a message's: the page posted JSON (text; json() parses it)
	isJson: boolean;
	// a message's binary (an ArrayBuffer or a typed array the page posted)
	bytes: Uint8Array | null;
	progress: number;
	code: number;
	// a message's value: its JSON parsed, else its text
	json(): any;
}

// What a web view's own origin serves (WebView.content): the files of the
// app's bundle (assets the program names, helder.asset's keys under a
// prefix) or of a directory, or a function's responses, each with headers
// of its own beside the MIME type its extension gives. By default every
// response is cross-origin isolated (COOP same-origin, COEP require-corp,
// CORP same-origin: the page's crossOriginIsolated, SharedArrayBuffer and
// wasm threads), never cached, and a .wasm is application/wasm (what
// WebAssembly.instantiateStreaming asks for).
//
// The origin is the platform's: on iOS and macOS http://127.0.0.1:<port>,
// a loopback server of the app's own (WebServer: WebKit isolates HTTP
// origins only), or, with local false, a custom scheme (WKURLSchemeHandler:
// `app://localhost/`, the scheme WebContent.scheme); on Android https on a host of its own (shouldInterceptRequest, as
// WebViewAssetLoader does: `https://appassets.androidplatform.net/`), so
// the page is a secure context everywhere. `url(path)` is a path's URL
// there (on the loopback under the server's secret, base(): WebServer
// answers nothing else, its origin the same); a web view's src may be a
// path, resolved against it.
//
//   var content = WebContent.bundle("web/");                  // Asset.bytes("web/index.html") etc. in the bundle
//   var content = WebContent.directory(dir);                  // a folder on disk
//   var content = WebContent.handler(path -> WebResponse.text("hi"));
export declare class WebContent {
	constructor(serve: (arg0: string) => WebResponse | null);
	// the bundle's files under prefix (helder.asset's keys: each must be
	// named by the program, Asset.bytes(prefix + path), to be bundled)
	// (none in a browser: a page has no web view of its own here, and its
	// program does not take helder.asset's fetches for it)
	static bundle(prefix?: string): WebContent;
	// the files of a directory on disk
	static directory(dir: string): WebContent;
	// a function's responses, by path (null: 404)
	static handler(f: (arg0: string) => WebResponse | null): WebContent;
	// the custom scheme on Apple's systems
	scheme: string;
	// the host (Apple: app://<host>/; Android: https://<host>/)
	host: string;
	// the headers every response gets (cross-origin isolation, no cache)
	readonly headers: unknown;
	// the path a directory's request gets (a path ending in /)
	index: string;
	// served over HTTP on the loopback address instead of a scheme
	// (WebServer: http://127.0.0.1:<port>), set before its first use: by
	// default on Apple's systems, whose WebKit isolates (crossOriginIsolated,
	// SharedArrayBuffer) an HTTP origin, never a custom scheme's; Android's
	// scheme (https, intercepted) puts the bridge in its pages first
	local: boolean;
	// the origin, without a slash at the end (the loopback's: no secret in it)
	origin(): string;
	// what every URL of the content starts with, without a slash at the end:
	// the origin, and on the loopback the server's secret after it
	// (http://127.0.0.1:<port>/<secret>: WebServer answers nothing else)
	base(): string;
	// a path's URL at the origin (on the loopback under its secret: the
	// page's relative URLs are too, never a path from the root)
	url(path: string): string;
	// whether a URL is the content's (the request this handles)
	owns(url: string): boolean;
	// the response to a URL of the content's (any thread: Android's requests
	// come on the web view's own); 404 when nothing serves it
	respond(url: string): WebResponse;
}

// A response of WebContent's: its status, MIME type, headers and body
export declare class WebResponse {
	constructor(status: number, mime: string, body: Uint8Array);
	static bytes(b: Uint8Array, mime: string): WebResponse;
	static text(s: string, mime?: string): WebResponse;
	static error(code: number, mime: string, s: string): WebResponse;
	// the reason phrase of a status
	static reason(code: number): string;
	// a path's MIME type, by its extension (text as UTF-8)
	static mimeOf(path: string): string;
	status: number;
	mime: string;
	readonly headers: unknown;
	body: Uint8Array;
}

// A node of the UI tree: a box laid out by its parent's flexbox (Layout),
// drawn by a renderer (Canvas) and receiving events (Ui). Its children are
// in drawing order (the last on top). x, y, width and height are the
// layout's result in pixels, relative to the parent's border box (rounded
// to whole pixels: absX, absY are the window's), valid after Ui.update. A
// change to the tree or to a layout property of the style marks the node
// and its ancestors for layout; a paint property asks only for a frame.
// Subclasses with content (TextNode) measure it (measureContent) and draw it
// (paintContent).
// (helder.view's markup: its renderer, NodeRenderer)
export declare class Node {
	constructor(tag?: string);
	readonly parent: Node | null;
	// (a leaf's: one empty array shared by all, replaced by its own when a child comes)
	readonly children: Node[];
	// a name for debugging and markup (the element's name)
	tag: string;
	// the layout's result (Layout): relative to the parent, then absolute; rounded
	readonly x: number;
	readonly y: number;
	readonly width: number;
	readonly height: number;
	readonly absX: number;
	readonly absY: number;
	// the extent of the children past the padding box's origin (scrolling;
	// right to left: from its right edge, what overflows on the left)
	readonly contentWidth: number;
	readonly contentHeight: number;
	// Overflow Scroll: the children's offset (clamped by Ui to the content;
	// right to left, scrollX from 0 down: Ui.scrollStart)
	scrollX: number;
	scrollY: number;
	// events (Ui dispatches them; Event.stop() ends bubbling to the ancestors;
	// kept in a Handlers made when the first is set: most nodes have none)
	onPointerDown: ((arg0: Event) => void) | null;
	onPointerUp: ((arg0: Event) => void) | null;
	onPointerMove: ((arg0: Event) => void) | null;
	onPointerEnter: ((arg0: Event) => void) | null;
	onPointerLeave: ((arg0: Event) => void) | null;
	// a pointer's press taken from it: the system cancelled it (a call, the
	// browser panning the page), its node left the tree, or a gesture took
	// it over (a scroller's drag): no click follows
	onPointerCancel: ((arg0: Event) => void) | null;
	// it no longer has a pointer it had captured (the pointer's release or
	// cancel, releaseCapture, another node's capture)
	onLostPointerCapture: ((arg0: Event) => void) | null;
	onClick: ((arg0: Event) => void) | null;
	// a press: a click, or Enter or Space while it has the focus (after onKeyDown, unless it
	// prevented the default), as a DOM button's click (a link's: Enter, not Space, as a DOM link's)
	onPress: ((arg0: Event) => void) | null;
	onWheel: ((arg0: Event) => void) | null;
	onKeyDown: ((arg0: Event) => void) | null;
	onKeyUp: ((arg0: Event) => void) | null;
	onTextInput: ((arg0: Event) => void) | null;
	// a text field's text changed by its user (Event.text: its text; the DOM's input)
	onInput: ((arg0: Event) => void) | null;
	// Overflow Scroll: its scrollX or scrollY changed (the wheel, a thumb, clamping)
	onScroll: (() => void) | null;
	onComposition: ((arg0: Event) => void) | null;
	onFocus: ((arg0: Event) => void) | null;
	onBlur: ((arg0: Event) => void) | null;
	// (bubbling: the focus coming into this node or one under it, or leaving)
	onFocusIn: ((arg0: Event) => void) | null;
	onFocusOut: ((arg0: Event) => void) | null;
	// its laid-out size changed, and when it was first laid out: after the
	// layout, the size its width and height (a 3D camera fitted to its box)
	onResize: ((arg0: Event) => void) | null;
	// drag and drop: dragData makes it draggable (what its drag carries);
	// the handlers of a source (start, end) and of a target (over: call
	// preventDefault to accept; leave; drop)
	dragData: any;
	onDragStart: ((arg0: Event) => void) | null;
	onDragOver: ((arg0: Event) => void) | null;
	onDragLeave: ((arg0: Event) => void) | null;
	onDrop: ((arg0: Event) => void) | null;
	onDragEnd: ((arg0: Event) => void) | null;
	// takes the keyboard focus when clicked or tabbed to
	focusable: boolean;
	// takes the focus when it comes into a window (a dialog's first button, a
	// menu's first item: as the DOM's autofocus, wherever it is inserted)
	autofocus: boolean;
	// whether its text can be selected (Ui.textSelection: a drag, a double
	// click a word, a triple a line, Shift extending; Mod+C copies it, Mod+A
	// selects all of it): a TextNode's with its spans; any other node's
	// texts all in one selection, as a document's (TextSelection: its scope,
	// the outermost such node)
	selectable: boolean;
	// what it is to assistive technology (helder.ui.access.AccessTree)
	semantics: unknown | null;
	// the pointer is over it (or a descendant), the button is down on it, it has the focus
	readonly hovered: boolean;
	readonly pressed: boolean;
	readonly focused: boolean;
	// a legend (a page's legend element): its parent's first, as a fieldset's
	// rendered legend, no flex item (Layout: no gap after it in a column)
	legend: boolean;
	// what a theme styles it as (Rule, StyleSheet): the part it is
	// ("button", "switch-thumb"), its variant and
	// size ("destructive", "sm"); its attributes, the states rules match
	// ("data-state" "checked", "data-disabled" present: attr, setAttr); and
	// a theme for this subtree (null: the parent's, else the window's)
	slot: string | null;
	variant: string | null;
	size: string | null;
	theme: StyleSheet | null;
	// what it is to the keymap (helder.ui.actions: "Editor mode=full"; markup's key-context)
	keyContext: unknown | null;
	// Tab's order among the focusable (as the DOM's tabindex): those above 0
	// first, in its order, then 0's in tree order; below 0: focusable by a
	// click or focus(), passed over by Tab
	tabIndex: number;
	// the language of its text, inherited (null: the parent's; as HTML's lang,
	// a BCP 47 tag: "nl", "en-GB"): its words' hyphenation (Style.hyphens)
	lang: string | null;
	// motion (helder.ui.motion.Motions): what it declares for itself and its
	// subtree (markup's motion="snappy"); the id a matched counterpart flies
	// from or to (matched="tile-3"); its subtree's changes without motion
	// (instant); kept against its parent's trailing edges while the parent's
	// size moves (ride: 1 across, 2 down, 3 both; markup's ride="trailing")
	motion: unknown | null;
	instant: boolean;
	append(child: Node): Node;
	// child at index (moved if it is already a child of this node)
	insert(child: Node, index: number): Node;
	// the index of a child (-1: not one), looked for from the end, where
	// anchors and new children usually are
	indexOf(child: Node): number;
	// puts nodes, all children of this node and as many as the children from
	// start, in that order from start (a keyed list's rows, reordered at once)
	reorder(start: number, nodes: Node[]): void;
	remove(child: Node): void;
	removeChildren(): void;
	// handles e's actions dispatched through it (Ui.dispatchAction: from the focus
	// up): handle true takes one, false lets it bubble; state what a menu
	// shows it as (default: Enabled). Returns what removes it.
	on<T>(type: any, handle: (arg0: T) => boolean, state?: (arg0: T) => ActionState): (() => void);
	// it or a descendant has the focus (CSS's :focus-within)
	focusWithin(): boolean;
	// its gesture recognisers (helder.ui.gesture: Tap, Pan, Scale), in the
	// order added; each joins the arena of a pointer pressed on it or inside it
	readonly gestures: unknown[] | null;
	addGesture<T>(g: T): T;
	removeGesture(g: unknown): void;
	// its first gesture of that class (null: none)
	gesture<T>(c: any): T | null;
	// whether a pointer pressed on it is ui's (helder.os's Pointer.owner: a
	// game's controls leave it alone): a node drawing a world under the ui
	// (a <Scene>'s box) says no
	ownsPointer(): boolean;
	// the glass inside it drawn together, nearer than this many points
	// merged (null: not a group; markup's glassSpacing, any view's; GlassGroup.of sets it)
	readonly glassSpacing: number | null;
	textColor(): Color;
	// whether it is seen: its visibility, else its nearest ancestor's (Style.visibility)
	visible(): boolean;
	// whether the pointer finds it: seen, and its pointerEvents (else its
	// nearest ancestor's) not None
	hittable(): boolean;
	// whether its text wraps: its textWrap, else its nearest ancestor's (Style.textWrap)
	wraps(): boolean;
	// how its text wraps: its textWrap, else its nearest ancestor's
	textWrap(): number;
	// how its text's letters are shown: its textTransform, else its nearest ancestor's
	textTransform(): number;
	textAlign(): TextAlign;
	// whether its inline direction is right to left (Style.dir, inherited)
	// its text's user-select as set on it or an ancestor (Auto: none set)
	userSelect(): number;
	rtl(): boolean;
	// its direction as set on it or an ancestor (null: none set)
	dir(): number | null;
	// a window position in this node's coordinates (from its border box's
	// top left), its ancestors' scrolling and transforms (its own too) taken
	// into account
	localX(windowX: number, windowY: number): number;
	localY(windowX: number, windowY: number): number;
	focus(visible?: boolean): void;
	rect(): Rect;
	scrollIntoView(): void;
	// (a press's pointer: the pressed node's until released (Ui.capture), this one's now;
	// in a pointer event's handler, that pointer: a finger's, a pen's)
	capture(): void;
	// lets go of the pointers it captured: their moves go to what is under them again
	releaseCapture(): void;
	// (a text field's: EditableText's)
	select(start: number, end: number): void;
	// the scope its text is selected in: its outermost selectable ancestor
	// (itself too; user-select none: not one), else null
	selectionScope(): Node | null;
	// (kept wherever nodes are laid out: a Part's, which a component calls opaquely in a page too)
	editable(): boolean;
	contains(p: unknown): boolean;
	// the border box where it is drawn, in window pixels: its ancestors'
	// scrolling taken off, through the transforms (its own too; the bounds
	// of the box they turn)
	windowBounds(): Rect;
	// windowBounds, written into out (returned): its corners in locals, no
	// array or box made (a transformed ancestor's matrix still is: transformMatrix)
	windowBoundsInto(out: Rect): Rect;
	// the transform (Style.transform about Style.transformOrigin) in window
	// pixels, as Canvas.pushTransform takes it; null: none
	transformMatrix(): unknown | null;
	hasContent(): boolean;
	// a text input's value for assistive technology when it is not a
	// TextNode's text (a code editor's document); null: none
	accessValue(): string | null;
	// a text input's selection and caret (UTF-16 indices) and whether it is
	// read only, for assistive technology; null: it edits no text
	accessText(): { start: number; end: number; caret: number; readOnly: boolean } | null;
	// where text is typed into it (its caret, window pixels, after a paint):
	// an input method's place; null: it takes no text
	textInputArea(): Rect | null;
	// the text around its caret, for an input method (Window.textContext:
	// its text, the selection in UTF-16 indices, its kind); null: none to give
	textContext(): { text: string; start: number; end: number; multiline: boolean; secret: boolean } | null;
	// what it takes for the system's keyboard (helder.os.TextKind: its
	// keys, Enter key, capitalisation); null: it takes no text
	textKind(): unknown | null;
	// an input method's edit of that text: start...end replaced by s, the
	// caret after it (a node with no text context: s typed)
	replaceText(start: number, end: number, s: string): void;
	backgroundImage(scale: number): Image;
	// whether it takes typed text while focused (a text field): keys that type are its, not shortcuts
	takesText(): boolean;
	// draws the content in its content box at (x, y), in window pixels
	paintContent(canvas: unknown, x: number, y: number, width: number, height: number): void;
	// the topmost node under (px, py) in window pixels, among this subtree
	// (clipped by Overflow, through the transforms), or null
	hitTest(px: number, py: number): Node | null;
	// what its content draws, from its content box's top left, when it may reach past the box (a text's paragraph)
	// its first baseline below its border box's top, once laid out: a text's
	// first line's, a row's items aligned on theirs, else its first item's
	// (one without any: its bottom edge, as CSS's flexbox synthesizes it);
	// NaN: none (no text, no items)
	firstBaseline(): number;
	// the first descendant (or this) with the tag, depth first
	find(tag: string): Node | null;
	toString(): string;
	// called when its states (hover, press, focus, the focus ring's
	// visibility) or attributes change: helder.ui.view.States' signals
	onStates: (() => void) | null;
	// an attribute (null: not set; "" when it is present without a value)
	attr(name: string): string | null;
	// sets an attribute (null: removes it); the rules matching it follow
	setAttr(name: string, value: string | null): void;
	// the theme it is styled by: its own or the nearest ancestor's, else the window's
	sheet(): StyleSheet | null;
}

// A run of text: measured and wrapped by the Ui's TextEngine to the width
// its parent gives it (the content box), with the node's inherited font,
// colour and alignment. Its children, when it has some, are spans: TextNodes
// whose texts (or their own spans) make the paragraph instead of its own
// text, each in its style (inheriting this one's): bold, a colour, a size.
// They are not laid out as boxes; a pointer over one's text hits it.
export declare class TextNode extends Node {
	constructor(text?: string, tag?: string);
	text: string;
	// the whole text, as shown: its own, or its spans'
	allText(): string;
	// the span whose text is at index i (null: none, or no spans)
	spanAt(i: number): TextNode | null;
	// the character index nearest to a point in the window (its lines' alignment taken off)
	textIndexAt(px: number, py: number): number;
	// a point over a span's text: that span (its handlers, its cursor)
	hitTest(px: number, py: number): Node | null;
	// the paragraph as drawn (after Ui.update), or null
	laidOut(): unknown | null;
	// (its first line's, in its content box)
	firstBaseline(): number;
}

// helder.ui's own control flow components for markup (import
// helder.ui.view.UiFlow.*), beside helder.view.Flow's:
//
//   <Popover open={open} placement="below">{...}</Popover>
//   <VirtualList each={rows} by={r -> r.id} estimate={44} selected={sel}>{(row, i) -> ...}</VirtualList>
declare class UiFlow {
}

// a long list in a scroller (helder.ui.VirtualScroll): only the rows in
// view are made, and overscan more on each side (3); rows that leave are
// hidden and kept (keep of them, 64, the farthest let go first), by key
// as For keeps them: by the item itself, by what by gives for it (a
// row's Read then its key's latest item: a change to one item changes
// its row alone), or keyed={false} by index. Its rows' heights are their
// own, estimated (estimate, 44 pixels) until each is measured, the scroll
// anchored to the row in view (an estimate made real, rows put in or
// taken out above it: nothing moves); itemHeight: every row that high.
// height pixels high, else it grows in its parent from 0 (flex: 1). A
// listbox of options to assistive technology (label: its name), each
// with its place among all of them; Up, Down, Page Up and Down, Home
// and End move the focus to a row (made if need be), selected (the key
// of the row selected, by's K: written as the focus moves, a row
// pressed) and onActivate (Enter, Space) given its index ([i]). Its
// child function gets a row's item (a Read) and its index when made; ref
// the VirtualScroll (scrollToIndex, focusIndex, the window). With a
// Selection onActivate takes the selected indices (Enter or double
// click); by still keys rows; selectMode as VirtualGrid's.
export declare function VirtualList<T, K>(props: VirtualListProps<T, K>): unknown;
// VirtualGrid: each's items in cells cellWidth (at least) by cellHeight,
// gap apart and padding in (4, 12), in a GridScroll: only the rows in
// view made, a cell made again when its row's keys (by) change, else
// its item written. A Selection (its own unless given; ref: the
// GridScroll's) with the keyboard, presses and a marquee from empty
// space; onActivate given the selected indices (Enter, double click),
// onContextMenu an item and where; textOf: type-ahead; selectMode: a
// press toggles, a drag sideways selects a run (a phone's Select).
export declare function VirtualGrid<T>(props: VirtualGridProps<T>): unknown;
// the children in a popup (helder.ui.Popup: a layer over the tree), open
// while open is true: anchored to anchor (else the node the markup puts
// it in), placed by placement ("below", "above", "right", "left",
// "center"; gap pixels away), modal or not; onDismiss when a click
// outside (unless dismissOnOutside is false) or Escape asks it to close; onOpen once it is open (to move
// the focus into it); a modal one's scrim its colour; the popup's
// slot for a theme (Node.slot). Its content is rendered once, kept while closed.
export declare function Popover(props: { open: Read<boolean>; anchor?: Node; placement?: Placement; gap?: number; modal?: boolean; scrim?: Color; slot?: string; onDismiss?: () => void; dismissOnOutside?: boolean; onOpen?: (arg0: unknown) => void; at?: () => { x: number; y: number }; tag?: string; children?: unknown }): unknown;
// the window's menu bar (helder.ui.menu.MenuBar): the platform's, or
// drawn here (put it first in the window's content); ref: the bar
export declare function MenuBarView(props: { menus: Menu[]; ref?: (arg0: unknown) => void }): unknown;

// The main window's safe area for markup, as CSS's env(): a literal
// attribute naming env(safe-area-inset-top) (right, bottom, left; a
// fallback after a comma for another name) is bound to it, its value the
// insets in UI pixels, again whenever they change (a rotation, the bars
// hidden): <view paddingTop="env(safe-area-inset-top)">,
// padding="calc(env(safe-area-inset-top) + 8px) 16px", margin-bottom="max(12px,
// env(safe-area-inset-bottom))". calc(), max() and min() of pixels fold to
// one length; a percentage in calc() stays for Dim's. The insets are
// UiWindow's first window's (a phone has one: Window.safe.top..., over the
// UI's scale), each frame they changed; Ui.safeArea has each window's own.
// Code reads insets() (a signal: what reads it in an effect or a reactive
// attribute follows it). env(titlebar-area-x), -y, -width and -height are an
// inset title bar's area free of the window's buttons (the Window Controls
// Overlay's: helder.os's Window.titlebarArea), bound the same
// way; without one (not inset, the browser, a phone) the fallback, else 0.
export declare class SafeArea {
	// top, right, bottom, left in UI pixels (the current screen's:
	// helder.ui.ScreenContext, a story host's screens each their own)
	static readonly insets: Read<Edges>;
	// the main window's soft keyboard over it, in UI pixels (0 while hidden;
	// helder.os.Window.keyboard): the insets' bottom is at least this while it
	// is up
	static readonly keyboard: Signal<number>;
	// an inset title bar's area (the current screen's; null: none)
	static readonly titlebar: Signal<Rect | null>;
}

// Screens by path, kept as a stack (helder.ui.Stack shows it): routes are
// matched in the order they were added, a segment ":name" taking any one
// segment (its value given to the route, decoded), the fallback any path
// none matched. go pushes (still: faded in place and popped so, not slid,
// when the app moves what matters itself: a picture zoomed from its tile),
// back pops (false at the root; backTo several),
// replace swaps the top, reset starts a new stack, open a link's (a full
// URL or a path): the root and the matched route. Each entry's screen is
// made once, when it is pushed. Haxe's helder.ui.nav.Routes types a route's params by its path.
export declare class Router {
	constructor();
	// the top's path (without its query), how many entries are above the root, the top's query
	readonly path: Read<string>;
	readonly depth: Read<number>;
	readonly query: Read<Record<string, string>>;
	// a route: render given its params (an object of the path's names, each a string)
	route: <P extends string>(path: P, render: (params: RouteParams<P>) => View) => Router;
	// what a path no route matches shows (else go throws)
	fallback(render: (path: string) => View): Router;
	go(path: string, still?: boolean): void;
	back(): boolean;
	// pops to the entry depth entries above the root (0: the root): whether it moved
	backTo(depth: number): boolean;
	replace(path: string): void;
	reset(path: string): void;
	open(url: string): void;
}

// A grid of many rows, drawn (a table browser's, a spreadsheet's): only
// the cells in view are laid out and drawn, their text cut with an
// ellipsis and kept laid out by its text and width. A header of columns
// that stays at the top (a press sorts by one, onSort; its right edge drags
// to resize it, a double click fits it to what is shown), a gutter of row
// numbers that stays at the left (a press selects rows), both scrolled
// with the cells; scrollbars over the edges, dragged too. Cells are given
// by text (a cell's text: null for SQL's NULL) and flags (NULL, EDITED,
// LOADING, ADDED, DELETED; DEFAULT: what a new row's cell will be; LINK: an
// arrow on the hovered row's cell that follows it, onLink): what the grid
// shows of a row is asked for when it comes into view (onWindow), so a
// source can load it then. A secondary press on a title or a cell is
// onHeaderContext's or onContext's.
//
// A cell is the cursor (the keyboard's, focused), a range from an anchor
// to it is selected (Shift with the keys or a press, a drag). The keys:
// the arrows, Home and End (the row's ends; with Control or Command the
// grid's), Page Up and Down, Control or Command+A (all), +C (the selection
// as tab separated text, rows by lines), +V (onPaste: the clipboard's text), Enter or F2 or a double click
// edits the cursor's cell (onEdit, or the grid's own editor: edit), a
// character typed starts it with that character, Delete or Backspace clears
// the selection (onClear), Escape collapses it. The editor is a TextField
// inside the cell's ring (slot "grid-editor"; a press in it its own): Enter or Down keeps the text
// (onCommit) and moves down, Up up, Tab right, Escape drops it.
//
// It has no look of its own beyond its tokens (GridTheme: "grid-*" colours
// of the sheet) and its font (the style's, its figures tabular; the titles'
// family may be another). To
// assistive technology a table, its name the label given, the cursor's
// cell its value.
export declare class DataGrid extends Node {
	constructor(tag?: string);
	static readonly NULL: number;
	static readonly EDITED: number;
	static readonly LOADING: number;
	static readonly ADDED: number;
	static readonly DELETED: number;
	static readonly DEFAULT: number;
	static readonly LINK: number;
	readonly gridTheme: GridTheme;
	columns: GridColumn[];
	rowCount: number;
	rowHeight: number;
	headerHeight: number;
	// the row numbers' gutter
	rowNumbers: boolean;
	// the titles' family (null: the cells', the style's)
	titleFamily: string | null;
	// the cells can't be edited
	readOnly: boolean;
	// a cell's text (null: NULL), its flags
	text: ((row: number, col: number) => string | null);
	flags: ((row: number, col: number) => number) | null;
	// the rows in view changed (first, before end), drawn as LOADING until given
	onWindow: ((first: number, end: number) => void) | null;
	// a column's title pressed
	onSort: ((arg0: number) => void) | null;
	// the cursor or the selection moved
	onSelect: (() => void) | null;
	// the cursor's cell asked to be edited (null: the grid's editor), with the character typed if any
	onEdit: ((row: number, col: number, typed: string | null) => void) | null;
	// the grid's editor's text kept
	onCommit: ((row: number, col: number, text: string) => void) | null;
	// the selection to clear (Delete, Backspace)
	onClear: (() => void) | null;
	// a secondary press on a cell (window pixels); the cursor moved there first unless it is in the selection
	onContext: ((row: number, col: number, x: number, y: number) => void) | null;
	// a secondary press on a column's title (window pixels)
	onHeaderContext: ((col: number, x: number, y: number) => void) | null;
	// a LINK cell's arrow pressed
	onLink: ((row: number, col: number) => void) | null;
	// the clipboard's text to paste at the selection
	onPaste: ((arg0: string) => void) | null;
	// the column sorted by (-1: none) and whether descending: an arrow in its title
	sortColumn: number;
	sortDown: boolean;
	// the cursor and the selection's anchor (row, column); whole rows selected from the gutter
	readonly cursorRow: number;
	readonly cursorCol: number;
	readonly anchorRow: number;
	readonly anchorCol: number;
	readonly wholeRows: boolean;
	readonly scrollTop: number;
	readonly scrollLeft: number;
	// the editor while a cell is edited
	readonly editor: TextField | null;
	// the cells' text or flags changed: drawn again
	refresh(): void;
	// back to the top left, the cursor on the first cell
	reset(): void;
	// the selected range: its first and last rows and columns
	range(): { top: number; bottom: number; left: number; right: number };
	selected(row: number, col: number): boolean;
	// the cursor to a cell (extend: the anchor kept), brought into view
	moveTo(row: number, col: number, extend?: boolean, rows?: boolean): void;
	selectAll(): void;
	// text to the clipboard: the selection's (selectionText), or what is given
	copy(text?: string): void;
	// the clipboard's text to onPaste (it may come later)
	paste(): void;
	// the selection as tab separated text: a row a line, NULL empty
	selectionText(): string;
	// scrolled to (clamped): whether it moved; the editor moved with its
	// cell, kept when the cell leaves the view
	scrollTo(left: number, top: number): boolean;
	// a cell brought into view (col -1: only its row)
	reveal(row: number, col: number): void;
	// a column's width (at least 48)
	resizeColumn(col: number, width: number): void;
	// a column as wide as its title and the cells in view
	fitColumn(col: number): void;
	// a cell's box in window pixels (as it is scrolled now)
	cellBounds(row: number, col: number): Rect;
	// a view kept earlier (scroll, cursor) given back
	restore(top: number, left: number, row: number, col: number): void;
	// the grid's editor over a cell, its text the cell's (or typed: replacing it)
	edit(row: number, col: number, typed?: string): void;
	// the editor's text kept (then the cursor down a row, or moved by dx)
	commitEdit(refocus?: boolean, dy?: number, dx?: number): void;
	cancelEdit(): void;
}

export declare class EditableText extends TextNode {
	constructor(text: string, tag: string);
	// the seconds after a change the words are checked
	static spellDelay: number;
	// the time (seconds; tests replace it)
	static now: (() => number);
	placeholder: string;
	// a password: shown as dots (one a UTF-16 unit, the indices kept), not
	// copied or cut, moved through by words as one (Semantics.secret)
	secret: boolean;
	placeholderColor: Color;
	selectionColor: Color;
	// null: the text's colour (as Chromium's caret)
	caretColor: Color | null;
	onChange: ((arg0: string) => void) | null;
	// its words checked by the platform's spellchecker, the misspelled underlined
	spellcheck: boolean;
	// the misspelled words, start and end pairs in text (UTF-16), as last checked
	readonly misspelled: number[];
	spellColor: Color;
	// the words checked now
	checkSpelling(): void;
	// the misspelled word around i (start and end; null: none)
	misspelledAt(i: number): { start: number; end: number } | null;
	// what the system's keyboard shows for it (helder.os.TextKind): its keys,
	// its Enter key (a TextField's next moves the focus to the next field,
	// done lets go of it and the keyboard), what is capitalised and whether
	// words are corrected (null: sentences and corrected, but for an email,
	// a URL and a password)
	keyboard: "text" | "email" | "number" | "decimal" | "phone" | "url" | "search";
	enterkey: "default" | "done" | "next" | "go" | "search" | "send";
	autocapitalize: "none" | "words" | "sentences" | "characters" | null;
	autocorrect: boolean | null;
	// what AutoFill offers it (as an input's autocomplete; "new-password": a
	// password suggested, on iOS)
	autocomplete: string;
	textKind(): unknown | null;
	// read only: selected and copied, not edited (as an input's readonly)
	readOnly: boolean;
	// the most UTF-16 units it takes by typing or pasting (-1: any; as an input's maxlength)
	maxLength: number;
	// the caret (and the selection's other end), UTF-16 indices
	readonly caret: number;
	readonly anchor: number;
	// an input method's composition (Ui.composition): shown at the caret, not
	// in text until committed; the caret in it
	readonly composition: string;
	accessText(): { start: number; end: number; caret: number; readOnly: boolean } | null;
	// (native: the editor takes it, not the window's text input)
	takesText(): boolean;
	textInputArea(): Rect | null;
	textContext(): { text: string; start: number; end: number; multiline: boolean; secret: boolean } | null;
	// (an input method's edit: as typed, over that range)
	replaceText(start: number, end: number, s: string): void;
	// the composition now (empty: none), the caret in it: shown, not typed
	compose(s: string, at: number): void;
	// sets the text from outside (the caret clamped)
	setText(s: string): void;
	select(start: number, end: number): void;
	readonly selectionStart: number;
	readonly selectionEnd: number;
	// the selection to the clipboard, and out of the text
	cut(): void;
	// the selection to the clipboard
	copy(): void;
	// the clipboard's text over the selection (it may come later: typed where the selection is then)
	paste(): void;
	selectAll(): void;
	// the last edit undone (redo: done again)
	undo(): void;
	redo(): void;
	editorEdited(t: string, start: number, end: number): void;
	editorSelected(start: number, end: number): void;
	editorFocused(on: boolean): void;
	editorKey(k: number, mods: number): void;
}

// A data grid's column: its title, a detail drawn quieter beside it (a
// type), its width (pixels; the user resizes it) and how its cells align.
export declare class GridColumn {
	constructor(title: string, width?: number, align?: TextAlign, detail?: string);
	readonly title: string;
	readonly detail: string;
	width: number;
	readonly align: TextAlign;
}

// A data grid's colours, by theme token: a StyleSheet's light and dark
// colours named "grid-" and one of NAMES win, else a look's token for it
// (TOKENS: Look's sheet names its colours by the palette's names), else
// the neutral defaults here. Resolved once per sheet and appearance.
declare class GridTheme {
	constructor();
	// the colours now, by the indices above
	readonly colors: Color[];
	// the colours for a sheet and an appearance; whether they changed
	resolve(sheet: StyleSheet | null, dark: boolean): boolean;
}

// lucide's icons (ISC) by name: what the neutral element icon's name
// draws (<icon name="check"/>), each the markup inside an <svg> of 24 by
// 24, stroked (currentColor, 2 wide, round). ui's an Svg (svg), parsed once;
// a page's its inline <svg>'s content (helder.web.Neutral)
export declare class Icons {
	// the <svg> an icon's markup goes in (a page's: NeutralMacro's element)
	static readonly OPEN: string;
	static markup(name: string): string;
	// an icon of the program's own, from its SVG text (an <svg> with its
	// viewBox; currentColor where it takes the text's colour)
	static parse(text: string): Svg;
	// an icon as ui draws it
	static svg(name: string): Svg;
}

// Pages side by side, one shown, swiped between: a horizontal drag moves
// them with the finger (resisting past the first and the last), let go a
// fifth of the way or fast enough it snaps to the next or the previous
// (onPage), else back; a change of page (a tab pressed) slides to it. Its
// position (in pages, fractional while dragged or sliding) is for a tab
// bar to follow. The shown page sets the pager's height (the others laid
// beside it, cut to it). A vertical drag is left to what is around it.
//   var pager = new Pager(page, 3, p -> page(p));   // (in a component)
//   <Pager.Pages pager={pager} slides={[<Overview/>, <Build/>, <Recruit/>]}/>
//   <view left={(pager.position() * 100 / 3) + "%"} .../>   // a tab bar's pill
declare class Pager {
	// (made in a component: its spring stops with it)
	constructor(page: Read<number>, count: number, onPage: (arg0: number) => void);
	readonly page: Read<number>;
	readonly count: number;
	// where the pages are: the shown one's index, between two while moving
	readonly position: Signal<number>;
}

export declare function pager(page: Read<number>, count: number, onPage: (arg0: number) => void): Pager;
// the pages (slides), shown as the pager has them
export declare function Pages(props: { pager: Pager; slides: View[] }): View;

// Several lines of text edited in place (EditableText's keys and pointer):
// wrapped to its width, rows lines high unless its style says (a height;
// fieldSizing Content: as tall as its lines), scrolled
// (the wheel, and to keep the caret in view). Enter types a new line; Up
// and Down move a line keeping the column; Home and End go to the line's
// start and end (with Control: the text's). A composition shows at the
// caret, underlined. Its lines are aligned as the style says (else the
// start side: right to left, on the right). Spellchecked by default
// (EditableText.spellcheck).
export declare class TextArea extends EditableText {
	constructor(text?: string);
	// the height in lines when the style gives none
	rows: number;
	// (always wrapped, whatever it inherits: as a textarea's own pre-wrap)
	textWrap(): number;
}

// A one-line text field (EditableText's keys and pointer; Enter submits):
// its text scrolls sideways to keep the caret in view, and while it fits
// it is aligned as the style says (else the start side: right to left, on
// the right); the placeholder shows while it is empty; a paste goes on one
// line. onSubmit gets the text on Enter (the keyboard's Enter key, whatever
// its label), then enterkey next moves the focus to the next field, done
// lets go of the focus (the soft keyboard goes). A composition shows at the
// caret, underlined. Its line is centred in a taller box, as a browser's input's.
export declare class TextField extends EditableText {
	constructor(text?: string);
	onSubmit: ((arg0: string) => void) | null;
	// (a value from outside on one line too, as a browser's input's)
	setText(s: string): void;
}

// The window's buttons in an inset title bar (helder.os's TitleBar, a
// <Surface titlebar="inset">), where the app's layout puts them: macOS's own
// (a box of their size, the system's buttons placed at it: Ui.controlsAt),
// else drawn here: Windows' minimise, maximise and close (46 by 32, the
// close button red when hovered; the maximise button Windows' snap
// layouts' through WM_NCHITTEST), Linux's round ones. Nothing where the
// window has the system's title bar, in the browser or on a phone. Its
// colour is the text's (currentColor).
//   <view flexDirection="row" dragRegion><text>Title</text><view flexGrow={1}/><WindowControls/></view>
// A layout whose top left and top right are different bars (a sidebar's,
// an inspector's) puts one at each end with its side: only the one where
// the system puts them is drawn (side(): macOS's at the start, Windows' and
// Linux's at the end), the other nothing.
//   <view dragRegion><WindowControls side="start"/><text>Project</text></view>
//   <view dragRegion><text>Inspector</text><view flexGrow={1}/><WindowControls side="end"/></view>
// height: the drawn buttons' (32 by default, Windows' caption): a bar's
// own height, so that they fill it from the window's top edge as Windows
// 11's do in a taller title bar (WinUI's, Explorer's); their hit areas and
// snap layouts follow.
declare class WindowButtons {
}

// the side of the window the system puts its buttons: "start" (macOS's,
// at the left: env(titlebar-area-x) after them), "end" (Windows', Linux's),
// null without an inset title bar (the system's, the browser, a phone).
// Reactive, as SafeArea.titlebar: a bar's padding at that end can follow it.
export declare function windowControlsSide(): string | null;
export declare function WindowControls(props: { tag?: string; side?: string; height?: number }): View;

// A control's states as amounts that ease between 0 and 1 (hover, pressed,
// checked, focus: the keyboard's ring, open), each over its look's time
// for it, on its window's clock; under reduced motion they jump. What a
// recipe's states blend (colours, opacity, transforms, shadows, rings)
// eases the same way, through the parts' transitions (Look); these are
// for what draws itself: a part's shader (helder.ui.draw.PartShader), a
// replaced rendering.
declare class Eased {
	// times: each state's seconds (HOVER... OPEN)
	constructor(times: number[]);
	readonly hover: number;
	readonly pressed: number;
	readonly checked: number;
	readonly focus: number;
	readonly open: number;
	// called while they move (a shader's node asks for its frame)
	onChange: (() => void) | null;
	// the node whose window's clock they move on
	node: Node | null;
	// a state's amount (HOVER... OPEN)
	get(state: number): number;
	// where a state is going: 1 while it holds; at once without moving
	// (a control's first state, reduced motion)
	set(state: number, on: boolean, now?: boolean): void;
}

// What the controls look like: tokens, a recipe per control (a function
// of the tokens giving each part's style, by state and by variant), the
// renderings an app replaced, its own parts. Compiled once into a
// StyleSheet (sheet: a rule per part and state, its colours the tokens'
// light and dark values), which Rules runs: a control's states change
// what holds, nothing is made a frame. Look.base is helder's (Base); an
// app's is Look.base.with({...}) (LookOf.with: a patch's keys over the
// look's, by part and state, property by property; its variants added to
// the look's, which the controls' variant and size are checked against).
// <Themed look={look}> installs one for a subtree; a control outside any
// installs base for itself.
//
// Each state of a recipe is an amount that eases from 0 to 1 over the
// look's time for it (hoverTime, toggleTime, openTime): what blends
// (colours, opacity, transforms, shadows, rings) blends through the parts'
// transitions, which compile gives them (unless a part gives its own), on
// the quad every part already draws as; Eased has the amounts for what
// draws itself. Under reduced motion, travel jumps and colours fade.
export declare class Look<V> {
	static readonly base: Look<BaseVariants>;
	// the token references, as inline markup takes them (color={Look.ref.fg3}): resolved with the nearest sheet's colours
	// (every one there: TypeScript's Refs, a patch's, has them optional)
	static readonly ref: Required<Refs>;
	// the look of the subtree (Themed's)
	static readonly context: unknown;
	// a tone (a token's light and dark colours), as CSS writes them (one for both)
	static tone(light: string, dark?: string): Tone;
	// (every one there, as a patch's are not)
	readonly tokens: Required<Tokens>;
	// this look with a patch over it (TypeScript's; Haxe's: LookOf.with, which checks the patch)
	with: <P extends import('./style').LookPatch>(patch: P) => Look<V & import('./style').PatchVariants<P>>;
	// the look's StyleSheet: its rules and colours, made once
	sheet(): StyleSheet;
	// what its recipes read: the colours as references, the rest as they are
	refs(): Refs;
	// the Button, Checkbox and Switch whose variant and size are this look's
	// (the nearest look still draws them: Themed's); values, so that markup
	// of either language takes them as components (<look.Button>)
	readonly Button: ((arg0: ButtonProps<V>) => View);
	readonly Checkbox: ((arg0: CheckboxProps<V>) => View);
	readonly Switch: ((arg0: SwitchProps<V>) => View);
}

// a tone (a token's light and dark colours), as CSS writes them (one for both)
export declare function tone(light: string, dark?: string): Tone;

// The behaviour of what is pressed (WAI-ARIA's button): a click, Enter or
// Space activates it (Ui's onPress), none while it is disabled (then
// not focusable either). Its states are signals (hovered: never by touch;
// pressed: the pointer down on it and still over it, cancelled when it
// leaves; focusVisible: focused from the keyboard) and eased amounts
// (Eased). No look: root and part bind it to nodes, by ref, setting their
// slots (the control's, "button"; its part's, "button-icon"), the root's
// role, label, variant and size and its data-disabled (and a toggle's
// data-selected), which a look's recipes read.
//
//   final p = Press.of(props, "button");
//   <button ref={p.root}><image ref={p.part("icon")} .../></button>
declare class Press {
	constructor(slot: string, disabled?: Read<boolean>, onPress?: () => void);
	readonly hovered: Signal<boolean>;
	readonly pressed: Signal<boolean>;
	readonly focusVisible: Signal<boolean>;
	readonly disabled: Read<boolean>;
	readonly eased: Eased;
	readonly slot: string;
	// the look it was made under (Themed's, else Look.base): its states' times, its parts' draws
	readonly look: Look<any>;
	readonly node: Node | null;
	// set before root binds: the root's name for assistive technology, variant, size
	label: string | null;
	variant: string | null;
	size: string | null;
	// activates it, as a press does (nothing while it is disabled)
	press(): void;
	// binds the control's root node
	root(n: Node): void;
	// binds a part: its slot, the control's followed by the part's name (a
	// look's draw for it: its shader's node under its children)
	part(name: string): ((arg0: Node) => void);
}

// helder's standard controls, drawn by the nearest look (Themed's, else
// Look.base), their behaviour Press's and Toggle's: a Button, a Checkbox
// (indeterminate too), a Switch, a Slider, a Segmented choice and a
// Tooltip. A look that replaces one's rendering
// (render: {switch: Lamp}) is drawn instead, there and inside other
// widgets. A look's own variants: look.Button's (Look). A control under
// no look takes Look.base's sheet as its own.
//
//   <Button variant="primary" onPress={save}>Save</Button>
//   <Checkbox label="Remember me" checked={remember} onChange={v -> remember(v)}/>
//   <Switch label="Dark mode" checked={dark} onChange={v -> dark(v)}/>
//   <Slider label="Weight" value={weight} min={20} max={200} step={1} onChange={weight}/>
//   <Segmented label="Tool" value={tool} options={[{value: "draw", label: "Draw"}, ...]} onChange={tool}/>
//   <Tooltip label="Tracing letter" keys="T"><Button icon={eye}/></Tooltip>
// (pinned to ui's renderer, UiView: drawn controls, of no other renderer)
declare class Standard {
}

export declare function Button(props: ButtonProps<BaseVariants>): View;
export declare function PathBar(props: PathBarProps): View;
export declare function Checkbox(props: CheckboxProps<BaseVariants>): View;
export declare function Switch(props: SwitchProps<BaseVariants>): View;
// A number between min and max, shown as a field (its label inside on
// the left, its value on the right, the part up to it filled): a press
// or a drag anywhere sets it, the arrow keys step it (Shift: ten steps),
// Home and End go to the ends. step 0: any value. Parts: "slider",
// "slider-fill", "slider-label", "slider-value".
export declare function Slider(props: { label: string; value: Read<number>; min: number; max: number; step?: number; digits?: number; unit?: string; onChange: (arg0: number) => void; tag?: string }): View;
// One of a few options side by side, the chosen one selected: a press
// chooses, the arrow keys move between them (a radio group). compact:
// an option with an icon shows the icon alone. Parts: "segmented",
// "segmented-item" (selected: the chosen; an icon follows its colour).
export declare function Segmented(props: { label: string; value: Read<string>; options: Array<{ value: string; label: string; icon?: Svg; hint?: string }>; onChange: (arg0: string) => void; tag?: string; compact?: boolean }): View;
// What a control does, said under it once the pointer rests on it (half
// a second), with its shortcut beside it: for a button that shows only an
// icon. A press or the pointer leaving hides it. Parts: "tooltip",
// "tooltip-keys".
export declare function Tooltip(props: { label: string; keys?: string; placement?: Placement; children?: unknown }): View;
// a look for what it holds: its sheet, and the look its controls draw with
export declare function Themed(props: { look: Look<any>; children?: unknown }): View;

// The behaviour of what is on or off (WAI-ARIA's checkbox and switch): a
// Press whose activation toggles it, Space and a click (a switch's Enter
// too; a checkbox's not, as the pattern has it), mixed (a checkbox's
// indeterminate) turning on. Its root is a checkbox or a switch to
// assistive technology, checked or mixed, and data-state checked,
// unchecked or mixed for a look's recipes. checked given with no onChange:
// toggled by nothing but the caller; neither: its own state.
//
//   final sw = Toggle.of(props, "switch");
//   <view ref={sw.root}><view ref={sw.part("knob")}/></view>
export declare class Toggle extends Press {
	constructor(slot: string, role: number, checked?: Read<boolean>, mixed?: Read<boolean>, onChange?: (arg0: boolean) => void, disabled?: Read<boolean>);
	// a toggle of props' (a replaced rendering's: Look's render) for a control
	// named slot: a switch ("switch") or a checkbox (any other)
	static of(props: { label: string; checked?: Read<boolean>; indeterminate?: Read<boolean>; onChange?: (arg0: boolean) => void; disabled?: Read<boolean> }, slot: string): Toggle;
	readonly checked: Read<boolean>;
	readonly mixed: Read<boolean>;
	// turns it over (mixed: on), as a press does
	toggle(): void;
}

export declare class CodeActions {
	// the actions declared (once) and their default bindings added to the global keymap (once each)
	static declare(): void;
}

// A code editor's suggestions at the caret (CodeEditor.complete): a list
// drawn under the word they replace, eight rows at most (it scrolls to
// keep the chosen one in view), the chosen one tinted; a row's label, its
// detail quieter at its right. A press on a row chooses and accepts it.
// Colours are the editor's CodeTheme's (its panel, panel border, foreground,
// line numbers and selection).
export declare class CodeCompletion extends Node {
	constructor(editor: CodeEditor);
	readonly items: Completion[];
	readonly chosen: number;
	readonly open: boolean;
	// a row pressed
	onPick: ((arg0: number) => void) | null;
	// shown with these items, its top left at x, y (the editor's pixels)
	show(list: Completion[], x: number, y: number): void;
	hide(): void;
	// the chosen row moved by d (wrapping)
	move(d: number): void;
}

// A code editor (helder.ui.code; helder.ui's README): a CodeView of a CodeModel,
// with its find and replace panel (secondary-F, secondary-H: the matches
// as you type, case, whole words and regular expressions, the next and
// previous, one replaced or all) and its go to line panel (secondary-G),
// over the text's top right. The studio's hooks: revealRange,
// setSelection, decorations (ranges drawn another way: "selected on the
// canvas"), diagnostics (helder.compiler.service's), and onChange with
// each edit's changes (helder.syntax's Change: a Transaction's). complete
// gives suggestions at the caret (CodeCompletion): asked as a word is
// typed and on Control+Space, shown under the word, Up and Down to choose,
// Enter or Tab to put one in, Escape (or moving away) to close them.
//
//   var editor = new CodeEditor(File.getContent(path), path);
//   editor.onChange = changes -> doc = doc.apply(new Transaction(changes));
//   editor.setDiagnostics(service.check(words, cwd).diagnostics, path);
//   editor.addDecoration(el.start, el.end, Color.rgba(0x3b82f6, 0.12));
export declare class CodeEditor extends Node {
	constructor(text?: string, path?: string);
	readonly view: CodeView;
	readonly model: CodeModel;
	// each edit's changes (against the text before, in order: new Transaction(changes))
	onChange: ((arg0: unknown[]) => void) | null;
	// suggestions for the text at caret (null: none), the word they replace from where they say
	complete: ((text: string, caret: number) => Completions | null) | null;
	readonly completion: CodeCompletion;
	// the file's path: its language by its extension (CodeLanguages)
	path: string | null;
	// find's state
	readonly findOpen: boolean;
	readonly replaceOpen: boolean;
	readonly query: string;
	readonly caseSensitive: boolean;
	readonly wholeWord: boolean;
	readonly regex: boolean;
	readonly gotoOpen: boolean;
	// asked for the caret's word (force: also before a word starts, Control+Space)
	suggest(force: boolean): void;
	// the chosen suggestion put in place of its word
	accept(): void;
	// the text (setting it: a new document, its history cleared)
	text: string;
	// the range brought into view (centred), selected when asked
	revealRange(start: number, end: number, select?: boolean): void;
	// one selection, anchor to head (the caret)
	setSelection(anchor: number, head: number): void;
	// several selections ([anchor, head, anchor, head...]; the last the primary)
	setSelections(pairs: number[]): void;
	// a range drawn another way: its background, border, underline; the whole lines it covers or its characters; its id
	addDecoration(start: number, end: number, background?: Color, border?: Color, underline?: Color, wholeLine?: boolean): number;
	removeDecoration(id: number): boolean;
	clearDecorations(): void;
	// a compiler's diagnostics (Service.check's) of this file (file: its path; others left out)
	setDiagnostics(list: Array<{ file: string | null; line: number; column: number; endColumn: number; severity: string; message: string }>, file?: string): void;
	// "Ln 12, Col 5", the selections' count when more than one
	status(): string;
	// the find panel shown (with replace), its query the selection's when on one line, the field focused
	openFind(withReplace: boolean): void;
	closePanels(): void;
	// the matches found again (the query, its options, the text now)
	refreshMatches(): void;
	// the next match after the selection (dir < 0: the one before)
	findNext(dir: number): boolean;
	// the current match replaced, the next one selected
	replaceOne(): boolean;
	// every match replaced (one edit)
	replaceAll(): number;
	// the find options: 0 case, 1 whole word, 2 regular expression
	toggle(k: number): void;
	// the query set (a find panel opened), the first match from the caret selected
	search(q: string): number;
	setReplacement(t: string): void;
	openGoto(): void;
	// to a line (from 1) and column (from 1)
	goToLine(line: number, column?: number): void;
}

// What highlights a language's lines in a code editor (CodeModel): a line
// read from the state at its start, its tokens appended to out (start, end,
// class: helder.syntax.TokenClass, relative to the line, in order) and the
// next line's state returned. States are Ints that are equal when what is
// open at a line's start is the same: the editor reads again only from an
// edited line until a line's state is the one it had. Languages are
// registered by file extension (CodeLanguages); TypeScript, TSX and Haxe
// are helder.syntax's Lexer.
export declare interface CodeLanguage {
	// its name ("tsx", "haxe")
	name(): string;
	startState(): number;
	tokenize(line: string, state: number, out: number[]): number;
	// what starts a line comment ("//"; null: none)
	lineComment(): string | null;
}

// helder.syntax's Lexer as a CodeLanguage (TypeScript, TSX, Haxe, design files)
export declare class SyntaxLanguage {
	constructor(lang: number);
	name(): string;
	startState(): number;
	tokenize(line: string, state: number, out: number[]): number;
	lineComment(): string | null;
}

// The languages by file extension: TypeScript (.ts, .mts, .cts, .js),
// TSX (.tsx, .jsx), Haxe (.hx), design files (.helder) and SQL (.sql) built in;
// register adds more
export declare class CodeLanguages {
	// a language for files ending in .ext (made fresh for each editor: a language may keep state)
	static register(ext: string, make: () => CodeLanguage): void;
	// the language of a path by its extension (null: none, plain text)
	static forPath(path: string): CodeLanguage | null;
}

// A selection: anchor (where it started) to head (the caret); goal: the
// column Up and Down keep (-1: the head's)
declare class Sel {
	constructor(anchor: number, head: number);
	anchor: number;
	head: number;
	goal: number;
	readonly from: number;
	readonly to: number;
	empty(): boolean;
	toString(): string;
}

// A range of the text drawn another way (the studio's "selected on the
// canvas", a search's matches): its background, border and underline (null:
// none), the whole lines it covers or its characters. Its offsets move
// with edits (an insertion at its start or end is outside it).
declare class Decoration {
	constructor(id: number, start: number, end: number, background?: Color, border?: Color, underline?: Color, wholeLine?: boolean);
	readonly id: number;
	start: number;
	end: number;
	background: Color | null;
	border: Color | null;
	underline: Color | null;
	wholeLine: boolean;
}

// A compiler's message on a range of the text (helder.compiler.service's
// Diagnostic placed: its line and columns as offsets), moving with edits
export declare class CodeDiagnostic {
	constructor(start: number, end: number, severity: string, message: string);
	start: number;
	end: number;
	// "error", "warning", "info"
	readonly severity: string;
	readonly message: string;
}

// A code editor's document (CodeEditor's, usable without one): its text
// (Rope), its lines' cached texts and highlighting (CodeLanguage, read
// again from an edited line until a line's state is the one it had), its
// selections (several: multi-cursor), the undo history (each command one
// step, a run of typing or of deleting one; undo restores the selections
// too), and the commands the editor's keys and actions run, each on every
// selection: typing with brackets and quotes paired, Enter keeping the
// indentation (and adding one after an opening bracket), Backspace and
// Delete by characters (grapheme clusters) or words, moves by character,
// word, line, page and file, indent and outdent, a line comment toggled,
// lines duplicated and moved, cursors added above, below and at the next
// occurrence, find and replace. Every edit is a list of changes
// (helder.syntax's Change: offsets of the text before, in order), given to
// onChange as they are: a Transaction's.
declare class CodeModel {
	constructor(text?: string, language?: CodeLanguage);
	readonly rope: Rope;
	language: CodeLanguage | null;
	// the selections, in order and not overlapping; primary: the one the view follows
	readonly sels: Sel[];
	readonly primary: Sel;
	tabSize: number;
	// Tab inserts spaces (else a tab); setText guesses from the file
	insertSpaces: boolean;
	// the file's line endings ("\n" or "\r\n"; the text's are "\n")
	readonly eol: string;
	// lines Page Up and Down move by (the view's)
	pageLines: number;
	// each edit's changes (against the text before, in order)
	onChange: ((arg0: unknown[]) => void) | null;
	// bumped by each edit and selection change
	readonly version: number;
	readOnly: boolean;
	// the most undo steps kept
	historyLimit: number;
	readonly decorations: Decoration[];
	readonly diagnostics: CodeDiagnostic[];
	// the whole text replaced (its line endings made "\n", eol kept; the
	// indentation guessed; the selection at the start, the history cleared)
	setText(text: string): void;
	text(): string;
	// the text with the file's line endings
	fileText(): string;
	readonly length: number;
	readonly lineCount: number;
	// a line's text (kept until it changes)
	line(i: number): string;
	lineStart(i: number): number;
	lineEnd(i: number): number;
	lineOf(pos: number): number;
	// line i's tokens (start, end, TokenClass, ... in the line), read by highlight (null: not yet, or no language)
	lineTokens(i: number): number[] | null;
	// whether every line is highlighted
	highlighted(): boolean;
	// the lines up to last highlighted (read from the first that is not, until
	// a line's state is the one it had; then on to the next edited line);
	// at most budget lines read (-1: any): the lines read
	highlight(last: number, budget?: number): number;
	// changes (against the text now, in order, not overlapping) applied:
	// the selections after (null: the selections mapped through them), the
	// history's kind (TYPE, DELETE: runs joined); false when read only or none
	apply(changes: unknown[], after?: Sel[], kind?: number, record?: boolean): boolean;
	// the selections replaced (the last the primary, unless one given)
	setSels(list: Sel[], primaryOne?: Sel): void;
	// one selection, anchor to head
	select(anchor: number, head: number): void;
	// a cursor (or selection) added
	addSel(anchor: number, head: number): void;
	// the selections sorted, those that overlap (or cursors at the same place) merged
	normalize(): void;
	// only the primary selection kept (Escape)
	collapse(): boolean;
	selectAll(): void;
	moveLeft(extend?: boolean): void;
	moveRight(extend?: boolean): void;
	moveWordLeft(extend?: boolean): void;
	moveWordRight(extend?: boolean): void;
	// Home: to the line's first non-blank character, from there to the line's start
	moveLineStart(extend?: boolean): void;
	moveLineEnd(extend?: boolean): void;
	moveDocStart(extend?: boolean): void;
	moveDocEnd(extend?: boolean): void;
	moveUp(extend?: boolean): void;
	moveDown(extend?: boolean): void;
	movePageUp(extend?: boolean): void;
	movePageDown(extend?: boolean): void;
	// the column of offset pos on its line (tabs to the next stop, wide characters two)
	column(pos: number): number;
	// the column of the first n units of a line's text t
	columnIn(t: string, n: number): number;
	// the columns a UTF-16 unit takes at column col: a tab to the next stop,
	// a pair's second unit none, East Asian wide characters and others
	// outside the BMP two
	width(c: number, col: number): number;
	// the offset at a column of a line (the nearest character boundary; its end when shorter)
	offsetAtColumn(l: number, col: number): number;
	// the offset a grapheme cluster before pos (a line's start: the line before's end)
	prevChar(pos: number): number;
	nextChar(pos: number): number;
	// the start of the word (or run of punctuation) before pos, over blanks; a line's start stops it
	wordLeft(pos: number): number;
	wordRight(pos: number): number;
	// the word around pos (or the run of other characters), start and end
	wordAt(pos: number): { start: number; end: number };
	// text typed at every selection: a bracket or quote paired (around a
	// selection, or before a blank, a closer or the line's end), a closer
	// typed over the same one after the caret; a run of typing is one undo
	type(s: string): void;
	// Enter: a line break at every selection, the line's indentation kept
	// (one more after an opening bracket or tag; between a pair, the
	// closer on a line of its own)
	newline(): void;
	// the indentation one level adds: a tab or tabSize spaces
	unit(): string;
	// Backspace: the selections' text, else the cluster (or word) before
	// each caret; between a pair just typed, both; in a line's indentation
	// of spaces, back to the previous stop
	backspace(word?: boolean): void;
	// Delete: the selections' text, else the cluster (or word) after each caret
	deleteForward(word?: boolean): void;
	// text over every selection (a paste: as many pieces as cursors, one each)
	insert(text: string, kind?: number): void;
	// the selections' text, one a line (empty selections: their whole lines)
	copyText(): string;
	// copy, then the selections deleted (empty ones: their lines)
	cutText(): string;
	// the lines of every selection deleted
	deleteLines(): void;
	// Tab: the selected lines indented, else an indentation at each caret
	indent(): void;
	// Shift+Tab: one indentation off the selected lines (or the carets')
	outdent(): void;
	// the selected lines commented with the language's line comment, or
	// uncommented when every one (but blank ones) is
	toggleComment(): void;
	// each selection's lines copied below them (up: above), the selections on the copies
	duplicateLines(up?: boolean): void;
	// each selection's lines moved a line up (or down), the selections with them; false at the file's edge
	moveLines_(down: boolean): boolean;
	moveLinesUp(): boolean;
	moveLinesDown(): boolean;
	// a cursor on the line above (below) each one, at its column
	addCursorVertical(by: number): void;
	// Secondary+D: the word at the primary caret selected; then the next
	// occurrence of the selected text added as a selection (from the last
	// one on, around the end); false when there is no other
	addNextOccurrence(caseSensitive?: boolean): boolean;
	// the matches of query (start, end pairs, in order): plain text (case
	// sensitive or not, whole words or not) or a regular expression
	findAll(query: string, caseSensitive?: boolean, wholeWord?: boolean, regex?: boolean): number[];
	// the matches replaced (start, end pairs; one edit, undone as one)
	replaceMatches(matches: number[], replacement: string): boolean;
	canUndo(): boolean;
	canRedo(): boolean;
	undo(): boolean;
	redo(): boolean;
	// a range drawn another way (Decoration): its id, for removeDecoration
	addDecoration(start: number, end: number, background?: Color, border?: Color, underline?: Color, wholeLine?: boolean): number;
	removeDecoration(id: number): boolean;
	clearDecorations(): void;
	// a compiler's messages placed on the text: its lines (from 1) and
	// columns (Haxe's: characters from 1, the end excluded; an empty range
	// one character wide); messages of other files (file given and not
	// ending as theirs) and without a line left out
	setDiagnostics(list: Array<{ file: string | null; line: number; column: number; endColumn: number; severity: string; message: string }>, file?: string): void;
	// the diagnostics over offset pos (the most severe first)
	diagnosticsAt(pos: number): CodeDiagnostic[];
}

// A code editor's colours, by theme token: a StyleSheet's light and dark
// colours of these names (without the dashes) win, else a look's token for
// it (TOKENS: the page's and the gutter's, the selection, the cursor, the
// diagnostics', the panels'; the syntax's have none), else the defaults here
// (GitHub's light and dark): "code-background", "code-foreground", the
// token classes' ("code-keyword", "code-string", "code-number",
// "code-comment", "code-type", "code-function", "code-tag",
// "code-attribute", "code-punctuation"), the gutter's ("code-gutter",
// "code-line-number", "code-line-number-active"), "code-current-line",
// "code-selection", "code-cursor", "code-indent-guide", "code-whitespace",
// the diagnostics' ("code-error", "code-warning", "code-info"), find's
// ("code-find-match", "code-find-current") and "code-panel" (find's and go
// to line's panel). Resolved once per sheet and appearance.
export declare class CodeTheme {
	constructor();
	static readonly NAMES: string[];
	static readonly BACKGROUND: number;
	static readonly FOREGROUND: number;
	// (the token classes' colours: TokenClass + 1, Plain the foreground)
	static readonly GUTTER: number;
	static readonly LINE_NUMBER: number;
	static readonly LINE_NUMBER_ACTIVE: number;
	static readonly CURRENT_LINE: number;
	static readonly SELECTION: number;
	static readonly CURSOR: number;
	static readonly INDENT_GUIDE: number;
	static readonly WHITESPACE: number;
	static readonly ERROR: number;
	static readonly WARNING: number;
	static readonly INFO: number;
	static readonly FIND_MATCH: number;
	static readonly FIND_CURRENT: number;
	static readonly PANEL: number;
	static readonly PANEL_BORDER: number;
	static readonly TOOLTIP: number;
	// the colours now, by the indices above
	readonly colors: Color[];
	// the colours for a sheet and an appearance (again only when either changed)
	resolve(sheet: StyleSheet | null, dark: boolean): void;
	// a token class's colour
	token(cls: number): Color;
}

// A code editor's text, drawn (CodeEditor's; usable alone): a CodeModel's
// lines virtualised (only the lines in view are highlighted, laid out and
// drawn; a line laid out is kept with it until its text or tokens change,
// and by its content: lines alike share one), in a monospace font
// (JetBrains Mono, bundled; ligatures off unless asked), on a grid of
// columns (tabs to tabSize, wide characters two). A gutter of line
// numbers and diagnostics' markers, the current line, selections,
// cursors that blink (moved at once, as editors do), indentation guides,
// whitespace shown in selections, decorations, find's matches,
// diagnostics' squiggles with their message on hover. Typing, an input
// method's composition (at the primary caret, its text context the
// caret's line: TSF, NSTextInputClient, text-input-v3 and XIM as for
// EditableText), the pointer (a click places the caret, a drag selects,
// a double click a word, a triple click a line, Shift extends, Alt adds a
// cursor; in the gutter, lines) and the wheel; keys are CodeAction's,
// through the keymap. To assistive technology a multi-line text input:
// its text, the primary selection and caret.
export declare class CodeView extends Node {
	constructor(model?: CodeModel);
	readonly model: CodeModel;
	readonly codeTheme: CodeTheme;
	// the font: a monospace family (the bundled JetBrains Mono by default), its size, the lines' height in pixels
	fontFamily: string;
	fontSize: number;
	lineHeight: number;
	// ligatures (calt, liga): off by default
	ligatures: boolean;
	lineNumbers: boolean;
	indentGuides: boolean;
	// the caret's line marked; its background and gutter's drawn (false: what is behind shows, a document's code block)
	currentLine: boolean;
	background: boolean;
	// the scroll offsets (pixels)
	readonly scrollTop: number;
	readonly scrollLeft: number;
	// after each edit, move or change of what is shown (a status bar's line and column)
	onUpdate: (() => void) | null;
	// a find's matches drawn (start, end pairs, in order) and the current one (-1: none)
	matches: number[];
	currentMatch: number;
	// an input method's composition at the primary caret (not in the text until committed)
	readonly composition: string;
	// (keys that type are its: not shortcuts, not the window's scrolling)
	takesText(): boolean;
	changed(reveal?: boolean): void;
	// the range's start brought into view (centred: in the middle of the view)
	revealRange(start: number, end: number, center?: boolean): void;
	// scrolled to (clamped): whether it moved
	scrollTo(left: number, top: number): boolean;
	// where offset pos is drawn, from the view's top left (pixels): x, its line's top
	pointOf(pos: number): { x: number; y: number };
	// the offset at a point of the node (its own pixels)
	offsetAt(lx: number, ly: number): number;
	// the composition now (empty: none), its caret: shown at the primary caret, not typed
	compose(s: string, at: number): void;
	textInputArea(): Rect | null;
	// (the caret's line and the primary selection in it, for the input method)
	textContext(): { text: string; start: number; end: number; multiline: boolean; secret: boolean } | null;
	// (an input method's edit of the caret's line: start...end of it replaced)
	replaceText(start: number, end: number, s: string): void;
	accessValue(): string | null;
	accessText(): { start: number; end: number; caret: number; readOnly: boolean } | null;
	select(start: number, end: number): void;
	// a CodeAction on the text: whether it did something
	run(a: unknown): boolean;
}

// A code editor's text: a rope of chunks (each at most MAX UTF-16 units,
// never splitting a surrogate pair), each with its length, its UTF-8
// length and its line breaks, and their prefix sums kept from the first
// chunk an edit touched: an edit rebuilds one or two chunks (a few KB, not
// the file), an offset's line and a line's start are binary searches over
// the chunks then a search in one, and UTF-16 offsets (the String's, the
// editor's) map to UTF-8 bytes (helder.view.Source's, a language
// server's) and back the same way. Lines end with "\n" ("\r\n" is the
// owner's to normalise: CodeModel does on load).
declare class Rope {
	constructor(text?: string);
	// UTF-16 units, lines (breaks + 1), UTF-8 bytes
	readonly length: number;
	readonly lineCount: number;
	readonly utf8Length: number;
	// bumped by each edit
	readonly version: number;
	// the whole text replaced
	set(text: string): void;
	toString(): string;
	// start...end replaced by text (offsets clamped)
	replace(start: number, end: number, text: string): void;
	insert(pos: number, text: string): void;
	delete(start: number, end: number): void;
	// the UTF-16 unit at pos (-1: none)
	codeAt(pos: number): number;
	substring(start: number, end: number): string;
	// the offset where line starts (0-based; past the last: the length)
	lineStart(line: number): number;
	// the offset of line's end (before its "\n")
	lineEnd(line: number): number;
	// the line of offset pos
	lineOf(pos: number): number;
	// a line's text, without its "\n"
	lineText(line: number): string;
	// the UTF-8 byte offset of UTF-16 offset pos
	utf8Of(pos: number): number;
	// the UTF-16 offset of UTF-8 byte offset b (inside a character: its start)
	utf16Of(b: number): number;
	// the chunks (tests: their sizes within MAX)
	chunkLengths(): number[];
}

// SQL's lines highlighted: keywords (any case), strings ('...', a quote
// doubled inside), quoted names ("..." and `...`: types' colour), numbers,
// -- comments and /* */ ones across lines, a name before "(" a function's
export declare class SqlLanguage {
	constructor();
	name(): string;
	startState(): number;
	lineComment(): string | null;
	tokenize(line: string, state: number, out: number[]): number;
}

export declare function Stack(props: { router: Router; transition?: StackTransition }): View;

export declare function NavScreen(props: NavScreenProps): View;
// a bar's item: an icon or a label, 44 points square at least (a touch's)
export declare function NavButton(props: { label: string; icon?: Svg; tag?: string; disabled?: Read<boolean>; variant?: string; onPress: () => void }): View;

export declare function Sheet(props: SheetProps): unknown;

// (TypeScript's builders of the model, helder/ui's item, separator,
// submenu and role: Haxe has MenuItem's constructors)
export declare function item(label: string, action: any): MenuItem;
export declare function separator(): MenuItem;
export declare function submenu(label: string, items: MenuItem[]): MenuItem;
// (a standard item: "about", "quit", "copy"..., MenuRole's; its label the platform's unless given)
export declare function role(role: string, label?: string): MenuItem;
// a context menu at x, y (window layout pixels) for from (its actions
// dispatched from there; default: the focus)
export declare function popup(ui: unknown, items: MenuItem[], x: number, y: number, from?: Node): void;
// (TypeScript's resolve: the items as the platform's menus take them, from the focus or from)
export declare function resolve(ui: unknown, items: MenuItem[], from?: Node): PlatformMenuItem[];

// a value, or a function of none that reads it (bound)
type Value<T> = T | (() => T);

// a neutral element's attributes (helder.view.Vocabulary): the style
// properties (StyleProps, CSS's names in camel), the others HTML's and
// helder's in camel, ARIA's and data-* as HTML writes them, its handlers
// given ui's events (helder.ui.view.NodeEvents)
// a text's content: text, values, its spans (elements), what reads them
export type TextContent = string | number | boolean | null | undefined | import("helder/view").View | (() => unknown) | TextContent[];

// (a number's also a length as CSS writes one, "12px", "env(safe-area-inset-top)")
export type StyleAttributes = {[K in keyof import("./style").StyleProps]?: Value<import("./style").StyleProps[K] | (number extends import("./style").StyleProps[K] ? string : never)>};

export interface Attributes extends StyleAttributes {
	key?: unknown;
	style?: import("./style").StyleProps | null;
	id?: Value<string>;
	class?: Value<string>;
	role?: Value<string>;
	hidden?: Value<boolean>;
	disabled?: Value<boolean>;
	required?: Value<boolean>;
	tabIndex?: Value<number | string>;
	autoFocus?: Value<boolean>;
	focusable?: Value<boolean>;
	selectable?: Value<boolean>;
	slot?: Value<string>;
	variant?: Value<string>;
	size?: Value<string>;
	host?: Value<string>;
	group?: Value<string>;
	peer?: Value<string>;
	tag?: Value<string>;
	states?: Value<unknown>;
	keyContext?: Value<string>;
	actions?: Value<unknown>;
	trackFocus?: Value<unknown>;
	dragRegion?: Value<boolean>;
	dragData?: Value<unknown>;
	panAxis?: Value<"x" | "y" | "both">;
	panMinPointers?: Value<number>;
	motion?: Value<unknown>;
	motionLayout?: Value<unknown>;
	motionOpacity?: Value<unknown>;
	motionColor?: Value<unknown>;
	motionTransform?: Value<unknown>;
	motionRadius?: Value<unknown>;
	motionPresence?: Value<unknown>;
	lead?: Value<unknown>;
	trail?: Value<unknown>;
	instant?: Value<boolean>;
	matched?: Value<string>;
	ride?: Value<unknown>;
	lang?: Value<string>;
	[aria: `aria-${string}`]: unknown;
	[data: `data-${string}`]: unknown;
	onPress?: ((event: Event) => void) | null;
	onPointerDown?: ((event: Event) => void) | null;
	onPointerUp?: ((event: Event) => void) | null;
	onPointerMove?: ((event: Event) => void) | null;
	onPointerEnter?: ((event: Event) => void) | null;
	onPointerLeave?: ((event: Event) => void) | null;
	onPointerCancel?: ((event: Event) => void) | null;
	onLostPointerCapture?: ((event: Event) => void) | null;
	onWheel?: ((event: Event) => void) | null;
	onKeyDown?: ((event: Event) => void) | null;
	onKeyUp?: ((event: Event) => void) | null;
	onTextInput?: ((event: Event) => void) | null;
	onComposition?: ((event: Event) => void) | null;
	onInput?: ((event: Event) => void) | null;
	onFocus?: ((event: Event) => void) | null;
	onBlur?: ((event: Event) => void) | null;
	onFocusIn?: ((event: Event) => void) | null;
	onFocusOut?: ((event: Event) => void) | null;
	onDragStart?: ((event: Event) => void) | null;
	onDragOver?: ((event: Event) => void) | null;
	onDragLeave?: ((event: Event) => void) | null;
	onDrop?: ((event: Event) => void) | null;
	onDragEnd?: ((event: Event) => void) | null;
	onResize?: ((event: Event) => void) | null;
	onTap?: ((event: unknown) => void) | null;
	onLongPress?: ((event: unknown) => void) | null;
	onPan?: ((event: unknown) => void) | null;
	onPinch?: ((event: unknown) => void) | null;
	onScale?: ((event: unknown) => void) | null;
}

export interface ViewAttributes extends Attributes {
	ref?: ((node: Node) => void) | null;
	children?: unknown;
	glassSpacing?: Value<number>;
}

export interface ScrollAttributes extends Attributes {
	ref?: ((node: Node) => void) | null;
	children?: unknown;
	glassSpacing?: Value<number>;
}

export interface TextAttributes extends Attributes {
	ref?: ((node: TextNode) => void) | null;
	children?: TextContent;
	text?: Value<string>;
}

export interface ImageAttributes extends Attributes {
	ref?: ((node: Node) => void) | null;
	children?: never;
	src?: Value<unknown>;
	objectFit?: Value<ImageFit>;
	objectPosition?: Value<string>;
	mirrored?: Value<boolean>;
}

export interface IconAttributes extends Attributes {
	ref?: ((node: Node) => void) | null;
	children?: never;
	name?: Value<string>;
	mirrored?: Value<boolean>;
}

export interface FieldAttributes extends Attributes {
	ref?: ((node: TextField) => void) | null;
	children?: never;
	value?: Value<string>;
	placeholder?: Value<string>;
	type?: Value<string>;
	readOnly?: Value<boolean>;
	maxLength?: Value<number>;
	spellCheck?: Value<boolean>;
	inputMode?: Value<string>;
	autoComplete?: Value<string>;
	keyboard?: Value<string>;
	enterKeyHint?: Value<string>;
	autoCapitalize?: Value<string>;
	autoCorrect?: Value<boolean>;
	onSubmit?: ((event: Event) => void) | null;
}

export interface TextAreaAttributes extends Omit<FieldAttributes, "ref" | "onSubmit"> {
	ref?: ((node: TextArea) => void) | null;
	rows?: Value<number>;
}

export interface GlassAttributes extends Attributes {
	ref?: ((node: Node) => void) | null;
	children?: unknown;
	tint?: Value<Color | string>;
	interactive?: Value<boolean>;
}

export interface WebViewAttributes extends Attributes {
	ref?: ((node: Node) => void) | null;
	children?: never;
	src?: Value<unknown>;
	html?: Value<string>;
	content?: Value<unknown>;
	inspectable?: Value<boolean>;
	zoom?: Value<boolean>;
	transparent?: Value<boolean>;
	backGesture?: Value<boolean>;
	onMessage?: ((event: WebViewEvent) => void) | null;
	onNavigate?: ((event: WebViewEvent) => void) | null;
	onUrlChange?: ((event: WebViewEvent) => void) | null;
	onLoad?: ((event: WebViewEvent) => void) | null;
	onTitle?: ((event: WebViewEvent) => void) | null;
	onProgress?: ((event: WebViewEvent) => void) | null;
	onLoadError?: ((event: WebViewEvent) => void) | null;
	onConsole?: ((event: WebViewEvent) => void) | null;
	onCrash?: ((event: WebViewEvent) => void) | null;
}

export interface LinkAttributes extends Omit<TextAttributes, "ref"> {
	ref?: ((node: TextNode) => void) | null;
	href?: Value<string>;
}

export interface LabelAttributes extends Omit<TextAttributes, "ref"> {
	ref?: ((node: TextNode) => void) | null;
	for?: Value<string>;
}

declare global {
	namespace JSX {
		// the neutral elements: ui's, realised by each renderer
		interface IntrinsicElements {
			view: ViewAttributes;
			text: TextAttributes;
			scroll: ScrollAttributes;
			image: ImageAttributes;
			icon: IconAttributes;
			field: FieldAttributes;
			glass: GlassAttributes;
			webview: WebViewAttributes;
			a: LinkAttributes;
			article: ViewAttributes;
			aside: ViewAttributes;
			button: ViewAttributes;
			code: TextAttributes;
			em: TextAttributes;
			fieldset: ViewAttributes;
			footer: ViewAttributes;
			form: ViewAttributes;
			h1: TextAttributes;
			h2: TextAttributes;
			h3: TextAttributes;
			h4: TextAttributes;
			h5: TextAttributes;
			h6: TextAttributes;
			header: ViewAttributes;
			label: LabelAttributes;
			legend: TextAttributes;
			li: ViewAttributes;
			main: ViewAttributes;
			nav: ViewAttributes;
			ol: ViewAttributes;
			p: TextAttributes;
			section: ViewAttributes;
			strong: TextAttributes;
			textarea: TextAreaAttributes;
			ul: ViewAttributes;
		}
	}
}

export {};
