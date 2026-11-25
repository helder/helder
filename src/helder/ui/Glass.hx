package helder.ui;

// Liquid Glass, `<glass>` in markup: a surface that lenses and blurs what is
// behind it, its children over it. Its shape is its box with its corners'
// radius (a capsule unless given one: `radius={12}`); `variant="clear"` is
// the system's clear glass (else regular), `tint` the colour it leans to
// (its alpha how far), `interactive` makes it answer a press. On iOS and
// macOS 26 it is the system's own (helder.ui.platform.apple.Glass) where the
// window's layers are the system's (Ui.layered), a view placed in the layer
// tree (LayerSlot) that samples what is behind it; elsewhere, and in frames
// read back, it is drawn. In a `<glass-group>` (GlassGroup) glass near each
// other merge.
//
//   <glass direction="row" padding={12} column-gap={8} tint="#3478f640" interactive>
//     <icon name="play"/><text>Play</text>
//   </glass>
class Glass extends Node {
	// (a radius past any box's: a capsule, fitted as CSS fits radii)
	static inline var CAPSULE = 1e4;

	public var tint(default, set):Null<Color> = null;
	public var interactive(default, set) = false;

	var native:Null<GlassNative> = null;
	// (its drawing's, helder.ui.draw.GlassPass: a GPU's, natively)
	@:allow(helder.ui.GlassDraw) var pass:Any = null;

	public function new() {
		super("glass");
		style.radius = CAPSULE;
	}

	public var clear(get, never):Bool;

	inline function get_clear():Bool
		return variant == "clear";

	function set_tint(v:Null<Color>):Null<Color> {
		tint = v;
		paintChanged();
		return v;
	}

	function set_interactive(v:Bool):Bool {
		interactive = v;
		paintChanged();
		return v;
	}

	// (its group's, if it is in one: drawn and placed by it)
	function group():Null<GlassGroup> {
		var p = parent;
		while (p != null) {
			if (Std.isOfType(p, GlassGroup)) return cast p;
			p = p.parent;
		}
		return null;
	}

	// its corners' radius as drawn, in points (one for all: the system's glass has one)
	public function radius():Float
		return Math.min(style.radius, Math.min(width, height) / 2);

	@:noCompletion override public function hasContent():Bool
		return true;

	override function statesChanged() {
		super.statesChanged();
		if (interactive) paintChanged();
	}

	@:noCompletion override public function paintContent(canvas:Canvas, x:Float, y:Float, width:Float, height:Float) {
		if (systemLayer != null || native != null && native.grouped || group() != null) return;
		GlassDraw.draw(canvas, this);
	}

	override function attach(u:Null<Ui>) {
		if (ui != null && ui != u) {
			@:privateAccess ui.natives.remove(this);
			drop();
		}
		super.attach(u);
		if (u != null && @:privateAccess u.natives.indexOf(this) < 0) @:privateAccess u.natives.push(this);
	}

	function drop() {
		systemLayer = null;
		if (native != null) native.dispose();
		native = null;
	}

	// (after each layout: the system's glass made, its look and place kept in step)
	override function syncNative() {
		if (ui == null) return;
		var g = group(), on = visible() && width > 0 && height > 0;
		if (!@:privateAccess ui.layered || g != null && g.native == null) {
			if (native != null) {
				drop();
				paintChanged();
			}
			return;
		}
		if (native == null) {
			native = GlassNative.make(ui, g == null ? null : g.native);
			if (native == null) return;
			paintChanged();
		}
		var t:Int = tint ?? 0;
		native.look(clear, t, interactive, radius());
		if (g != null) native.place(absX - g.absX, absY - g.absY, width, height, on);
		else {
			systemLayer = native.slot;
			systemLayer.shown = on;
		}
	}
}

#if ((!helder.os || helder.os == "macos" || helder.os == "ios") && (hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64" || hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64"))
typedef GlassNative = helder.ui.platform.apple.Glass;
#else
// (no system glass here: drawn)
@:noCompletion
class GlassNative {
	public static function make(ui:Ui, ?into:GlassNative, group = false):Null<GlassNative>
		return null;

	public var grouped(default, null) = false;
	public var slot(default, null):Null<LayerSlot> = null;

	public function look(clear:Bool, tint:Int, interactive:Bool, radius:Float) {}

	public function spacing(v:Float) {}

	public function place(x:Float, y:Float, w:Float, h:Float, shown:Bool) {}

	public function dispose() {}
}
#end
