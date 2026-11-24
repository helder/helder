package helder.ui.draw;

#if ((!helder.os || helder.os == "macos" || helder.os == "ios") && hxmc.target != "wasm32-wasi")
import helder.os.objc.*;
import hxmc.unsafe.*;

// The views CaLayers places native views between (a LayerSlot's view, in a
// host view: host): AppKit and UIKit own a view's layer, which can go in no
// tree but its superview's, so the native view stays a view and what is
// drawn over it goes in a view over it (HxmcOverView, hosting those
// layers), in paint order: helder's view, then each host and the view of
// what is over it. An over view takes a press only where something is
// drawn over a host (hits: a popup over a field), the rest passing to the
// views under it; a host takes one only on its view, inside its clip. All
// of it the main thread's.
@:hxmc.unsafe(gc)
@:access(helder.ui.draw.CaLayers)
class CaViews {
	static var hostClass = Ptr.nil();
	static var overClass = Ptr.nil();
	static var passiveClass = Ptr.nil();
	// (each over view's: what is drawn over a host, x0, y0, x1, y1 in its points top down; by its address)
	static final hits = new Map<Int, Array<Float>>();
	// (the subviews' ranks while they are sorted: their keys, in order)
	static final ranked:Array<Int> = [];
	static final ios = hxmc.Platform.apple() >= 1;

	final parent:Ptr; // (where the hosts are: the window's content view, iOS's helder view)
	final under:Ptr; // (helder's view)
	public final overs:Array<Ptr> = [];
	public final stacks:Array<Ptr> = [];
	var arranged:Array<Ptr> = [];

	public function new(view:Ptr) {
		under = view;
		parent = ios ? view : Msg.id(view, ObjC.sel("superview"));
	}

	// a host for a native view, hidden: its clip's, clipping it (main thread);
	// passive: taking no press, the view only shown (glass)
	public static function host(passive = false):Ptr {
		classes();
		var h = Arena.scopedValue(a -> {
			var r = a.make(CGRect);
			r.value.size.width = 10;
			r.value.size.height = 10;
			Msg.idRect(Msg.id(passive ? passiveClass : hostClass, ObjC.sel("alloc")), ObjC.sel("initWithFrame:"), r.value);
		});
		if (ios) Msg.vBool(h, ObjC.sel("setClipsToBounds:"), true) else {
			Msg.vBool(h, ObjC.sel("setWantsLayer:"), true);
			Msg.vBool(Msg.id(h, ObjC.sel("layer")), ObjC.sel("setMasksToBounds:"), true);
		}
		Msg.vBool(h, ObjC.sel("setHidden:"), true);
		return h;
	}

	static function classes() {
		if (!hostClass.isNull()) return;
		pt = LibC.malloc(16);
		var base = ios ? ObjC.cls("UIView") : ObjC.cls("NSView");
		// (hxmc dev's host: the classes an earlier build made, their methods this build's)
		var h = ObjC.cls("HxmcHostView"), hostFresh = h.isNull();
		if (hostFresh) h = Runtime.objc_allocateClassPair(base, Mem.cstr("HxmcHostView"), 0);
		var o = ObjC.cls("HxmcOverView"), overFresh = o.isNull();
		if (overFresh) o = Runtime.objc_allocateClassPair(base, Mem.cstr("HxmcOverView"), 0);
		var p = ObjC.cls("HxmcPassiveView"), passiveFresh = p.isNull();
		if (passiveFresh) p = Runtime.objc_allocateClassPair(base, Mem.cstr("HxmcPassiveView"), 0);
		if (ios) Runtime.class_replaceMethod(p, ObjC.sel("hitTest:withEvent:"), Callback.addr(noHitIos), Mem.cstr("@@:dd@")) else {
			Runtime.class_replaceMethod(p, ObjC.sel("isFlipped"), Callback.addr(flipped), Mem.cstr("c@:"));
			Runtime.class_replaceMethod(p, ObjC.sel("hitTest:"), Callback.addr(noHit), Mem.cstr("@@:dd"));
		}
		if (passiveFresh) Runtime.objc_registerClassPair(p);
		passiveClass = p;
		if (ios) {
			Runtime.class_replaceMethod(h, ObjC.sel("hitTest:withEvent:"), Callback.addr(hostHitIos), Mem.cstr("@@:dd@"));
			Runtime.class_replaceMethod(o, ObjC.sel("hitTest:withEvent:"), Callback.addr(overHitIos), Mem.cstr("@@:dd@"));
		} else {
			Runtime.class_replaceMethod(h, ObjC.sel("isFlipped"), Callback.addr(flipped), Mem.cstr("c@:"));
			Runtime.class_replaceMethod(h, ObjC.sel("hitTest:"), Callback.addr(hostHit), Mem.cstr("@@:dd"));
			Runtime.class_replaceMethod(o, ObjC.sel("hitTest:"), Callback.addr(overHit), Mem.cstr("@@:dd"));
		}
		if (hostFresh) Runtime.objc_registerClassPair(h);
		if (overFresh) Runtime.objc_registerClassPair(o);
		hostClass = h;
		overClass = o;
	}

