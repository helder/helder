// helder.scenario for TypeScript programs (helder.typescript):
// scenario({name, boot, time, zone, locale, settings, http, steps, seed, size, dark,
// loop, play}), the real program at a moment: its root rendered in a screen
// with a store of its own, boot writing the app's signals first, its steps
// (tap, type, press, scroll, drag, waitFor) after (helder/story's
// screens(stories, scenarios), the studio's preview host)
//
// Generated from helder's Haxe types (helder.typescript.api.Declarations: node
// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.
import type {SettingsOverride} from "helder/os";

declare const __haxe: {scenario: "helder.scenario.Scenario.define", hold: "helder.scenario.Player.hold", play: "helder.scenario.Player.run", tap: "helder.scenario.Steps.tap", type: "helder.scenario.Steps.type", press: "helder.scenario.Steps.press", scroll: "helder.scenario.Steps.scroll", drag: "helder.scenario.Steps.drag", waitFor: "helder.scenario.Steps.waitFor", __module: "helder.scenario.TypeScript"};

export declare class Scenario {
	private readonly scenario: never;
}

// a step (tap, type, press, scroll, drag, waitFor make one)
export declare class Step {
	private readonly step: never;
}

// a query's fields, each given matched (a string: a role's name, else a label, a text, an id)
export type Query = { role?: string; name?: string; label?: string; text?: string; id?: string };

// scenario({...})'s fields (TypeScript's helder/scenario the same)
export type ScenarioDef = { name: string; boot?: () => void; time?: string | number; seed?: number; zone?: string; locale?: string; settings?: SettingsOverride; http?: Record<string, number | string | object>; steps?: Step[]; size?: number[]; dark?: boolean; loop?: number; play?: number };

// (TypeScript's scenario({...}): helder/scenario; its position this file's, none)
export declare function scenario(def: ScenarioDef): Scenario;

// (main's root held, its top-level effects recorded: before the app's modules run)
export declare function hold(): void;
// the window of one of list, by its name (another of them played later
// in it); no name: the one the page's ?scenario= names (a share's web
// build, helder.run's Play from here), else the app from its start
export declare function play(list: Scenario[], name?: string): void;

// a tap at the node's centre (a press and its release)
export declare function tap(query: string | Query): Step;
// text typed into the node (tapped first: its focus)
export declare function type(query: string | Query, text: string): Step;
// a key pressed and let go in what has the focus: "Enter", "Escape", "Tab",
// "Backspace", "ArrowUp" and the other arrows, "Space", or a character
export declare function press(key: string): Step;
// the scroll view of the node scrolled: to "end", "start", by points (a
// number), or until another query is shown
export declare function scroll(query: string | Query, to: "end" | "start" | number | string | Query): Step;
// a press at from (a query, or {x, y} in points) moved to to (a query, or
// {x, y}, or {dx, dy} from from) and let go, as a mouse drags
export declare function drag(from: string | Query | {x: number; y: number}, to: string | Query | {x: number; y: number} | {dx: number; dy?: number}): Step;
// the clock run until the query is shown (a minute of it at most)
export declare function waitFor(query: string | Query): Step;

export {};
