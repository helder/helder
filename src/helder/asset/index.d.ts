/// <reference path="./imports.d.ts" />
// helder.asset for TypeScript programs (helder.typescript): image(path),
// font, model, sound and bytes, each a handle (Asset) of a file of the
// program found and bundled when it is built (definitions: ScriptAssets);
// loaded(asset), a promise of its value. imports.d.ts declares the
// imports of files with a type (`import icon from "./icon.png" with
// {type: "image"}`, the same definition).
//
// Generated from helder's Haxe types (helder.typescript.api.Declarations: node
// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.
import type {Model} from "../scene/runtime";

declare const __haxe: {Strings: "helder.asset.Strings", image: "helder.asset.ScriptAssets.image", font: "helder.asset.ScriptAssets.font", model: "helder.asset.ScriptAssets.model", sound: "helder.asset.ScriptAssets.sound", bytes: "helder.asset.ScriptAssets.bytes", loaded: "helder.asset.ScriptAssets.loaded", ready: "helder.asset.ScriptAssets.ready", strings: "helder.asset.ScriptAssets.strings", __module: "helder.asset.TypeScript"};

// A file of the program, by its path (AssetPath): an image, a font, a model,
// a sound or bytes. The path is checked when compiling (the file there, in
// that case) and the file goes with every build that still uses it after
// dead code elimination (Bundle: the executable's data on desktop, the APK's
// assets/ on Android, the app's on iOS, beside the page on the web).
//
//   @:coroutine static function start() {
//     var ship = Asset.model("models/ship.glb").load();  // suspends until loaded
//     ship.instantiate(world, device);
//   }
//
// A handle is returned at once, its load started (one per path and kind:
// the same handle each time); load() suspends the calling coroutine until
// it is ready (at once if it is) and throws if it failed. Several at once
// with tasks: task.async(_ -> a.load()), then Async.all. Without
// suspending (the frame loop): ready, peek() (null until then), state.
//
// The handle is an async memo in helder.view's graph. read() tracks it,
// as markup does with the handle itself
// (<image src={icon}/>, a Read prop): pending while it loads (a <Loading>
// boundary above shows its fallback on its first load), the AssetError
// after a failure (an <Errored>'s). A reload's new value is pending in turn
// (Graph.isPending says so), the last one kept meanwhile.
//
// Under `helder dev` the files are read from disk and watched: a change is
// sent to the running program, which loads it again and puts it behind
// the same handle, the engine's objects swapped in place (an Image's
// pixels, a FontFile's glyphs, a Model's meshes and materials: what draws
// them shows the new ones) and its readers run again.
//
// Loads advance on the main thread's loop (helder.async: App.run turns it;
// Assets.poll turns it for a program with a loop of its own).
export declare class Asset<T> {
	private readonly asset: never;
}

// An image's pixels: RGBA8, rows top to bottom, straight (not
// premultiplied) alpha. decode reads a PNG file (PngDecoder), a JPEG
// (JpegDecoder), a GIF (GifDecoder) or a WebP (WebpDecoder); renderers
// (helder.ui's ImageNode, a texture: helder.gfx.ImageTexture) upload it
// once (id: their key) and again after changed(); replace(other) puts
// another image's pixels in this one (helder.asset's reload: what shows it
// shows the new one).
//
// Its pixels are dropped once a renderer uploaded them (uploaded()), when
// it can have them again: from the file it was decoded from (source), or
// in a browser from the file the browser decoded (browser images:
// helder.asset's with decodeInBrowser, never in the module's memory unless
// read). Reading pixels after that decodes the file again, on the calling
// thread; retain keeps them, for an image whose pixels are read back (a
// hit test's alpha, a picker's colours).
//
// With hxmc its pixels may be off the collected heap (held: a job's
// decode, ImageJobs), freed once uploaded or when the image is collected.
// On iOS and Android 11 and later the system decodes all but PNGs
// (SystemDecoder: ImageIO, AImageDecoder): decode reads the file's size only, its pixels decoded where they are first used (an
// upload, premultiplied as the system draws them) and dropped after, so an
// image's pixels are never on the heap unless read.
export declare class Image {
	private readonly image: never;
}

// An OpenType font (an sfnt; one face of a collection, .ttc): its metrics
// in font units, the character map (formats 4 and 12), horizontal
// advances, kerning (GPOS's pair adjustments for the kern feature, else
// the kern table's format 0 pairs) and glyph outlines:
// TrueType's (glyf: simple and composite glyphs, as quadratic contours) or
// CFF's ('OTTO', .otf: Cff, cubic curves). A variable TrueType font's
// axes (axes) give instances (instance: gvar's deltas applied to outlines
// and advances; Variations). CFF2 (variable) outlines are not read:
// FontFile.parse throws. A glyph's points are read into buffers kept for
// the next (outline: nothing allocated but a variable instance's deltas).
export declare class FontFile {
	private readonly fontFile: never;
}

export declare class Strings {
	private constructor();
	// Read a message with named string and number arguments.
	get(key: string, params?: any): string;
}

// an image (helder.image.Image)
export declare function image(path: string, file?: string): Asset<Image>;
// a font (helder.text.FontFile)
export declare function font(path: string, file?: string): Asset<FontFile>;
// a glTF model (helder.scene.render.Model; its names are Haxe's alone)
export declare function model(path: string, file?: string): Asset<Model<any, any, any, any>>;
// a sound file's bytes
export declare function sound(path: string, file?: string): Asset<Uint8Array>;
// a file's bytes
export declare function bytes(path: string, file?: string): Asset<Uint8Array>;
// the asset's value once it is loaded (its AssetError if it failed): a promise
export declare function loaded<T>(asset: Asset<T>): Promise<T>;
// whether it is loaded
export declare function ready<T>(asset: Asset<T>): boolean;
// Load a folder of locale JSON files. Use get(key, params) to read a message.
export declare const strings: (path: string) => Strings;

export {};