	// (no wrapper, nothing allocated: AppKit asks them from inside calls
	// that are no collection's point (a window's release))
	@:hxmc.callback @:hxmc.unsafe static function flipped(self:Ptr, cmd:Ptr):Int
		return 1;

	@:hxmc.callback @:hxmc.unsafe static function noHit(self:Ptr, cmd:Ptr, x:Float, y:Float):Ptr
		return Ptr.nil();

	@:hxmc.callback @:hxmc.unsafe static function noHitIos(self:Ptr, cmd:Ptr, x:Float, y:Float, e:Ptr):Ptr
		return Ptr.nil();

	// (a CGPoint by value: two doubles, as the ABI passes them)
	@:hxmc.callback static function hostHit(self:Ptr, cmd:Ptr, x:Float, y:Float):Ptr {
		var v = Msg.id(Msg.id(self, ObjC.sel("subviews")), ObjC.sel("firstObject"));
		if (v.isNull()) return Ptr.nil();
		pt.value.x = x;
		pt.value.y = y;
		var p = Msg.pointPointPtr(self, ObjC.sel("convertPoint:fromView:"), pt.value, Msg.id(self, ObjC.sel("superview")));
		var b = Msg.rect(self, ObjC.sel("bounds"));
		if (p.x < 0 || p.y < 0 || p.x >= b.size.width || p.y >= b.size.height) return Ptr.nil();
		pt.value.x = p.x;
		pt.value.y = p.y;
		return Msg.idPoint(v, ObjC.sel("hitTest:"), pt.value);
	}

	@:hxmc.callback static function overHit(self:Ptr, cmd:Ptr, x:Float, y:Float):Ptr {
		pt.value.x = x;
		pt.value.y = y;
		var p = Msg.pointPointPtr(self, ObjC.sel("convertPoint:fromView:"), pt.value, Msg.id(self, ObjC.sel("superview")));
		var b = Msg.rect(self, ObjC.sel("bounds"));
		return hit(self, p.x, b.size.height - p.y) ? self : Ptr.nil();
	}

	@:hxmc.callback static function hostHitIos(self:Ptr, cmd:Ptr, x:Float, y:Float, e:Ptr):Ptr {
		var v = Msg.id(Msg.id(self, ObjC.sel("subviews")), ObjC.sel("firstObject")), b = Msg.rect(self, ObjC.sel("bounds"));
		if (v.isNull() || Msg.b(self, ObjC.sel("isHidden")) || x < 0 || y < 0 || x >= b.size.width || y >= b.size.height) return Ptr.nil();
		pt.value.x = x;
		pt.value.y = y;
		var p = Msg.pointPointPtr(self, ObjC.sel("convertPoint:toView:"), pt.value, v);
		pt.value.x = p.x;
		pt.value.y = p.y;
		return ViewMsg.idPointPtr(v, ObjC.sel("hitTest:withEvent:"), pt.value, e);
	}

	@:hxmc.callback static function overHitIos(self:Ptr, cmd:Ptr, x:Float, y:Float, e:Ptr):Ptr
		return hit(self, x, y) ? self : Ptr.nil();

	static var pt:Ptr<CGPoint> = Ptr.nil();

	static function hit(self:Ptr, x:Float, y:Float):Bool {
		var r = hits.get(key(self));
		if (r == null) return false;
		var i = 0;
		while (i < r.length) {
			if (x >= r[i] && y >= r[i + 1] && x < r[i + 2] && y < r[i + 3]) return true;
			i += 4;
		}
		return false;
	}

	static inline function key(v:Ptr):Int {
		var a = v.toI64();
		return (a >> 32).toInt() ^ a.toInt();
	}

