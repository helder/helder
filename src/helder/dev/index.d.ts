// helder.dev for TypeScript programs (helder.typescript): keep(key, () =>
// initial), a value kept across a reload under `helder dev`, as a signal
// is (a definition: Slot).
//
// Generated from helder's Haxe types (helder.typescript.api.Declarations: node
// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.

declare const __haxe: {keep: "helder.dev.Slot.keep", __module: "helder.dev.TypeScript"};

// a value kept across a reload under `helder dev`: the key a string
// literal, the initial value made by a function of no arguments
export declare function keep<T>(key: string, init: () => T): T;

export {};
