package helder.ui.draw.soft;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

// QuadRecord's fields as properties over its memory: the ints and
// addresses first, then Quads' Floats (8 bytes each, Haxe's doubles: the
// same math as on the heap), then a band's own state, which only its
// copy has (RECORD bytes recorded, SIZE with the state)
class QuadBuild {
	// Quads' fields into its record r (after its draw found its pixels)
	public static macro function store():haxe.macro.Expr
		return macro $b{[for (n in FLOATS) n == "isFlat" ? macro r.isFlat = flat ? 1 : 0 : macro r.$n = $i{n}]};

	#if macro
	public static final INTS = ["kind", "px0", "py0", "px1", "py1", "tw", "th", "ox", "oy", "texW", "texH", "word"];
	public static final PTRS = ["target", "tex"];
	public static final FLOATS = [
		"mode", "isFlat", "cx", "cy", "fx", "fy", "ax", "ay", "bx", "by", "lx", "ly", "x0", "y0", "x1", "y1", "hx", "hy", "ex", "ey", "u0", "v0", "u1", "v1", "fr",
		"fg", "fb", "fa", "br", "bg", "bb", "ba", "r0", "r1", "r2", "r3", "w0", "w1", "w2", "w3", "blur", "style", "contrast", "g0", "g1", "g2", "g3", "cx0", "cy0",
		"cx1", "cy1", "cr0", "cr1", "cr2", "cr3"
	];
	public static final STATE = ["sr", "sg", "sb", "sa", "blurY", "blurHx", "blurHy"];
	// (the blur's rows: 8 weights, 8 widths, 2 sides straight)
	public static inline var ROWS = 18;

	public static function build():Array<Field> {
		var fields = Context.getBuildFields(), pos = Context.currentPos();
		function prop(name:String, t:ComplexType, get:Expr, set:Expr) {
			fields.push({name: name, access: [APublic], kind: FProp("get", "set", t), pos: pos});
			fields.push({
				name: "get_" + name,
				access: [AInline],
				meta: [{name: ":hxmc.unsafe", params: [macro gc], pos: pos}],
				kind: FFun({args: [], ret: t, expr: macro return $get}),
				pos: pos
			});
			fields.push({
				name: "set_" + name,
				access: [AInline],
				meta: [{name: ":hxmc.unsafe", params: [macro gc], pos: pos}],
				kind: FFun({args: [{name: "v", type: t}], ret: t, expr: macro {$set; return v;}}),
				pos: pos
			});
		}
		var at = 0;
		for (n in INTS) {
			var o = at;
			prop(n, macro :Int, macro hxmc.unsafe.Mem.getI32(this, $v{o}), macro hxmc.unsafe.Mem.setI32(this, $v{o}, v));
			at += 4;
		}
		at = (at + 7) & ~7;
		for (n in PTRS) {
			var o = at;
			prop(n, macro :hxmc.unsafe.Ptr, macro hxmc.unsafe.Mem.getPtr(this, $v{o}), macro hxmc.unsafe.Mem.setPtr(this, $v{o}, v));
			at += 8;
		}
		for (n in FLOATS.concat(STATE)) {
			var o = at;
			prop(n, macro :Float, macro hxmc.unsafe.Mem.getF64(this, $v{o}), macro hxmc.unsafe.Mem.setF64(this, $v{o}, v));
			at += 8;
			if (n == FLOATS[FLOATS.length - 1]) fields.push({name: "RECORD", access: [APublic, AStatic, AInline], kind: FVar(macro :Int, macro $v{at}), pos: pos});
		}
		fields.push({name: "ROWS_AT", access: [AStatic, AInline], kind: FVar(macro :Int, macro $v{at}), pos: pos});
		fields.push({name: "SIZE", access: [APublic, AStatic, AInline], kind: FVar(macro :Int, macro $v{at + 8 * ROWS}), pos: pos});
		return fields;
	}
	#end
}
