package helder.scenario;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.TypeTools;

// helder.scenario.Monkey's macros: an atom's generator and printer derived
// from its type, a scenario's path in code
class MonkeyMacro {
	public static function atom(signal:Expr, ?gen:Expr):Expr {
		var typed = Context.typeExpr(signal);
		var t = switch TypeTools.follow(typed.t) {
			case TAbstract(_.get() => {pack: ["helder", "view", "graph"], name: "Signal"}, [t]): t;
			case _: Context.error('Monkey.atom: ${TypeTools.toString(typed.t)} is not a signal (Graph.signal\'s)', signal.pos);
		}
		var ct = TypeTools.toComplexType(t);
		var g = switch gen {
			case null | {expr: EConst(CIdent("null"))}: derive(t, signal.pos, 0).gen;
			case e: e;
		}
		var show = derive(t, signal.pos, 0).show;
		var name = path(typed) ?? Context.error("Monkey.atom: a signal at a module's or a class's top level (its path names it in the scenario file)", signal.pos);
		return macro helder.scenario.Monkey.MonkeyAtom.make($v{name}, ($g : helder.test.Gen<$ct>), (v:$ct) -> $show, (v:$ct) -> $signal(v));
	}

	public static function from(rest:Array<Expr>):Expr {
		var out = [];
		for (e in rest)
			switch e.expr {
				case EConst(CString(module)):
					for (t in Context.getModule(module))
						switch t {
							case TInst(_.get() => c, _) if (c.kind.match(KModuleFields(_))):
								var fields = c.statics.get().filter(f -> switch TypeTools.followWithAbstracts(f.type) {
									case TInst(_.get() => {pack: ["helder", "scenario"], name: "Scenario"}, _): true;
									case _: false;
								});
								fields.sort((a, b) -> Context.getPosInfos(a.pos).min - Context.getPosInfos(b.pos).min);
								for (f in fields) {
									var p = module.split(".").concat([f.name]);
									out.push(macro {scenario: $p{p}, path: $v{p.join(".")}});
								}
							case _:
						}
				case _:
					var name = path(Context.typeExpr(e)) ?? Context.error("Monkey.from: a scenario at a module's or a class's top level (its path names it in the scenario file)", e.pos);
					out.push(macro {scenario: ($e : helder.scenario.Scenario), path: $v{name}});
			}
		return macro([$a{out}] : Array<helder.scenario.Monkey.Base>);
	}

	// (a static's path as code names it: a module's field by its module)
	static function path(e:TypedExpr):Null<String>
		return switch e.expr {
			case TField(_, FStatic(c, f)):
				var cl = c.get();
				switch cl.kind {
					case KModuleFields(m): m + "." + f.get().name;
					case _: typePath(cl.pack, cl.module, cl.name) + "." + f.get().name;
				}
			case TParenthesis(e) | TCast(e, null) | TMeta(_, e): path(e);
			case _: null;
		}

	static function typePath(pack:Array<String>, module:String, name:String):String
		return module.split(".").pop() == name ? pack.concat([name]).join(".") : module + "." + name;

