package helder.gfx.shader;

#if macro
import helder.math.*;
import haxe.macro.Context;
import haxe.macro.Expr;
import helder.gfx.shader.Ir;
import helder.gfx.shader.Phases;

// The CPU back end's form of a shader (helder.gfx.soft), a fifth output of
// the definition beside the four languages: each stage's IR as Haxe over
// helder.gfx.soft's lane types, one call shading 4 lanes (a 2x2 quad of
// pixels, as GPUs shade, which gives sample() its derivatives; or 4
// vertices), compiled ahead of time with the program (-D helder.soft).
//
// What every lane computes alike stays scalar: a uniform analysis marks
// the values that do not depend on the stage's input (constants, uniform
// blocks, the locals assigned only those where every lane runs alike),
// computed as the scalar CPU code computes them (helder.math's types
// and builtins) and splatted where they meet a lane's value; their ifs and
// loops are plain. The rest runs under a mask of the lanes it is for: an
// if on lanes runs each branch its lanes take (skipped when none does), a
// local assigned there keeps the other lanes' values (select), a loop runs
// while any lane is in it, a return or discard takes its lanes out. A
// uniform block is the bytes the draw bound (read at their std140
// offsets), a texture the back end's record of it and its sampler.
//
// Each stage is an entry, `soft_vs` / `soft_fs`, a GC-free callback of the
// back end's context (helder.gfx.soft.Abi): its inputs' and outputs' lanes,
// the lanes to shade, the uniform blocks' and textures' addresses by slot.
// With -D helder.soft.reference the same stages also as scalar code, lane
// by lane (soft_vs_ref, soft_fs_ref), which SoftShaderCheck compares.
//
// A compute stage's call runs 4 invocations of a workgroup, a subgroup of
// 4 (helder.gfx.soft.Subgroup). Its workgroup memory is a block of the back
// end's for each workgroup, an array of it a storage buffer's record (read
// and written as one); with barrier()s its function is cut there into
// phases (Phases), the back end running each over the whole workgroup
// before the next: the call takes the phase and returns the next (-1: the
// end), the locals that live across a barrier kept in a frame of the
// call's invocations (SoftCode.frame bytes) between them.
class Soft {
	static inline var ABI_IN = 0;
	static inline var ABI_OUT = 8;
	static inline var ABI_MASK = 16;
	static inline var ABI_UNIFORMS = 24;
	static inline var ABI_TEXTURES = 24 + 8 * 16;
	static inline var ABI_STORAGE = 24 + 16 * 16;
	static inline var ABI_IMAGES = 24 + 16 * 16 + 8 * 16;
	static inline var ABI_WORKGROUP = ABI_IMAGES + 8 * 16;
	static inline var ABI_FRAME = ABI_WORKGROUP + 8;
	static inline var ABI_PHASE = ABI_FRAME + 8;

	final prog:SProgram;
	final prefix:String;
	final pack:Array<String>;
	final module:String;
	final pos:Position;
	// the uniform blocks' structs and each field's offset
	final blocks = new Map<SStruct, SUniform>();
	public final fields:Array<Field> = [];
	// (what was emitted, by name: functions, structs)
	final made = new Map<String, Bool>();
	final pending:Array<Void->Void> = [];
	final laneStructs = new Map<SStruct, String>();
	final scalarStructs = new Map<SStruct, String>();
	final discards = new Map<SFunction, Bool>();

	// (a compute stage's storage layouts: each element type's)
	final storage:Array<SStorage> = [];
	// (a compute stage's workgroup memory, and the bytes of its phases' frame)
	var shared:Array<SShared> = [];
	public var frame = 0;

	// (helder.parallel's kernels) the locals whose lanes a call holds
	// consecutively (the item's index and its copies: the range form calls 4
	// items in a row), their storage elements read and written as rows
	// (rowsRead)
	public final rows = new Map<SVar, Bool>();

	public function new(prog:SProgram, prefix:String, pack:Array<String>, module:String) {
		this.prog = prog;
		this.prefix = prefix;
		this.pack = pack;
		this.module = module;
		pos = Context.currentPos();
		for (u in prog.uniforms)
			blocks.set(u.struct, u);
	}

	public static function dot(e:Expr, n:String):Expr
		return {expr: haxe.macro.Expr.ExprDef.EField(e, n), pos: e.pos};

	public static function enabled():Bool
		return Context.defined("helder.soft") && Context.definedValue("target.name") == "hxmc";

	// a compute stage's form (compute({size, main})): its entry, ShaderCode's
	// soft field. Each call runs 4 invocations, a lane each
	public static function compute(c:SCompute, prefix:String, pack:Array<String>, module:String):{soft:Soft, code:Expr} {
		var s = new Soft(new SProgram(c.entry, c.entry, c.entry.uniforms, c.entry.textures), prefix, pack, module);
		for (b in c.storage)
			s.storage.push(b);
		// (workgroup memory: laid out as storage)
		for (w in c.shared)
			s.storage.push(new SStorage(w.name, -1, w.element, true, w.offsets, w.stride, -1));
		s.shared = c.shared;
		var cs = s.entry(c.entry, false);
		s.flush();
		var bytes = 0;
		for (w in c.shared)
			bytes += w.bytes;
		return {soft: s, code: macro {entry: $i{cs}(), varyings: 0, workgroup: $v{bytes}, frame: $v{s.frame}}};
	}

	// (the std430 layout of a storage buffer of t: any of the stage's of that element)
	function layout(t:SType):SStorage {
		for (b in storage)
			if (Names.same(b.element, t)) return b;
		return Context.error('soft: no storage of ${Names.typeName(t)}', pos);
	}

	// element i of the storage buffer at b (its binding), of type t, as
	// lanes (each lane its i) or a scalar (i shared)
	public function storageRead(t:SType, b:Expr, i:Expr, lanes:Bool):Expr {
		var l = layout(t);
		function read(t:SType, off:Int):Expr
			return switch t {
				case TFloat: lanes ? macro helder.gfx.soft.Buffers.f32($b, $i, $v{l.stride}, $v{off}) : macro helder.gfx.soft.Buffers.f32At($b, $i, $v{l.stride}, $v{off});
				case TInt: lanes ? macro helder.gfx.soft.Buffers.i32($b, $i, $v{l.stride}, $v{off}) : macro helder.gfx.soft.Buffers.i32At($b, $i, $v{l.stride}, $v{off});
				case TBool: lanes ? macro helder.gfx.soft.Buffers.i32($b, $i, $v{l.stride}, $v{off}).ne(helder.gfx.soft.LaneInt.splat(0)) : macro helder.gfx.soft.Buffers.i32At($b,
						$i, $v{l.stride}, $v{off}) != 0;
				case TVec(n):
					{expr: haxe.macro.Expr.ExprDef.ENew({pack: lanes ? SOFT : MATH, name: (lanes ? 'Lane' : 'Vec') + n}, [for (k in 0...n) read(TFloat, off + 4 * k)]), pos: pos};
				// (std430: four Vec4 columns)
				case TMat4:
					{expr: haxe.macro.Expr.ExprDef.ENew({pack: lanes ? SOFT : MATH, name: lanes ? "LaneMat" : "Mat4"}, [for (k in 0...4) read(TVec(4), off + 16 * k)]), pos: pos};
				case t: Context.error('soft: a storage element of ${Names.typeName(t)}', pos);
			}
		return switch t {
			case TStruct(st):
				var xs = [for (k in 0...st.fields.length) read(st.fields[k].type, l.offsets[k])];
				lanes ? laneMake(st, xs) : {expr: haxe.macro.Expr.ExprDef.ENew({pack: pack, name: scalarStruct(st)}, xs), pos: pos};
			case _: read(t, 0);
		}
	}

	// element i of the storage buffer at b set to v (lanes) where m's lanes are
	public function storageWrite(t:SType, b:Expr, i:Expr, v:Expr):Expr {
		var l = layout(t);
		function write(t:SType, off:Int, v:Expr):Array<Expr>
			return switch t {
				case TFloat: [macro helder.gfx.soft.Buffers.setF32($b, $i, $v{l.stride}, $v{off}, $v, m)];
				case TInt: [macro helder.gfx.soft.Buffers.setI32($b, $i, $v{l.stride}, $v{off}, $v, m)];
				case TBool: [macro helder.gfx.soft.Buffers.setI32($b, $i, $v{l.stride}, $v{off},
					helder.gfx.soft.LaneInt.select($v, helder.gfx.soft.LaneInt.splat(1), helder.gfx.soft.LaneInt.splat(0)), m)];
				case TVec(n): [for (k in 0...n) for (x in write(TFloat, off + 4 * k, Soft.dot(v, "xyzw".charAt(k)))) x];
				case TMat4: [for (k in 0...4) for (x in write(TVec(4), off + 16 * k, Soft.dot(v, "c" + k))) x];
				case t: Context.error('soft: a storage element of ${Names.typeName(t)}', pos);
			}
		var out = switch t {
			case TStruct(st): [for (k in 0...st.fields.length) for (x in write(st.fields[k].type, l.offsets[k], Soft.dot(macro sv, "f_" + st.fields[k].name))) x];
			case _: write(t, 0, macro sv);
		}
		return macro {
			var sv = $v;
			$b{out};
		};
	}

	// element i of the storage buffer at b set to v, one element (the scalar form's)
	public function storageWriteAt(t:SType, b:Expr, i:Expr, v:Expr):Expr {
		var l = layout(t);
		function write(t:SType, off:Int, v:Expr):Array<Expr>
			return switch t {
				case TFloat: [macro helder.gfx.soft.Buffers.setF32At($b, $i, $v{l.stride}, $v{off}, $v)];
				case TInt: [macro helder.gfx.soft.Buffers.setI32At($b, $i, $v{l.stride}, $v{off}, $v)];
				case TBool: [macro helder.gfx.soft.Buffers.setI32At($b, $i, $v{l.stride}, $v{off}, $v ? 1 : 0)];
				case TVec(n): [for (k in 0...n) for (x in write(TFloat, off + 4 * k, Soft.dot(v, "xyzw".charAt(k)))) x];
				case TMat4: [for (k in 0...4) for (x in write(TVec(4), off + 16 * k, Soft.dot(v, "c" + k))) x];
				case t: Context.error('soft: a storage element of ${Names.typeName(t)}', pos);
			}
		var out = switch t {
			case TStruct(st): [for (k in 0...st.fields.length) for (x in write(st.fields[k].type, l.offsets[k], Soft.dot(macro sv, "f_" + st.fields[k].name))) x];
			case _: write(t, 0, macro sv);
		}
		return macro {
			var sv = $v;
			$b{out};
		};
	}

