package helder.pack.android;

import helder.pack.android.Dex;

// Dalvik's instructions as Jvm writes them: units with no reference, the
// references (strings, types, fields, methods) resolved against the
// file's pools when it is written, branches to labels. `code` lays them
// out (gotos and ifs grown until each offset fits: an if too far is
// inverted over a goto/32; const-string/jumbo past 65,535 strings), the
// switches' payloads after the code, 4-byte aligned, and gives the try
// items over labels.
class Dalvik {
	public static inline var INVOKE_VIRTUAL = 0x6e;
	public static inline var INVOKE_SUPER = 0x6f;
	public static inline var INVOKE_DIRECT = 0x70;
	public static inline var INVOKE_STATIC = 0x71;
	public static inline var INVOKE_INTERFACE = 0x72;
	public static inline var FILLED_NEW_ARRAY = 0x24;

	final ops:Array<Op> = [];
	var labels = 0;

	public function new() {}

	public function label():Int
		return labels++;

	public function place(l:Int)
		ops.push(Place(l));

	public function raw(units:Array<Int>)
		ops.push(Raw(units));

	// a 21c (op vAA, ref) or 22c (op vA, vB, ref: a = A | B << 4) instruction
	public function ref(op:Int, a:Int, r:DRef)
		ops.push(Ref(op, a, r));

	public function string(reg:Int, s:String)
		ops.push(Str(reg, s));

	// regs: five at most, each under 16; else consecutive (the range form)
	public function invoke(op:Int, regs:Array<Int>, r:DRef)
		ops.push(Invoke(op, regs, r));

	public function goto(l:Int)
		ops.push(Goto(l));

	// if-test vA, vB (b < 0: the z form, vAA)
	public function branch(op:Int, a:Int, b:Int, l:Int)
		ops.push(If(op, a, b, l));

	public function switchOf(reg:Int, keys:Array<Int>, targets:Array<Int>)
		ops.push(Switch(reg, keys, targets));

	// whether regs fit the five-register form
	public static function short(regs:Array<Int>):Bool {
		if (regs.length > 5) return false;
		for (r in regs) if (r > 15) return false;
		return true;
	}

	// whether regs are consecutive (the range form)
	public static function consecutive(regs:Array<Int>):Bool {
		for (k in 1...regs.length) if (regs[k] != regs[0] + k) return false;
		return true;
	}

	static function refIndex(refs:Refs, r:DRef):Int
		return switch r {
			case RType(d): refs.type(d);
			case RString(s): refs.string(s);
			case RField(o, n, t): refs.field(o, n, t);
			case RMethod(o, n, ret, ps): refs.method(o, n, ret, ps);
		}

