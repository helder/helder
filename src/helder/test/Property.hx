package helder.test;

import haxe.PosInfos;
import helder.test.Choices;
import helder.test.Runner;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// a property's budget and its seed (Test.property, Test.stateful)
typedef PropertyOptions = {
	// cases generated (100)
	?cases:Int,
	// seconds to generate them in, and again to shrink a failure (5)
	?seconds:Float,
	// the run's seed, as a failure reports it (else HELDER_PROPERTY_SEED's,
	// a number or "random"; else 0: the same cases on every run)
	?seed:Int,
	// a failure's choices, as reported: that case alone
	?replay:String,
	// a stateful case's most steps (50)
	?steps:Int,
	// a robustness property's: a case's most seconds, past which a
	// watchdog ends the process as hung (natively); each case kept in the
	// store before it runs, so that a hang or a crash leaves it for the
	// next run to replay first. HELDER_PROPERTY_SOAK (seconds) runs it that
	// long, its cases unbounded
	?limit:Float,
	// with limit: the most MB the process may grow by in a case (natively,
	// where the system tells), else the watchdog ends it
	?memory:Float
}

// a stateful property's system: made for each case, then steps drawn
// among those whose when holds and run on it, check after setup and
// after each step, teardown at the end (also after a failure)
typedef Machine<S> = {
	setup:() -> S,
	steps:Array<{name:String, run:(S, Choices) -> Void, ?when:S->Bool}>,
	?check:S->Void,
	?teardown:S->Void
}

// (a case's run: its choices and what it ended in)
private typedef Run = {
	choices:Choices,
	value:Dynamic,
	outcome:Outcome
}

private enum Outcome {
	Passed;
	Failed(failures:Array<String>);
	Rejected;
	Overran;
}

// (the search's end: the smallest failing run, if any)
private typedef Result = {
	failed:Null<Run>,
	cases:Int,
	rejected:Int,
	shrinks:Int,
	seed:Int,
	stored:Bool
}

// Property-based tests as Hypothesis runs them: each case a sequence of
// choices (Choices) its generators draw from, made at random from the
// run's seed; the first failing case shrunk by editing its sequence (spans
// deleted, chunks zeroed, values lowered, siblings sorted) as long as it
// still fails, then reported smallest first with its seed and sequence.
// A failure's sequence is kept in bin/test/properties and replayed first
// on the next run, until it passes.
@:allow(helder.test)
class Property {
	static inline var STORE = "bin/test/properties";

	// (the last Rejected or Overran thrown: a TypeScript body's catch takes
	// it, PropertyScript throws it again)
	static var control:Null<haxe.Exception>;
	// (which property of the running test: its index is its key)
	static var test:Null<Case>;
	static var index = 0;
	// (a robustness property's key, its place and its case running: kept
	// before each case, reported by the watchdog)
	static var guarded:Null<String>;
	static var at:Null<PosInfos>;
	static var current:Null<Choices>;

	static function check<T>(gen:Gen<T>, body:T->Void, show:Null<T->String>, options:Null<PropertyOptions>, pos:PosInfos) {
		Runner.check();
		var k = key(pos);
		if (options?.limit != null) {
			guarded = k;
			at = pos;
			Guard.watch(options.limit, options.memory ?? 0, hung);
		}
		var r = try search(gen, body, options ?? {}, k) catch (e:haxe.Exception) {
			unguard();
			throw helder.async.Errors.kept(e);
		}
		unguard();
		if (r.failed != null) Runner.failure(report(r, show), pos);
		else if (r.rejected > 0 && r.cases == 0 || r.rejected > 4 * (options?.cases ?? 100))
			Runner.failure('the generator rejects too much: ${r.rejected} cases rejected, ${r.cases} run', pos);
	}

	// (show: the steps' arguments' text, Equal.show's else)
	static function stateful<S>(m:Machine<S>, options:Null<PropertyOptions>, pos:PosInfos, ?show:Dynamic->String) {
		var most = options?.steps ?? 50;
		check(c -> c, c -> steps(m, c, most, show ?? Equal.show), null, options, pos);
	}

	// --- searching

	// (the cases' checks not counted: a property is one)
	static function search<T>(gen:Gen<T>, body:T->Void, options:PropertyOptions, key:String):Result {
		var checks = Runner.checks;
		var r = find(gen, body, options, key);
		Runner.checks = checks;
		return r;
	}