	// whether an index is a row index (rows: its lanes consecutive)
	public function isRow(i:SExpr):Bool
		return switch i.e {
			case ELocal(v): rows.exists(v);
			case _: false;
		}

	// element i's lanes when i's lanes are consecutive (from i.get(0)): a
	// Float or Int element one 128-bit load, a Vec4 at a 16-byte offset (a
	// Mat4's columns) four loads transposed (Rows), other fields lane by
	// lane; no bounds check (helder.parallel's range form: its items are
	// there, the buffer padded to 4 elements)
	public function rowsRead(t:SType, b:Expr, i:Expr):Expr {
		var l = layout(t), s = l.stride;
		function read(t:SType, off:Int):Expr
			return switch t {
				case TFloat if (s == 4): macro helder.gfx.soft.Lane.load(rd, ro);
				case TInt if (s == 4): macro helder.gfx.soft.LaneInt.of(hxmc.simd.I32x4.loadPtr(rd, ro));
				case TFloat: macro helder.gfx.soft.Rows.f32(rd, ro + $v{off}, $v{s});
				case TInt: macro helder.gfx.soft.Rows.i32(rd, ro + $v{off}, $v{s});
				case TBool: macro helder.gfx.soft.Rows.i32(rd, ro + $v{off}, $v{s}).ne(helder.gfx.soft.LaneInt.splat(0));
				case TVec(4) if (off % 16 == 0): macro helder.gfx.soft.Rows.vec4(rd, ro + $v{off}, $v{s});
				case TVec(n): {expr: haxe.macro.Expr.ExprDef.ENew({pack: SOFT, name: 'Lane$n'}, [for (k in 0...n) read(TFloat, off + 4 * k)]), pos: pos};
				case TMat4: {expr: haxe.macro.Expr.ExprDef.ENew({pack: SOFT, name: "LaneMat"}, [for (k in 0...4) read(TVec(4), off + 16 * k)]), pos: pos};
				case t: Context.error('soft: a storage element of ${Names.typeName(t)}', pos);
			}
		var value = switch t {
			case TStruct(st): laneMake(st, [for (k in 0...st.fields.length) read(st.fields[k].type, l.offsets[k])]);
			case _: read(t, 0);
		}
		return macro {
			var rd = hxmc.unsafe.Mem.getPtr($b, 0);
			var ro = $i.get(0) * $v{s};
			$value;
		};
	}

	// element i set to v (lanes) where m's lanes are, i's lanes consecutive:
	// all four as rows (rowsRead's), else lane by lane (storageWrite's); full:
	// m all of them (the range form's whole groups, funcFull's)
	public function rowsWrite(t:SType, b:Expr, i:Expr, v:Expr, full = false):Expr {
		var l = layout(t), s = l.stride;
		function write(t:SType, off:Int, v:Expr):Array<Expr>
			return switch t {
				case TFloat if (s == 4): [macro $v.store(rd, ro)];
				case TInt if (s == 4): [macro $v.bits().storePtr(rd, ro)];
				case TFloat: [macro helder.gfx.soft.Rows.setF32(rd, ro + $v{off}, $v{s}, $v)];
				case TInt: [macro helder.gfx.soft.Rows.setI32(rd, ro + $v{off}, $v{s}, $v)];
				case TBool: [macro helder.gfx.soft.Rows.setI32(rd, ro + $v{off}, $v{s}, helder.gfx.soft.LaneInt.select($v, helder.gfx.soft.LaneInt.splat(1), helder.gfx.soft.LaneInt.splat(0)))];
				case TVec(4) if (off % 16 == 0): [macro helder.gfx.soft.Rows.setVec4(rd, ro + $v{off}, $v{s}, $v)];
				case TVec(n): [for (k in 0...n) for (x in write(TFloat, off + 4 * k, Soft.dot(v, "xyzw".charAt(k)))) x];
				case TMat4: [for (k in 0...4) for (x in write(TVec(4), off + 16 * k, Soft.dot(v, "c" + k))) x];
				case t: Context.error('soft: a storage element of ${Names.typeName(t)}', pos);
			}
		var out = switch t {
			case TStruct(st): [for (k in 0...st.fields.length) for (x in write(st.fields[k].type, l.offsets[k], Soft.dot(macro rv, "f_" + st.fields[k].name))) x];
			case _: write(t, 0, macro rv);
		}
		if (full) return macro {
			var rv = $v;
			var rd = hxmc.unsafe.Mem.getPtr($b, 0);
			var ro = $i.get(0) * $v{s};
			$b{out};
		};
		var scattered = storageWrite(t, b, i, macro rv);
		return macro {
			var rv = $v;
			if (m.all()) {
				var rd = hxmc.unsafe.Mem.getPtr($b, 0);
				var ro = $i.get(0) * $v{s};
				$b{out};
			} else $scattered;
		};
	}

	// the stages' entries and ShaderCode's soft fields for each
	public function stages():{vertex:Expr, fragment:Expr} {
		var vs = entry(prog.vertex, false), fs = entry(prog.fragment, false);
		if (Context.defined("helder.soft.reference")) {
			entry(prog.vertex, true);
			entry(prog.fragment, true);
			check();
		}
		flush();
		var n = varyingComponents();
		return {
			vertex: macro {entry: $i{vs}(), varyings: $v{n}},
			fragment: macro {entry: $i{fs}(), varyings: $v{n}}
		};
	}

	// (-D helder.soft.reference) the shader's check against its scalar
	// reference (helder.gfx.soft.Check), registered when the program starts
	function check() {
		var body:Array<Expr> = [macro var k = new helder.gfx.soft.Check(seed)];
		for (u in prog.uniforms) {
			var kinds = [for (_ in 0...u.size >> 2) 0];
			for (i in 0...u.struct.fields.length)
				if (u.struct.fields[i].type == TInt || u.struct.fields[i].type == TBool) kinds[u.offsets[i] >> 2] = 1;
			body.push(macro k.block($v{u.binding}, $v{kinds}));
		}
		for (t in prog.textures)
			body.push(macro k.texture($v{t.slot}, $v{t.dimension}));
		var n = varyingComponents(), name = prefix;
		body.push(macro var e = k.stage($v{name + " vertex"}, soft_vs_addr(), soft_vs_ref_addr(), $v{64 * prog.vertex.input.fields.length}, $v{64 + 16 * n}, false));
		body.push(macro if (e == null) e = k.stage($v{name + " fragment"}, soft_fs_addr(), soft_fs_ref_addr(), $v{64 + 16 * n}, 64, true));
		body.push(macro k.free());
		body.push(macro return e);
		fields.push({
			name: "soft_check",
			access: [APublic, AStatic],
			meta: [{name: ":hxmc.unsafe", params: [macro gc], pos: pos}],
			kind: FFun({args: [{name: "seed", type: macro :Int}], ret: macro :Null<String>, expr: macro $b{body}}),
			pos: pos
		});
		fields.push({
			name: "softCheck",
			access: [APublic, AOverride],
			kind: FFun({args: [{name: "seed", type: macro :Int}], ret: macro :Null<String>, expr: macro return soft_check(seed)}),
			pos: pos
		});
	}

	function flush()
		while (pending.length > 0)
			pending.shift()();

	// the varyings' components after the position (the back end interpolates them)
	function varyingComponents():Int {
		var n = 0;
		for (f in prog.varyings.fields)
			if (!f.position) n += components(f.type);
		return n;
	}

	static function components(t:SType):Int
		return switch t {
			case TFloat: 1;
			case TVec(n): n;
			case TMat4: 16;
			case t: Context.error('soft: a varying of ${Names.typeName(t)}', Context.currentPos());
		}

	// ---- types

	static final SOFT = ["helder", "gfx", "soft"];
	static final MATH = ["helder", "math"];

	function isBlock(t:SType):Bool
		return switch t {
			case TStruct(s): blocks.exists(s);
			case _: false;
		}

	static function isTexture(t:SType):Bool
		return Textures.isTexture(t);

	// (values held by address: a uniform block's bytes, a texture's record, a storage buffer's binding, a storage texture's record)
	function isPtr(t:SType):Bool
		return isTexture(t) || isBlock(t) || t.match(TStorage(_, _) | TImage(_) | TWorkgroup(_));

	function laneType(t:SType):ComplexType
		return switch t {
			case TFloat: TPath({pack: SOFT, name: "Lane"});
			case TInt: TPath({pack: SOFT, name: "LaneInt"});
			case TBool: TPath({pack: SOFT, name: "LaneBool"});
			case TVec(n): TPath({pack: SOFT, name: 'Lane$n'});
			case TMat4: TPath({pack: SOFT, name: "LaneMat"});
			case t if (isPtr(t)): macro :hxmc.unsafe.Ptr;
			case TStruct(s): TPath({pack: pack, name: laneStruct(s)});
			case TVoid: macro :Void;
			case t: Context.error('soft: no lanes of ${Names.typeName(t)}', pos);
		}

	function scalarType(t:SType):ComplexType
		return switch t {
			case TFloat: macro :Float;
			case TInt: macro :Int;
			case TBool: macro :Bool;
			case TVec(n): TPath({pack: MATH, name: 'Vec$n'});
			case TMat4: macro :helder.math.Mat4;
			case t if (isPtr(t)): macro :hxmc.unsafe.Ptr;
			case TStruct(s): TPath({pack: pack, name: scalarStruct(s)});
			case TVoid: macro :Void;
			case t: Context.error('soft: no scalar of ${Names.typeName(t)}', pos);
		}