	// the units, every label's address (in units), the code's length before the payloads
	public function layout(refs:Refs):{insns:Array<Int>, at:Array<Int>} {
		var n = ops.length, size = [for (_ in 0...n) 1], at = [for (_ in 0...labels) 0];
		var strIdx = [for (o in ops) switch o {
			case Str(_, s): refs.string(s);
			case _: 0;
		}];
		for (k in 0...n)
			size[k] = switch ops[k] {
				case Place(_): 0;
				case Raw(u): u.length;
				case Ref(_, _, _): 2;
				case Str(_, _): strIdx[k] > 0xffff ? 3 : 2;
				case Invoke(_, _, _): 3;
				case Goto(_): 1;
				case If(_, _, _, _): 2;
				case Switch(_, _, _): 3;
			};
		var pos = [for (_ in 0...n) 0];
		var changed = true;
		while (changed) {
			changed = false;
			var p = 0;
			for (k in 0...n) {
				pos[k] = p;
				switch ops[k] {
					case Place(l): at[l] = p;
					case _:
				}
				p += size[k];
			}
			for (k in 0...n)
				switch ops[k] {
					case Goto(l):
						var d = at[l] - pos[k];
						var s = d == 0 ? 3 : d >= -128 && d < 128 ? 1 : d >= -32768 && d < 32768 ? 2 : 3;
						if (s > size[k]) {
							size[k] = s;
							changed = true;
						}
					case If(_, _, _, l):
						var d = at[l] - pos[k];
						if (size[k] == 2 && (d < -32768 || d >= 32768)) {
							size[k] = 5;
							changed = true;
						}
					case _:
				}
		}
		var end = 0;
		for (k in 0...n)
			end = pos[k] + size[k];
		var out:Array<Int> = [], payloads:Array<{k:Int, units:Array<Int>}> = [];
		var payloadAt = end + (end % 2);
		for (k in 0...n) {
			var here = pos[k];
			switch ops[k] {
				case Place(_):
				case Raw(u): for (x in u) out.push(x);
				case Ref(op, a, r):
					out.push(op | a << 8);
					out.push(refIndex(refs, r) & 0xffff);
				case Str(reg, _):
					var i = strIdx[k];
					if (size[k] == 3) {
						out.push(0x1b | reg << 8);
						out.push(i & 0xffff);
						out.push(i >>> 16);
					} else {
						out.push(0x1a | reg << 8);
						out.push(i);
					}
				case Invoke(op, regs, r):
					var i = refIndex(refs, r);
					if (short(regs)) {
						var g = regs.length == 5 ? regs[4] : 0;
						out.push(op | regs.length << 12 | g << 8);
						out.push(i & 0xffff);
						var w = 0;
						for (j in 0...(regs.length < 4 ? regs.length : 4))
							w |= regs[j] << (4 * j);
						out.push(w);
					} else {
						if (!consecutive(regs) || regs.length > 255) throw "Dalvik: an invoke's registers are not consecutive";
						out.push((op + (op == FILLED_NEW_ARRAY ? 1 : 6)) | regs.length << 8);
						out.push(i & 0xffff);
						out.push(regs.length == 0 ? 0 : regs[0]);
					}
				case Goto(l):
					var d = at[l] - here;
					switch size[k] {
						case 1: out.push(0x28 | (d & 0xff) << 8);
						case 2:
							out.push(0x29);
							out.push(d & 0xffff);
						case _:
							out.push(0x2a);
							out.push(d & 0xffff);
							out.push((d >> 16) & 0xffff);
					}
				case If(op, a, b, l):
					var d = at[l] - here;
					if (size[k] == 2) {
						out.push(b < 0 ? op | a << 8 : op | a << 8 | b << 12);
						out.push(d & 0xffff);
					} else {
						// (the test inverted over a goto/32: if-eq and if-ne,
						// lt and ge, gt and le are pairs)
						var inv = op ^ 1;
						out.push(b < 0 ? inv | a << 8 : inv | a << 8 | b << 12);
						out.push(5);
						d = at[l] - (here + 2);
						out.push(0x2a);
						out.push(d & 0xffff);
						out.push((d >> 16) & 0xffff);
					}
				case Switch(reg, keys, targets):
					var packed = keys.length > 0;
					for (j in 1...keys.length) if (keys[j] != keys[0] + j) packed = false;
					var u = [];
					if (packed) {
						u.push(0x0100);
						u.push(keys.length);
						u.push(keys[0] & 0xffff);
						u.push(keys[0] >>> 16);
						for (t in targets) {
							var d = at[t] - here;
							u.push(d & 0xffff);
							u.push((d >> 16) & 0xffff);
						}
					} else {
						u.push(0x0200);
						u.push(keys.length);
						for (key in keys) {
							u.push(key & 0xffff);
							u.push(key >>> 16);
						}
						for (t in targets) {
							var d = at[t] - here;
							u.push(d & 0xffff);
							u.push((d >> 16) & 0xffff);
						}
					}
					var d = payloadAt - here;
					out.push((packed ? 0x2b : 0x2c) | reg << 8);
					out.push(d & 0xffff);
					out.push((d >> 16) & 0xffff);
					payloads.push({k: k, units: u});
					payloadAt += u.length + (u.length % 2);
			}
		}
		if (payloads.length > 0 && out.length % 2 == 1) out.push(0);
		for (p in payloads) {
			for (x in p.units)
				out.push(x);
			if (out.length % 2 == 1) out.push(0);
		}
		return {insns: out, at: at};
	}

	// the method's code: its instructions and the try items over labels
	// (ranges' handlers in order, each a type's descriptor and a label, the catch-all's)
	public function code(registers:Int, ins:Int, outs:Int, ?tries:Array<{start:Int, end:Int, handlers:Array<{type:String, label:Int}>, ?all:Int}>):DexCode {
		var c:DexCode = {registers: registers, ins: ins, outs: outs, insns: refs -> layout(refs).insns};
		if (tries != null && tries.length > 0) c.tries = refs -> {
			var at = layout(refs).at, out:Array<DexTry> = [];
			for (t in tries) {
				var s = at[t.start], e = at[t.end];
				if (e <= s) continue;
				var hs = [for (h in t.handlers) {type: h.type, addr: at[h.label]}];
				var all = t.all == null ? null : at[t.all];
				var key = [for (h in hs) h.type + h.addr].join(",") + all;
				var last = out[out.length - 1];
				if (last != null && last.start + last.count == s && [for (h in last.handlers) h.type + h.addr].join(",") + last.all == key && e - last.start <= 0xffff) {
					last.count = e - last.start;
					continue;
				}
				while (e - s > 0xffff) {
					out.push({start: s, count: 0xffff, handlers: hs, all: all});
					s += 0xffff;
				}
				out.push({start: s, count: e - s, handlers: hs, all: all});
			}
			out;
		};
		return c;
	}
}

enum DRef {
	RType(desc:String);
	RString(s:String);
	RField(owner:String, name:String, type:String);
	RMethod(owner:String, name:String, ret:String, params:Array<String>);
}

private enum Op {
	Place(label:Int);
	Raw(units:Array<Int>);
	Ref(op:Int, a:Int, r:DRef);
	Str(reg:Int, s:String);
	Invoke(op:Int, regs:Array<Int>, r:DRef);
	Goto(label:Int);
	If(op:Int, a:Int, b:Int, label:Int);
	Switch(reg:Int, keys:Array<Int>, targets:Array<Int>);
}
