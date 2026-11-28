// helder.ui.fast for TypeScript programs (helder.typescript): fast nodes,
// their styles (style({...}): a Style; a CSS module imported is its
// classes' Styles), themes, and <Fast>, the boundary from helder.ui's
// markup. Markup inside <Fast> is fast nodes' (FastRenderer): helder.ui's
// elements and attributes, style={...} a Style.
//
// Generated from helder's Haxe types (helder.typescript.api.Declarations: node
// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.
import "helder/ui";
import type {Rect} from "helder/os";
import type {Cursor, Event, Node, TextAlign} from "helder/ui";
import type {Read} from "helder/view";

declare const __haxe: {Node: "helder.ui.fast.Node", TextNode: "helder.ui.fast.TextNode", FieldNode: "helder.ui.fast.FieldNode", IconNode: "helder.ui.fast.IconNode", Tree: "helder.ui.fast.Tree", Theme: "helder.ui.fast.Theme", Style: "helder.ui.fast.Style", Fast: "helder.ui.fast.FastTags.Fast", style: "helder.ui.fast.Style.ofProps", __module: "helder.ui.fast.TypeScript"};

export type FastView = unknown;

export type StateProps = { hover?: StyleProps; pressed?: StyleProps; focus?: StyleProps; disabled?: StyleProps; selected?: StyleProps; checked?: StyleProps };

// What a style says, each optional: unset, the initial value (an
// inherited one's: the parent's). The inherited ones are the text's:
// color, fontSize, fontWeight, fontFamily, fontStyle, lineHeight,
// letterSpacing, textAlign, wrap. A literal given to Style.of or with()
// is checked and made typed when the program is built (Props); another
// is read when it runs.
export type StyleProps = { display?: number; flexDirection?: number; flexWrap?: boolean; alignItems?: number; alignSelf?: number; justifyContent?: number; alignContent?: number; flexGrow?: number; flexShrink?: number; flexBasis?: unknown; gap?: number; rowGap?: number; columnGap?: number; width?: unknown; height?: unknown; minWidth?: unknown; minHeight?: unknown; maxWidth?: unknown; maxHeight?: unknown; padding?: number[]; margin?: number[]; borderWidth?: number[]; borderColor?: unknown; borderRadius?: number; background?: unknown; opacity?: number; overflow?: number; position?: number; top?: unknown; right?: unknown; bottom?: unknown; left?: unknown; zIndex?: number; color?: unknown; fontSize?: number; fontWeight?: number; fontFamily?: string; fontStyle?: number; lineHeight?: number; letterSpacing?: number; textAlign?: TextAlign; wrap?: boolean; textOverflow?: number; lineClamp?: number; textDecoration?: number; cursor?: Cursor; justifyItems?: number; justifySelf?: number; gridTemplateColumns?: string; gridTemplateRows?: string; gridTemplateAreas?: string; gridAutoColumns?: string; gridAutoRows?: string; gridAutoFlow?: string; gridColumn?: string; gridRow?: string; gridArea?: string; hover?: StyleProps; pressed?: StyleProps; focus?: StyleProps; disabled?: StyleProps; selected?: StyleProps; checked?: StyleProps; placeholder?: StyleProps; dark?: StyleProps; group?: StateProps };

// A node of a fast tree: a box made from code and styled by a Style, with
// no element, selector or cascade behind it. It is retained: its box is
// kept from one layout to the next and restyled only where its style,
// states, theme or what it inherits change. A Tree shows it in helder.ui.
//
//   final list = new Node(Style.of({rowGap: 4, padding: 8}));
//   list.append(new TextNode("Buy milk", Style.of({fontSize: 16})));
export declare class Node {
	constructor(style?: Style);
	// its style (markup's style={...}; its style attributes over it)
	style: Style;
	readonly parent: Node | null;
	// its subtree's theme (null: its parent's)
	theme: Theme | null;
	// its states are its descendants' group states (a style's group: {...})
	group: boolean;
	// a name to find it by (markup's tag)
	tag: string | null;
	// what it is to assistive technology (its role, label, checked...)
	semantics: unknown | null;
	// focused by Tab and a press (a button and a field are)
	focusable: boolean;
	// above 0: first, in order; 0: in tree order; below 0: by a press alone
	tabIndex: number;
	// pressed: a click let go over it, or Enter or Space while it has the focus (the innermost node with one)
	onPress: ((arg0: Event) => void) | null;
	// a key while it or a node in it has the focus (then its parent's, unless stopped)
	onKeyDown: ((arg0: Event) => void) | null;
	onFocus: ((arg0: Event) => void) | null;
	onBlur: ((arg0: Event) => void) | null;
	onPointerDown: ((arg0: Event) => void) | null;
	onPointerUp: ((arg0: Event) => void) | null;
	onPointerEnter: ((arg0: Event) => void) | null;
	onPointerLeave: ((arg0: Event) => void) | null;
	// A style attribute (markup's: padding={8}, color="#3b82f6"), over its style.
	attr(name: string, value: any): boolean;
	// A node as it was made, without its children: its style, attributes, states, focus and what it is to
	// assistive technology (a markup template's clone, FastRenderer.cloneNode).
	clone(): Node;
	// Its children, in order.
	children(): Node[];
	append(child: Node): void;
	// child before another of its children (null: last); taken from where it was
	insert(child: Node, before: Node | null): void;
	// It out of its parent.
	remove(): void;
	// A state on or off: Style.HOVER, PRESSED, FOCUS, DISABLED, SELECTED, CHECKED.
	state(bit: number, on: boolean): void;
	has(bit: number): boolean;
}

