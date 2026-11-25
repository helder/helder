// helder.test's runner for TypeScript programs (helder.typescript): what
// helder/test (src/helder/test/index.ts: test, describe, the hooks, the
// assertions, snapshots) registers and reports through, the runner of
// `*.test.hx` (helder.test.Script). A program imports helder/test, not
// this module.
//
// Generated from helder's Haxe types (helder.typescript.api.Declarations: node
// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.
import type {View} from "helder/view";

declare const __haxe: {Script: "helder.test.Script", Entry: "helder.test.Runner.Entry", UiScript: "helder.test.UiScript", PropertyScript: "helder.test.PropertyScript", Choices: "helder.test.Choices", __module: "helder.test.TypeScript"};

// helder.test's runner for TypeScript test files (helder/test, its
// index.ts, over runner.d.ts: helder.test.TypeScript): the same
// groups, hooks, filters, snapshots and report as `*.test.hx`'s. Each step
// of a TypeScript test is started with its timeout and calls done once:
// with null, with the error's text, or stopped (require and fail, their
// failure recorded already). Positions are "file:line", the call's, which
// helder's compiler gives each assertion of helder/test (the lowering's
// Definitions).
export declare class Script {
	// a test file's tests follow, its module evaluated (helder test's main
	// imports each one after this call)
	static file(path: string): void;
	static test(name: string, start: (seconds: number, done: (error: string | null, stopped: boolean) => void) => void): Entry;
	static describe(name: string, body: () => void): Entry;
	// beforeEach (0), afterEach (1), beforeAll (2), afterAll (3)
	static hook(kind: number, start: (seconds: number, done: (error: string | null, stopped: boolean) => void) => void): void;
	// an error while the file's tests or a group's are registered
	static registering(error: string): void;
	static check(): void;
	static failure(message: string, at: string): void;
	static timedOut(seconds: number): void;
	// a value's text against the file's snapshot of this name (Foo.test.ts's Foo.test.snap)
	static snapshot(name: string, value: string, at: string): void;
	static run(): void;
}

// a test or a group, as registered: marked skipped, only, or with a timeout
export declare class Entry {
	readonly name: string;
	// left out (reported as skipped)
	skip(): Entry;
	// run with the others marked only, the rest left out
	only(): Entry;
	// seconds each async step may take (a group's: each of its tests')
	timeout(seconds: number): Entry;
	// "describe > test", without the file
	fullName(): string;
}

export declare class UiScript {
	// on macOS secondary is Command (Keymap.mac, known at start)
	static setMac(mac: boolean): void;
	// a Ui of no window (tests), its text helder's own (helder.story's, the same on every system)
	static headless(width: number, height: number): unknown;
	// content rendered into its root and laid out (dispose removes it)
	static mount(ui: unknown, content: View): (() => void);
	static layout(ui: unknown): void;
	// each keystroke of keys typed ("ctrl-k ctrl-s"), through the keymap
	static type(ui: unknown, keys: string): void;
}

// helder/test's properties for TypeScript (its index.ts: Gen, property,
// stateful, assume): the generators of helder.test.Gen as functions of a
// case's Choices, and a property's run through Property. A TypeScript body
// or step returns null when it passed, "" when it stopped (its failure
// recorded), else its error's text; one that caught a Rejected or an
// Overran (assume, a filter, a sequence run out) has it thrown again here.
// Options a property doesn't set are null.
export declare class PropertyScript {
	static int(min: number, max: number): ((arg0: Choices) => number);
	static float(min: number, max: number): ((arg0: Choices) => number);
	static bool(): ((arg0: Choices) => boolean);
	static char(nul: boolean): ((arg0: Choices) => string);
	// an index into n items, shrinking to 0 (pick, oneOf)
	static index(n: number): ((arg0: Choices) => number);
	// min to max items drawn by item, each one given to add (an array's)
	static items(c: Choices, item: (arg0: Choices) => any, min: number, max: number, add: (arg0: any) => void): void;
	// (a TypeScript catch took a Rejected or an Overran)
	static pending(): boolean;
	static reject(): void;
	static property(gen: (arg0: Choices) => any, body: (arg0: any) => string | null, show: (arg0: any) => string, cases: number | null, seconds: number | null, seed: number | null, replay: string | null, at: string): void;
	// a machine of count steps, its system kept by the TypeScript side
	// (a value through Dynamic is a copy): step i's name, its run (its result
	// as a body's), whether it can run
	static stateful(setup: () => void, count: number, name: (arg0: number) => string, run: (arg0: number, arg1: Choices) => string | null, when: (arg0: number) => boolean, check: () => string | null, teardown: () => void, show: (arg0: any) => string, cases: number | null, seconds: number | null, seed: number | null, replay: string | null, steps: number | null, at: string): void;
}

// A property's test case as the choices it made (Hypothesis' choice
// sequence): each draw reads one or more ints, each in 0...=bound, made at
// random when generating and read back when replaying a sequence. Shrinking
// edits the sequence (Property), so 0 is each choice's simplest value and
// the generators (Gen) map it to theirs: an int's 0 or its bound nearest
// to it, an array's end, a pick's first item.
export declare class Choices {
	// the most choices a case makes: past it the case is overran (a
	// recursion's bound in the last resort)
	static readonly MAX: number;
	// a value of g (a Gen), drawn from these choices
	draw<T>(g: (arg0: Choices) => T): T;
	// a choice in 0...=bound, shrinking to 0 (when generating: a fifth of
	// them 0, bound or small, else uniform)
	choice(bound: number): number;
	// true with probability p when generating (a choice of 0 or 1, false shrunk to)
	weighted(p: number): boolean;
	// text shown with a failing case (a stateful step's name and arguments)
	note(text: string): void;
	// the case is left out (assume, filter): rejected, not failed
	reject(): any;
}

export {};
