package helder.ui.controls;

#if macro
import helder.ui.controls.Variant;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
#end

// A look as Haxe holds one (Look.base's, with's): with checks a patch
// against Recipe.Patch where it is written, and its result's type names
// the look's variants with the patch's added (a recipe's variants:
// {variant: {soft: ...}}), so that look.Button's variant="soft" is checked
// at compile time. TypeScript's is Look<V> (the same, by its types).
#if !macro
@:typescript.type("Look<V>")
@:forward(tokens, sheet, refs, Button, Checkbox, Switch)
abstract LookOf<V>(Look<V>) from Look<V> to Look<V> to Look<Dynamic> {
	public macro function with(ethis:haxe.macro.Expr, patch:haxe.macro.Expr):haxe.macro.Expr
		return LookMacro.with(ethis, patch);
}
#else
// (the macro's side: the look not typed here, its with)
abstract LookOf<V>(Dynamic) {
	public macro function with(ethis:Expr, patch:Expr):Expr
		return LookMacro.with(ethis, patch);
}
#end

#if macro
class LookMacro {
	static final CONTROLS = ["button", "checkbox", "switch"];

	public static function with(ethis:Expr, patch:Expr):Expr {
		var pos = Context.currentPos();
		var values = new Map<String, Array<String>>();
		for (axis in Variants.AXES)
			values.set(axis, []);
		// (the look's own: its type's)
		switch Context.follow(Context.typeof(ethis)) {
			case TAbstract(_, [v]):
				switch Context.follow(v) {
					case TAnonymous(a):
						for (f in a.get().fields)
							if (values.exists(f.name)) values.set(f.name, Variants.names(f.type));
					case _:
				}
			case _:
		}
		var p = renamed(patch);
		switch p.expr {
			case EObjectDecl(fields):
				for (f in fields) {
					var control = f.field == "switch_" ? "switch" : f.field;
					if (CONTROLS.indexOf(control) < 0) continue;
					var r = returned(f.expr);
					var variants = r == null ? null : field(r, "variants");
					if (variants == null) continue;
					for (axis in ["variant", "size"]) {
						var named = field(variants, axis);
						if (named == null) continue;
						switch named.expr {
							case EObjectDecl(vs):
								var into = values.get(control + "_" + axis);
								for (v in vs)
									if (into.indexOf(v.field) < 0) into.push(v.field);
							case _:
						}
					}
				}
			case _:
		}
		var ct = ComplexType.TAnonymous([
			for (axis in Variants.AXES)
				({
					name: axis,
					pos: pos,
					kind: FieldType.FVar(ComplexType.TAnonymous([for (v in values.get(axis)) ({name: v, pos: pos, kind: FieldType.FVar(macro :Bool)} : Field)]))
				} : Field)
		]);
		return macro @:pos(pos) (cast(@:privateAccess (cast $ethis : helder.ui.controls.Look<Dynamic>).extend(($p : helder.ui.controls.Recipe.Patch)))
			: helder.ui.controls.LookOf<$ct>);
	}

	// (what TypeScript's Look.with takes, typed, so that its functions are
	// called through the lowering's adapters, as Haxe functions: a structure
	// whose control is "switch", which a typedef cannot name)
	public static function tsPatch():ComplexType {
		var pos = Context.currentPos();
		function opt(name:String, t:ComplexType):Field
			return {name: name, pos: pos, meta: [{name: ":optional", pos: pos}], kind: FieldType.FVar(t)};
		var renders = ComplexType.TAnonymous([
			opt("button", macro :helder.ui.controls.Props.ButtonProps<Dynamic>->helder.ui.view.UiView),
			opt("checkbox", macro :helder.ui.controls.Props.CheckboxProps<Dynamic>->helder.ui.view.UiView),
			opt("switch", macro :helder.ui.controls.Props.SwitchProps<Dynamic>->helder.ui.view.UiView)
		]);
		return ComplexType.TAnonymous([
			opt("density", macro :String),
			opt("accent", macro :String),
			opt("tokens", macro :helder.ui.controls.Tokens),
			opt("button", macro :helder.ui.controls.Tokens.Refs->Dynamic),
			opt("checkbox", macro :helder.ui.controls.Tokens.Refs->Dynamic),
			opt("switch", macro :helder.ui.controls.Tokens.Refs->Dynamic),
			opt("render", renders)
		]);
	}

	// (a patch with "switch" written as Patch names it: switch_, a key of its own and of render's)
	static function renamed(e:Expr):Expr
		return switch e.expr {
			case EObjectDecl(fields):
				{
					expr: EObjectDecl([
						for (f in fields)
							{
								field: f.field == "switch" ? "switch_" : f.field,
								expr: f.field == "render" ? renamed(f.expr) : f.expr,
								quotes: f.field == "switch" ? Unquoted : f.quotes
							}
					]),
					pos: e.pos
				};
			case _: e;
		}

	// (what a recipe returns: its body's object, a function's or the object itself)
	static function returned(e:Expr):Null<Expr>
		return switch e.expr {
			case EFunction(_, f) if (f.expr != null): returned(f.expr);
			case EReturn(x) if (x != null): returned(x);
			case EBlock(es) if (es.length > 0): returned(es[es.length - 1]);
			case EParenthesis(x) | EMeta(_, x) | ECheckType(x, _): returned(x);
			case EObjectDecl(_): e;
			case _: null;
		}

	static function field(e:Expr, name:String):Null<Expr>
		return switch e.expr {
			case EObjectDecl(fields):
				var f = Lambda.find(fields, f -> f.field == name);
				f == null ? null : f.expr;
			case _: null;
		}
}
#end