	static function find<T>(gen:Gen<T>, body:T->Void, options:PropertyOptions, key:String):Result {
		var cases = options.cases ?? 100, seconds = options.seconds ?? 5.0;
		var soak = options.limit != null ? Std.parseFloat(Sys.getEnv("HELDER_PROPERTY_SOAK") ?? "") : Math.NaN;
		if (soak > 0) {
			// (4 times it still an Int: the rejections' bound)
			cases = 0x1FFFFFFF;
			seconds = soak;
		}
		var seed = options.seed ?? envSeed();
		var r:Result = {failed: null, cases: 0, rejected: 0, shrinks: 0, seed: seed, stored: false};
		if (options.replay != null) {
			var run = once(gen, body, new Choices(parse(options.replay), false));
			r.cases = 1;
			if (run.outcome.match(Failed(_))) r.failed = run;
			return r;
		}
		var stored = load(key);
		if (stored != null && guarded != null) Sys.println('${Runner.file(at.fileName)}:${at.lineNumber}: the case kept in ${path(key)} replayed first (a failure, a hang or a crash of a run before)');
		if (stored != null) {
			var run = once(gen, body, new Choices(stored, false));
			if (run.outcome.match(Failed(_))) {
				r.failed = run;
				r.stored = true;
				r.cases = 1;
			} else remove(key);
		}
		var end = haxe.Timer.stamp() + seconds, base = mix(seed ^ hash(key));
		var i = 0;
		while (r.failed == null && r.cases < cases && r.rejected <= 4 * cases && haxe.Timer.stamp() < end) {
			var run = once(gen, body, new Choices([], true, mix(base + i++)));
			switch run.outcome {
				case Passed: r.cases++;
				case Failed(_):
					r.cases++;
					r.failed = run;
				case Rejected | Overran: r.rejected++;
			}
		}
		if (r.failed == null) return r;
		var shrunk = shrink(gen, body, r.failed, haxe.Timer.stamp() + seconds);
		r.failed = shrunk.run;
		r.shrinks = shrunk.shrinks;
		save(key, r.failed.choices.values);
		return r;
	}

	// (one case: its failures are the assertions' failures in it, or what it threw)
	static function once<T>(gen:Gen<T>, body:T->Void, c:Choices):Run {
		var outer = Runner.capture, failures = [];
		Runner.capture = failures;
		var value:Dynamic = null, outcome = Passed;
		control = null;
		try {
			value = c.draw(gen);
			if (guarded != null) {
				save(guarded, c.values);
				current = c;
				Guard.enter();
			}
			body(value);
		} catch (e:Rejected) {
			outcome = Rejected;
		} catch (e:Overran) {
			outcome = Overran;
		} catch (e:Stop) {} catch (e:haxe.Exception) {
			failures.push(Runner.error(e));
		}
		Runner.capture = outer;
		if (guarded != null) {
			Guard.leave();
			current = null;
		}
		if (failures.length > 0) outcome = Failed(failures);
		else if (guarded != null) remove(guarded);
		return {choices: c, value: value, outcome: outcome};
	}

	// (the steps of a stateful case, until one fails)
	static function steps<S>(m:Machine<S>, c:Choices, most:Int, show:Dynamic->String) {
		var s = m.setup();
		try {
			if (m.check != null) m.check(s);
			var p = 1 - 1 / most;
			for (_ in 0...most) {
				if (Runner.capture.length > 0) break;
				var start = c.values.length;
				if (!c.weighted(p)) break;
				var can = [for (step in m.steps) if (step.when == null || step.when(s)) step];
				if (can.length == 0) break;
				var step = can[c.choice(can.length - 1)], from = c.drawn.length;
				function noted()
					c.note(step.name + "(" + [for (a in c.drawn.slice(from)) show(a)].join(", ") + ")");
				try step.run(s, c) catch (e:haxe.Exception) {
					noted();
					throw helder.async.Errors.kept(e);
				}
				noted();
				c.span(start);
				if (m.check != null) m.check(s);
			}
		} catch (e:haxe.Exception) {
			if (m.teardown != null) m.teardown(s);
			throw helder.async.Errors.kept(e);
		}
		if (m.teardown != null) m.teardown(s);
	}

