package helder.ui;

enum abstract Placement(String) {
	var Below = "below";
	var Above = "above";
	var Right = "right";
	var Left = "left";
	var Center = "center";
	var Manual = "manual";
	var Point = "point";
	var TopLeft = "top-left";
	var TopRight = "top-right";
	var BottomLeft = "bottom-left";
	var BottomRight = "bottom-right";

	@:noCompletion @:from static macro function ofString(e:haxe.macro.Expr.ExprOf<String>):haxe.macro.Expr
		return helder.os.Literal.of(e);

	// a placement written by a person ("bottom" Below's too); throws when it is none
	public static function parse(s:String):Placement
		return switch s.toLowerCase() {
			case "below" | "bottom": Below;
			case "above" | "top": Above;
			case "right": Right;
			case "left": Left;
			case "center": Center;
			case "manual": Manual;
			case "point": Point;
			case "top-left": TopLeft;
			case "top-right": TopRight;
			case "bottom-left": BottomLeft;
			case "bottom-right": BottomRight;
			case _: throw "Placement: not a placement: " + s;
		}
}
