package helder.gfx.shader;

import helder.gfx.shader.Ir;

// What the four emitters share: a stage's source is its header, its
// structs, its functions (callees first) and the entry point, which reads
// the stage's inputs into the input struct, calls the stage's function and
// writes its result out. Statements and expressions print alike in all
// four (C's syntax; WGSL's differs in declarations, which Wgsl overrides);
// nested operations are parenthesized. The entry points' names (main,
// main0, StageIn, StageOut, in_*, v_*, out_*, u_*, make_*, tex_*, smp_*) are
// kept from the program's own names by Lower. A texture parameter is two
// where the language separates the sampler (<name>_smp, which Lower keeps
// free); sample reads the mip level the fragment's footprint needs (its
// derivatives) in the fragment stage and the first in the vertex stage,
// sampleLevel the level given.
//
// A compute stage (compute) is its header, its structs, its resources
// (storage buffers and textures: globals but in MSL, named sb_<slot> and
// img_<slot>, which its parameters are renamed to), its functions and the
// entry point, which builds the ComputeInput from the language's ids and
// calls the stage's function with its uniform blocks and textures. Storage
// is read and written in the stage's function only (Lower): an element read
// is load(b, i), written store(b, i, v), each language's own.
class Emit {
	var buf:StringBuf;
	var indent = "";
	// the stage being emitted is the fragment stage (sample's derivatives)
	var fragment = false;

	public function new() {}

	public function stage(p:SProgram, e:SEntry):String {
		buf = new StringBuf();
		fragment = e.stage == Fragment;
		header(e);
		for (s in e.structs)
			struct(s);
		for (f in e.functions)
			func(f);
		entry(p, e);
		return buf.toString();
	}

	// the compute stage's source
	public function compute(c:SCompute):String {
		buf = new StringBuf();
		fragment = false;
		var e = c.entry;
		// (its storage parameters: the globals' names)
		for (i in 0...e.resources.length)
			switch e.resources[i] {
				case RStorage(s): e.fn.params[i + 1].name = "sb_" + s.slot;
				case RImage(m): e.fn.params[i + 1].name = "img_" + m.slot;
				case _:
			}
		computeHeader(c);
		for (s in e.structs)
			struct(s);
		storage(c);
		for (f in e.functions)
			func(f);
		computeEntry(c);
		return buf.toString();
	}

	function header(e:SEntry) {}

	function entry(p:SProgram, e:SEntry) {}

	function computeHeader(c:SCompute) {}

	// the storage buffers' and textures' declarations (and their helpers)
	function storage(c:SCompute) {}

	function computeEntry(c:SCompute) {}

	// a storage parameter is a global (GLSL, WGSL, HLSL), not a parameter
	function global(t:SType):Bool
		return t.match(TStorage(_, _) | TImage(_));

	// b[i] of a storage buffer, and b[i] = v
	function load(b:SExpr, i:SExpr):String
		return operand(b) + "[" + expr(i) + "]";

	function store(b:SExpr, i:SExpr, v:SExpr):String
		return operand(b) + "[" + expr(i) + "] = " + expr(v) + ";";

	// the uniform blocks and textures a compute stage's function takes, by their globals' names
	static function computeArgs(e:SEntry, uniform:SUniform->String, texture:STexture->String, storageArg:SStorage->Null<String>, image:SImage->Null<String>):Array<String> {
		var out = [];
		for (r in e.resources) {
			var a = switch r {
				case RUniform(u): uniform(u);
				case RTexture(t): texture(t);
				case RStorage(s): storageArg(s);
				case RImage(m): image(m);
			}
			if (a != null) out.push(a);
		}
		return out;
	}

	function type(t:SType):String
		return "";

	function struct(s:SStruct) {
		line('struct ${s.name} {');
		for (f in s.fields)
			line('\t${decl(f.type, f.name)};');
		line("};");
	}

	// a name of a type declared (HLSL: an array's length after the name)
	function decl(t:SType, name:String):String
		return type(t) + " " + name;

	function func(f:SFunction) {
		line(type(f.ret) + " " + f.name + "(" + [for (p in f.params) if (!global(p.type)) param(p)].join(", ") + ") {");
		body(f.body);
		line("}");
	}

	// a parameter (a texture: with its sampler, where the language has one)
	function param(v:SVar):String
		return type(v.type) + " " + v.name;

	// an argument (a texture: with its sampler)
	function arg(e:SExpr):String
		return expr(e);

	function declare(v:SVar, init:Null<SExpr>):String
		return type(v.type) + " " + v.name + (init == null ? "" : " = " + expr(init)) + ";";

