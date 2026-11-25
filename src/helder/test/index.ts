// helder.test for TypeScript programs: `*.test.ts` and `*.test.tsx` files,
// found and run by `helder test` beside the `*.test.hx` ones, natively and
// as wasm32-wasi, through the same runner (helder.test.Runner: its groups,
// hooks, filters, snapshots and report). Tests register at a file's top
// level, as bun's and jest's:
//
//   import { describe, test, equals, snapshot } from "helder/test";
//
//   describe("todos", () => {
//     test("adds", () => equals(add([], "milk").length, 1));
//     test("later", async () => { await delay(1); equals(1, 1); }).timeout(1);
//   });
//
// A body is a function, or an async one (its promise awaited, within its
// timeout). An assertion's failure is located at its call: helder's
// compiler gives each one its file and line (its last parameter, `at`,
// never written by hand: the lowering's Definitions). `equals` compares
// JavaScript values deeply (primitives by SameValueZero, arrays, plain
// objects and instances of the same prototype by their own enumerable
// properties, Map, Set, Date, typed arrays), shown as `show` writes them;
// `snapshot` checks a string, or a value shown, against the file's
// `.snap` beside it (Foo.test.ts's Foo.test.snap; `helder test -u`
// rewrites it). TSX mounts headless with helder/story's `tree`, its
// tree as text, which a snapshot keeps.
import {Script, Entry, UiScript, PropertyScript, Choices as Draws} from './runner'
import type {Ui} from 'helder/ui/actions'

export type { Entry };

// whether secondary is Command (macOS: a window sets it) rather than Control
export function setMac(mac: boolean): void {
  UiScript.setMac(mac)
}

// a Ui of no window (tests), its root to render into, its keymap
export function headless(width: number, height: number): Ui {
  return UiScript.headless(width, height) as any
}

// content (TSX) rendered into its root and laid out, removed by the function returned
export function mount(ui: Ui, content: unknown): () => void {
  return UiScript.mount(ui as any, content as any)
}

// its layout updated (a headless one's)
export function update(ui: Ui): void {
  UiScript.layout(ui as any)
}

// each keystroke of keys typed into the Ui ("ctrl-k ctrl-s"), through its keymap
export function press(ui: Ui, keys: string): void {
  UiScript.type(ui as any, keys)
}

// (thrown by require and fail: the test stops, its failure recorded)
class Stop extends Error {}

type Body = () => void | Promise<unknown>;
type Start = (seconds: number, done: (error: string | null, stopped: boolean) => void) => void;

function errorText(e: unknown): string {
	if (e instanceof Error) return e.name === "Error" ? e.message : `${e.name}: ${e.message}`;
	return show(e);
}

// (a body as the runner's step: its errors and its promise reported once,
// a promise within the step's timeout)
function step(body: Body): Start {
	return (seconds, done) => {
		let finished = false;
		const end = (error: unknown, failed: boolean) => {
			if (finished) return;
			finished = true;
			if (!failed) done(null, false);
			else if (error instanceof Stop) done(null, true);
			else done(errorText(error), false);
		};
		let r: unknown;
		try {
			r = body();
		} catch (e) {
			end(e, true);
			return;
		}
		if (!(r instanceof Promise)) {
			end(undefined, false);
			return;
		}
		const timer = setTimeout(() => {
			if (finished) return;
			Script.timedOut(seconds);
			end(undefined, false);
		}, seconds * 1000);
		r.then(() => {
			clearTimeout(timer);
			end(undefined, false);
		}, (e: unknown) => {
			clearTimeout(timer);
			end(e, true);
		});
	};
}

// a test: its body run with the group's hooks around it
export function test(name: string, body: Body): Entry {
	return Script.test(name, step(body));
}

// a group: body registers its tests, hooks and groups at once
export function describe(name: string, body: () => void): Entry {
	return Script.describe(name, () => {
		try {
			body();
		} catch (e) {
			Script.registering(errorText(e));
		}
	});
}

// before each test of this group (or file) and its groups, outer ones first
export function beforeEach(body: Body): void {
	Script.hook(0, step(body));
}

// after each test, inner ones first, also after a failure
export function afterEach(body: Body): void {
	Script.hook(1, step(body));
}

// once before the group's first test (a failure leaves its tests out)
export function beforeAll(body: Body): void {
	Script.hook(2, step(body));
}

// once after its last
export function afterAll(body: Body): void {
	Script.hook(3, step(body));
}

