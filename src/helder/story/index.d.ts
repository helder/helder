// helder.story for TypeScript programs (helder.typescript): story({name,
// render, seed, store, caption, background, color}), a definition (its
// fields checked where they are written, as Haxe's helder.story.Story.story;
// nothing in a release build), each story's view made from its Controls;
// tree(story), its tree mounted headless as helder test snapshots it
// (its markup helder.ui's: the neutral elements, its renderer); screens
// (stories), the studio's program of a project's screens (Screens); play
// (story), one in a window of its own (the studio's Play); shots
// (stories), helder publish's program of its screenshots (StoreShots).
//
// Generated from helder's Haxe types (helder.typescript.api.Declarations: node
// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.
import "helder/ui";
import type {Scenario} from "helder/scenario";
import type {Signal, View} from "helder/view";

declare const __haxe: {Controls: "helder.story.Story.Controls", story: "helder.story.Stories.define", tree: "helder.story.Stories.tree", screens: "helder.story.Screens.run", play: "helder.story.Screens.play", shots: "helder.story.StoreShots.run", __module: "helder.story.TypeScript"};

export declare class Story {
	private readonly story: never;
}

// story({...})'s fields, as a TypeScript program gives them (helder/story:
// Stories.define, the definition checked them where they are written)
export type StoryDef = { name: string; render: (arg0: Controls) => View; seed?: number; width?: number; height?: number; loop?: number; store?: boolean; caption?: string; background?: number; color?: number; feature?: boolean };

// A story's controls: each a signal its view reads, recorded with its name
// and kind for an editor (the values a store screenshot uses are their
// defaults); random, a generator of the story's seed; settled, false while
// the scene is not ready (a store screenshot waits for it); play, a story
// that runs to a moment (a game mid-play): unsettled until its clock has
// run that long, the renderers running its frames on a virtual clock;
// onDispose, what to let go with the story
declare class Controls {
	constructor(seed?: number);
	readonly seed: number;
	readonly list: Array<{ name: string; kind: string; value: any; options?: string[] }>;
	// each control's signal by its name (an editor's change: the studio's Story.set)
	readonly signals: unknown;
	readonly settled: Signal<boolean>;
	number(name: string, value: number): Signal<number>;
	bool(name: string, value: boolean): Signal<boolean>;
	text(name: string, value: string): Signal<string>;
	choice(name: string, options: string[], value?: string): Signal<string>;
	// 0xAARRGGBB
	color(name: string, value: number): Signal<number>;
	// the story plays for seconds of its clock, then is settled: what runs
	// on the clock (helder.ui's Clock: a game's frame, its physics, the
	// transitions) gets there frame by frame, Stories.FPS a second, whatever
	// the machine's speed (Stories.settle; a store screenshot, helder.run's,
	// a test's tree: that moment). In the studio it runs live, as it would.
	// Called while the story renders (its render function): its clock's
	play(seconds: number): void;
	// f called when the story is let go (a renderer done with it: a store
	// screenshot taken, a test's tree read): what it made that outlives its
	// view, a game's scene world, its GPU resources
	onDispose(f: () => void): void;
	// (the renderer's: the story let go, onDispose's in their order)
	dispose(): void;
	// the next of the seed's numbers in [0, 1) (xorshift32): the same story, the same scene
	random(): number;
}

// story({...}) in a TypeScript program (helder/story; the definition
// checked its fields where they are written)
export declare function story(def: StoryDef): Story;
// the tree as text: each node's tag (or kind), box and text, indented
// (in a phone's size, WIDTH x HEIGHT, unless given)
export declare function tree(s: Story, width?: number, height?: number): string;

// (scenarios: the program's moments, its main run for each: helder.scenario)
export declare function screens(stories: Story[], scenarios?: Scenario[], program?: () => void): void;
// one story in a window of its own, at its size, live, its input its own:
// the studio's Play (`helder dev` on a main of it, rebuilt in place)
//
//   import { play } from "helder/story"; import { serve } from "./pong.story"; play(serve);
export declare function play(story: Story): void;

// (TypeScript's shots(stories): main over them; helder/story)
export declare function shots(stories: Story[]): void;

export {};