// A node of text: a block of one paragraph, its lines broken to its width.
//
//   final title = new TextNode("Inbox", Style.of({fontSize: 20, fontWeight: 600}));
//   title.text = "Inbox (3)";
export declare class TextNode extends Node {
	constructor(text: string, style?: Style);
	text: string;
	// Its text and its spans', in order.
	allText(): string;
}

// A field of one line typed into: its value, a caret and a selection
// (keys, the clipboard), its placeholder while it is empty (styled by the
// placeholder state's variant). Its Tree gives it the keys and the text
// typed while it has the focus.
//
//   final draft = new FieldNode(Style.of({padding: [8, 12], placeholder: {color: 0xFFA1A1AA}}));
//   draft.placeholder = "What needs to be done?";
//   draft.onInput = e -> trace(e.text);
export declare class FieldNode extends TextNode {
	constructor(style?: Style);
	value: string;
	placeholder: string;
	// its value changed by its user (Event.text: the value)
	onInput: ((arg0: Event) => void) | null;
}

// An icon: lucide's of that name (helder.ui.controls.Icons), drawn in its
// text colour at its size.
//
//   new IconNode("check", Style.of({width: 12, height: 12}));
export declare class IconNode extends Node {
	constructor(name?: string, style?: Style);
	name: string | null;
}

// A fast tree in helder.ui: its root node's boxes laid out at this node's
// size by the engine's block and flex layout, painted from its paint order
// (made again from the last one where boxes kept their fragments, and
// contexts' calls copied from the last paint), hit, hovered, pressed and
// scrolled.
//
//   final tree = new Tree(list, app);  // app: its palette, a Theme
//   UiWindow.run(<UiWindow.Surface title="List">{tree}</UiWindow.Surface>);
export declare class Tree extends Node {
	constructor(root: Node, theme?: Theme);
	readonly root: Node;
	// the theme its nodes resolve tokens in where none of theirs has one
	palette: Theme;
	// Where a node is in the window, as last laid out and scrolled: x, y, width, height (zeros: not laid out).
	rectOf(n: Node): number[];
	// Gives n (one of its nodes, or none) the focus in it, its ring drawn or not.
	focusOn(n: Node | null, ring?: boolean): void;
	takesText(): boolean;
	textInputArea(): Rect | null;
	textContext(): { text: string; start: number; end: number; multiline: boolean; secret: boolean } | null;
	replaceText(start: number, end: number, s: string): void;
	// (no selection begun by a press on what takes presses or the focus)
	selectionScope(): Node | null;
}

// A theme: its tokens' colours, light and dark each, and whether it is
// dark. A style's Theme.token resolves in the theme of the node's scope
// (Node.theme, else its parent's), part of what a style is resolved for,
// so that a theme changed restyles what reads its tokens.
//
//   final app = new Theme(["surface" => [0xFFFFFFFF, 0xFF18181B], "fg" => [0xFF18181B, 0xFFFAFAFA]]);
//   card = Style.of({background: Theme.token("surface"), color: Theme.token("fg")});
export declare class Theme {
	constructor(tokens: unknown, dark?: boolean);
	// the theme of no tokens (a token's colour transparent), light
	static readonly base: Theme;
	// A token of the theme a style resolves in.
	static token(name: string): unknown;
	readonly tokens: unknown;
	readonly dark: boolean;
	// The same tokens, dark or light (one theme each way: what styles resolved in it are cached by).
	tone(dark: boolean): Theme;
	// This theme with others over its tokens.
	with(more: unknown): Theme;
	// a token's colour here (0: none)
	color(name: string): number;
}

// A node's style: an immutable value, interned (equal styles are one
// object, a style on a thousand rows resolved once for each state, parent
// text and theme it meets), with its state variants. with() makes another
// over it. A literal given to Style.of or with() is checked when the
// program is built (a misspelt name, a value of another type: an error
// there) and made as typed fields, no object read field by name at run
// time.
//
//   final row = Style.of({flexDirection: Row, padding: [4, 6], hover: {background: 0xFFF4F4F5}});
//   final picked = row.with({background: Theme.token("accent")});
export declare class Style {
	// the style that says nothing
	static readonly none: Style;
	// The style of props: the one made of the same before, else a new one.
	static of(props: any): Style;
	// (a style of props an object read when the program runs)
	static ofProps(props: StyleProps): Style;
	// a state's bit (Node.state's): hover, pressed, focus, disabled, selected, checked, placeholder; a group's, it shifted by GROUP
	static readonly HOVER: number;
	static readonly PRESSED: number;
	static readonly FOCUS: number;
	static readonly DISABLED: number;
	static readonly SELECTED: number;
	static readonly CHECKED: number;
	static readonly PLACEHOLDER: number;
	static readonly GROUP: number;
	// what it says, its variants in it
	readonly props: unknown;
	// This style with p over it (a variant's too: merged); p a literal, an object, or a Style.
	with(p: any): Style;
	// (what it says in states: its own (mask's low bits) and its group's (shifted by GROUP), the variants over it
	// in order; dark: the theme's tone)
	at(mask: number, dark?: boolean): unknown;
	// (the states it has a variant for: what a change of the others leaves it as it is)
	readonly states: number;
}

// (a style of props an object read when the program runs)
export declare function style(props: StyleProps): Style;

export declare function Fast(props: { theme?: Read<Theme>; style?: any; flexGrow?: number; ref?: (arg0: Tree) => void; actions?: any; children?: FastView }): Node;

export {};
