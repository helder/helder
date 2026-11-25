package helder.media.ui;

#if (hxmc.target == "wasm32-wasi")
import helder.ui.ImageFit;
import helder.ui.LayerSlot;
import helder.ui.UiWindow;
import helder.ui.layers.web.Layers;

// A video shown by the page (SampleLayer's in a browser, in a window whose
// layers are the page's: helder.ui.layers.web.Layers): a canvas of the page in
// the node's slot, among the window's layers in paint order (in its scroll
// view where its scroller's content is a layer), each frame as it falls
// due read into an ImageBitmap (the browser's VideoFrame: no copy through
// the module) and shown there, fit as CSS's object-fit; helder draws
// nothing for it. Until a frame was shown the node draws them (showing).
// null where the window's layers are not the page's.
@:hxmc.unsafe(gc)
class WebSample {
	public final slot:LayerSlot;
	public var showing(default, null) = false;
	final canvas:Int;
	final id:Int;
	var last:Null<VideoFrame> = null;

	public static function make(owner:VideoNode):Null<WebSample> {
		var p = owner.player, ui = owner.ui;
		if (p == null || p.video == null || ui == null) return null;
		for (w in @:privateAccess UiWindow.open)
			if (w.ui == ui && w.compositor != null && Std.isOfType(w.compositor.layers, Layers) && w.compositor.layers.frames > 0) {
				var c = w.window.surface.handle.toI64().toInt();
				return new WebSample(c, WebLayerImports.layers_slot(c));
			}
		return null;
	}

	function new(canvas:Int, id:Int) {
		this.canvas = canvas;
		this.id = id;
		slot = new LayerSlot(hxmc.unsafe.Ptr.ofI64(id));
	}

	public function fit(f:ImageFit)
		WebLayerImports.layers_slot_fit(canvas, id, cast f);

	// (each tick: the frame due shown once)
	public function feed(p:Player):Null<VideoFrame> {
		var f = p.update();
		if (f != null && f != last) {
			last = f;
			WebLayerImports.layers_slot_frame(canvas, id, f.handle());
			showing = true;
		}
		return f;
	}

	public function clear() {
		last = null;
		WebLayerImports.layers_slot_frame(canvas, id, 0);
	}

	public function dispose()
		WebLayerImports.layers_slot_free(canvas, id);
}
#end