	// --- shrinking

	// (the smallest failing run found from run: shorter, else lower, sequences)
	static function shrink<T>(gen:Gen<T>, body:T->Void, run:Run, end:Float):{run:Run, shrinks:Int} {
		var best = run, shrinks = 0, tries = 0;
		function attempt(values:Array<Int>):Bool {
			if (tries > 10000 || haxe.Timer.stamp() > end || !smaller(values, best.choices.values)) return false;
			tries++;
			var r = once(gen, body, new Choices(values, false));
			if (!r.outcome.match(Failed(_)) || !smaller(r.choices.values, best.choices.values)) return false;
			best = r;
			shrinks++;
			return true;
		}
		var changed = true;
		while (changed && tries <= 10000 && haxe.Timer.stamp() <= end) {
			changed = false;
			// spans deleted, the longest first
			var i = 0;
			while (i < spans(best).length) {
				var s = spans(best)[i], v = best.choices.values;
				if (attempt(v.slice(0, s.start).concat(v.slice(s.end)))) changed = true else i++;
			}
			// chunks deleted, then zeroed, from the end
			for (k in [8, 4, 2, 1]) {
				var at = best.choices.values.length - k;
				while (at >= 0) {
					var v = best.choices.values;
					if (at + k <= v.length && attempt(v.slice(0, at).concat(v.slice(at + k)))) changed = true;
					at--;
				}
			}
			for (k in [8, 4, 2]) {
				var at = best.choices.values.length - k;
				while (at >= 0) {
					var v = best.choices.values;
					if (at + k <= v.length && Lambda.exists(v.slice(at, at + k), x -> x != 0)) {
						var z = v.copy();
						for (j in at...at + k) z[j] = 0;
						if (attempt(z)) changed = true;
					}
					at--;
				}
			}
			// each value lowered: to 0, else the least that still fails
			for (j in 0...best.choices.values.length) {
				if (j >= best.choices.values.length) break;
				var hi = best.choices.values[j];
				if (hi == 0) continue;
				if (attempt(with(best.choices.values, j, 0))) {
					changed = true;
					continue;
				}
				var lo = 0;
				while (lo + 1 < hi) {
					var mid = lo + ((hi - lo) >> 1);
					if (j < best.choices.values.length && attempt(with(best.choices.values, j, mid))) {
						hi = mid;
						changed = true;
					} else lo = mid;
				}
			}
			// a value moved onto a later one (a sum kept: a + b > 9 to 1 and 9)
			for (j in 0...best.choices.values.length) for (k in j + 1...j + 9) {
				var v = best.choices.values;
				if (k >= v.length || v[j] == 0) continue;
				var d = v[j];
				while (d > 0) {
					var moved = with(with(v, j, v[j] - d), k, v[k] + d);
					if (attempt(moved)) {
						changed = true;
						break;
					}
					d >>= 1;
				}
			}
			// siblings of one length sorted (an array's items, a machine's steps)
			var list = spans(best);
			for (a in list) for (b in list) {
				if (b.start != a.end || b.end - b.start != a.end - a.start) continue;
				var v = best.choices.values;
				if (b.end > v.length || !smaller(v.slice(b.start, b.end), v.slice(a.start, a.end))) continue;
				if (attempt(v.slice(0, a.start).concat(v.slice(b.start, b.end)).concat(v.slice(a.start, a.end)).concat(v.slice(b.end)))) {
					changed = true;
					break;
				}
			}
		}
		return {run: best, shrinks: shrinks};
	}

	// (a run's spans, distinct, the longest first)
	static function spans(r:Run):Array<{start:Int, end:Int}> {
		var s = r.choices.spans, seen = new Map<Int, Bool>(), out = [];
		var i = 0;
		while (i < s.length) {
			var a = s[i], b = s[i + 1];
			i += 2;
			if (b - a >= r.choices.values.length || seen.exists(a * 8192 + b)) continue;
			seen.set(a * 8192 + b, true);
			out.push({start: a, end: b});
		}
		out.sort((x, y) -> (y.end - y.start) - (x.end - x.start));
		return out;
	}

	static function with(v:Array<Int>, i:Int, x:Int):Array<Int> {
		var out = v.copy();
		out[i] = x;
		return out;
	}

