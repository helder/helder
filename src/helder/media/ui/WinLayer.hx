package helder.media.ui;

#if ((!helder.os || helder.os == "windows") && hxmc.target != "wasm32-wasi" && !helder.soft)
import helder.gfx.d3d11.D3D11;
import helder.gfx.d3d11.D3D11Backend;
import helder.gfx.d3d11.DComp;
import helder.os.windows.Com;
import helder.ui.ImageFit;
import helder.ui.LayerSlot;
import helder.ui.layers.windows.Layers;
import helder.ui.UiWindow;
import hxmc.unsafe.*;

// A video shown by Windows' compositor (SampleLayer's on Windows, in a
// window of system layers: helder.ui.layers.windows.Layers): a DirectComposition
// surface of the picture's size (as Layers' own layers are), the content
// of a visual under the node's slot (Layers.visualFor), scaled and
// centred as fit says, cut by the slot's clip. Each frame is drawn into it
// and committed as it falls due on the player's clock, so DWM shows it at
// its next composition and helder draws nothing for it. The frame is
// turned to RGB on the CPU (as VideoShader turns it: its matrix, range and
// depth) from its planes, Media Foundation's in memory (a DXVA frame's
// read back: the GPU's video processor would save that, later). Until a
// frame was presented the node draws them (showing). null where the window
// has no system layers or before they showed a frame.
@:hxmc.unsafe(gc)
@:access(helder.ui.layers.windows.Layers)
class WinLayer {
	public final slot:LayerSlot;
	public var fit:ImageFit = Contain;
	// whether a frame was presented on it (until then the node draws)
	public var showing(default, null) = false;

	final owner:VideoNode;
	final layers:Layers;
	final device:helder.gfx.Device;
	// (the render thread's: the visual in the slot's, its surface, its size)
	var inner = Ptr.nil();
	var surface = Ptr.nil();
	var failed = false;
	var width = 0;
	var height = 0;
	var last:Null<VideoFrame>;
	final placed = [-1.0, -1.0, -1.0, -1.0];

	public static function make(owner:VideoNode):Null<WinLayer> {
		var p = owner.player, ui = owner.ui;
		if (p == null || p.video == null || ui == null) return null;
		var layers:Null<Layers> = null;
		for (w in @:privateAccess UiWindow.open)
			if (w.ui == ui && w.compositor != null) layers = Std.downcast(w.compositor.layers, Layers);
		if (layers == null || layers.frames == 0) return null;
		var v = layers.visualFor();
		if (v.isNull()) return null;
		return new WinLayer(owner, layers, v);
	}

	function new(owner:VideoNode, layers:Layers, visual:Ptr) {
		this.owner = owner;
		this.layers = layers;
		device = layers.device;
		slot = new LayerSlot(visual);
	}

	// (each tick: the frame due presented once, the picture placed in the box)
	public function feed(p:Player):Null<VideoFrame> {
		var f = p.update();
		if (f != null && f != last) {
			last = f;
			if (present(f)) showing = true;
		}
		place(p);
		return f;
	}

	// (f in RGBA onto the surface on the render thread, committed: the
	// surface (made, or made again at its size, the first time) drawn whole)
	function present(f:VideoFrame):Bool {
		var px = f.pixels(), w = f.width, h = f.height;
		if (px.length == 0 || w <= 0 || h <= 0) return false;
		var rgba:Ptr<UInt8> = LibC.malloc(w * h * 4);
		convert(f, px, rgba);
		var visual = slot.handle, dc = layers.dev;
		device.inOrder(r -> {
			var d3d:D3D11Backend = cast r.impl;
			if (surface.isNull() || w != width || h != height) made(dc, visual, w, h);
			if (!surface.isNull()) Arena.scoped(a -> {
				var out:Ptr<Ptr> = a.alloc(8), at:Ptr<Int32> = a.alloc(8), box:Ptr<Int32> = a.alloc(24);
				var hr = IDCompositionSurface.BeginDraw(surface, Ptr.nil(), IID.ID3D11Texture2D, out, at);
				if (hr < 0) {
					if (!failed) Sys.println('helder.media: the video\'s layer not drawn (BeginDraw 0x${StringTools.hex(hr, 8)})');
					failed = true;
					return;
				}
				// (D3D11_BOX: where the update is in the surface's texture, which may be an atlas)
				box[0] = at[0];
				box[1] = at[1];
				box[2] = 0;
				box[3] = at[0] + w;
				box[4] = at[1] + h;
				box[5] = 1;
				ID3D11DeviceContext.UpdateSubresource(@:privateAccess d3d.context, out.value, 0, cast box, rgba, w * 4, 0);
				Com.release(out.value);
				IDCompositionSurface.EndDraw(surface);
				IDCompositionDevice.Commit(dc);
			});
			LibC.free(rgba);
		});
		return true;
	}