	// (a generator and a printer (an expression of v) for values of t)
	static function derive(t:Type, pos:Position, depth:Int):{gen:Expr, show:Expr} {
		var G = macro helder.test.Gen;
		switch t {
			case TAbstract(_.get() => {pack: [], name: "Null"}, [p]):
				var d = derive(p, pos, depth + 1), ct = TypeTools.toComplexType(p), s = d.show;
				return {gen: depth > 3 ? macro $G.constant(null) : macro $G.oneOf([$G.constant(null), ${d.gen}]), show: macro v == null ? "null" : ((v:$ct) -> $s)(v)};
			case TType(_) | TMono(_) | TLazy(_):
				return derive(TypeTools.follow(t, true), pos, depth);
			case _:
		}
		switch TypeTools.follow(t) {
			case TAbstract(_.get() => {pack: [], name: "Int"}, _):
				return {gen: macro $G.oneOf([$G.int(-10, 100), $G.int(-2147483647, 2147483647)]), show: macro Std.string(v)};
			case TAbstract(_.get() => {pack: [], name: "Float"}, _):
				return {gen: macro $G.oneOf([$G.float(-10, 1000), $G.float(-1e12, 1e12)]), show: macro helder.scenario.Monkey.number(v)};
			case TAbstract(_.get() => {pack: [], name: "Bool"}, _):
				return {gen: macro $G.bool(), show: macro v ? "true" : "false"};
			case TInst(_.get() => {pack: [], name: "String"}, _):
				return {gen: macro helder.scenario.Monkey.TEXTS, show: macro helder.scenario.Steps.quote(v)};
			case TInst(_.get() => {pack: [], name: "Array"}, [p]):
				var d = derive(p, pos, depth + 1), ct = TypeTools.toComplexType(p), s = d.show;
				return {
					gen: depth > 3 ? macro $G.constant([]) : macro $G.array(${d.gen}, 0, 300),
					show: macro "[" + [for (x in v) ((v:$ct) -> $s)(x)].join(", ") + "]"
				};
			case TAnonymous(_.get() => a):
				var gs = [], parts = [];
				var fs = a.fields.copy();
				fs.sort((x, y) -> Context.getPosInfos(x.pos).min - Context.getPosInfos(y.pos).min);
				for (f in fs) {
					var d = derive(f.type, pos, depth + 1), ct = TypeTools.toComplexType(f.type), s = d.show, n = f.name, g = d.gen;
					gs.push({field: n, expr: macro c.draw($g)});
					parts.push(macro $v{n + ": "} + ((v:$ct) -> $s)(v.$n));
				}
				var obj = {expr: EObjectDecl(gs), pos: pos};
				return {gen: macro (c:helder.test.Choices) -> $obj, show: macro "{" + [$a{parts}].join(", ") + "}"};
			case TEnum(_.get() => e, _):
				var name = typePath(e.pack, e.module, e.name), gens = [], cases = [];
				for (n in e.names) {
					var f = e.constructs.get(n), ctor = macro $p{name.split(".").concat([n])};
					switch TypeTools.follow(f.type) {
						case TFun(args, _):
							if (depth > 3) continue;
							var draws = [], vars = [], shows = [];
							for (i => a in args) {
								var d = derive(a.t, pos, depth + 1), ct = TypeTools.toComplexType(a.t), s = d.show, g = d.gen, id = 'a$i';
								draws.push(macro c.draw($g));
								vars.push(macro $i{id});
								shows.push(macro((v:$ct) -> $s)($i{id}));
							}
							gens.push(macro (c:helder.test.Choices) -> $ctor($a{draws}));
							cases.push({values: [macro $ctor($a{vars})], expr: macro $v{name + "." + n + "("} + [$a{shows}].join(", ") + ")"});
						case _:
							gens.push(macro $G.constant($ctor));
							cases.push({values: [macro $ctor], expr: macro $v{name + "." + n}});
					}
				}
				if (gens.length == 0) Context.error('Monkey.atom: no generator for ${e.name} this deep (give one)', pos);
				var sw = {expr: ESwitch(macro v, cases, null), pos: pos};
				return {gen: macro $G.oneOf([$a{gens}]), show: sw};
			case TAbstract(_.get() => a, _) if (a.meta.has(":enum")):
				var name = typePath(a.pack, a.module, a.name), values = [], cases = [];
				for (f in a.impl.get().statics.get())
					if (f.meta.has(":enum") || f.meta.has(":value")) {
						var v = macro $p{name.split(".").concat([f.name])};
						values.push(v);
						cases.push({values: [v], expr: macro $v{name + "." + f.name}});
					}
				if (values.length == 0) Context.error('Monkey.atom: ${a.name} has no values', pos);
				var sw = {expr: ESwitch(macro v, cases, macro "null"), pos: pos};
				return {gen: macro $G.pick([$a{values}]), show: sw};
			case other:
				return Context.error('Monkey.atom: no generator for ${TypeTools.toString(other)} (give one: Monkey.atom(signal, gen))', pos);
		}
	}
}
#end
