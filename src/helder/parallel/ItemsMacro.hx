package helder.parallel;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import helder.gfx.shader.Ir;
import helder.gfx.shader.ShaderDefinition;

using haxe.macro.Tools;

// Items<T> (genericBuild): an abstract over ItemsData of its own for each
// element type, helder.parallel.gen.Items_<T>, marked @:parallel.items
// (what a body's lowering takes for a storage buffer of T: its get's
// result), its elements loaded and stored at their std430 offsets (the
// shader compiler's layout: what the GPU's buffer will hold).
@:access(helder.gfx.shader.Lower)
class ItemsMacro {
	public static function build():ComplexType {
		var pos = Context.currentPos();
		var t = switch Context.getLocalType() {
			case TInst(_, [t]): t;
			// (Items.of(values): ItemsOf's, of the values' type)
			case TInst(_, []): return macro :helder.parallel.ItemsOf;
			case _: Context.error("Items<T>: its element type T (Items<Float>, Items<Particle>)", pos);
		}
		switch Context.follow(t) {
			case TMono(_): Context.error("Items<T>: T is not known here (new Items<Float>(n))", pos);
			case TInst(_.get() => {kind: KTypeParameter(_)}, _): Context.error('Items<${t.toString()}>: a type parameter is not an element type (its layout is not known)', pos);
			case TInst(_.get() => c, _) if (c.isPrivate): Context.error('Items<${c.name}>: ${c.name} is private (an element type is public: its Items is a type of its own)', pos);
			case _:
		}
		var lower = new ParallelLower("Items");
		var st = lower.typeOf(t, pos);
		switch st {
			case TVec(3): Context.error("Items<Vec3>: a Vec3 has no storage layout (16 bytes in std430 and WGSL, 12 in HLSL): pack it in a Vec4", pos);
			case TBool: Context.error("Items<Bool>: a Bool has no storage layout: an Int (0, 1)", pos);
			case _:
		}
		var layout = ShaderDefinition.std430(lower, st, "Items", pos);
		var text = t.toString();
		var short = helder.gfx.shader.Names.sanitize(text.split("<")[0].split(".").pop());
		var name = "Items_" + short + (short == "Float" || short == "Int" ? "" : "_" + haxe.crypto.Md5.encode(text).substr(0, 6));
		var pack = ["helder", "parallel", "gen"];
		var path:TypePath = {pack: pack, name: name};
		var exists = try Context.getType(pack.concat([name]).join(".")) != null catch (_:Dynamic) false;
		if (exists) return TPath(path);
		var ct = t.toComplexType(), self = TPath(path);
		var stride = layout.stride;
		var cls = macro class $name {
			// zeros, length of them
			public inline function new(length:Int)
				this = new helder.parallel.ItemsData(length, $v{stride});

			public var length(get, never):Int;

			inline function get_length():Int
				return this.length;

			// whether dispose() freed it
			public var disposed(get, never):Bool;

			inline function get_disposed():Bool
				return this.disposed;

			// item i (0 <= i < length)
			@:arrayAccess public function get(i:Int):$ct {
				var o = this.at(i);
				return ${load(t, st, layout, 0)};
			}

			@:arrayAccess public function set(i:Int, v:$ct):$ct {
				var o = this.atWrite(i);
				$b{store(t, st, layout, 0, macro v)};
				return v;
			}

			// the memory freed now (an Items never disposed is freed once collected)
			public inline function dispose()
				this.dispose();

			// the items of values, in order
			public static function of(values:Array<$ct>):$self {
				var x = new $path(values.length);
				for (i in 0...values.length)
					x.set(i, values[i]);
				return x;
			}

			// values[0...length] set to the items
			public function copyTo(values:Array<$ct>):Void
				for (i in 0...this.length)
					values[i] = get(i);

			@:noCompletion public inline function data():helder.parallel.ItemsData
				return this;

			// its GPU buffer on device (a storage buffer, a vertex and
			// instance buffer too: drawn from without a copy where a dispatch
			// wrote it), its values uploaded where the CPU's are newer; a
			// body that writes it then runs on the GPU under Auto
			public function buffer(device:helder.gfx.Device):helder.gfx.Buffer
				return helder.parallel.GpuRunner.drawn(this, device);
		};
		// (a struct class's item set from an object literal of its fields: items[i] = {pos: p, vel: v})
		switch Context.follow(t) {
			case TInst(c, _) if (c.get().meta.has(":structInit")):
				var at:ComplexType = TAnonymous([
					for (f in c.get().fields.get())
						if (f.kind.match(FVar(_, _))) {name: f.name, kind: FVar(f.type.toComplexType()), pos: pos}
				]);
				cls.fields = cls.fields.concat((macro class {
					@:arrayAccess @:noCompletion public function setFields(i:Int, v:$at):$at {
						var o = this.atWrite(i);
						$b{store(t, st, layout, 0, macro v)};
						return v;
					}
				}).fields);
			case _:
		}
		var td:TypeDefinition = {
			pack: pack,
			name: name,
			pos: pos,
			meta: [{name: ":parallel.items", pos: pos}],
			kind: TDAbstract(macro :helder.parallel.ItemsData, [], [], []),
			fields: cls.fields
		};
		Context.defineType(td);
		return TPath(path);
	}

