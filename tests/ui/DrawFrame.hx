import haxe.io.Bytes;
import helder.ui.*;
import helder.ui.draw.soft.SoftCanvas;
#if !helder.soft
import helder.gfx.*;
import helder.ui.draw.Renderer;
#end

// What the image tests draw a Ui with, headless, and read back (RGBA8,
// rows top to bottom): the GPU (a headless device, the Renderer: Mesa's
// llvmpipe on Linux, Metal on macOS), or the CPU's canvas
// (helder.ui.draw.soft) with HELDER_SOFT=1 or in a -D helder.soft build,
// which links no GPU. One a program, its device and renderer (or canvas)
// kept from frame to frame, as a window keeps them.
class DrawFrame {
	public final width:Int;
	public final height:Int;
	public final soft:Null<SoftCanvas>;
	#if !helder.soft
	public final device:Null<Device>;
	public final renderer:Null<Renderer>;
	final pass:PassDesc = {colors: [{load: Clear, clear: new helder.gfx.Color(1, 1, 1)}]};
	#end

	public function new(width:Int, height:Int) {
		this.width = width;
		this.height = height;
		#if helder.soft
		soft = new SoftCanvas();
		#else
		if (SoftCanvas.wanted()) {
			soft = new SoftCanvas();
			device = null;
			renderer = null;
		} else {
			soft = null;
			device = Device.create(helder.os.Surface.headless(width, height));
			renderer = new Renderer(device);
		}
		#end
	}

	public var scale(get, set):Float;

	function get_scale():Float
		return #if !helder.soft soft == null ? renderer.scale : #end soft.scale;

	function set_scale(s:Float):Float {
		#if !helder.soft
		if (soft == null) return renderer.scale = s;
		#end
		return soft.scale = s;
	}

	public var snap(get, set):Bool;

	function get_snap():Bool
		return #if !helder.soft soft == null ? renderer.snap : #end soft.snap;

	function set_snap(g:Bool):Bool {
		#if !helder.soft
		if (soft == null) return renderer.snap = g;
		#end
		return soft.snap = g;
	}

	public var groups(get, set):Bool;

	function get_groups():Bool
		return #if !helder.soft soft == null ? renderer.groups : #end soft.groups;

	function set_groups(g:Bool):Bool {
		#if !helder.soft
		if (soft == null) return renderer.groups = g;
		#end
		return soft.groups = g;
	}

	// the ui painted on background (opaque), its pixels read into out (a new buffer when not given)
	public function draw(ui:Ui, ?out:Bytes, background:helder.ui.Color = helder.ui.Color.WHITE):Bytes
		return paint(c -> ui.paint(c), out, background);

	// what f draws on a canvas, the same way
	public function paint(f:Canvas->Void, ?out:Bytes, background:helder.ui.Color = helder.ui.Color.WHITE):Bytes {
		var pixels = out ?? Bytes.alloc(width * height * 4);
		if (soft != null) {
			soft.begin(width, height, background);
			f(soft);
			soft.readPixels(pixels);
			return pixels;
		}
		#if !helder.soft
		var c = pass.colors[0].clear;
		@:privateAccess {
			c.r = background.r / 255;
			c.g = background.g / 255;
			c.b = background.b / 255;
		}
		var enc = device.beginFrame();
		renderer.begin(width, height);
		f(renderer);
		renderer.prepare(enc);
		enc.beginPass(pass);
		renderer.end(enc);
		enc.endPass();
		device.readPixels(pixels);
		device.endFrame();
		#end
		return pixels;
	}

	public function dispose() {
		#if !helder.soft
		if (device != null) device.dispose();
		#end
	}

	// what draws: "soft" or the GPU's back end
	public function toString():String
		return soft != null ? "soft" : #if helder.soft "soft" #else ["GL", "Metal", "D3D11", "WebGPU"][(cast device.backend : Int)] ?? "GPU" #end;
}
