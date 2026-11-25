package helder.ui.layers.web;

import helder.gfx.*;
import helder.ui.*;

// The browser's side of a window's compositor (UiWindow's on the web, in
// place of Compositor): the program's frames alone, each one's state
// (helder.ui.layers.CompositeFrame, as Ui's paint fills it) shown on the page's layers
// (Layers) in order with its commands. No mirror of the scrollers and
// no frames of its own: the browser scrolls the scroll views, moves the
// layers in them and runs the Web Animations while the program is busy.
@:hxmc.unsafe(gc)
@:access(helder.ui.layers.CompositeFrame)
@:access(helder.ui.draw.Renderer)
class Compositor {
	final device:Device;
	final frames = [new helder.ui.layers.CompositeFrame(), new helder.ui.layers.CompositeFrame()];
	var filling = 0;
	var shown:Null<helder.ui.layers.CompositeFrame> = null;
	final buffers:Array<Buffer> = [];
	var capacity = 0;
	var loud = true;

	public final layers:Layers;
	// (Compositor's: never a frame of its own here)
	public final drewSince = false;

	public function new(device:Device) {
		this.device = device;
		layers = new Layers(device);
	}

	// whether the program's frames go to the page's layers
	public function planes():Bool {
		layers.prepare();
		return !layers.single && !layers.priming;
	}

	// (before the program's frame: onto the canvas, or only into targets, the layers drawn from it after)
	public function quiet(on:Bool) {
		if (loud == !on) return;
		loud = !on;
		var l = layers;
		device.inOrder(r -> {
			l.quiet(r, on);
			if (!on) l.suspend();
		});
	}

	public function begin(r:helder.ui.draw.Renderer)
		r.composite = frames[filling];

	public function end(ui:Ui, r:helder.ui.draw.Renderer) {
		var f = frames[filling];
		r.composite = null;
		if (!f.ready || !r.ended(f)) return;
		var need = (f.quads() + 64) * helder.ui.layers.CompositeFrame.STRIDE;
		if (need > capacity) {
			for (b in buffers)
				device.destroyBuffer(b);
			buffers.resize(0);
			capacity = need * 2;
			for (_ in 0...QuadBatch.RING)
				buffers.push(device.createBuffer({size: capacity, usage: Vertex}));
		}
		f.paintedAt = Ui.now();
		f.buffers = buffers.copy();
		f.capacity = capacity;
		filling = 1 - filling;
		var l = layers;
		device.inOrder(_ -> {
			shown = f;
			l.adopt();
		});
	}

	// (after the program's frame ended: shown on the page's layers; onto the canvas, split only, for the next)
	public function present(planes:Bool) {
		var l = layers;
		device.inOrder(r -> {
			var f = shown;
			if (f == null) return;
			if (!planes) {
				l.check(f);
				l.windowShown();
				return;
			}
			var t = f.paintedAt, bars = f.overlay ? [for (v in f.barAt) {
				var age = t - v;
				age >= SHOWN + FADE ? 0 : age <= SHOWN ? 1 : 1 - (age - SHOWN) / FADE;
			}] : null;
			l.show(r, f, f.offsets, t, bars, true, []);
		});
		if (planes) @:privateAccess device.flush();
	}

	static inline var SHOWN = @:privateAccess Ui.BAR_SHOWN;
	static inline var FADE = @:privateAccess Ui.BAR_FADE;

	// (a frame wanted: a layer's view not made yet)
	public function moving():Bool
		return layers.redraw;

	public function drain(ui:Ui) {}

	public function rest() {}

	public function dispose() {
		var l = layers;
		// (helder dev's swap disposes the device first: the page's layers let go of alone, nothing more queued on it)
		if (@:privateAccess device.disposed) {
			l.dispose();
			buffers.resize(0);
			return;
		}
		device.inOrder(_ -> l.dispose());
		for (b in buffers)
			device.destroyBuffer(b);
		buffers.resize(0);
	}
}