	// a struct's lanes: a field each, its lanes. Made by make(fields...), a
	// static inline function storing each field into a value of an empty
	// constructor: no constructor call takes the value's address (hxmc's
	// inliner keeps a constructor of large struct arguments a call, and its
	// Sroa then keeps the value in memory: the range form measured 1.8x
	// slower so)
	function laneStruct(s:SStruct):String {
		var name = laneStructs.get(s);
		if (name != null) return name;
		name = prefix + "_" + s.name + "_l";
		laneStructs.set(s, name);
		var fs:Array<Field> = [for (f in s.fields) {name: "f_" + f.name, access: [APublic], kind: FVar(laneType(f.type)), pos: pos}];
		var args = [for (f in s.fields) {name: "a_" + f.name, type: laneType(f.type)}];
		var self = TPath({pack: pack, name: name}), tp:TypePath = {pack: pack, name: name};
		fs.push({
			name: "new",
			access: [APublic, AInline],
			kind: FFun({args: [], ret: null, expr: macro {}}),
			pos: pos
		});
		var stores = [for (f in s.fields) {var n = "f_" + f.name, a = "a_" + f.name; macro r.$n = $i{a};}];
		fs.push({
			name: "make",
			access: [APublic, AStatic, AInline],
			kind: FFun({args: args, ret: self, expr: macro {
				var r = new $tp();
				$b{stores};
				return r;
			}}),
			pos: pos
		});
		var make = macro $p{pack.concat([name, "make"])};
		var sel = [for (f in s.fields) select(f.type, macro m, Soft.dot(macro a, "f_" + f.name), Soft.dot(macro b, "f_" + f.name))];
		var zeros = [for (f in s.fields) zero(f.type)];
		fs.push({
			name: "select",
			access: [APublic, AStatic, AInline],
			kind: FFun({args: [{name: "m", type: laneType(TBool)}, {name: "a", type: self}, {name: "b", type: self}], ret: self, expr: macro return $make($a{sel})}),
			pos: pos
		});
		fs.push({
			name: "zero",
			access: [APublic, AStatic, AInline],
			kind: FFun({args: [], ret: self, expr: macro return $make($a{zeros})}),
			pos: pos
		});
		define(name, fs);
		return name;
	}

	// a struct's lanes of its fields' (laneStruct's make)
	function laneMake(s:SStruct, args:Array<Expr>):Expr
		return macro $p{pack.concat([laneStruct(s), "make"])}($a{args});

	function scalarStruct(s:SStruct):String {
		var name = scalarStructs.get(s);
		if (name != null) return name;
		name = prefix + "_" + s.name + "_s";
		scalarStructs.set(s, name);
		var fs:Array<Field> = [for (f in s.fields) {name: "f_" + f.name, access: [APublic, AFinal], kind: FVar(scalarType(f.type)), pos: pos}];
		var args = [for (f in s.fields) {name: "a_" + f.name, type: scalarType(f.type)}];
		fs.push({
			name: "new",
			access: [APublic, AInline],
			kind: FFun({args: args, ret: null, expr: macro $b{[for (f in s.fields) {var n = "f_" + f.name, a = "a_" + f.name; macro this.$n = $i{a};}]}}),
			pos: pos
		});
		define(name, fs);
		return name;
	}

	function define(name:String, fs:Array<Field>) {
		var exists = try Context.getType(pack.concat([name]).join(".")) != null catch (_:Dynamic) false;
		if (exists) return;
		Context.defineType({
			pack: pack,
			name: name,
			pos: pos,
			meta: [{name: ":hxmc.struct", pos: pos}, {name: ":noCompletion", pos: pos}],
			kind: TDClass(null, [], false, true),
			fields: fs
		}, module);
	}

	// a value's lanes all of one value, from its scalar
	function splat(t:SType, e:Expr):Expr
		return switch t {
			case TFloat: macro helder.gfx.soft.Lane.splat($e);
			case TInt: macro helder.gfx.soft.LaneInt.splat($e);
			case TBool: macro helder.gfx.soft.LaneBool.splat($e);
			case TVec(n): macro $p{SOFT.concat(['Lane$n', "splat"])}($e);
			case TMat4: macro helder.gfx.soft.LaneMat.splat($e);
			case t if (isPtr(t)): e;
			case t: Context.error('soft: no splat of ${Names.typeName(t)}', pos);
		}

	// a constant's lanes from its float32 bits, else null
	function constant(e:SExpr):Null<Expr> {
		function x(e:SExpr):Null<Float>
			return switch e.e {
				case EFloat(v): v;
				case EInt(v) if (e.t == TFloat): v;
				case EUnop(Neg, a): var v = x(a); v == null ? null : -v;
				case _: null;
			}
		// (hxmc builds a Float's splat as a double converted at each use: 7
		// instructions; an integer's in 2 or 3. Round to nearest, ties to even, as at run time)
		inline function one(v:Float):Expr
			return macro helder.gfx.soft.Lane.constant($v{haxe.io.FPHelper.floatToI32(v)}, $v{v});
		return switch [e.t, e.e] {
			case [TFloat, _]:
				var v = x(e);
				v == null ? null : one(v);
			case [TVec(n), ENew(args)] if (Lambda.foreach(args, a -> a.t == TFloat && x(a) != null)):
				var cs = [for (a in args) one(x(a))];
				if (cs.length == 1) cs = [for (_ in 0...n) cs[0]];
				cs.length != n ? null : {expr: haxe.macro.Expr.ExprDef.ENew({pack: SOFT, name: 'Lane$n'}, cs), pos: pos};
			case _: null;
		}
	}

	function zero(t:SType):Expr
		return switch t {
			case TFloat: macro helder.gfx.soft.Lane.zero();
			case TInt: macro helder.gfx.soft.LaneInt.splat(0);
			case TBool: macro helder.gfx.soft.LaneBool.none();
			case TVec(n): macro $p{SOFT.concat(['Lane$n', "zero"])}();
			case TMat4: macro helder.gfx.soft.LaneMat.zero();
			case t if (isPtr(t)): macro hxmc.unsafe.Ptr.nil();
			case TStruct(s): macro $p{pack.concat([laneStruct(s), "zero"])}();
			case t: Context.error('soft: no zero of ${Names.typeName(t)}', pos);
		}

	function scalarZero(t:SType):Expr
		return switch t {
			case TFloat: macro 0.0;
			case TInt: macro 0;
			case TBool: macro false;
			case TVec(2): macro new helder.math.Vec2(0, 0);
			case TVec(3): macro new helder.math.Vec3(0, 0, 0);
			case TVec(4): macro new helder.math.Vec4(0, 0, 0, 0);
			case TMat4: macro helder.gfx.shader.ShaderMath.mat4(0.0);
			case t if (isPtr(t)): macro hxmc.unsafe.Ptr.nil();
			case TStruct(s):
				var tp:TypePath = {pack: pack, name: scalarStruct(s)};
				macro new $tp($a{[for (f in s.fields) scalarZero(f.type)]});
			case t: Context.error('soft: no zero of ${Names.typeName(t)}', pos);
		}

	function select(t:SType, m:Expr, a:Expr, b:Expr):Expr
		return switch t {
			case TFloat: macro helder.gfx.soft.Lane.select($m, $a, $b);
			case TInt: macro helder.gfx.soft.LaneInt.select($m, $a, $b);
			case TBool: macro helder.gfx.soft.LaneBool.select($m, $a, $b);
			case TVec(n): macro $p{SOFT.concat(['Lane$n', "select"])}($m, $a, $b);
			case TMat4: macro helder.gfx.soft.LaneMat.select($m, $a, $b);
			case TStruct(s) if (!isPtr(t)): macro $p{pack.concat([laneStruct(s), "select"])}($m, $a, $b);
			case t: Context.error('soft: a ${Names.typeName(t)} differing between lanes', pos);
		}

	// ---- the uniform analysis

	// a function's uniform locals (the others' lanes differ)
	final uniforms = new Map<SFunction, Map<SVar, Bool>>();

	function uniformsOf(f:SFunction, scalar:Bool):Map<SVar, Bool> {
		var key = f;
		if (scalar) {
			// (the reference: everything scalar)
			var all = new Map<SVar, Bool>();
			return all;
		}
		var u = uniforms.get(key);
		if (u != null) return u;
		u = new Map<SVar, Bool>();
		var varying = new Map<SVar, Bool>();
		for (p in f.params)
			if (!isPtr(p.type)) varying.set(p, true);
		var depths = new Map<SVar, Int>();
		var changed = true;
		function isUniform(v:SVar):Bool
			return isPtr(v.type) || (!varying.exists(v) && !v.type.match(TStruct(_)));
		function mark(v:SVar)
			if (!varying.exists(v) && !isPtr(v.type)) {
				varying.set(v, true);
				changed = true;
			}
		function uni(e:SExpr):Bool
			return exprUniform(e, isUniform);
		// whether a loop's body leaves it on lanes (a break or continue under a test of lanes)
		function diverges(ss:Array<SStmt>, d:Int):Bool {
			for (s in ss)
				switch s {
					case SBreak | SContinue if (d > 0): return true;
					case SIf(c, a, b):
						var k = uni(c) ? d : d + 1;
						if (diverges(a, k) || (b != null && diverges(b, k))) return true;
					case _:
				}
			return false;
		}
		function walk(ss:Array<SStmt>, d:Int)
			for (s in ss)
				switch s {
					case SDecl(v, init):
						depths.set(v, d);
						if (init != null && !uni(init)) mark(v);
					case SAssign(v, op, e):
						var at = depths.exists(v) ? depths.get(v) : 0;
						if (!uni(e) || d > at) mark(v);
					case SIf(c, a, b):
						var k = uni(c) ? d : d + 1;
						walk(a, k);
						if (b != null) walk(b, k);
					case SWhile(c, body):
						walk(body, uni(c) && !diverges(body, 0) ? d : d + 1);
					case _:
				}
		while (changed) {
			changed = false;
			walk(f.body, 0);
		}
		function all(ss:Array<SStmt>)
			for (s in ss)
				switch s {
					case SDecl(v, _): if (isUniform(v)) u.set(v, true);
					case SIf(_, a, b):
						all(a);
						if (b != null) all(b);
					case SWhile(_, body): all(body);
					case _:
				}
		all(f.body);
		for (p in f.params)
			if (isUniform(p)) u.set(p, true);
		uniforms.set(key, u);
		return u;
	}

	// whether every lane has e's value (its locals' by isUniform)
	function exprUniform(e:SExpr, isUniform:SVar->Bool):Bool {
		function u(x:SExpr):Bool
			return exprUniform(x, isUniform);
		return switch e.e {
			case EFloat(_) | EInt(_) | EBool(_): true;
			case ELocal(v): isUniform(v);
			case EField(x, _) | ESwizzle(x, _) | EColumn(x, _) | EUnop(_, x) | EConvert(x): u(x);
			case EIndex(x, i): u(x) && u(i);
			case EBinop(_, a, b): u(a) && u(b);
			case ECond(c, a, b): u(c) && u(a) && u(b);
			case ENew(args): !e.t.match(TStruct(_)) && Lambda.foreach(args, u);
			case EBuiltin("discard" | "atomicAdd" | "atomicMin" | "atomicMax" | "textureStore", _): false;
			// (a subgroup's value: computed from its lanes)
			case EBuiltin(name, _) if (Subgroups.isOp(name)): false;
			case EBuiltin(_, args): Lambda.foreach(args, u);
			case ECall(f, args): !mayDiscard(f) && !f.ret.match(TStruct(_)) && Lambda.foreach(args, u);
		}
	}