// --- assertions: a failure is recorded and the test goes on, except for
// require and fail, which stop it. `at`, the call's file and line, is
// given by helder's compiler.

function failure(message: string, at?: string): void {
	Script.failure(message, at ?? "(unknown)");
}

// a failure if false
export function assert(cond: boolean, msg?: string, at?: string): void {
	Script.check();
	if (!cond) failure(msg ?? "assertion failed", at);
}

// deeply equal: both values shown, and where they differ (.list[0].a)
export function equals<T>(actual: T, expected: T, msg?: string, at?: string): void {
	Script.check();
	const where = diff(actual, expected, "");
	if (where === null) return;
	const lines = [msg ?? "not equal", `  expected: ${show(expected)}`, `  actual:   ${show(actual)}`];
	if (where !== "") lines.push(`  (differing at ${where})`);
	failure(lines.join("\n"), at);
}

export function notEquals<T>(actual: T, expected: T, msg?: string, at?: string): void {
	Script.check();
	if (diff(actual, expected, "") === null) failure(`${msg ?? "equal, expected a difference"}\n  both: ${show(actual)}`, at);
}

// |actual - expected| <= epsilon
export function approx(actual: number, expected: number, epsilon?: number, msg?: string, at?: string): void {
	Script.check();
	const e = epsilon ?? 1e-6;
	if (!(Math.abs(actual - expected) <= e)) failure(`${msg ?? "not within " + e}\n  expected: ${expected}\n  actual:   ${actual}`, at);
}

// the error f throws (as thrown); a failure if none
export function throws(f: () => void, msg?: string, at?: string): unknown {
	Script.check();
	try {
		f();
	} catch (e) {
		if (e instanceof Stop) throw e;
		return e;
	}
	failure(msg ?? "nothing thrown", at);
	return undefined;
}

// the error f's promise rejects with; a failure if it fulfils
export async function rejects(f: () => Promise<unknown>, msg?: string, at?: string): Promise<unknown> {
	Script.check();
	try {
		await f();
	} catch (e) {
		if (e instanceof Stop) throw e;
		return e;
	}
	failure(msg ?? "nothing thrown", at);
	return undefined;
}

// v, not null or undefined; else the test stops
export function require<T>(v: T | null | undefined, msg?: string, at?: string): T {
	Script.check();
	if (v === null || v === undefined) {
		failure(msg ?? `required a value, got ${v}`, at);
		throw new Stop("required");
	}
	return v;
}

// a failure, the test stopped
export function fail(msg: string, at?: string): never {
	failure(msg, at);
	throw new Stop(msg);
}

// value (a string, or shown) against the snapshot of this name in the
// test file's .snap: written when missing, rewritten by `helder test -u`
export function snapshot(name: string, value: unknown, at?: string): void {
	Script.snapshot(name, typeof value === "string" ? value : show(value), at ?? "(unknown)");
}

// --- properties: body run on values of gen (100 cases), each case's
// failures its assertions' (or what it threw); the first failing case
// shrunk and reported smallest, with its seed and choices to replay (as
// helder.test's Property: src/helder/test/README.md)

export type PropertyOptions = {
	// cases generated (100)
	cases?: number;
	// seconds to generate them in, and again to shrink a failure (5)
	seconds?: number;
	// the run's seed, as a failure reports it (else HELDER_PROPERTY_SEED's; else 0)
	seed?: number;
	// a failure's choices, as reported: that case alone
	replay?: string;
	// a stateful case's most steps (50)
	steps?: number;
};

// a stateful property's system: made for each case, steps drawn among those
// whose when holds and run on it, check after setup and each step, teardown at the end
export type Machine<S> = {
	setup: () => S;
	steps: Array<{name: string; run: (system: S, c: Choices) => void; when?: (system: S) => boolean}>;
	check?: (system: S) => void;
	teardown?: (system: S) => void;
};

// a case's choices, which generators draw from
export class Choices {
	constructor(readonly raw: Draws) {}

	draw<T>(g: Gen<T>): T {
		return this.raw.draw(g.next) as T;
	}

	// a choice in 0 to bound, shrinking to 0
	choice(bound: number): number {
		return this.raw.choice(bound);
	}

	// true with probability p, shrinking to false
	weighted(p: number): boolean {
		return this.raw.weighted(p);
	}

	// text shown with a failing case
	note(text: string): void {
		this.raw.note(text);
	}
}

