// helder.scenario for TypeScript programs (helder.typescript):
// scenario({name, set, time, seed, size, dark, loop, play}), the real
// program (its main) at a moment of its named data signals' values
// (helder.view.Named), a screen of the studio's preview host beside the
// stories (helder/story's screens(stories, scenarios, main))
//
// Generated from helder's Haxe types (helder.typescript.api.Declarations: node
// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.

declare const __haxe: {scenario: "helder.scenario.Scenario.define", __module: "helder.scenario.TypeScript"};

export declare class Scenario {
	private readonly scenario: never;
}

// scenario({...})'s fields (TypeScript's helder/scenario the same)
export type ScenarioDef = { name: string; set?: {[name: string]: unknown}; time?: string | number; seed?: number; size?: number[]; dark?: boolean; loop?: number; play?: number };

// (TypeScript's scenario({...}): helder/scenario)
export declare function scenario(def: ScenarioDef): Scenario;

export {};
