package helder.ui.controls;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
#end

// A control's variant and size, checked where they are written against the
// values its look declares: V is the look's (Look<V>: a structure naming,
// by control and axis, each value: {button_variant: {primary: Bool, ...},
// ...}, which Look.with's macro extends with a patch's). A literal the look
// lacks is an error at the attribute; another String is too.
@:typescript.type("import(\'./style\').Axis<V, 'button_variant'>")
abstract ButtonVariant<V>(String) to String {
	@:from public static macro function of(e:Expr):Expr
		return Variants.check(e, "button_variant");
}

@:typescript.type("import(\'./style\').Axis<V, 'button_size'>")
abstract ButtonSize<V>(String) to String {
	@:from public static macro function of(e:Expr):Expr
		return Variants.check(e, "button_size");
}

@:typescript.type("import(\'./style\').Axis<V, 'checkbox_variant'>")
abstract CheckboxVariant<V>(String) to String {
	@:from public static macro function of(e:Expr):Expr
		return Variants.check(e, "checkbox_variant");
}

@:typescript.type("import(\'./style\').Axis<V, 'checkbox_size'>")
abstract CheckboxSize<V>(String) to String {
	@:from public static macro function of(e:Expr):Expr
		return Variants.check(e, "checkbox_size");
}

@:typescript.type("import(\'./style\').Axis<V, 'switch_variant'>")
abstract SwitchVariant<V>(String) to String {
	@:from public static macro function of(e:Expr):Expr
		return Variants.check(e, "switch_variant");
}

@:typescript.type("import(\'./style\').Axis<V, 'switch_size'>")
abstract SwitchSize<V>(String) to String {
	@:from public static macro function of(e:Expr):Expr
		return Variants.check(e, "switch_size");
}

// the default look's variants
typedef BaseVariants = {
	button_variant:{primary:Bool, secondary:Bool, outline:Bool, ghost:Bool, danger:Bool},
	button_size:{sm:Bool, md:Bool, lg:Bool},
	checkbox_variant:{},
	checkbox_size:{},
	switch_variant:{},
	switch_size:{}
}

@:typescript.hide
class Variants {
	public static final AXES = ["button_variant", "button_size", "checkbox_variant", "checkbox_size", "switch_variant", "switch_size"];

	#if macro
	// (e, a literal, as the expected abstract when its look declares it)
	public static function check(e:Expr, axis:String):Expr {
		var t = Context.getExpectedType();
		var ct = t == null ? null : Context.toComplexType(t);
		var lit = switch e.expr {
			case EConst(CString(s, _)): s;
			case _: null;
		}
		if (lit == null) Context.error('$axis: a variant is written as a literal ("primary"), checked against the look', e.pos);
		var values = valuesOf(t, axis);
		if (values != null && values.indexOf(lit) < 0)
			Context.error('"$lit" is no ${axis.split("_").join(" ")} of this look' + (values.length == 0 ? " (it has none)" : ': ${values.join(", ")}'), e.pos);
		return ct == null ? macro cast $e : macro(cast $e : $ct);
	}

	// (the values the look's structure names for axis, null: any)
	public static function valuesOf(t:Null<Type>, axis:String):Null<Array<String>> {
		if (t == null) return null;
		var v = switch Context.follow(t) {
			case TAbstract(_.get() => {name: "Null", pack: []}, [p]): return valuesOf(p, axis);
			case TAbstract(_, [p]): p;
			case _: return null;
		}
		return switch Context.follow(v) {
			case TAnonymous(a):
				var f = Lambda.find(a.get().fields, f -> f.name == axis);
				f == null ? [] : names(f.type);
			case _: null;
		}
	}

	public static function names(t:Type):Array<String>
		return switch Context.follow(t) {
			case TAnonymous(a): [for (f in a.get().fields) f.name];
			case _: [];
		}
	#end
}