	function body(ss:Array<SStmt>) {
		var saved = indent;
		indent += "\t";
		for (s in ss)
			stmt(s);
		indent = saved;
	}

	function stmt(s:SStmt)
		switch s {
			case SDecl(v, init): line(declare(v, init));
			case SAssign(v, op, e): line(v.name + " " + (op == null ? "" : binop(op)) + "= " + expr(e) + ";");
			case SEval(e): line(expr(e) + ";");
			case SIf(c, a, b):
				line("if (" + expr(c) + ") {");
				var b = b;
				body(a);
				// (else if)
				while (b != null && b.length == 1 && b[0].match(SIf(_, _, _)))
					switch b[0] {
						case SIf(c2, a2, b2):
							line("} else if (" + expr(c2) + ") {");
							body(a2);
							b = b2;
						case _:
					}
				if (b != null && b.length > 0) {
					line("} else {");
					body(b);
				}
				line("}");
			case SWhile(c, ss):
				line("while (" + expr(c) + ") {");
				body(ss);
				line("}");
			case SBreak: line("break;");
			case SContinue: line("continue;");
			case SReturn(null): line("return;");
			case SReturn(e): line("return " + expr(e) + ";");
			case SStore(b, i, v): line(store(b, i, v));
		}

	function expr(e:SExpr):String
		return switch e.e {
			case EFloat(f): float(f);
			case EInt(i): Std.string(i);
			case EBool(b): b ? "true" : "false";
			case ELocal(v): v.name;
			case EField(x, n): operand(x) + "." + n;
			case ESwizzle(x, c): operand(x) + "." + c;
			case EColumn(x, i): operand(x) + "[" + i + "]";
			case EIndex(x, i) if (x.t.match(TStorage(_, _))): load(x, i);
			case EIndex(x, i): operand(x) + "[" + expr(i) + "]";
			case EUnop(op, x): (op == Neg ? "-" : op == Not ? "!" : "~") + operand(x);
			case EBinop(op, a, b): binary(op, a, b);
			case ECond(c, a, b): cond(c, a, b);
			case ENew(args): construct(e.t, args);
			case EBuiltin(name, args): builtin(name, args, e.t);
			case ECall(f, args): f.name + "(" + [for (a in args) arg(a)].join(", ") + ")";
			case EConvert(x): type(e.t) + "(" + expr(x) + ")";
		}

	// an operand: parenthesized unless atomic
	function operand(e:SExpr):String {
		var s = expr(e);
		return switch e.e {
			case EBinop(_, _, _) | ECond(_, _, _) | EUnop(_, _): "(" + s + ")";
			case EFloat(f) if (f < 0 || 1 / f < 0): "(" + s + ")";
			case EInt(i) if (i < 0): "(" + s + ")";
			case _: s;
		}
	}

	function binary(op:SBinop, a:SExpr, b:SExpr):String
		return operand(a) + " " + binop(op) + " " + operand(b);

	function cond(c:SExpr, a:SExpr, b:SExpr):String
		return operand(c) + " ? " + operand(a) + " : " + operand(b);

	function construct(t:SType, args:Array<SExpr>):String
		return type(t) + "(" + [for (a in args) expr(a)].join(", ") + ")";

	function builtin(name:String, args:Array<SExpr>, t:SType):String
		return name == "discard" ? "discard" : name + "(" + [for (a in args) expr(a)].join(", ") + ")";

	static function binop(op:SBinop):String
		return switch op {
			case Add: "+";
			case Sub: "-";
			case Mul: "*";
			case Div: "/";
			case Mod: "%";
			case Eq: "==";
			case Ne: "!=";
			case Lt: "<";
			case Le: "<=";
			case Gt: ">";
			case Ge: ">=";
			case And: "&&";
			case Or: "||";
			case BitAnd: "&";
			case BitOr: "|";
			case BitXor: "^";
			case Shl: "<<";
			case Shr: ">>";
		}

	// a float literal: always with a point or an exponent
	static function float(f:Float):String {
		var s = Std.string(f);
		return s.indexOf(".") < 0 && s.indexOf("e") < 0 ? s + ".0" : s;
	}

	function line(s:String) {
		buf.add(indent);
		buf.add(s);
		buf.add("\n");
	}

	// the varyings but the position, in order: locations 0, 1, ...
	// a texture parameter's type (its dimension's)
	public static function textureType(t:STexture):SType
		return t.dimension == 1 ? TTextureCube : t.dimension == 2 ? TTextureArray : TTexture;

	static function varyings(p:SProgram):Array<SField>
		return [for (f in p.varyings.fields) if (!f.position) f];

	static function position(p:SProgram):SField
		return Lambda.find(p.varyings.fields, f -> f.position);
}