	// whether a function (or one it calls) discards the fragment
	function mayDiscard(f:SFunction):Bool {
		var k = discards.get(f);
		if (k != null) return k;
		discards.set(f, false);
		var found = false;
		function ex(e:SExpr)
			switch e.e {
				case EBuiltin("discard", _): found = true;
				case ECall(g, args):
					if (mayDiscard(g)) found = true;
					for (a in args)
						ex(a);
				case EField(x, _) | ESwizzle(x, _) | EColumn(x, _) | EUnop(_, x) | EConvert(x): ex(x);
				case EIndex(x, i):
					ex(x);
					ex(i);
				case EBinop(_, a, b):
					ex(a);
					ex(b);
				case ECond(c, a, b):
					ex(c);
					ex(a);
					ex(b);
				case ENew(args) | EBuiltin(_, args): for (a in args) ex(a);
				case _:
			}
		function st(ss:Array<SStmt>)
			for (s in ss)
				switch s {
					case SDecl(_, x) if (x != null): ex(x);
					case SAssign(_, _, x) | SEval(x): ex(x);
					case SReturn(x) if (x != null): ex(x);
					case SIf(c, a, b):
						ex(c);
						st(a);
						if (b != null) st(b);
					case SWhile(c, b):
						ex(c);
						st(b);
					case _:
				}
		st(f.body);
		discards.set(f, found);
		return found;
	}

	// ---- functions

	// whether a function is emitted inline: straight-line (declarations, then
	// one return) and small with the inlined functions it calls, so that a
	// helper's struct values stay in registers rather than going through
	// memory at each call, while code size stays bounded
	final costs = new Map<SFunction, Int>();

	static inline var INLINE = 48;

	function inlined(f:SFunction):Bool
		return cost(f) <= INLINE;

	function cost(f:SFunction):Int {
		var k = costs.get(f);
		if (k != null) return k;
		costs.set(f, INLINE + 1);
		var n = 0, straight = f.body.length > 0 && f.body[f.body.length - 1].match(SReturn(_));
		function ex(e:SExpr)
			switch e.e {
				case ECall(g, args):
					n += inlined(g) ? cost(g) : 1;
					for (a in args)
						ex(a);
				case EField(x, _) | ESwizzle(x, _) | EColumn(x, _) | EUnop(_, x) | EConvert(x):
					n++;
					ex(x);
				case EIndex(x, i):
					n++;
					ex(x);
					ex(i);
				case EBinop(_, a, b):
					n++;
					ex(a);
					ex(b);
				case ECond(c, a, b):
					n++;
					ex(c);
					ex(a);
					ex(b);
				case ENew(args) | EBuiltin(_, args):
					n++;
					for (a in args)
						ex(a);
				case _:
			}
		for (st in f.body)
			switch st {
				case SDecl(_, x):
					n++;
					if (x != null) ex(x);
				case SReturn(x) if (x != null): ex(x);
				case _: straight = false;
			}
		if (!straight || mayDiscard(f)) n = INLINE + 1;
		costs.set(f, n);
		return n;
	}

	// (helder.parallel's range form) a stage function's lanes for calls whose
	// lanes are all there: its rows written whole, no masked path (whose
	// calls cost its loop registers): its name
	public function funcFull(f:SFunction):String {
		var name = "l_full_" + f.name;
		if (made.exists(name)) return name;
		made.set(name, true);
		pending.push(() -> {
			var fn = new Fn(this, f, false, false);
			fn.full = true;
			fields.push(fn.field(name));
		});
		return name;
	}

	// a function's lane form (or, scalar, its scalar form) for a stage: its name
	function func(f:SFunction, fragment:Bool, scalar:Bool, phased = false):String {
		var name = (scalar ? "s_" : "l_") + (fragment ? "f_" : "v_") + f.name;
		if (made.exists(name)) return name;
		made.set(name, true);
		pending.push(() -> fields.push(phased ? new Fn(this, f, fragment, scalar).phased(name) : new Fn(this, f, fragment, scalar).field(name)));
		return name;
	}

	// a stage's entry, the GC-free callback the back end calls: its name's address getter
	function entry(e:SEntry, scalar:Bool):String {
		var fragment = e.stage == Fragment, compute = e.stage == Compute;
		var name = "soft_" + (compute ? "cs" : fragment ? "fs" : "vs") + (scalar ? "_ref" : "");
		var phased = compute && Phases.barriers(e.fn.body);
		var fn = func(e.fn, fragment, scalar, phased);
		var body:Array<Expr> = [
			(macro var input = hxmc.unsafe.Mem.getPtr(c, $v{ABI_IN})),
			(macro var output = hxmc.unsafe.Mem.getPtr(c, $v{ABI_OUT})),
			(macro var lanes = hxmc.unsafe.Mem.getI32(c, $v{ABI_MASK})),
			macro var kill = hxmc.unsafe.Mem.stack(16)
		];
		body.push(macro hxmc.unsafe.Mem.setI32(kill, 0, 0));
		var resources:Array<Expr> = [];
		for (r in e.resources)
			resources.push(switch r {
				case RUniform(u): macro hxmc.unsafe.Mem.getPtr(c, $v{ABI_UNIFORMS + 8 * u.binding});
				case RTexture(t): macro hxmc.unsafe.Mem.getPtr(c, $v{ABI_TEXTURES + 8 * t.slot});
				case RStorage(b): macro hxmc.unsafe.Mem.getPtr(c, $v{ABI_STORAGE + 8 * b.slot});
				case RImage(m): macro hxmc.unsafe.Mem.getPtr(c, $v{ABI_IMAGES + 8 * m.slot});
			});
		// (workgroup memory: a storage buffer's record of each array, at its place in the workgroup's block)
		if (shared.length > 0) {
			body.push(macro var wr = hxmc.unsafe.Mem.stack($v{16 * shared.length}));
			body.push(macro var wg = hxmc.unsafe.Mem.getPtr(c, $v{ABI_WORKGROUP}));
			var at = 0;
			for (k in 0...shared.length) {
				// (Buffers.DATA, Buffers.BYTES)
				body.push(macro hxmc.unsafe.Mem.setPtr(wr, $v{16 * k}, wg.add($v{at})));
				body.push(macro hxmc.unsafe.Mem.setI32(wr, $v{16 * k + 8}, $v{shared[k].bytes}));
				resources.push(macro wr.add($v{16 * k}));
				at += shared[k].bytes;
			}
		}
		if (phased) resources = resources.concat([macro hxmc.unsafe.Mem.getI32(c, $v{ABI_PHASE}), macro hxmc.unsafe.Mem.getPtr(c, $v{ABI_FRAME})]);
		// the input's fields from its lanes: the vertex's attributes at 64
		// bytes a location (4 components, 16 bytes each), the varyings' position
		// then each component in order
		var inFields:Array<{type:SType, at:Int}> = [], at = 0;
		for (i in 0...e.input.fields.length) {
			var f = e.input.fields[i];
			if (compute) inFields.push({type: f.type, at: 16 * i}) else if (!fragment) inFields.push({type: f.type, at: 64 * i}) else if (f.position) inFields.push({type: f.type, at: 0}) else {
				inFields.push({type: f.type, at: 64 + 16 * at});
				at += components(f.type);
			}
		}
		function load(t:SType, off:Int, lane:Null<Int>):Expr {
			function one(o:Int):Expr
				return lane == null ? macro helder.gfx.soft.Lane.load(input, $v{o}) : macro(hxmc.unsafe.Mem.getF32(input, $v{o + 4 * lane}) : Float);
			return switch t {
				case TFloat: one(off);
				case TInt: lane == null ? macro helder.gfx.soft.LaneInt.of(hxmc.simd.I32x4.loadPtr(input, $v{off})) : macro hxmc.unsafe.Mem.getI32(input, $v{off + 4 * lane});
				case TVec(n):
					var cs = [for (k in 0...n) one(off + 16 * k)];
					{expr: haxe.macro.Expr.ExprDef.ENew({pack: lane == null ? SOFT : MATH, name: lane == null ? 'Lane$n' : 'Vec$n'}, cs), pos: pos};
				case TMat4:
					var cols = [for (c in 0...4) load(TVec(4), off + 64 * c, lane)];
					lane == null ? macro new helder.gfx.soft.LaneMat($a{cols}) : macro new helder.math.Mat4($a{cols});
				case t: Context.error('soft: an input of ${Names.typeName(t)}', pos);
			}
		}
		function store(t:SType, v:Expr, off:Int, lane:Null<Int>):Array<Expr> {
			function one(x:Expr, o:Int):Expr
				return lane == null ? macro $x.store(output, $v{o}) : macro hxmc.unsafe.Mem.setF32(output, $v{o + 4 * lane}, $x);
			return switch t {
				case TFloat: [one(v, off)];
				case TVec(n): [for (k in 0...n) one(Soft.dot(v, "xyzw".charAt(k)), off + 16 * k)];
				case TMat4: [for (c in 0...4) for (x in store(TVec(4), Soft.dot(v, "c" + c), off + 64 * c, lane)) x];
				case t: Context.error('soft: an output of ${Names.typeName(t)}', pos);
			}
		}
		function inputOf(lane:Null<Int>):Expr {
			var args = [for (f in inFields) load(f.type, f.at, lane)];
			if (lane == null) return laneMake(e.input, args);
			var tp:TypePath = {pack: pack, name: scalarStruct(e.input)};
			return macro new $tp($a{args});
		}
		function outputs(r:Expr, lane:Null<Int>):Array<Expr> {
			if (compute) return [];
			if (fragment) return store(TVec(4), r, 0, lane);
			var out = [], k = 0;
			for (f in prog.varyings.fields)
				if (f.position) out = out.concat(store(f.type, Soft.dot(r, "f_" + f.name), 0, lane));
			for (f in prog.varyings.fields)
				if (!f.position) {
					out = out.concat(store(f.type, Soft.dot(r, "f_" + f.name), 64 + 16 * k, lane));
					k += components(f.type);
				}
			return out;
		}
		if (!scalar) {
			var args = [macro helder.gfx.soft.LaneBool.ofMask(lanes), inputOf(null)].concat(resources);
			if (mayDiscard(e.fn)) args.push(macro kill);
			// (a compute stage's: the next phase, -1 the end)
			if (phased) body.push(macro return $i{fn}($a{args})) else {
				body.push(compute ? macro $i{fn}($a{args}) : macro var r = $i{fn}($a{args}));
				body = body.concat(outputs(macro r, null));
				body.push(compute ? macro return -1 : macro return lanes & ~hxmc.unsafe.Mem.getI32(kill, 0));
			}
		} else {
			// (lane by lane, its scalar code)
			body.push(macro var left = lanes);
			for (lane in 0...4) {
				var args = [inputOf(lane)].concat(resources);
				if (mayDiscard(e.fn)) args.push(macro kill);
				var stores = outputs(macro r, lane);
				body.push(macro if (lanes & $v{1 << lane} != 0) {
					hxmc.unsafe.Mem.setI32(kill, 0, 0);
					var r = $i{fn}($a{args});
					$b{stores};
					if (hxmc.unsafe.Mem.getI32(kill, 0) != 0) left &= ~$v{1 << lane};
				});
			}
			body.push(macro return left);
		}
		fields.push({
			name: name,
			access: [APublic, AStatic],
			meta: [{name: ":hxmc.callback", pos: pos}, {name: ":hxmc.unsafe", pos: pos}],
			kind: FFun({args: [{name: "c", type: macro :hxmc.unsafe.Ptr}], ret: macro :Int, expr: macro $b{body}}),
			pos: pos
		});
		var getter = name + "_addr";
		fields.push({
			name: getter,
			access: [APublic, AStatic],
			meta: [{name: ":hxmc.unsafe", pos: pos}],
			kind: FFun({args: [], ret: macro :hxmc.I64, expr: macro return hxmc.unsafe.Callback.addr($i{name}).toI64()}),
			pos: pos
		});
		return getter;
	}