// values drawn from a case's choices, shrinking to the simplest
export class Gen<T> {
	constructor(readonly next: (c: Draws) => T) {}

	map<R>(f: (value: T) => R): Gen<R> {
		const next = this.next;
		return new Gen(c => f(c.draw(next) as T));
	}

	// its values for which ok holds (three draws, else the case is rejected)
	filter(ok: (value: T) => boolean): Gen<T> {
		const next = this.next;
		return new Gen(c => {
			for (let k = 0; k < 3; k++) {
				const v = c.draw(next) as T;
				if (ok(v)) return v;
			}
			PropertyScript.reject();
			throw new Error("rejected");
		});
	}
}

// a generator of your own, drawing from others: gen(c => ({x: c.draw(int(0, 9))}))
export function gen<T>(f: (c: Choices) => T): Gen<T> {
	return new Gen(c => f(new Choices(c)));
}

// an integer in min to max, shrinking to 0 or the bound nearest to it
export function int(min: number, max: number): Gen<number> {
	return new Gen(PropertyScript.int(min, max));
}

// a finite number in min to max, shrinking to round numbers
export function float(min: number, max: number): Gen<number> {
	return new Gen(PropertyScript.float(min, max));
}

export function bool(): Gen<boolean> {
	return new Gen(PropertyScript.bool());
}

export function constant<T>(value: T): Gen<T> {
	return new Gen(() => value);
}

// one of values, shrinking to the first
export function pick<T>(values: Array<T>): Gen<T> {
	const index = PropertyScript.index(values.length);
	return new Gen(c => values[c.draw(index) as number]);
}

// a value of one of gens, shrinking to the first's
export function oneOf<T>(gens: Array<Gen<T>>): Gen<T> {
	const index = PropertyScript.index(gens.length);
	return new Gen(c => c.draw(gens[c.draw(index) as number].next) as T);
}

// min to max items of item (0 to 100), shrinking to fewer
export function array<T>(item: Gen<T>, min?: number, max?: number): Gen<Array<T>> {
	return new Gen(c => {
		const out: Array<T> = [];
		PropertyScript.items(c, item.next, min ?? 0, max ?? 100, v => {
			out.push(v as T);
		});
		return out;
	});
}

// a character: letters mostly, and whitespace, line ends, right-to-left,
// combining marks, emoji, other scripts; nul: NUL and controls too
export function char(nul?: boolean): Gen<string> {
	return new Gen(PropertyScript.char(nul ?? false));
}

// min to max characters of chars (char()'s; 0 to 2000), sometimes long
export function string(chars?: Gen<string>, min?: number, max?: number): Gen<string> {
	return array(chars ?? char(), min ?? 0, max ?? 2000).map(c => c.join(""));
}

// base, or extend's value of a smaller one, at most depth (3) levels deep
export function recursive<T>(base: Gen<T>, extend: (inner: Gen<T>) => Gen<T>, depth?: number): Gen<T> {
	const d = depth ?? 3;
	return d <= 0 ? base : oneOf([base, extend(recursive(base, extend, d - 1))]);
}

// the case left out when cond is false (rejected, not failed)
export function assume(cond: boolean): void {
	if (!cond) PropertyScript.reject();
}

// (a body's end as PropertyScript takes it: null, "" when stopped, else the error)
function outcome(f: () => void): string | null {
	try {
		f();
		return null;
	} catch (e) {
		if (e instanceof Stop || PropertyScript.pending()) return "";
		return errorText(e);
	}
}

// body holds for gen's values
export function property<T>(gen: Gen<T>, body: (value: T) => void, options?: PropertyOptions, at?: string): void {
	const o = options ?? {};
	PropertyScript.property(gen.next, v => outcome(() => body(v as T)), show, o.cases ?? null, o.seconds ?? null, o.seed ?? null, o.replay ?? null, at ?? "(unknown)");
}

// steps of m drawn and run on its system, its check holding after each
export function stateful<S>(m: Machine<S>, options?: PropertyOptions, at?: string): void {
	const o = options ?? {}, steps = m.steps;
	// (the system kept here: through Haxe's Dynamic it would be a copy)
	let system = undefined as S;
	PropertyScript.stateful(() => {
		system = m.setup();
	}, steps.length, i => steps[i].name, (i, c) => outcome(() => steps[i].run(system, new Choices(c))), i => {
		const when = steps[i].when;
		return when === undefined || when(system);
	}, () => outcome(() => {
		if (m.check !== undefined) m.check(system);
	}), () => {
		if (m.teardown !== undefined) m.teardown(system);
	}, show, o.cases ?? null, o.seconds ?? null, o.seed ?? null, o.replay ?? null, o.steps ?? null, at ?? "(unknown)");
}

