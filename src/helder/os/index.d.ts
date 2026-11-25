// helder.os for TypeScript programs (helder.typescript): what an app keeps
// between runs (Store), the platform's settings, locale and app services
// (Settings, Locale, Format, Plural, Network, Share, Permissions,
// Notifications, Photos, Location, Biometrics, Paths, Places, Trash, DeviceInfo,
// StatusBar), the program's arguments and environment (args(), env(name):
// Sys's). Its windows, events and App are helder/scene's.
//
// Generated from helder's Haxe types (helder.typescript.api.Declarations: node
// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.
import type {Read} from "helder/view";

declare const __haxe: {Store: "helder.os.Store", Settings: "helder.os.Settings", Locale: "helder.os.Locale", Format: "helder.os.Format", Plural: "helder.os.Plural", Network: "helder.os.Network", Share: "helder.os.Share", Permissions: "helder.os.Permissions", Notifications: "helder.os.Notifications", Photos: "helder.os.Photos", Location: "helder.os.Location", Biometrics: "helder.os.Biometrics", Paths: "helder.os.Paths", Places: "helder.os.Places", Trash: "helder.os.Trash", DeviceInfo: "helder.os.DeviceInfo", StatusBar: "helder.os.StatusBar", Sys: "Sys", __module: "helder.os.TypeScript"};

export type Contrast = "normal" | "more" | "less" | "custom";

export type Orientation = "portrait" | "landscape";

export type Style = "short" | "medium" | "long" | "full";

export type NumberOptions = { decimals?: number; percent?: boolean; currency?: string; locale?: string };

export type DateOptions = { date?: Style; time?: Style; locale?: string };

export type PluralCategory = "zero" | "one" | "two" | "few" | "many" | "other";

export type NetworkKind = "none" | "wifi" | "cellular" | "wired" | "other";

export type Permission = "camera" | "microphone" | "photos" | "location" | "notifications";

export type PermissionStatus = "granted" | "denied" | "prompt" | "unsupported";

export type GeoPosition = { latitude: number; longitude: number; accuracy: number; altitude?: number; heading?: number; speed?: number; time: number };

export type BiometricKind = "none" | "face" | "fingerprint" | "other";

export type DeviceKind = "phone" | "tablet" | "desktop" | "web";

export type DeviceDetails = { model: string; manufacturer: string; os: string; osVersion: string; kind: DeviceKind };

export type BarStyle = "light" | "dark" | "auto";

export type PlaceKind = "Home" | "Desktop" | "Documents" | "Downloads" | "Pictures" | "Movies" | "Music";

export type Place = { kind: PlaceKind; name: string; path: string };

export type Volume = { name: string; path: string; total: number; free: number; removable: boolean; network: boolean; root: boolean };

// A small key-value store kept between runs: an app's settings, a game's
// save. Strings by key, read into memory when opened, written through at
// each change (set, remove, clear), where the platform keeps an app's data:
//
//   Linux     $XDG_DATA_HOME/<name>/store.json (~/.local/share/<name>/)
//   macOS     ~/Library/Application Support/<name>/store.json
//   Windows   RoamingAppData\<name>\store.json (%APPDATA%)
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

// Local notifications: shown at a time (at), after some seconds (after),
// or now; a tap opens the app and gives onOpen the notification's id,
// those tapped before it was set given when it is. Asking to show them
// is Permissions.request(Notify)'s.
export declare class Notifications {
	static onOpen: ((arg0: string) => void) | null;
	// whether it was scheduled (false where the system has none for the app)
	static schedule(n: { id: string; title: string; body?: string; at?: Date; after?: number }): boolean;
	static cancel(id: string): void;
}

// The system's photo picker: the images the user picks, each its file's
// bytes as encoded (JPEG, PNG, HEIC...; helder.image decodes most), at
// most max (1); none when cancelled. Picking needs no permission.
export declare class Photos {
	// the camera: a photo the user takes, as a JPEG (the web: the file the
	// browser gives); null when cancelled or where there is no camera
	// (front: the front camera, where the system lets the app choose). iOS
	// asks to use the camera by itself, with helder.json's usage string
	// "camera"; Android's camera app takes the photo, no permission needed.
	static take(options?: { front?: boolean }): Promise<Uint8Array | null>;
	static pick(options?: { max?: number }): Promise<Uint8Array[]>;
}

// Where the device is: one fix (current) or each new one until stopped
// (watch), while the app is in use. The permission is Permissions'
// Location, asked for by current and watch while it is Prompt; null (no
// fix) when it is denied or there is none. Precise false asks for
// coarse accuracy (Android's ACCESS_COARSE_LOCATION alone; a few
// kilometres on Apple's), which may answer sooner.
export declare class Location {
	static current(options?: { precise?: boolean }): Promise<GeoPosition | null>;
	// f with each fix, on the app's loop, until the function returned is called
	static watch(f: (arg0: GeoPosition) => void, options?: { precise?: boolean }): (() => void);
}

// The device's biometrics: what verify would use (None where there is none
// or none is enrolled), and whether the user is verified by it, the
// system's prompt showing the reason. iOS's Face ID needs helder.json's
// usage string "faceid"; Android's USE_BIOMETRIC is added to the manifest.
export declare class Biometrics {
	static kind(): BiometricKind;
	static verify(reason: string): Promise<boolean>;
}

// The app's directories, absolute, each made when missing; null where
// there are none (the web):
// - data: persistent and the app's own;
// - cache: kept while there is room, which the system may empty;
// - temp: for a while;
// - documents: the user's, where they see the app's files: the Files app
//   on iOS (Info.plist's UIFileSharingEnabled and
//   LSSupportsOpeningDocumentsInPlace, set by use), the app's folder of
//   Android's shared storage, the desktop's Documents.
// The desktop's data and cache are under the app's name (macOS: its bundle
// id; else the executable's name).
export declare class Paths {
	static data(): string | null;
	static cache(): string | null;
	static temp(): string | null;
	static documents(): string | null;
}

// Existing user folders, and mounted volumes a file browser can show.
export declare class Places {
	static user(): Place[];
	// The system volume first; capacities in bytes (zero when unknown).
	static volumes(): Volume[];
}

// The system's trash (desktop only).
export declare class Trash {
	static available(): boolean;
	// Answers the item's new path where the system gives it. Throws on failure.
	static move(path: string): string | null;
}

// What the app runs on: the model ("iPhone16,1", "Pixel 4a", "Mac14,2"),
// its maker, the system ("iOS", "Android", "macOS", "Windows", "Linux"; the
// web: the browser's platform) and its version (Linux: the distribution's
// name and version), and the kind of device. "" where the system does
// not tell.
export declare class DeviceInfo {
	static get(): DeviceDetails;
}

// A phone's status bar: its style and whether it shows (iOS's and
// Android's; nothing elsewhere). Android's navigation bar takes the style
// too. Window.immersive hides it as well.
export declare class StatusBar {
	static style(s: BarStyle): void;
	static hidden(h: boolean): void;
}

declare class Sys {
	static args(): string[];
	static getEnv(s: string): string | null;
}

export declare const args: typeof Sys.args;
export declare const env: typeof Sys.getEnv;
