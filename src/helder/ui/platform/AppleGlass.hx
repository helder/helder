package helder.ui.platform;

#if ((!helder.os || helder.os == "macos" || helder.os == "ios") && (hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64" || hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64"))
import helder.os.OsThread;
import helder.os.objc.*;
import hxmc.unsafe.*;

// The system's Liquid Glass (iOS and macOS 26, helder.ui.Glass's): macOS's
// NSGlassEffectView, iOS's UIVisualEffectView of a UIGlassEffect; a group's
// NSGlassEffectContainerView or UIVisualEffectView of a
// UIGlassContainerEffect, its glass views inside its content view. Each in a
// host (CaViews) that takes no press: helder's view under it keeps the
// input, the glass only shows. Called from the program's thread, its views
// the main thread's.
@:hxmc.unsafe(gc)
@:access(helder.ui.draw.CaLayers)
class AppleGlass {
	static final ios = hxmc.Platform.apple() >= 1;

	public final slot:helder.ui.LayerSlot;
	// in a group's content view (no slot of its own: the group's)
	public final grouped:Bool;
	// (the glass view; a group's content view, where its glass goes)
	final view:Ptr;
	final content:Ptr;
	var set:Array<Float> = [];
	var disposed = false;

	// ui's window's glass (group: a group's; into: in a group's), null where the system has none
	public static function make(ui:helder.ui.Ui, ?into:AppleGlass, group = false):Null<AppleGlass> {
		for (w in @:privateAccess helder.ui.draw.UiWindow.open)
			if (w.ui == ui) {
				var v = w.window.surface.handle;
				return OsThread.get(() -> {
					if ((ios ? ObjC.cls("UIGlassEffect") : ObjC.cls("NSGlassEffectView")).isNull()) return null;
					var parent = ios ? v : Msg.id(Msg.id(v, ObjC.sel("window")), ObjC.sel("contentView"));
					new AppleGlass(parent, group, into);
				});
			}
		return null;
	}

	function new(parent:Ptr, group:Bool, into:Null<AppleGlass>) {
		var pool = Runtime.objc_autoreleasePoolPush();
		grouped = into != null;
		if (ios) {
			var e = group ? Msg.id(ObjC.cls("UIGlassContainerEffect"), ObjC.sel("new")) : Runtime.objc_retain(Msg.idInt(ObjC.cls("UIGlassEffect"), ObjC.sel("effectWithStyle:"), 0));
			view = Msg.idPtr(Msg.id(ObjC.cls("UIVisualEffectView"), ObjC.sel("alloc")), ObjC.sel("initWithEffect:"), e);
			ObjC.release(e);
			content = Msg.id(view, ObjC.sel("contentView"));
			Msg.vBool(view, ObjC.sel("setUserInteractionEnabled:"), false);
		} else {
			view = Msg.id(Msg.id(group ? ObjC.cls("NSGlassEffectContainerView") : ObjC.cls("NSGlassEffectView"), ObjC.sel("alloc")), ObjC.sel("init"));
			if (group) {
				// (flipped, as helder's: its glass placed top down)
				content = helder.ui.draw.CaViews.host(true);
				Msg.vBool(content, ObjC.sel("setHidden:"), false);
				Msg.vBool(Msg.id(content, ObjC.sel("layer")), ObjC.sel("setMasksToBounds:"), false);
				Msg.vPtr(view, ObjC.sel("setContentView:"), content);
			} else content = Ptr.nil();
		}
		if (into != null) {
			slot = new helder.ui.LayerSlot(Ptr.nil(), true);
			Msg.vPtr(into.content, ObjC.sel("addSubview:"), view);
		} else {
			var h = helder.ui.draw.CaViews.host(true);
			Msg.vPtr(h, ObjC.sel("addSubview:"), view);
			Msg.vPtr(parent, ObjC.sel("addSubview:"), h);
			slot = new helder.ui.LayerSlot(h, true);
			slot.inner = view;
			slot.content = false;
		}
		Runtime.objc_autoreleasePoolPop(pool);
	}