// --- values

// where a and b differ ("" at the top, ".a[1]" inside), null when deeply equal
export function diff(a: unknown, b: unknown, path: string): string | null {
	if (a === b || (a !== a && b !== b)) return null;
	if (typeof a !== "object" || typeof b !== "object" || a === null || b === null) return path;
	if (Object.getPrototypeOf(a) !== Object.getPrototypeOf(b)) return path;
	if (a instanceof Date && b instanceof Date) return a.getTime() === b.getTime() ? null : path;
	if (Array.isArray(a) && Array.isArray(b)) {
		if (a.length !== b.length) return path;
		for (let i = 0; i < a.length; i++) {
			const d = diff(a[i], b[i], `${path}[${i}]`);
			if (d !== null) return d;
		}
		return null;
	}
	if (ArrayBuffer.isView(a) && ArrayBuffer.isView(b)) {
		const x = new Uint8Array(a.buffer, a.byteOffset, a.byteLength), y = new Uint8Array(b.buffer, b.byteOffset, b.byteLength);
		if (x.length !== y.length) return path;
		for (let i = 0; i < x.length; i++) if (x[i] !== y[i]) return `${path}[${i}]`;
		return null;
	}
	if (a instanceof Map && b instanceof Map) {
		if (a.size !== b.size) return path;
		for (const [k, v] of a) {
			if (!b.has(k)) return path;
			const d = diff(v, b.get(k), `${path}[${show(k)}]`);
			if (d !== null) return d;
		}
		return null;
	}
	if (a instanceof Set && b instanceof Set) {
		if (a.size !== b.size) return path;
		for (const v of a) if (!b.has(v)) return path;
		return null;
	}
	const ka = Object.keys(a), kb = Object.keys(b);
	if (ka.length !== kb.length) return path;
	for (const k of ka) {
		if (!Object.prototype.hasOwnProperty.call(b, k)) return `${path}.${k}`;
		const d = diff((a as Record<string, unknown>)[k], (b as Record<string, unknown>)[k], `${path}.${k}`);
		if (d !== null) return d;
	}
	return null;
}

// a value as a literal: strings quoted, arrays, objects ({a: 1}), Map, Set,
// Date, typed arrays, an instance by its class's name
export function show(v: unknown): string {
	return text(v, 0);
}

// (a key written bare: an identifier's characters, not starting with a digit)
function plainKey(k: string): boolean {
	if (k === "") return false;
	for (let i = 0; i < k.length; i++) {
		const c = k.charCodeAt(i);
		const letter = (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c === 95 || c === 36;
		if (!letter && !(i > 0 && c >= 48 && c <= 57)) return false;
	}
	return true;
}

function text(v: unknown, depth: number): string {
	if (typeof v === "string") return JSON.stringify(v);
	if (typeof v === "function") return `[Function ${v.name || "(anonymous)"}]`;
	if (typeof v !== "object" || v === null) return String(v);
	if (depth > 8) return "...";
	if (v instanceof Date) return `Date(${v.toISOString()})`;
	if (v instanceof Error) return `${v.name}(${JSON.stringify(v.message)})`;
	if (Array.isArray(v)) return `[${v.map(x => text(x, depth + 1)).join(", ")}]`;
	if (ArrayBuffer.isView(v)) {
		const bytes = new Uint8Array(v.buffer, v.byteOffset, v.byteLength);
		return `${v.constructor.name} [${Array.from(bytes).join(", ")}]`;
	}
	if (v instanceof Map) return `Map {${Array.from(v).map(([k, x]) => `${text(k, depth + 1)} => ${text(x, depth + 1)}`).join(", ")}}`;
	if (v instanceof Set) return `Set {${Array.from(v).map(x => text(x, depth + 1)).join(", ")}}`;
	const proto = Object.getPrototypeOf(v);
	const name = proto === null || proto === Object.prototype ? "" : (proto.constructor?.name ?? "") + " ";
	const fields = Object.keys(v).map(k => `${plainKey(k) ? k : JSON.stringify(k)}: ${text((v as Record<string, unknown>)[k], depth + 1)}`);
	return `${name}{${fields.join(", ")}}`;
}