	// n over views, each hosting a layer that holds what is over its host (stacks)
	public function ensure(n:Int) {
		classes();
		while (overs.length > n) {
			var o = overs.pop(), s = stacks.pop();
			hits.remove(key(o));
			Msg.v(o, ObjC.sel("removeFromSuperview"));
			Runtime.objc_release(o);
			Runtime.objc_release(s);
		}
		while (overs.length < n) {
			var b = Msg.rect(under, ObjC.sel("frame"));
			var o = Arena.scopedValue(a -> {
				var r = a.make(CGRect);
				r.value = b;
				Msg.idRect(Msg.id(overClass, ObjC.sel("alloc")), ObjC.sel("initWithFrame:"), r.value);
			});
			var s = Runtime.objc_retain(Msg.id(ObjC.cls("CALayer"), ObjC.sel("layer")));
			CaLayers.setPoint(s, ObjC.sel("setAnchorPoint:"), 0, 0);
			if (ios) {
				Msg.vBool(o, ObjC.sel("setOpaque:"), false);
				Msg.vPtr(Msg.id(o, ObjC.sel("layer")), ObjC.sel("addSublayer:"), s);
			} else {
				// (a layer-hosting view, as helder's: the layer first, then wantsLayer; y up, its layers placed top down)
				var l = Msg.id(ObjC.cls("CALayer"), ObjC.sel("layer"));
				Msg.vPtr(o, ObjC.sel("setLayer:"), l);
				Msg.vBool(o, ObjC.sel("setWantsLayer:"), true);
				Msg.vBool(s, ObjC.sel("setGeometryFlipped:"), true);
				Msg.vPtr(l, ObjC.sel("addSublayer:"), s);
			}
			// (width and height sizable)
			Msg.vInt(o, ObjC.sel("setAutoresizingMask:"), 18);
			Msg.vPtr(parent, ObjC.sel("addSubview:"), o);
			overs.push(o);
			stacks.push(s);
			arranged = [];
		}
	}

	// the over views' size, w x h points
	public function size(w:Float, h:Float)
		for (i in 0...overs.length) {
			var s = stacks[i];
			CaLayers.setPoint(s, ObjC.sel("setPosition:"), 0, 0);
			CaLayers.setRect(s, ObjC.sel("setBounds:"), 0, 0, w, h);
		}

	// what over view i takes presses on
	public function hitsOf(i:Int, r:Array<Float>)
		hits.set(key(overs[i]), r);

	// the views in order over the others: each host, the over view after it
	public function arrange(hosts:Array<Ptr>) {
		var list = [];
		for (i in 0...hosts.length) {
			list.push(hosts[i]);
			list.push(overs[i]);
		}
		var same = list.length == arranged.length;
		if (same) for (i in 0...list.length)
			if (list[i] != arranged[i]) same = false;
		if (same) return;
		arranged = list;
		if (ios) {
			// (brought to the front, not added again: a field keeps its first responder)
			for (v in list)
				Msg.vPtr(parent, ObjC.sel("bringSubviewToFront:"), v);
			return;
		}
		// (sorted, not added again: AppKit takes the first responder from a view removed)
		ranked.resize(0);
		var subs = Msg.id(parent, ObjC.sel("subviews")), n = Msg.i(subs, ObjC.sel("count")).toInt(), mine = [for (v in list) key(v)];
		for (i in 0...n) {
			var k = key(Msg.idInt(subs, ObjC.sel("objectAtIndex:"), i));
			if (mine.indexOf(k) < 0) ranked.push(k);
		}
		for (k in mine)
			ranked.push(k);
		Msg.vPtrPtr(parent, ObjC.sel("sortSubviewsUsingFunction:context:"), Callback.addr(compare), Ptr.nil());
	}

	@:hxmc.callback @:hxmc.unsafe static function compare(a:Ptr, b:Ptr, ctx:Ptr):Int64 {
		var ka = key(a), kb = key(b), x = 0, y = 0;
		for (i in 0...ranked.length) {
			if (ranked[i] == ka) x = i;
			if (ranked[i] == kb) y = i;
		}
		return x < y ? -1 : x > y ? 1 : 0;
	}

	public function dispose()
		ensure(0);
}

// (the message shapes beside Msg's)
@:build(helder.os.objc.Sender.build())
@:hxmc.unsafe(gc)
private class ViewMsg {
	static function idPointPtr(self:Ptr, sel:Ptr, p:CGPoint, a:Ptr):Ptr;
}
#end