	// (the surface of w x h, the content of a visual in the slot's)
	function made(dc:Ptr, visual:Ptr, w:Int, h:Int) {
		drop(visual, dc);
		Arena.scoped(a -> {
			var out:Ptr<Ptr> = a.alloc(8);
			// (premultiplied, as Layers' layers are: every pixel opaque)
			var hr = IDCompositionDevice.CreateSurface(dc, w, h, D3D.FORMAT_R8G8B8A8_UNORM, D3D.ALPHA_MODE_PREMULTIPLIED, out);
			if (hr < 0) {
				Sys.println('helder.media: no surface for the video\'s layer (CreateSurface 0x${StringTools.hex(hr, 8)})');
				return;
			}
			surface = out.value;
			if (IDCompositionDevice.CreateVisual(dc, out) < 0) return;
			inner = out.value;
			IDCompositionVisual.SetContent(inner, surface);
			IDCompositionVisual.AddVisual(visual, inner, 1, Ptr.nil());
			width = w;
			height = h;
			placed[0] = -1;
		});
	}

	// (the render thread's: the visual and the surface let go)
	function drop(visual:Ptr, dc:Ptr) {
		if (!inner.isNull()) IDCompositionVisual.RemoveVisual(visual, inner);
		Com.release(inner);
		Com.release(surface);
		inner = surface = Ptr.nil();
		IDCompositionDevice.Commit(dc);
	}

	// (Y'CbCr to RGBA as VideoShader turns it: the frame's matrix over the
	// samples read as a texture reads them, chroma sited left (between two
	// across, on the odd columns))
	static function convert(f:VideoFrame, px:haxe.io.Bytes, out:Ptr<UInt8>) {
		var m = VideoTexture.matrix(f), w = f.width, h = f.height, cw = (w + 1) >> 1;
		var deep = f.bits > 8, scale = deep ? 1 / 65535 : 1 / 255, bs = deep ? 2 : 1, base = w * h * bs;
		inline function sample(i:Int):Float
			return (deep ? px.getUInt16(i * 2) : px.get(i)) * scale;
		inline function chroma(x:Int, y:Int, c:Int):Float
			return sample(Std.int(base / bs) + (y * cw + x) * 2 + c);
		inline function level(v:Float):Int
			return v <= 0 ? 0 : v >= 1 ? 255 : Std.int(v * 255 + 0.5);
		var r = m[0], g = m[1], b = m[2];
		for (y in 0...h) {
			var cy = y >> 1;
			for (x in 0...w) {
				var l = sample(y * w + x), cx = x >> 1, u = chroma(cx, cy, 0), v = chroma(cx, cy, 1);
				if (x & 1 == 1 && cx + 1 < cw) {
					u = (u + chroma(cx + 1, cy, 0)) / 2;
					v = (v + chroma(cx + 1, cy, 1)) / 2;
				}
				var o = (y * w + x) * 4;
				out[o] = level(r.x * l + r.y * u + r.z * v + r.w);
				out[o + 1] = level(g.x * l + g.y * u + g.z * v + g.w);
				out[o + 2] = level(b.x * l + b.y * u + b.z * v + b.w);
				out[o + 3] = 255;
			}
		}
	}

	// (the picture in the slot's box, in pixels: scaled and centred as fit says)
	function place(p:Player) {
		var v = p.video, u = owner.ui;
		if (v == null || u == null || width == 0 || height == 0) return;
		var bw = owner.box[0] * u.scale, bh = owner.box[1] * u.scale;
		var kx = bw / width, ky = bh / height;
		switch fit {
			case Contain: kx = ky = Math.min(kx, ky);
			case Cover: kx = ky = Math.max(kx, ky);
			case _:
		}
		var x = Math.round((bw - width * kx) / 2), y = Math.round((bh - height * ky) / 2);
		if (placed[0] == x && placed[1] == y && placed[2] == kx && placed[3] == ky) return;
		placed[0] = x;
		placed[1] = y;
		placed[2] = kx;
		placed[3] = ky;
		var dc = layers.dev;
		device.inOrder(_ -> {
			if (inner.isNull()) return;
			Arena.scoped(a -> {
				var m:Ptr<Float32> = a.alloc(24);
				m[0] = kx;
				m[1] = 0;
				m[2] = 0;
				m[3] = ky;
				m[4] = x;
				m[5] = y;
				IDCompositionVisual.SetTransform(inner, m);
			});
			IDCompositionDevice.Commit(dc);
		});
	}

	// (the visual out of the slot's and the surface let go; the slot's
	// visual a second later, once Layers' commit no longer names it)
	public function dispose() {
		var visual = slot.handle, dc = layers.dev, d = device;
		d.inOrder(_ -> drop(visual, dc));
		helder.ui.Clock.after(1, () -> d.inOrder(_ -> Com.release(visual)));
	}
}
#end
