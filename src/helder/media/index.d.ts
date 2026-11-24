// helder.media for TypeScript programs (helder.typescript): <Video> in a
// window's markup (its node, VideoNode: play, pause, seek, step and its
// time, duration and playing signals), a Player for audio alone, the
// byte sources a file is read from.
//
// Generated from helder's Haxe types (helder.typescript.api.Declarations: node
// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.
import type {Node} from "helder/ui";
import type {Read, Signal} from "helder/view";

declare const __haxe: {Player: "helder.media.Player", VideoNode: "helder.media.ui.VideoNode", FileSource: "helder.media.FileSource", MemorySource: "helder.media.MemorySource", MediaTags: "helder.media.ui.MediaTags", __module: "helder.media.TypeScript"};

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
	static open(source: unknown, options?: PlayerOptions): Player;
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

// A video in helder.ui (<Video>, MediaTags): its Player's frame shown in
// the content box as fit says (contain by default), its size the
// picture's (upright) where the style gives none. Drawn by helder
// (VideoTexture: the frame turned to RGB in a pass of its own, then drawn
// as a <Scene>'s box is), so that it is in captures, headless frames and
// every compositor. layer: the system's own layer instead, in a window of
// system layers (helder.ui.draw.CaLayers) where the node is a plain
// rectangle (no radius) and the picture upright (SampleLayer:
// AVSampleBufferDisplayLayer, the frames queued with their times on a
// timebase kept to the player's clock; Android's ScLayers: SurfaceLayer,
// MediaCodec rendering onto a SurfaceControl; Windows' DcLayers: WinLayer,
// a swap chain in the slot's visual), clipped and moved with its
// scrollers; asked for, not the default, until its colours are measured
// on hardware (a virtual Mac's window server showed them some 30 levels
// off). While it plays the animation clock ticks it (Clock.add): the
// frame due picked, time set. The controls are the app's.
export declare class VideoNode extends Node {
	constructor();
	readonly player: Player | null;
	fit: number;
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
	open(src: any | null): void;
	play(): void;
	pause(): void;
	// to t seconds (exact: the frame due then; else its keyframe, sooner)
	seek(t: number, exact?: boolean): void;
	// a frame on (1) or back (-1), paused
	step(n: number): void;
	// the picture's size upright (0 x 0 before it is loaded)
	picture(): { width: number; height: number };
	hasContent(): boolean;
	measureContent(engine: unknown, knownWidth: number, knownHeight: number, availWidth: number, availHeight: number): unknown;
	paintContent(canvas: unknown, x: number, y: number, width: number, height: number): void;
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

// helder.media's markup, imported with import helder.media.ui.MediaTags.*:
//
//   <Video src="clip.mp4" fit="cover" autoplay loop muted grow={1} ref={v -> video = v}/>
//
// layer={true}: the system's AVSampleBufferDisplayLayer where the window
// has system layers, not helder's drawing (VideoNode.layer)
//
// <Video> is a box of helder.ui's showing a video (VideoNode): src a path
// or a helder.media.ByteSource (a file's bytes: a MemorySource; a signal:
// another file when it changes); its player's controls are the node's
// (ref): play, pause, seek, step, and its time, duration and playing
// signals. An audio file plays the same way without a box (helder.media.Player).
export declare class MediaTags {
	static Video(props: { src?: any; fit?: any; autoplay?: boolean; loop?: boolean; muted?: Read<boolean>; volume?: Read<number>; rate?: Read<number>; layer?: boolean; grow?: number; width?: Read<any>; height?: Read<any>; style?: any; onLoaded?: () => void; onEnded?: () => void; onError?: (arg0: string) => void; onTime?: (arg0: number) => void; ref?: (arg0: VideoNode) => void }): Node;
}

export declare const Video: typeof MediaTags.Video;
