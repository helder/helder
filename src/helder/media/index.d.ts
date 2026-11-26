// helder.media for TypeScript programs (helder.typescript): <video> in a
// window's markup (its node, VideoNode: play, pause, seek, step and its
// time, duration and playing signals), a Player for audio alone, the
// byte sources a file is read from.
//
// Generated from helder's Haxe types (helder.typescript.api.Declarations: node
// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.
import type {ImageFit, Node} from "helder/ui";
import type {Signal} from "helder/view";

declare const __haxe: {Player: "helder.media.Player", ByteSource: "helder.media.ByteSource", VideoNode: "helder.media.ui.VideoNode", FileSource: "helder.media.FileSource", MemorySource: "helder.media.MemorySource", __module: "helder.media.TypeScript"};

export type PlayerOptions = { device?: string; silent?: boolean };

// A video or audio file played: its first video and audio tracks decoded
// by the system's decoders (Decoders) a little ahead of the clock
// (Playback) on a task of the loop, the audio into an output of its own
// (helder.os.audio.Audio, at the decoder's rate: the system resamples),
// which is the clock; the picture due now is update()'s. The controls
// are the app's: play, pause, seek, step, rate, volume, muted, loop.
//
//   var p = Player.open(new FileSource("clip.mp4"));
//   p.onLoaded = () -> p.play();
//   // each frame: var f = p.update(); draw f (helder.media.ui.VideoTexture)
export declare class Player {
	static open(source: ByteSource, options?: PlayerOptions): Player;
	readonly media: unknown | null;
	readonly video: unknown | null;
	readonly audio: unknown | null;
	// an audio track this system does not decode, played without it (Vorbis
	// where helder's decoder is not linked: VorbisDecoder.link; null: none)
	readonly unheard: unknown | null;
	// seconds (0 until loaded)
	readonly duration: number;
	readonly loaded: boolean;
	readonly error: string | null;
	readonly ended: boolean;
	readonly playing: boolean;
	readonly time: number;
	// the frame shown at the last update (null: none yet)
	readonly shown: unknown | null;
	rate: number;
	volume: number;
	muted: boolean;
	loop: boolean;
	onLoaded: (() => void) | null;
	onEnded: (() => void) | null;
	onError: ((arg0: string) => void) | null;
	// a frame came in (decoded, or due): what shows it draws again
	onFrame: (() => void) | null;
	play(): void;
	pause(): void;
	// to time (seconds): exact, the frame due then (decoded from the
	// keyframe before it, the frames between not shown); else the keyframe
	// before it, sooner
	seek(time: number, exact?: boolean): void;
	// a frame on (1) or back (-1), paused
	step(n: number): void;
	// the frame to show now: the latest due of those decoded (a frame:
	// update keeps it, its caller must not release it)
	update(): unknown | null;
	close(): void;
}

// A file's bytes at any offset, awaited: what the demuxers read, a box or
// a cluster at a time, never the whole file. read puts at most len bytes
// at offset into b from pos and returns how many (fewer only at the end,
// 0 past it); size is the bytes in all, -1 while not known.
export declare interface ByteSource {
	readonly size: number;
	read(offset: number, b: Uint8Array, pos: number, len: number): Promise<number>;
	close(): void;
}