	// ---- the phases' frames

	// a value kept in a frame at p + off (lanes, or a scalar): its bytes,
	// its load and the store of v (8 bytes a scalar, doubles for Floats:
	// its value as it is in either form of lanes)
	function spill(t:SType, lanes:Bool, p:Expr, off:Int, v:Null<Expr>):{bytes:Int, load:Expr, store:Array<Expr>} {
		var x = v ?? macro null;
		function parts(fields:Array<{name:String, type:SType}>, make:Array<Expr>->Expr):{bytes:Int, load:Expr, store:Array<Expr>} {
			var at = off, loads = [], stores = [];
			for (f in fields) {
				var r = spill(f.type, lanes, p, at, Soft.dot(x, f.name));
				at += r.bytes;
				loads.push(r.load);
				stores = stores.concat(r.store);
			}
			return {bytes: at - off, load: make(loads), store: stores};
		}
		function vec(n:Int):Array<{name:String, type:SType}>
			return [for (k in 0...n) {name: "xyzw".charAt(k), type: TFloat}];
		return switch [t, lanes] {
			case [TFloat, true]: {
					bytes: 32,
					load: macro helder.gfx.soft.Lane.make($a{[for (k in 0...4) macro hxmc.unsafe.Mem.getF64($p, $v{off + 8 * k})]}),
					store: [for (k in 0...4) macro hxmc.unsafe.Mem.setF64($p, $v{off + 8 * k}, $x.get($v{k}))]
				};
			case [TInt, true]: {
					bytes: 16,
					load: macro helder.gfx.soft.LaneInt.make($a{[for (k in 0...4) macro hxmc.unsafe.Mem.getI32($p, $v{off + 4 * k})]}),
					store: [for (k in 0...4) macro hxmc.unsafe.Mem.setI32($p, $v{off + 4 * k}, $x.get($v{k}))]
				};
			case [TBool, true]: {bytes: 8, load: macro helder.gfx.soft.LaneBool.ofMask(hxmc.unsafe.Mem.getI32($p, $v{off})), store: [macro hxmc.unsafe.Mem.setI32($p, $v{off}, $x.mask())]};
			case [TFloat, false]: {bytes: 8, load: macro hxmc.unsafe.Mem.getF64($p, $v{off}), store: [macro hxmc.unsafe.Mem.setF64($p, $v{off}, $x)]};
			case [TInt, false]: {bytes: 8, load: macro hxmc.unsafe.Mem.getI32($p, $v{off}), store: [macro hxmc.unsafe.Mem.setI32($p, $v{off}, $x)]};
			case [TBool, false]: {bytes: 8, load: macro hxmc.unsafe.Mem.getI32($p, $v{off}) != 0, store: [macro hxmc.unsafe.Mem.setI32($p, $v{off}, $x ? 1 : 0)]};
			case [TVec(n), _]: parts(vec(n), xs -> {expr: haxe.macro.Expr.ExprDef.ENew({pack: lanes ? SOFT : MATH, name: (lanes ? "Lane" : "Vec") + n}, xs), pos: pos});
			case [TMat4, _]:
				parts([for (k in 0...4) {name: "c" + k, type: TVec(4)}], xs -> lanes ? macro new helder.gfx.soft.LaneMat($a{xs}) : macro new helder.math.Mat4($a{xs}));
			case [TStruct(st), _]:
				// (lanes: laneStruct's make, its constructor of no fields)
				parts([for (f in st.fields) {name: "f_" + f.name, type: f.type}], xs -> lanes ? laneMake(st, xs) : {expr: haxe.macro.Expr.ExprDef.ENew({pack: pack, name: scalarStruct(st)}, xs), pos: pos});
			case [t, _]: Context.error('soft: a ${Names.typeName(t)} kept across a barrier', pos);
		}
	}

	// ---- reading uniform blocks

	// field n of the block at p (a Ptr expression), scalar
	public function blockField(s:SStruct, p:Expr, n:String):Expr {
		var u = blocks.get(s);
		var i = Lambda.findIndex(s.fields, f -> f.name == n);
		return readAt(s.fields[i].type, p, macro $v{u.offsets[i]});
	}

	// a block's field (or a vector field's components) in every lane, read
	// from its float32 bits (a Float's splat converts it to a double and back)
	public function blockLanes(s:SStruct, p:Expr, n:String, comps:Null<String>):Null<Expr> {
		var u = blocks.get(s);
		var i = Lambda.findIndex(s.fields, f -> f.name == n);
		var t = s.fields[i].type, off = u.offsets[i];
		inline function one(o:Int):Expr
			return macro helder.gfx.soft.Lane.loadSplat($p, $v{o});
		function vec(o:Int, cs:String):Expr
			return cs.length == 1 ? one(o + 4 * "xyzw".indexOf(cs)) : {
				expr: haxe.macro.Expr.ExprDef.ENew({pack: SOFT, name: 'Lane${cs.length}'}, [for (k in 0...cs.length) one(o + 4 * "xyzw".indexOf(cs.charAt(k)))]),
				pos: pos
			};
		return switch [t, comps] {
			case [TFloat, null]: one(off);
			case [TVec(k), null]: vec(off, "xyzw".substr(0, k));
			case [TVec(_), cs]: vec(off, cs);
			case [TMat4, null]: macro new helder.gfx.soft.LaneMat($a{[for (c in 0...4) vec(off + 16 * c, "xyzw")]});
			case _: null;
		}
	}

	public function blockArray(s:SStruct, p:Expr, n:String, index:Expr, lanes:Bool):Expr {
		var u = blocks.get(s);
		var i = Lambda.findIndex(s.fields, f -> f.name == n);
		var t = s.fields[i].type, off = u.offsets[i];
		return switch t {
			case TArray(et, len):
				var stride = et == TMat4 ? 64 : 16;
				if (!lanes) {
					var at = macro $v{off} + $v{stride} * helder.gfx.soft.Uniforms.index($index, $v{len});
					readAt(et, p, at);
				} else
					et == TMat4 ? macro helder.gfx.soft.Uniforms.mats($p, $v{off}, $index, $v{len}) : macro helder.gfx.soft.Uniforms.vec4s($p, $v{off}, $index,
						$v{len});
			case t: Context.error('soft: an index into ${Names.typeName(t)}', pos);
		}
	}

	static function readAt(t:SType, p:Expr, at:Expr):Expr
		return switch t {
			case TFloat: macro(hxmc.unsafe.Mem.getF32($p, $at) : Float);
			case TInt: macro hxmc.unsafe.Mem.getI32($p, $at);
			case TBool: macro hxmc.unsafe.Mem.getI32($p, $at) != 0;
			case TVec(n):
				var cs = [for (k in 0...n) macro(hxmc.unsafe.Mem.getF32($p, $at + $v{4 * k}) : Float)];
				{expr: haxe.macro.Expr.ExprDef.ENew({pack: MATH, name: 'Vec$n'}, cs), pos: Context.currentPos()};
			case TMat4:
				var cols = [for (c in 0...4) readAt(TVec(4), p, macro $at + $v{16 * c})];
				macro new helder.math.Mat4($a{cols});
			case t: Context.error('soft: a uniform of ${Names.typeName(t)}', Context.currentPos());
		}

	// (for Fn)
	@:allow(helder.gfx.shader.Fn) function useFunc(f:SFunction, fragment:Bool, scalar:Bool):String
		return func(f, fragment, scalar);

	@:allow(helder.gfx.shader.Fn) function useUniforms(f:SFunction, scalar:Bool):Map<SVar, Bool>
		return uniformsOf(f, scalar);

	@:allow(helder.gfx.shader.Fn) function uniformExpr(e:SExpr, isUniform:SVar->Bool):Bool
		return exprUniform(e, isUniform);

	@:allow(helder.gfx.shader.Fn) function inlines(f:SFunction):Bool
		return inlined(f);

	@:allow(helder.gfx.shader.Fn) function discardsIn(f:SFunction):Bool
		return mayDiscard(f);

	@:allow(helder.gfx.shader.Fn) function ptrType(t:SType):Bool
		return isPtr(t);

	@:allow(helder.gfx.shader.Fn) function blockType(t:SType):Bool
		return isBlock(t);

	@:allow(helder.gfx.shader.Fn) function lanesOf(t:SType):ComplexType
		return laneType(t);

	@:allow(helder.gfx.shader.Fn) function scalarOf(t:SType):ComplexType
		return scalarType(t);

