// helder.view for TypeScript programs (helder.typescript): signals,
// computations, markup (TSX) and its control flow, on helder.view.graph
// (DESIGN.md). Each class is the Haxe class `__haxe` names; a function is one
// of a class's statics (`__haxe` names it), called directly by the compiled
// program, its values converted by the types Haxe declares (the manifest,
// DESIGN.md 7.3); a signal, a memo or a Read comes to the program as a
// function.
//
// Generated from helder's Haxe types (helder.typescript.api.Declarations: node
// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.

declare const __haxe: {render: "helder.view.Render.render", insert: "helder.view.Render.insert", signal: "helder.view.graph.Graph.signalValue", memo: "helder.view.graph.Graph.memo", effect: "helder.view.graph.Graph.effect", renderEffect: "helder.view.graph.Graph.renderEffect", flush: "helder.view.graph.Scheduler.flush", untrack: "helder.view.graph.Graph.untrack", root: "helder.view.graph.Graph.root", onCleanup: "helder.view.graph.Graph.onCleanup", onSettled: "helder.view.graph.Graph.onSettled", isPending: "helder.view.graph.Graph.isPending", For: "helder.view.Flow.For", Repeat: "helder.view.Flow.Repeat", Show: "helder.view.Flow.Show", Switch: "helder.view.Flow.Switch", Match: "helder.view.Flow.Match", Loading: "helder.view.Flow.Loading", Errored: "helder.view.Flow.Errored", __module: "helder.view.TypeScript"};

// A value in the graph (DESIGN.md 3.1): called to read it (tracked inside
// a computation), called with a value to write it, with a function to
// update it from the latest value written (a write is committed at the
// next flush: reads see the committed value until then). Made by
// Graph.signal: a value, or a function for a value derived from what it
// reads that can also be written. Never a function itself.
export interface Signal<T> {
	(): T;
	// (update before write: an argument of no static type, Dynamic, is then a
	// write (Haxe picks the last overload it fits), a function literal an
	// update; chosen by the static type, never the value: a Dynamic that is
	// a function at run time is an error (Node.set), not written, not an update)
	(f: (arg0: T) => T): void;
	(value: T): void;
	// the committed value, not tracked
	peek(): T;
}

// A derived value (DESIGN.md 2, Memos): called to read it, computed when
// first read and again when read after what it read changed; its readers
// are marked only when the result differs.
export interface Memo<T> {
	(): T;
	// the value, not tracked
	peek(): T;
}

// A prop that reads (DESIGN.md 3.2): a constant, a signal, a memo or a
// function, each read by calling it (`props.step()`), tracked as what it
// reads is. Markup binds a prop of this type the way Solid binds props: a
// hole that may read (3.3) is given as a function of it, so the component
// reads the value when it uses it, not when it is made:
//
//   function Counter(props:{step:Read<Int>}) ...
//   <Counter step={1}/>  <Counter step={size}/>  <Counter step={a() + b()}/>
//
// A constant is a small cell, not a closure; a signal or a memo is its node.
declare const readBrand: unique symbol;
export interface Read<T> {
	readonly [readBrand]: T;
	(): T;
}

// what makes a Read: a TSX site's component props take one of these (JSX.LibraryManagedAttributes)
export type ReadFrom<T> = Read<T> | Signal<T> | Memo<T> | (() => T) | T;

// A markup literal's value: what mounts its nodes. Write markup in a class
// that implements Markup (every literal in it is compiled), or through
// view(<...>):
//
//   class App implements Markup {
//     static function main()
//       Render.render(<view padding={8}>
//         <text>Hello {name}!</text>
//         {[for (i in items) <text>{i}</text>]}
//         <Button label="OK" onClick={() -> trace("ok")}/>
//       </view>, root);
//   }
//
// The literal's holes ({expr} children and attribute values) are evaluated
// where it is; mount then makes its elements (the renderer's, by tag:
// lowercase names), sets their attributes and inserts them, each time it is
// mounted, by the renderer that owns the place it is mounted in (each
// literal is compiled for the renderer that owns it, or for each the
// program reaches). Other names
// are components: Button(props) called when mounted, untracked, in an
// owner of its own, props an object of its attributes (children: the
// content, a View), checked against Button's argument.
export declare class View {
	private readonly view: never;
}

