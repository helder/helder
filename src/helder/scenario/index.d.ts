// helder.scenario for TypeScript programs (helder.typescript):
// scenario({name, boot, time, seed, size, dark, loop, play}), the real
// program at a moment: its root rendered in a screen with a store of its
// own, boot writing the app's signals first (helder/story's
// screens(stories, scenarios), the studio's preview host)
//
// Generated from helder's Haxe types (helder.typescript.api.Declarations: node
// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.

declare const __haxe: {scenario: "helder.scenario.Scenario.define", __module: "helder.scenario.TypeScript"};

export declare class Scenario {
	private readonly scenario: never;
}

// scenario({...})'s fields (TypeScript's helder/scenario the same)
export type ScenarioDef = { name: string; boot?: () => void; time?: string | number; seed?: number; size?: number[]; dark?: boolean; loop?: number; play?: number };

// (TypeScript's scenario({...}): helder/scenario)
export declare function scenario(def: ScenarioDef): Scenario;

export {};
