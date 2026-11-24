package helder.ui.draw.soft;

import helder.gfx.Device;
import helder.gfx.Encoder;

// The soft canvas's GPU for the nodes drawn on one (GpuHost, -D helder.soft
// builds): a device on the CPU (helder.gfx.soft), headless; a node's pass
// runs at once (beforePass), or as the display list it was recorded into
// is replayed onto the canvas (SoftCanvas.pass), so that its texture is
// drawn when the canvas composites it (gpuTexture) right after
class SoftGpu {
	public final device:Device;
	public final canvas:SoftCanvas;
	public var scale(get, never):Float;
	public var frames(get, never):Int;

	var recording:Null<DisplayList> = null;

	public function new(canvas:SoftCanvas) {
		this.canvas = canvas;
		device = Device.create(helder.os.Surface.headless(1, 1));
	}

	inline function get_scale()
		return canvas.scale;

	inline function get_frames()
		return @:privateAccess canvas.frames;

	// the canvas's, through the display lists replayed onto it (as Renderer.of)
	public static function of(c:Null<helder.ui.Canvas>):Null<SoftGpu> {
		var l = Std.downcast(c, DisplayList);
		if (l != null) {
			var g = of(l.target);
			if (g != null) g.recording = l;
			return g;
		}
		var s = Std.downcast(c, SoftCanvas);
		if (s == null) return null;
		var g = s.gpu();
		g.recording = null;
		return g;
	}

	public function beforePass(f:Encoder->Void)
		if (recording != null) recording.pass(f) else run(f);

	// f's passes, run now
	public function run(f:Encoder->Void) {
		var enc = device.beginFrame();
		if (enc == null) return;
		f(enc);
		device.endFrame();
	}
}
