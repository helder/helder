package helder.ui.platform;

import helder.os.apple.objc.UIEdgeInsets;
import hxmc.unsafe.*;

// The message shapes IosViews sends beside Msg's (helder.os.apple.objc.Sender):
// named by the result, then the arguments, as Msg's.
@:build(helder.os.apple.objc.Sender.build())
@:hxmc.unsafe(gc)
class UkMsg {
	static function iPtrPtr(self:Ptr, sel:Ptr, a:Ptr, b:Ptr):Int64;
	static function vInsets(self:Ptr, sel:Ptr, a:UIEdgeInsets):Void;
	static function vPtrPtrInt(self:Ptr, sel:Ptr, a:Ptr, b:Ptr, c:Int64):Void;
	static function idFloat(self:Ptr, sel:Ptr, a:Float):Ptr;
	static function idFloatFloat(self:Ptr, sel:Ptr, a:Float, b:Float):Ptr;
	static function idPtrFloat(self:Ptr, sel:Ptr, a:Ptr, b:Float):Ptr;
	static function idFloat4(self:Ptr, sel:Ptr, a:Float, b:Float, c:Float, d:Float):Ptr;
}
