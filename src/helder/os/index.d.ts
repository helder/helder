// helder.os for TypeScript programs (helder.typescript): what an app keeps
// between runs (Store), the platform's settings, locale and app services
// (Settings, Locale, Format, Plural, Network, Share, Permissions), the
// program's arguments and environment (args(), env(name): Sys's). Its
// windows, events and App are helder/scene's.
//
// Generated from helder's Haxe types (helder.typescript.api.Declarations: node
// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.
import type {Read} from "helder/view";

declare const __haxe: {Store: "helder.os.Store", Settings: "helder.os.Settings", Locale: "helder.os.Locale", Format: "helder.os.Format", Plural: "helder.os.Plural", Network: "helder.os.Network", Share: "helder.os.Share", Permissions: "helder.os.Permissions", Sys: "Sys", __module: "helder.os.TypeScript"};

export type Contrast = "normal" | "more" | "less" | "custom";

export type Orientation = "portrait" | "landscape";

export type Style = "short" | "medium" | "long" | "full";

export type NumberOptions = { decimals?: number; percent?: boolean; currency?: string; locale?: string };

export type DateOptions = { date?: Style; time?: Style; locale?: string };

export type PluralCategory = "zero" | "one" | "two" | "few" | "many" | "other";

export type NetworkKind = "none" | "wifi" | "cellular" | "wired" | "other";

export type Permission = "camera" | "microphone" | "photos" | "location" | "notifications";

export type PermissionStatus = "granted" | "denied" | "prompt" | "unsupported";

// A small key-value store kept between runs: an app's settings, a game's
// save. Strings by key, read into memory when opened, written through at
// each change (set, remove, clear), where the platform keeps an app's data:
//
//   Linux     $XDG_DATA_HOME/<name>/store.json (~/.local/share/<name>/)
//   macOS     ~/Library/Application Support/<name>/store.json
//   Windows   %APPDATA%\<name>\store.json
//   Android   the app's files directory (ANativeActivity's internalDataPath)/<name>.json
//   iOS       the app's Library/Application Support/<name>.json ($HOME is its container)
//   the web   localStorage, the item "helder.store/<name>" (an origin's: a
//             page of several programs names each its own)
//
//   var save = Store.open("golf");
//   var best = save.get("best") ?? "";
//   save.set("best", "3,2,4");
//
// The file is JSON (an object of strings), written to a temporary file then
// renamed over the old one, so a crash mid-write leaves the last one whole.
// A store that cannot be read (none yet, damaged) opens empty; one that
// cannot be written (a read-only disk, a private window) keeps its values
// for the run (written false). dir puts the file elsewhere (tests; wasm32
// without localStorage, as under node's WASI: "." by default). In a
// headless run (-D helder.headless) a store without dir starts empty and
// stays in memory: what an earlier run, or the user's own app, kept does
// not change what the run shows, and the run keeps nothing.
export declare class Store {
	// the stores open() gives while set (null: the platform's): a screen's of
	// a story host (helder.ui.ScreenContext, which sets it while current),
	// each name's store in memory, kept for the run
	static scope: unknown | null;
	// the store of that name (letters, digits, '.', '-' and '_'), in the platform's place or in dir
	static open(name: string, dir?: string): Store;
	readonly name: string;
	// the file (the web: "")
	readonly path: string;
	// whether the last change reached the disk or localStorage
	readonly written: boolean;
	get(key: string): string | null;
	exists(key: string): boolean;
	keys(): string[];
	set(key: string, value: string): void;
	remove(key: string): void;
	clear(): void;
}

export declare class Settings {
	static readonly textScale: Read<number>;
	static readonly reducedMotion: Read<boolean>;
	static readonly contrast: Read<Contrast>;
	static readonly dark: Read<boolean>;
	static readonly orientation: Read<Orientation | null>;
}

// The device's preferred languages.
export declare class Locale {
	static readonly current: Read<string>;
	// An ordered list of the user's preferred language tags.
	static preferred(): string[];
}

export declare class Format {
	static number(x: number, options?: NumberOptions): string;
	static date(d: Date, options?: DateOptions): string;
}

export declare class Plural {
	static category(locale: string, n: number): PluralCategory;
}

// whether the device is online, and through what, sampled about once a
// second while the app runs and again when it comes back to the foreground
export declare class Network {
	static readonly online: Read<boolean>;
	static readonly kind: Read<NetworkKind>;
}

export declare class Share {
	// the system's share sheet of text, a URL and files (paths): whether the
	// user shared, where the system tells, else whether it was shown
	static share(item: { text?: string; url?: string; files?: string[] }): Promise<boolean>;
}

export declare class Permissions {
	// whether the app may use p: Prompt when asking would show the system's dialog
	static status(p: Permission): PermissionStatus;
	// the system's dialog where status is Prompt, its answer; otherwise the
	// status. What is asked for is declared by the build (Android's
	// manifest, iOS's usage strings: helder.json's ios.usage)
	static request(p: Permission): Promise<PermissionStatus>;
}

export declare class Sys {
	static args(): string[];
	static getEnv(s: string): string | null;
}

export declare const args: typeof Sys.args;
export declare const env: typeof Sys.getEnv;