	@:allow(helder.gfx.shader.Fn) function splatOf(t:SType, e:Expr):Expr
		return splat(t, e);

	@:allow(helder.gfx.shader.Fn) function readStorage(t:SType, b:Expr, i:Expr, lanes:Bool):Expr
		return storageRead(t, b, i, lanes);

	@:allow(helder.gfx.shader.Fn) function writeStorage(t:SType, b:Expr, i:Expr, v:Expr):Expr
		return storageWrite(t, b, i, v);

	@:allow(helder.gfx.shader.Fn) function blockLanesOf(s:SStruct, p:Expr, n:String, comps:Null<String>):Null<Expr>
		return blockLanes(s, p, n, comps);

	@:allow(helder.gfx.shader.Fn) function constantOf(e:SExpr):Null<Expr>
		return constant(e);

	@:allow(helder.gfx.shader.Fn) function zeroOf(t:SType):Expr
		return zero(t);

	@:allow(helder.gfx.shader.Fn) function scalarZeroOf(t:SType):Expr
		return scalarZero(t);

	@:allow(helder.gfx.shader.Fn) function selectOf(t:SType, m:Expr, a:Expr, b:Expr):Expr
		return select(t, m, a, b);

	@:allow(helder.gfx.shader.Fn) function laneStructPath(s:SStruct):TypePath
		return {pack: pack, name: laneStruct(s)};

	@:allow(helder.gfx.shader.Fn) function spillOf(t:SType, lanes:Bool, p:Expr, off:Int, v:Null<Expr>):{bytes:Int, load:Expr, store:Array<Expr>}
		return spill(t, lanes, p, off, v);

	@:allow(helder.gfx.shader.Fn) function laneMakeOf(s:SStruct, args:Array<Expr>):Expr
		return laneMake(s, args);

	@:allow(helder.gfx.shader.Fn) function scalarStructPath(s:SStruct):TypePath
		return {pack: pack, name: scalarStruct(s)};
}

// one function's form: its lanes (or scalar: the reference) for a stage
@:allow(helder.gfx.shader.Soft)
class Fn {
	final soft:Soft;
	final f:SFunction;
	final fragment:Bool;
	final scalar:Bool;
	final uniform:Map<SVar, Bool>;
	final pos:Position;
	final discards:Bool;
	// (Soft.funcFull's: every lane there)
	public var full = false;
	// the locals' depths of lane tests they were declared at
	final declared = new Map<SVar, Int>();
	var depth = 0;
	var temps = 0;
	// whether a return under a test of lanes set r
	var returned = false;
	// the loops' masks: the lanes that left it, continued
	final loops:Array<{exit:String, cont:String, lanes:Bool}> = [];
	// (a phased compute function: its locals kept in the frame, declared at
	// the phase's start, so their declarations assign them; a return the end)
	final kept = new Map<SVar, Bool>();
	var phasing = false;

	function new(soft:Soft, f:SFunction, fragment:Bool, scalar:Bool) {
		this.soft = soft;
		this.f = f;
		this.fragment = fragment;
		this.scalar = scalar;
		uniform = soft.useUniforms(f, scalar);
		pos = Context.currentPos();
		discards = soft.discardsIn(f);
	}

	function isUniform(v:SVar):Bool
		return scalar || soft.ptrType(v.type) || uniform.exists(v);

	function uni(e:SExpr):Bool
		return scalar || soft.uniformExpr(e, isUniform);

	static function name(v:SVar):String
		return "v_" + v.name;

	function temp():String
		return "t_" + temps++;

	function field(fname:String):Field {
		var args:Array<FunctionArg> = [];
		if (!scalar) args.push({name: "m", type: macro :helder.gfx.soft.LaneBool});
		for (p in f.params)
			args.push({name: name(p), type: isUniform(p) ? soft.scalarOf(p.type) : soft.lanesOf(p.type)});
		if (discards) args.push({name: "kill", type: macro :hxmc.unsafe.Ptr});
		for (p in f.params)
			declared.set(p, 0);
		var body:Array<Expr> = [];
		var ret = f.ret;
		// (one return, the last statement: no result kept for lanes)
		var single = ret != TVoid && !discards && returns(f.body) == 1 && f.body.length > 0 && f.body[f.body.length - 1].match(SReturn(_));
		if (ret != TVoid && !single) body.push(macro var r = ${scalar ? soft.scalarZeroOf(ret) : soft.zeroOf(ret)});
		body = body.concat(block(f.body));
		if (ret != TVoid && !single) body.push(macro return r);
		return {
			name: fname,
			access: soft.inlines(f) ? [APublic, AStatic, AInline] : [APublic, AStatic],
			meta: [{name: ":hxmc.unsafe", params: [macro gc], pos: pos}],
			kind: FFun({args: args, ret: scalar ? soft.scalarOf(ret) : soft.lanesOf(ret), expr: macro $b{body}}),
			pos: pos
		};
	}

	// a compute function with barriers (Phases), as the back end calls it:
	// its parameters, the phase and its invocations' frame; the next phase
	public function phased(fname:String):Field {
		var cut = Phases.cut(f.body);
		if (cut == null) Context.error("soft: a loop with barrier() in it has a break or continue", pos);
		phasing = true;
		var args:Array<FunctionArg> = [{name: "m", type: macro :helder.gfx.soft.LaneBool}];
		for (p in f.params) {
			args.push({name: name(p), type: isUniform(p) ? soft.scalarOf(p.type) : soft.lanesOf(p.type)});
			declared.set(p, 0);
		}
		args.push({name: "phase", type: macro :Int});
		args.push({name: "frame", type: macro :hxmc.unsafe.Ptr});
		// (the locals each phase reads or writes: those of two or more kept)
		var uses = [for (ph in cut.phases) locals(ph)];
		var count = new Map<SVar, Int>();
		for (u in uses)
			for (v in u)
				count.set(v, (count.get(v) ?? 0) + 1);
		var offsets = new Map<SVar, Int>(), at = 0;
		for (u in uses)
			for (v in u)
				if (count.get(v) > 1 && !offsets.exists(v)) {
					offsets.set(v, at);
					kept.set(v, true);
					at += soft.spillOf(v.type, !isUniform(v), macro frame, 0, null).bytes;
				}
		soft.frame = at;
		var cases:Array<Case> = [];
		for (i in 0...cut.phases.length) {
			var ph = cut.phases[i], here = [for (v in uses[i]) if (kept.exists(v)) v];
			var body:Array<Expr> = [];
			for (v in here) {
				var u = isUniform(v);
				declared.set(v, 0);
				body.push({expr: EVars([{name: name(v), type: u ? soft.scalarOf(v.type) : soft.lanesOf(v.type), expr: soft.spillOf(v.type, !u, macro frame, offsets.get(v), null).load}]), pos: pos});
			}
			body = body.concat(block(ph.body));
			body.push(macro var next = ${switch ph.next {
				case Next(k): macro $v{k};
				case End: macro -1;
				case Branch(c, a, b): macro ${uni(c) ? sx(c) : macro(${lx(c)} & m).any()} ? $v{a} : $v{b};
			}});
			for (v in here)
				for (x in soft.spillOf(v.type, !isUniform(v), macro frame, offsets.get(v), macro $i{name(v)}).store)
					body.push(x);
			body.push(macro return next);
			cases.push({values: [macro $v{i}], expr: macro $b{body}});
		}
		var sw = {expr: ESwitch(macro phase, cases, null), pos: pos};
		return {
			name: fname,
			access: [APublic, AStatic],
			meta: [{name: ":hxmc.unsafe", params: [macro gc], pos: pos}],
			kind: FFun({args: args, ret: macro :Int, expr: macro {$sw; return -1;}}),
			pos: pos
		};
	}

	// the locals a phase reads or writes (not the function's parameters), in order
	function locals(ph:Phase):Array<SVar> {
		var out:Array<SVar> = [];
		function v(x:SVar)
			if (!out.contains(x) && !f.params.contains(x)) out.push(x);
		function ex(e:SExpr)
			switch e.e {
				case ELocal(x): v(x);
				case EField(x, _) | ESwizzle(x, _) | EColumn(x, _) | EUnop(_, x) | EConvert(x): ex(x);
				case EIndex(x, i):
					ex(x);
					ex(i);
				case EBinop(_, a, b):
					ex(a);
					ex(b);
				case ECond(c, a, b):
					ex(c);
					ex(a);
					ex(b);
				case ENew(args) | EBuiltin(_, args) | ECall(_, args): for (a in args) ex(a);
				case EFloat(_) | EInt(_) | EBool(_):
			}
		function st(ss:Array<SStmt>)
			for (s in ss)
				switch s {
					case SDecl(x, init):
						v(x);
						if (init != null) ex(init);
					case SAssign(x, _, e):
						v(x);
						ex(e);
					case SEval(e): ex(e);
					case SReturn(e): if (e != null) ex(e);
					case SStore(b, i, e):
						ex(b);
						ex(i);
						ex(e);
					case SIf(c, a, b):
						ex(c);
						st(a);
						if (b != null) st(b);
					case SWhile(c, b):
						ex(c);
						st(b);
					case SBreak | SContinue:
				}
		st(ph.body);
		switch ph.next {
			case Branch(c, _, _): ex(c);
			case _:
		}
		return out;
	}

	static function returns(ss:Array<SStmt>):Int {
		var n = 0;
		for (s in ss)
			switch s {
				case SReturn(_): n++;
				case SIf(_, a, b): n += returns(a) + (b == null ? 0 : returns(b));
				case SWhile(_, b): n += returns(b);
				case _:
			}
		return n;
	}

	function block(ss:Array<SStmt>):Array<Expr>
		return [for (s in ss) for (x in stmt(s)) x];