// A video in helder.ui, <video> in markup (NodeRenderer's element_video):
//
//   <video src="clip.mp4" objectFit="cover" autoPlay loop muted flexGrow={1} ref={v -> video = v}/>
//
// src a path or a helder.media.ByteSource (a file's bytes: a MemorySource;
// a signal: another file when it changes); objectFit, autoPlay, loop,
// muted, volume, playbackRate; layer={true}: the system's
// AVSampleBufferDisplayLayer where the window has system layers, not
// helder's drawing; onLoaded, onEnded, onError, onTime (VideoEvents). Its
// player's controls are the node's (ref): play, pause, seek, step, and its
// time, duration and playing signals. An audio file plays the same way
// without a box (helder.media.Player).
//
// Its Player's frame shown in
// the content box as fit says (contain by default), its size the
// picture's (upright) where the style gives none. Drawn by helder
// (VideoTexture: the frame turned to RGB in a pass of its own, then drawn
// as a <Scene>'s box is), so that it is in captures, headless frames and
// every compositor. layer: the system's own layer instead, in a window of
// system layers (helder.ui.layers.apple.Layers) where the node is a plain
// rectangle (no radius) and the picture upright (SampleLayer:
// AVSampleBufferDisplayLayer, the frames queued with their times on a
// timebase kept to the player's clock; Android's android.Layers: SurfaceLayer,
// MediaCodec rendering onto a SurfaceControl; Windows' windows.Layers: WinLayer,
// a DirectComposition surface in the slot's visual), clipped and moved with its
// scrollers; asked for, not the default, until its colours are measured
// on hardware (a virtual Mac's window server showed them some 30 levels
// off). While it plays the animation clock ticks it (Clock.add): the
// frame due picked, time set. The controls are the app's.
export declare class VideoNode extends Node {
	constructor();
	readonly player: Player | null;
	fit: ImageFit;
	// the system's layer where the window has them (else drawn by helder)
	layer: boolean;
	autoplay: boolean;
	loop: boolean;
	muted: boolean;
	volume: number;
	rate: number;
	// seconds: where it is, how long it is; whether it plays
	readonly time: Signal<number>;
	readonly duration: Signal<number>;
	readonly playing: Signal<boolean>;
	onLoaded: (() => void) | null;
	onEnded: (() => void) | null;
	onError: ((arg0: string) => void) | null;
	// each frame it plays, and after a seek or a step: the time
	onTime: ((arg0: number) => void) | null;
	// what it plays: a path (in a browser: a URL) or a ByteSource (a file's bytes: a MemorySource; null: nothing)
	open(src: string | ByteSource | null): void;
	play(): void;
	pause(): void;
	// to t seconds (exact: the frame due then; else its keyframe, sooner)
	seek(t: number, exact?: boolean): void;
	// a frame on (1) or back (-1), paused
	step(n: number): void;
	// the picture's size upright (0 x 0 before it is loaded)
	picture(): { width: number; height: number };
	// lets go of the player and what shows it
	dispose(): void;
}

// A local file as a ByteSource: natively, and on wasm32-wasi where the
// runtime has files (node's WASI; a browser has none: WebSource). Reads
// do not suspend: a local file's are short.
export declare class FileSource {
	constructor(path: string);
	readonly size: number;
	read(offset: number, b: Uint8Array, pos: number, len: number): Promise<number>;
	close(): void;
}

// Bytes already in memory as a ByteSource.
export declare class MemorySource {
	constructor(bytes: Uint8Array);
	readonly size: number;
	read(offset: number, b: Uint8Array, pos: number, len: number): Promise<number>;
	close(): void;
}

type Value<T> = T | (() => T);
type UiAttributes = import("helder/ui").Attributes;

// <video> (helder.media.ui.VideoNode): a neutral element's attributes and its own
export interface VideoAttributes extends UiAttributes {
	ref?: ((node: VideoNode) => void) | null;
	children?: never;
	src?: Value<unknown>;
	objectFit?: Value<import("helder/ui").ImageFit>;
	autoPlay?: Value<boolean>;
	loop?: Value<boolean>;
	muted?: Value<boolean>;
	volume?: Value<number>;
	playbackRate?: Value<number>;
	layer?: Value<boolean>;
	onLoaded?: ((event: VideoNode) => void) | null;
	onEnded?: ((event: VideoNode) => void) | null;
	onError?: ((event: string) => void) | null;
	onTime?: ((event: number) => void) | null;
}

declare global {
	namespace JSX {
		interface IntrinsicElements {
			video: VideoAttributes;
		}
	}
}

export {};
