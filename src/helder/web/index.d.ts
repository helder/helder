// helder.web for TypeScript programs (helder.typescript): static pages
// rendered at build time, with islands of WebAssembly (see helder/view; the
// web's elements are lower-case TSX, their attributes as helder.web's
// README has them). Each class is the Haxe class `__haxe` names.
//
// Generated from helder's Haxe types (helder.typescript.api.Declarations: node
// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.
import type {View} from "helder/view";

declare const __haxe: {Static: "helder.web.Static", Island: "helder.web.Island", Surface: "helder.web.WebTags.Surface", Wasm: "helder.web.Island.Wasm", __module: "helder.web.TypeScript"};

// when the loader hydrates an island (data-load)
export type Load = "visible" | "idle" | "load" | "click";

// when a WebAssembly island stops its program (loader.js, data-stop)
export type Stop = "offscreen";

// Static pages: components rendered to HTML at build time with the static
// renderer (StaticRenderer), natively, on Eval or in node:
//
//   class Site implements Markup {
//     static function main() {
//       Static.write("out/index.html", Static.document(<html lang="en">
//         <head><title>hxmc</title><script src="islands-loader.js" defer></script></head>
//         <body><Layout><Demo.Counter start={3}/></Layout></body>
//       </html>));
//     }
//   }
//
// Effects run once, then the page's root is disposed; listeners are
// dropped. Islands (Island) carry their props and the module that hydrates
// them; regions carry the markers hydration reads (HtmlNode).
export declare class Static {
	// content as HTML
	static render(content: unknown): string;
	// a whole page: <!doctype html> and content (an <html> element)
	static document(content: unknown): string;
	// writes a page (or any text), its directories made
	static write(path: string, text: string): void;
	// copies a file (an example's wasm build, a script), its directories made
	static copy(from: string, to: string): void;
}

// Islands: the interactive parts of a static page. An island is a component
// defined once, in code both the page's build (the static renderer) and the
// island's bundle (JavaScript, the DOM renderer) compile:
//
//   class Demo implements Markup {
//     static function CounterView(props:{start:Int}):View ...
//     public static final Counter = Island.define("counter", CounterView, {script: "islands.js", load: Visible});
//   }
//
//   // the page (static): <Demo.Counter start={3}/>
//   // the bundle's main (JavaScript): Islands.start([Demo.Counter]);
//
// On the page it is rendered in an element <hxmc-island> carrying its name,
// its props as JSON (data-props), its bundle (data-src) and when to load it
// (data-load); the loader (src/helder/web/loader.js) loads the bundle then,
// which hydrates the island from its props. Props are JSON: numbers,
// strings, booleans, arrays and objects of them.
//
// A WebAssembly island (Island.Wasm) is a canvas the loader hands to a
// wasm32-wasi module, run by helder.os's browser.mjs with the imports of the
// packages it uses: a ui or gfx canvas inside a page.
export declare class Island<P> {
	// a WebAssembly island: a canvas (width x height, when given) the loader
	// hands to src, a wasm32-wasi module, run by runner (Island.runner) with
	// imports (each package's imports.mjs, as browser.mjs takes them) and
	// args, and fonts (files helder.text may use: a browser gives a module
	// none); its id names it (Wasm.island); children shown with the canvas
	// (a caption, what shows before it runs); assets: the URL of the build's
	// <module>.assets.json (helder.asset's: the files it reads before main,
	// fetched with the module); canvas false: none (a sound);
	// stop Offscreen: stopped once out of view, its GPU memory given back,
	// and run again as load says (loader.js)
	static Wasm(props: { src: string; imports?: string[]; args?: string[]; runner?: string; load?: Load; id?: string; width?: number; height?: number; fonts?: string[]; assets?: string; canvas?: boolean; stop?: Stop; children?: unknown }): View;
}

// a WebAssembly island: a canvas (width x height, when given) the loader
// hands to src, a wasm32-wasi module, run by runner (Island.runner) with
// imports (each package's imports.mjs, as browser.mjs takes them) and
// args, and fonts (files helder.text may use: a browser gives a module
// none); its id names it (Wasm.island); children shown with the canvas
// (a caption, what shows before it runs); assets: the URL of the build's
// <module>.assets.json (helder.asset's: the files it reads before main,
// fetched with the module); canvas false: none (a sound);
// stop Offscreen: stopped once out of view, its GPU memory given back,
// and run again as load says (loader.js)
export declare function Wasm(props: { src: string; imports?: string[]; args?: string[]; runner?: string; load?: Load; id?: string; width?: number; height?: number; fonts?: string[]; assets?: string; canvas?: boolean; stop?: Stop; children?: unknown }): View;

export declare function Surface(props: { src: string; imports?: string[]; fonts?: string[]; args?: string[]; runner?: string; load?: Load; id?: string; className?: string; style?: string; children?: unknown }): View;

export {};