	// its look: clear (else regular), the tint (ARGB, 0: none), interactive, its corners' radius in points
	public function look(clear:Bool, tint:Int, interactive:Bool, radius:Float) {
		var key = [clear ? 1 : 0, tint, interactive ? 1 : 0, radius];
		if (same(key)) return;
		set = key;
		OsThread.run(() -> {
			if (disposed) return;
			var r = (tint >> 16 & 0xFF) / 255, g = (tint >> 8 & 0xFF) / 255, b = (tint & 0xFF) / 255, a = (tint >>> 24) / 255;
			var color = tint == 0 ? Ptr.nil() : ios ? GlassMsg.idFloat4(ObjC.cls("UIColor"), ObjC.sel("colorWithRed:green:blue:alpha:"), r, g, b, a)
				: GlassMsg.idFloat4(ObjC.cls("NSColor"), ObjC.sel("colorWithSRGBRed:green:blue:alpha:"), r, g, b, a);
			if (ios) {
				var e = Msg.idInt(ObjC.cls("UIGlassEffect"), ObjC.sel("effectWithStyle:"), clear ? 1 : 0);
				Msg.vBool(e, ObjC.sel("setInteractive:"), interactive);
				Msg.vPtr(e, ObjC.sel("setTintColor:"), color);
				Msg.vPtr(view, ObjC.sel("setEffect:"), e);
				Msg.vFloat(Msg.id(view, ObjC.sel("layer")), ObjC.sel("setCornerRadius:"), radius);
				Msg.vBool(view, ObjC.sel("setClipsToBounds:"), true);
				return;
			}
			Msg.vInt(view, ObjC.sel("setStyle:"), clear ? 1 : 0);
			Msg.vPtr(view, ObjC.sel("setTintColor:"), color);
			Msg.vFloat(view, ObjC.sel("setCornerRadius:"), radius);
			// (macOS 27's)
			if (Msg.bPtr(view, ObjC.sel("respondsToSelector:"), ObjC.sel("setEffectIsInteractive:")))
				Msg.vBool(view, ObjC.sel("setEffectIsInteractive:"), interactive);
		});
	}

	// a group's: how near its glass merges, in points
	public function spacing(v:Float) {
		if (same([v])) return;
		set = [v];
		OsThread.run(() -> {
			if (disposed) return;
			var e = ios ? Msg.id(view, ObjC.sel("effect")) : view;
			Msg.vFloat(e, ObjC.sel("setSpacing:"), v);
			if (ios) Msg.vPtr(view, ObjC.sel("setEffect:"), e);
		});
	}

	// a glass in a group's content view: at x, y, w x h points of the group's box, shown
	public function place(x:Float, y:Float, w:Float, h:Float, shown:Bool) {
		if (!(Math.isFinite(x) && Math.isFinite(y) && Math.isFinite(w) && Math.isFinite(h))) return;
		OsThread.run(() -> {
			if (disposed) return;
			helder.ui.draw.CaLayers.setRect(view, ObjC.sel("setFrame:"), x, y, w, h);
			Msg.vBool(view, ObjC.sel("setHidden:"), !shown);
		});
	}

	function same(key:Array<Float>):Bool {
		if (key.length != set.length) return false;
		for (i in 0...key.length)
			if (key[i] != set[i]) return false;
		return true;
	}

	public function dispose()
		OsThread.run(() -> {
			if (disposed) return;
			disposed = true;
			Msg.v(view, ObjC.sel("removeFromSuperview"));
			var h = slot.handle;
			if (!h.isNull()) {
				Msg.v(h, ObjC.sel("removeFromSuperview"));
				ObjC.release(h);
			}
			if (!ios && !content.isNull()) ObjC.release(content);
			ObjC.release(view);
		});
}

@:build(helder.os.objc.Sender.build())
@:hxmc.unsafe(gc)
private class GlassMsg {
	static function idFloat4(self:Ptr, sel:Ptr, a:Float, b:Float, c:Float, d:Float):Ptr;
}
#end