// options of a signal and a memo
export type NodeOptions<T> = { equals?: (arg0: T, arg1: T) => boolean; unobserved?: () => void; ownedWrite?: boolean };

// a root's content (Root): a literal expected as one holds components only,
// a component returning one is a root (<Surface>), no renderer's markup
export type RootView = unknown;

// renders content into parent (its root: dispose removes it and stops its effects)
export declare const render: (content: unknown, parent: unknown) => () => void;
// inserts content into parent before a node (null: at the end); the nodes made
export declare const insert: (content: unknown, parent: unknown, before: unknown) => unknown[];

// (a value's signal, as TypeScript's signal(v) calls it: index.d.ts)
export declare function signal<T>(value: T extends Function ? never : T): Signal<T>;
export declare function memo<T>(fn: (prev: T | null) => T | PromiseLike<T>, options?: NodeOptions<T>): Memo<T>;
// compute runs now and again when what it read changes; apply after the
// commit, given its value and the previous one (the first: at the next
// flush); error, when given, takes compute's errors (else the nearest
// error boundary, else flush throws them)
export declare function effect<T>(compute: (prev: T | null) => T | PromiseLike<T>, apply: (value: T, prev: T | null) => void | (() => void), error?: (arg0: any) => void): void;
// as effect, its apply in the render phase: before every effect's
export declare function renderEffect<T>(compute: (prev: T | null) => T | PromiseLike<T>, apply: (value: T, prev: T | null) => void | (() => void), error?: (arg0: any) => void): void;
// fn's reads not tracked
export declare function untrack<T>(fn: () => T): T;
// a new ownership tree, owned by the current owner if any: fn gets its dispose
export declare function root<T>(fn: (dispose: () => void) => T): T;
// fn runs when the current owner is disposed or runs again
export declare function onCleanup(fn: () => void): void;
// fn run once the current commit has landed (its applies done), not
// tracked: after the nodes being rendered are in the tree (Solid 2's
// onSettled, onMount's successor); disposed with the current owner
export declare function onSettled(fn: () => void): void;
// whether what fn reads has a new value on its way (a held change, an
// async answer to a new question): looks ahead of the hold, never holds
// it; a first load gives no verdict (false; tracked, it suspends as the
// read would); an error in fn is false
export declare function isPending(fn: () => unknown): boolean;

export declare function flush(): void;

export declare function For<T>(props: { each: Read<T[]>; keyed?: boolean; by?: (arg0: T) => any; children: (arg0: Read<T>) => unknown }): unknown;
export declare function Repeat(props: { count: Read<number>; children: (arg0: number) => unknown }): unknown;
export declare function Show<T>(props: { when: Read<T>; fallback?: unknown; children?: unknown }): unknown;
export declare function Switch(props: { fallback?: unknown; children?: unknown }): unknown;
export declare function Match<T>(props: { when: Read<T>; children?: unknown }): unknown;
export declare function Loading(props: { fallback?: unknown; children?: unknown }): unknown;
export declare function Errored(props: { fallback: (error: any, reset: () => void) => unknown; children?: unknown }): unknown;

declare global {
	namespace JSX {
		type Element = View;
		// components may return any content
		type ElementType = string | ((props: any) => unknown);
		interface ElementChildrenAttribute {
			children: {};
		}
		// a component's props: Read as what makes one
		type LibraryManagedAttributes<C, P> = {[K in keyof P]: NonNullable<P[K]> extends Read<infer T> ? ReadFrom<T> | Extract<P[K], undefined> : P[K]};
		// a renderer's elements: their attributes are the renderer's to check
		interface IntrinsicElements {
			[tag: string]: {[attribute: string]: unknown};
		}
	}
}

export {};
