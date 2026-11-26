package helder.parallel;

#if macro
import haxe.macro.Expr;
#end

// (Items.of(values): Items<T> without its T, the values' element type's)
@:noCompletion class ItemsOf {
	// the items of values, in order
	public static macro function of(values:Expr):Expr
		return ItemsMacro.of(values);
}