	// (shortlex: fewer choices, else lower at the first difference)
	static function smaller(a:Array<Int>, b:Array<Int>):Bool {
		if (a.length != b.length) return a.length < b.length;
		for (i in 0...a.length) if (a[i] != b[i]) return a[i] < b[i];
		return false;
	}

	static function unguard() {
		if (guarded == null) return;
		Guard.stop();
		guarded = null;
		current = null;
	}

	// (the watchdog's, on its thread: the case running reported, the
	// process ended, the case left in the store)
	static function hung(why:String) {
		var c = current, k = guarded, pos = at;
		if (c == null || k == null || pos == null) return;
		var lines = ['${Runner.file(pos.fileName)}:${pos.lineNumber}: property failed: $why:'];
		for (n in c.notes) lines.push("  " + n);
		lines.push('  replay: {replay: "${c.values.join(" ")}"}, kept in ${path(k)}: the next run replays it first');
		Sys.println(lines.join("\n"));
		Sys.exit(3);
	}

	// --- reporting

	static function report(r:Result, show:Null<Dynamic->String>):String {
		var run = r.failed;
		var head = r.stored ? 'property failed: the failure kept in $STORE, replayed' : 'property failed after ${r.cases} case${r.cases == 1 ? "" : "s"}';
		var lines = [head + (r.shrinks > 0 ? ', shrunk ${r.shrinks} time${r.shrinks == 1 ? "" : "s"}' : "") + ":"];
		if (run.choices.notes.length == 0) lines.push("  " + (show ?? Equal.show)(run.value));
		for (n in run.choices.notes) lines.push("  " + n);
		switch run.outcome {
			case Failed(failures): for (f in failures) lines.push("  " + f.split("\n").join("\n  "));
			case _:
		}
		lines.push('  replay: {replay: "${run.choices.values.join(" ")}"}' + (r.stored ? "" : ', or {seed: ${r.seed}} (HELDER_PROPERTY_SEED=${r.seed})'));
		return lines.join("\n");
	}

	// --- seeds and the store

	static function envSeed():Int {
		var s = Sys.getEnv("HELDER_PROPERTY_SEED");
		if (s == null || s == "") return 0;
		if (s == "random") return Std.int(haxe.Timer.stamp() * 1000) ^ Std.int(Math.random() * 0x7FFFFFFF);
		return Std.parseInt(s) ?? 0;
	}

	// (the property's key: its file, its test, its index in the test)
	static function key(pos:PosInfos):String {
		var c = Runner.running();
		if (c != test) {
			test = c;
			index = 0;
		}
		var k = Runner.file(pos.fileName) + " > " + (c?.fullName() ?? "") + " #" + index++;
		return k;
	}

	// (shifts and xor: the same on every target, Eval's ints included)
	static function hash(s:String):Int {
		var h = 0x3C6EF372;
		for (i in 0...s.length) h = ((h << 5) ^ (h >>> 27)) ^ s.charCodeAt(i);
		return h;
	}

	static function mix(x:Int):Int {
		x ^= x << 13;
		x ^= x >>> 17;
		x ^= x << 5;
		x ^= x >>> 16;
		return x == 0 ? 1 : x;
	}

	static function parse(s:String):Array<Int>
		return [for (p in s.split(" ")) if (p != "") Std.parseInt(p) ?? 0];

	static function path(key:String):String {
		var h = hash(key), hex = StringTools.hex(h >>> 4, 7) + StringTools.hex(h & 15, 1);
		return '$STORE/$hex.txt';
	}

	static function load(key:String):Null<Array<Int>> {
		try {
			var p = path(key);
			if (!FileSystem.exists(p)) return null;
			var lines = File.getContent(p).split("\n");
			return lines[0] == key ? parse(lines[1] ?? "") : null;
		} catch (e:Dynamic) {
			return null;
		}
	}

	static function save(key:String, values:Array<Int>)
		try {
			if (!FileSystem.exists(STORE)) FileSystem.createDirectory(STORE);
			File.saveContent(path(key), key + "\n" + values.join(" ") + "\n");
		} catch (e:Dynamic) {}

	static function remove(key:String)
		try {
			if (FileSystem.exists(path(key))) FileSystem.deleteFile(path(key));
		} catch (e:Dynamic) {}
}