	function stmt(s:SStmt):Array<Expr>
		return switch s {
			case SDecl(v, init):
				declared.set(v, depth);
				var u = isUniform(v);
				var value = init == null ? (u ? soft.scalarZeroOf(v.type) : soft.zeroOf(v.type)) : u ? sx(init) : lx(init);
				kept.exists(v) ? [macro $i{name(v)} = $value] : [{expr: EVars([{name: name(v), type: u ? soft.scalarOf(v.type) : soft.lanesOf(v.type), expr: value}]), pos: pos}];
			case SAssign(v, op, e):
				var whole:SExpr = op == null ? e : {e: EBinop(op, {e: ELocal(v), t: v.type}, e), t: v.type};
				if (isUniform(v)) [macro $i{name(v)} = ${sx(whole)}] else {
					var x = lx(whole);
					var at = declared.exists(v) ? declared.get(v) : 0;
					[macro $i{name(v)} = ${depth > at ? soft.selectOf(v.type, macro m, x, macro $i{name(v)}) : x}];
				}
			case SEval(e):
				switch e.e {
					case EBuiltin("discard", _):
						if (scalar) [macro hxmc.unsafe.Mem.setI32(kill, 0, 1), f.ret == TVoid ? macro return : macro return r] else
							[macro hxmc.unsafe.Mem.setI32(kill, 0, hxmc.unsafe.Mem.getI32(kill, 0) | m.mask()), macro m = helder.gfx.soft.LaneBool.none()];
					case _: [uni(e) ? sx(e) : lx(e)];
				}
			case SReturn(_) if (phasing && depth == 0): [macro return -1];
			case SReturn(e):
				if (scalar || depth == 0) {
					if (e == null) [macro return] else {
						var x = scalar ? sx(e) : lx(e);
						[macro return ${returned ? soft.selectOf(f.ret, macro m, x, macro r) : x}];
					}
				} else {
					returned = true;
					var out = e == null ? [] : [macro r = ${soft.selectOf(f.ret, macro m, lx(e), macro r)}];
					out.concat([macro m = helder.gfx.soft.LaneBool.none()]);
				}
			case SIf(c, a, b):
				if (uni(c)) [{expr: EIf(sx(c), macro $b{block(a)}, b == null ? null : macro $b{block(b)}), pos: pos}] else {
					var k = temp(), m0 = temp(), ma = temp();
					depth++;
					var then = block(a), other = b == null ? null : block(b);
					depth--;
					var out = [
						(macro var $k = ${lx(c)}),
						(macro var $m0 = m),
						macro m = $i{m0} & $i{k},
						macro if (m.any()) $b{then}
					];
					if (other != null) out = out.concat([
						(macro var $ma = m),
						macro m = $i{m0}.andNot($i{k}),
						macro if (m.any()) $b{other},
						macro m = $i{ma} | m
					]) else out.push(macro m = m | $i{m0}.andNot($i{k}));
					[macro $b{out}];
				}
			case SWhile(c, body):
				var lanes = !scalar && (!uni(c) || divergesHere(body, 0));
				if (!lanes) {
					loops.push({exit: "", cont: "", lanes: false});
					var b = block(body);
					loops.pop();
					[macro while (${sx(c)}) $b{b}];
				} else {
					var exit = temp(), cont = temp(), k = temp();
					loops.push({exit: exit, cont: cont, lanes: true});
					depth++;
					var b = block(body);
					depth--;
					loops.pop();
					[
						macro {
							var $exit = helder.gfx.soft.LaneBool.none();
							while (true) {
								var $k = ${lx(c)};
								$i{exit} = $i{exit} | m.andNot($i{k});
								m = m & $i{k};
								if (!m.any()) break;
								var $cont = helder.gfx.soft.LaneBool.none();
								$b{b};
								m = m | $i{cont};
								if (!m.any()) break;
							}
							m = $i{exit};
						}
					];
				}
			case SBreak:
				var l = loops[loops.length - 1];
				l.lanes ? [macro $i{l.exit} = $i{l.exit} | m, macro m = helder.gfx.soft.LaneBool.none()] : [macro break];
			case SContinue:
				var l = loops[loops.length - 1];
				l.lanes ? [macro $i{l.cont} = $i{l.cont} | m, macro m = helder.gfx.soft.LaneBool.none()] : [macro continue];
			case SStore(b, i, v):
				switch b.t {
					case TStorage(t, _) | TWorkgroup(t) if (scalar): [soft.storageWriteAt(t, sx(b), sx(i), sx(v))];
					// (whole rows only where every lane is: outside tests of lanes, before a return under one)
					case TStorage(t, _) if (soft.isRow(i)): [soft.rowsWrite(t, sx(b), lx(i), lane(v), full && depth == 0 && !returned)];
					case TStorage(t, _) | TWorkgroup(t): [soft.writeStorage(t, sx(b), lane(i), lane(v))];
					case _: Context.error("soft: a store into what is not a storage buffer", pos);
				}
		}

	function divergesHere(ss:Array<SStmt>, d:Int):Bool {
		for (s in ss)
			switch s {
				case SBreak | SContinue if (d > 0): return true;
				case SIf(c, a, b):
					var k = uni(c) ? d : d + 1;
					if (divergesHere(a, k) || (b != null && divergesHere(b, k))) return true;
				case _:
			}
		return false;
	}

	// ---- scalar expressions (helder.math's types: the CPU code's)

	function sx(e:SExpr):Expr
		return switch e.e {
			case EFloat(x): macro($v{x} : Float);
			case EInt(i): macro $v{i};
			case EBool(b): macro $v{b};
			case ELocal(v): macro $i{name(v)};
			case EField(x, n) if (soft.blockType(x.t)):
				switch x.t {
					case TStruct(s): soft.blockField(s, sx(x), n);
					case _: throw "soft";
				}
			case EField(x, n): Soft.dot(sx(x), "f_" + n);
			case ESwizzle(x, cs) if (cs.length == 1): Soft.dot(sx(x), cs);
			case ESwizzle(x, cs):
				var t = temp();
				var parts = [for (i in 0...cs.length) Soft.dot(macro $i{t}, cs.charAt(i))];
				macro {
					var $t = ${sx(x)};
					${{expr: haxe.macro.Expr.ExprDef.ENew({pack: ["helder", "math"], name: 'Vec${cs.length}'}, parts), pos: pos}};
				};
			case EColumn(x, i): Soft.dot(sx(x), "c" + i);
			case EIndex(x, i):
				switch x.e {
					case EField(b, n) if (soft.blockType(b.t)):
						switch b.t {
							case TStruct(s): soft.blockArray(s, sx(b), n, sx(i), false);
							case _: throw "soft";
						}
					case _ if (x.t.match(TStorage(_, _) | TWorkgroup(_))):
						switch x.t {
							case TStorage(t, _) | TWorkgroup(t): soft.readStorage(t, sx(x), sx(i), false);
							case _: throw "soft";
						}
					case _: Context.error("soft: an index into what is not a uniform block's array", pos);
				}
			case EUnop(Neg, x): macro - ${sx(x)};
			case EUnop(Not, x): macro !${sx(x)};
			case EUnop(BitNot, x): macro ~${sx(x)};
			case EBinop(op, a, b): sbin(op, a, b, e.t);
			case ECond(c, a, b): macro ${sx(c)} ? ${sx(a)} : ${sx(b)};
			case ENew(args): construct(e.t, args, true);
			case EBuiltin(name, args): sbuiltin(name, args, e.t);
			case ECall(g, args):
				var xs = [for (a in args) sx(a)];
				if (soft.discardsIn(g)) xs.push(macro kill);
				macro $i{soft.useFunc(g, fragment, true)}($a{xs});
			case EConvert(x): e.t == TInt ? macro Std.int(${sx(x)}) : macro(${sx(x)} : Float);
		}

	function sbin(op:SBinop, a:SExpr, b:SExpr, t:SType):Expr {
		var x = sx(a), y = sx(b);
		return switch op {
			case Add: macro $x + $y;
			case Sub: macro $x - $y;
			case Mul: macro $x * $y;
			case Div if (a.t == TInt && b.t == TInt): macro Std.int($x / $y);
			case Div: macro $x / $y;
			case Mod: macro $x % $y;
			case Eq: macro $x == $y;
			case Ne: macro $x != $y;
			case Lt: macro $x < $y;
			case Le: macro $x <= $y;
			case Gt: macro $x > $y;
			case Ge: macro $x >= $y;
			case And: macro $x && $y;
			case Or: macro $x || $y;
			case BitAnd: macro $x & $y;
			case BitOr: macro $x | $y;
			case BitXor: macro $x ^ $y;
			case Shl: macro $x << $y;
			case Shr: macro $x >> $y;
		}
	}

	// a vector's or matrix's constructor of GLSL's form (components or
	// vectors in order, or one scalar for all), a struct's fields
	function construct(t:SType, args:Array<SExpr>, scalarForm:Bool):Expr {
		var conv = (a:SExpr) -> scalarForm ? sx(a) : lane(a);
		return switch t {
			case TVec(n):
				var pre:Array<Expr> = [], comps:Array<Expr> = [];
				for (a in args)
					switch a.t {
						case TFloat: comps.push(conv(a));
						case TInt: comps.push(scalarForm ? macro(${sx(a)} : Float) : macro helder.gfx.soft.Lane.ofInt(${lane(a)}));
						case TVec(k):
							var v = temp();
							pre.push(macro var $v = ${conv(a)});
							for (i in 0...k)
								comps.push(Soft.dot(macro $i{v}, "xyzw".charAt(i)));
						case t: Context.error('soft: a ${Names.typeName(t)} in a vector', pos);
					}
				if (comps.length == 1) {
					var s = temp();
					pre.push(macro var $s = ${comps[0]});
					comps = [for (_ in 0...n) macro $i{s}];
				}
				var made = {expr: haxe.macro.Expr.ExprDef.ENew({pack: scalarForm ? ["helder", "math"] : ["helder", "gfx", "soft"], name: scalarForm ? 'Vec$n' : 'Lane$n'}, comps), pos: pos};
				pre.length == 0 ? made : macro $b{pre.concat([made])};
			case TMat4:
				var cols = [for (a in args) conv(a)];
				scalarForm ? macro new helder.math.Mat4($a{cols}) : macro new helder.gfx.soft.LaneMat($a{cols});
			case TStruct(s):
				var xs = [for (a in args) conv(a)];
				scalarForm ? {expr: haxe.macro.Expr.ExprDef.ENew(soft.scalarStructPath(s), xs), pos: pos} : soft.laneMakeOf(s, xs);
			case t: Context.error('soft: a constructor of ${Names.typeName(t)}', pos);
		}
	}

	function sbuiltin(name:String, args:Array<SExpr>, t:SType):Expr {
		var xs = [for (a in args) sx(a)];
		return switch name {
			case "sample" | "sampleLevel": sampler(name, args, xs, true);
			case "discard": Context.error("soft: discard in an expression", pos);
			case "atomicAdd" | "atomicMin" | "atomicMax" | "textureStore": Context.error("soft: a compute builtin in a render stage", pos);
			case _: macro $p{["helder", "gfx", "shader", "ShaderMath", name]}($a{xs});
		}
	}