	// Items.of(values): the Items of values' element type
	public static function of(values:Expr):Expr {
		var t = switch Context.follow(Context.typeof(values)) {
			case TInst(_.get() => {name: "Array", pack: []}, [t]): t;
			case t: Context.error('Items.of takes an Array, not ${t.toString()}', values.pos);
		}
		var ct = t.toComplexType();
		var items = Context.resolveType(macro :helder.parallel.Items<$ct>, values.pos);
		var path = switch items {
			case TAbstract(a, _): a.get().pack.concat([a.get().name]);
			case _: throw "Items";
		}
		return macro @:pos(values.pos) $p{path}.of($values);
	}

	// (a struct's field types, by name: a class's, an anonymous structure's)
	static function fieldType(t:Type, name:String):Type {
		switch Context.follow(t) {
			case TInst(c, _):
				for (f in c.get().fields.get())
					if (f.name == name) return f.type;
			case TAnonymous(a):
				for (f in a.get().fields)
					if (f.name == name) return f.type;
			case _:
		}
		return Context.error('Items: no field $name', Context.currentPos());
	}

	static function load(t:Type, st:SType, layout:{offsets:Array<Int>, stride:Int}, off:Int):Expr {
		function f(o:Int):Expr
			return macro this.f32(o + $v{o});
		return switch st {
			case TFloat: f(off);
			case TInt: macro this.i32(o + $v{off});
			case TVec(n):
				{expr: haxe.macro.Expr.ExprDef.ENew(vecPath(t, n), [for (k in 0...n) f(off + 4 * k)]), pos: Context.currentPos()};
			case TMat4:
				var cols = [for (c in 0...4) {expr: haxe.macro.Expr.ExprDef.ENew({pack: ["helder", "math"], name: "Vec4"}, [for (k in 0...4) f(off + 16 * c + 4 * k)]), pos: Context.currentPos()}];
				{expr: haxe.macro.Expr.ExprDef.ENew(matPath(t), cols), pos: Context.currentPos()};
			case TStruct(s):
				var fields:Array<ObjectField> = [];
				for (k in 0...s.fields.length) {
					var sf = s.fields[k];
					fields.push({field: sf.field, expr: load(fieldType(t, sf.field), sf.type, layout, layout.offsets[k])});
				}
				var ct = t.toComplexType();
				macro(${{expr: EObjectDecl(fields), pos: Context.currentPos()}} : $ct);
			case _: throw "Items";
		}
	}

	static function store(t:Type, st:SType, layout:{offsets:Array<Int>, stride:Int}, off:Int, v:Expr):Array<Expr> {
		return switch st {
			case TFloat: [macro this.setF32(o + $v{off}, $v)];
			case TInt: [macro this.setI32(o + $v{off}, $v)];
			case TVec(n): [for (k in 0...n) {var c = "xyzw".charAt(k); macro this.setF32(o + $v{off + 4 * k}, $v.$c);}];
			case TMat4: [for (c in 0...4) for (k in 0...4) {var col = "c" + c, x = "xyzw".charAt(k); macro this.setF32(o + $v{off + 16 * c + 4 * k}, $v.$col.$x);}];
			case TStruct(s):
				var out = [];
				for (k in 0...s.fields.length) {
					var sf = s.fields[k], n = sf.field;
					out = out.concat(store(fieldType(t, n), sf.type, layout, layout.offsets[k], macro $v.$n));
				}
				out;
			case _: throw "Items";
		}
	}

	// (a vector's or matrix's type as written: its path, followed through typedefs)
	static function vecPath(t:Type, n:Int):TypePath
		return switch t.toComplexType() {
			case TPath(p) if (p.params == null || p.params.length == 0): p;
			case _: {pack: ["helder", "math"], name: 'Vec$n'};
		}

	static function matPath(t:Type):TypePath
		return switch t.toComplexType() {
			case TPath(p) if (p.params == null || p.params.length == 0): p;
			case _: {pack: ["helder", "math"], name: "Mat4"};
		}
}
#end
