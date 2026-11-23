package helder.os.objc;

// (CGRect) x' = a x + c y + tx, y' = b x + d y + ty
@:hxmc.struct @:publicFields class CGAffineTransform {
	var a:Float;
	var b:Float;
	var c:Float;
	var d:Float;
	var tx:Float;
	var ty:Float;
}