	// sample(t, uv), sampleLevel(t, uv, level) and their cube's and array's forms
	function sampler(name:String, args:Array<SExpr>, xs:Array<Expr>, scalarForm:Bool):Expr {
		var dim = Textures.dimension(args[0].t);
		var kind = dim == 1 ? "cube" : dim == 2 ? "array" : "flat";
		var level = name == "sampleLevel";
		// (the fragment stage: the quad's footprint; the vertex stage, and a value every lane shares: the first level)
		if (scalarForm) {
			var lv = level ? xs[xs.length - 1] : macro 0.0;
			return switch kind {
				case "cube": macro helder.gfx.soft.Sample.cubeAt(${xs[0]}, ${xs[1]}, $lv);
				case "array": macro helder.gfx.soft.Sample.arrayAt(${xs[0]}, ${xs[1]}, ${xs[2]}, $lv);
				case _: macro helder.gfx.soft.Sample.flatAt(${xs[0]}, ${xs[1]}, $lv);
			}
		}
		var lv = level ? xs[xs.length - 1] : null;
		var quad = !level && fragment;
		// (level 0 named, or the vertex stage's: the first level read directly)
		var first = (!level && !fragment) || (level && args[args.length - 1].e.match(EFloat(0) | EInt(0)));
		if (first && kind == "flat") return macro helder.gfx.soft.Sample.flatFirst(${xs[0]}, ${xs[1]});
		return switch kind {
			case "cube": lv != null ? macro helder.gfx.soft.Sample.cubeLevel(${xs[0]}, ${xs[1]}, $lv) : quad ? macro helder.gfx.soft.Sample.cube(${xs[0]}, ${xs[1]}) : macro helder.gfx.soft.Sample.cubeLevel(${xs[0]},
					${xs[1]}, helder.gfx.soft.Lane.zero());
			case "array": lv != null ? macro helder.gfx.soft.Sample.arrayLevel(${xs[0]}, ${xs[1]}, ${xs[2]}, $lv) : quad ? macro helder.gfx.soft.Sample.array(${xs[0]}, ${xs[1]},
					${xs[2]}) : macro helder.gfx.soft.Sample.arrayLevel(${xs[0]}, ${xs[1]}, ${xs[2]}, helder.gfx.soft.Lane.zero());
			case _: lv != null ? macro helder.gfx.soft.Sample.flatLevel(${xs[0]}, ${xs[1]}, $lv) : quad ? macro helder.gfx.soft.Sample.flat(${xs[0]}, ${xs[1]}) : macro helder.gfx.soft.Sample.flatLevel(${xs[0]},
					${xs[1]}, helder.gfx.soft.Lane.zero());
		}
	}

	// ---- lane expressions

	// e's lanes: its own, or its scalar splatted
	function lane(e:SExpr):Expr
		return uni(e) ? splat(e) : lx(e);

	function splat(e:SExpr):Expr {
		if (scalar) return soft.splatOf(e.t, sx(e));
		var k = soft.constantOf(e);
		if (k == null)
			k = switch e.e {
				case EField(x, n) if (soft.blockType(x.t)): blockLane(x, n, null);
				case ESwizzle({e: EField(x, n)}, cs) if (soft.blockType(x.t)): blockLane(x, n, cs);
				case _: null;
			}
		return k != null ? k : soft.splatOf(e.t, sx(e));
	}

	function blockLane(x:SExpr, n:String, cs:Null<String>):Null<Expr>
		return switch x.t {
			case TStruct(s): soft.blockLanesOf(s, sx(x), n, cs);
			case _: null;
		}

	function lx(e:SExpr):Expr {
		if (uni(e)) return splat(e);
		return switch e.e {
			case ELocal(v): macro $i{name(v)};
			case EField(x, n): Soft.dot(lx(x), "f_" + n);
			case ESwizzle(x, cs) if (cs.length == 1): Soft.dot(lx(x), cs);
			case ESwizzle(x, cs):
				var t = temp();
				var parts = [for (i in 0...cs.length) Soft.dot(macro $i{t}, cs.charAt(i))];
				macro {
					var $t = ${lx(x)};
					${{expr: haxe.macro.Expr.ExprDef.ENew({pack: ["helder", "gfx", "soft"], name: 'Lane${cs.length}'}, parts), pos: pos}};
				};
			case EColumn(x, i): Soft.dot(lx(x), "c" + i);
			case EIndex(x, i):
				switch x.e {
					case EField(b, n) if (soft.blockType(b.t)):
						switch b.t {
							case TStruct(s): soft.blockArray(s, sx(b), n, lane(i), true);
							case _: throw "soft";
						}
					case _ if (x.t.match(TStorage(_, _) | TWorkgroup(_))):
						switch x.t {
							case TStorage(t, _) if (soft.isRow(i)): soft.rowsRead(t, sx(x), lx(i));
							case TStorage(t, _) | TWorkgroup(t): soft.readStorage(t, sx(x), lane(i), true);
							case _: throw "soft";
						}
					case _: Context.error("soft: an index into what is not a uniform block's array", pos);
				}
			case EUnop(Neg, x): macro - ${lane(x)};
			case EUnop(Not, x): macro !${lane(x)};
			case EUnop(BitNot, x): macro ~${lane(x)};
			case EBinop(op, a, b): lbin(op, a, b, e.t);
			case ECond(c, a, b):
				uni(c) ? macro ${sx(c)} ? ${lane(a)} : ${lane(b)} : soft.selectOf(e.t, lane(c), lane(a), lane(b));
			case ENew(args): construct(e.t, args, false);
			case EBuiltin(name, args): lbuiltin(name, args, e.t);
			case ECall(g, args):
				var xs = [macro m].concat([for (i in 0...args.length) soft.ptrType(args[i].t) ? sx(args[i]) : lane(args[i])]);
				if (soft.discardsIn(g)) xs.push(macro kill);
				macro $i{soft.useFunc(g, fragment, false)}($a{xs});
			case EConvert(x): e.t == TInt ? macro ${lane(x)}.toInt() : macro helder.gfx.soft.Lane.ofInt(${lane(x)});
			case EFloat(_) | EInt(_) | EBool(_): throw "soft: uniform";
		}
	}

	// a vector's operand: a scalar's lanes in every component
	function widen(x:Expr, from:SType, to:SType):Expr
		return switch [from, to] {
			case [TFloat, TVec(n)]: macro $p{["helder", "gfx", "soft", 'Lane$n', "fill"]}($x);
			case _: x;
		}

	function lbin(op:SBinop, a:SExpr, b:SExpr, t:SType):Expr {
		var x = lane(a), y = lane(b);
		switch op {
			case Mul if (a.t == TMat4 && b.t.match(TVec(4))):
				return macro helder.gfx.soft.Lanes.mulVec($x, $y);
			case Mul if (a.t == TMat4 && b.t == TMat4):
				return macro helder.gfx.soft.Lanes.mulMat($x, $y);
			case Add | Sub | Mul | Div if (!Names.same(a.t, b.t)):
				x = widen(x, a.t, b.t);
				y = widen(y, b.t, a.t);
			case _:
		}
		var ints = a.t == TInt;
		return switch op {
			case Add: macro $x + $y;
			case Sub: macro $x - $y;
			case Mul: macro $x * $y;
			case Div if (ints): macro $x.div($y);
			case Div: macro $x / $y;
			case Mod: macro $x.mod($y);
			case Eq: macro $x.eq($y);
			case Ne: macro $x.ne($y);
			case Lt: macro $x.lt($y);
			case Le: macro $x.le($y);
			case Gt: macro $x.gt($y);
			case Ge: macro $x.ge($y);
			case And | BitAnd: macro $x & $y;
			case Or | BitOr: macro $x | $y;
			case BitXor: macro $x ^ $y;
			case Shl: macro $x.shl($y);
			case Shr: macro $x.shr($y);
		}
	}

	function lbuiltin(name:String, args:Array<SExpr>, t:SType):Expr
		return switch name {
			case "sample" | "sampleLevel":
				var xs = [for (i in 0...args.length) i == 0 ? sx(args[i]) : lane(args[i])];
				sampler(name, args, xs, false);
			case "discard": Context.error("soft: discard in an expression", pos);
			// (the compute stage's: lane by lane, where m's lanes are)
			case "atomicAdd" | "atomicMin" | "atomicMax":
				var op = name == "atomicAdd" ? 0 : name == "atomicMin" ? 1 : 2;
				macro helder.gfx.soft.Buffers.atomic(${sx(args[0])}, ${lane(args[1])}, ${lane(args[2])}, m, $v{op});
			case "textureStore": macro helder.gfx.soft.Buffers.store(${sx(args[0])}, ${lane(args[1])}, ${lane(args[2])}, ${lane(args[3])}, m);
			case name if (Subgroups.isOp(name)): subgroup(name, args);
			case _: macro $p{["helder", "gfx", "soft", "Lanes", name]}($a{[for (a in args) lane(a)]});
		}

	// a subgroup operation over the call's lanes (Subgroup), a vector's componentwise
	function subgroup(name:String, args:Array<SExpr>):Expr {
		var op = name.substr(8).toLowerCase();
		if (op == "all" || op == "any") return macro $p{["helder", "gfx", "soft", "Subgroup", op]}(m, ${lane(args[0])});
		var x = temp(), k = temp();
		var pre = [macro var $x = ${lane(args[0])}];
		if (op == "shuffle") pre.push(macro var $k = ${lane(args[1])});
		function one(v:Expr, t:SType):Expr {
			var f = ["helder", "gfx", "soft", "Subgroup", op + (t == TInt ? "Int" : "Float")];
			return switch op {
				case "broadcast": macro $p{f}($v, $v{switch args[1].e {
						case EInt(i): i;
						case _: Context.error("soft: subgroupBroadcast's lane is a constant", pos);
					}});
				case "shuffle": macro $p{f}($v, $i{k});
				case _: macro $p{f}(m, $v);
			}
		}
		var r = switch args[0].t {
			case TVec(n): {expr: haxe.macro.Expr.ExprDef.ENew({pack: ["helder", "gfx", "soft"], name: 'Lane$n'}, [for (c in 0...n) one(Soft.dot(macro $i{x}, "xyzw".charAt(c)), TFloat)]), pos: pos};
			case t: one(macro $i{x}, t);
		}
		return macro $b{pre.concat([r])};
	}
}
#end
