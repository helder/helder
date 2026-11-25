package helder.ui.actions;

// what a menu shows an action as, from the handler that would take it
enum abstract ActionState(String) {
	// no handler on the path takes it
	var Unhandled = "unhandled";
	var Disabled = "disabled";
	var Enabled = "enabled";
	// enabled, a check mark shown (or not: Unchecked)
	var Checked = "checked";
	var Unchecked = "unchecked";

	public var enabled(get, never):Bool;

	inline function get_enabled()
		return abstract != Unhandled && abstract != Disabled;

	@:noCompletion @:from static macro function ofString(e:haxe.macro.Expr.ExprOf<String>):haxe.macro.Expr
		return helder.os.Literal.of(e);
}
