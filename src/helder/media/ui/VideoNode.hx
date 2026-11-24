package helder.media.ui;

import helder.media.*;
import helder.ui.Canvas;
import helder.ui.ImageFit;
import helder.ui.Node;
import helder.ui.TextEngine;
import helder.ui.draw.Renderer;
import helder.ui.draw.TextureCanvas;
import helder.view.graph.Graph;
import helder.view.graph.Signal;

// A video in helder.ui (<Video>, MediaTags): its Player's frame shown in
// the content box as fit says (contain by default), its size the
// picture's (upright) where the style gives none. Drawn by helder
// (VideoTexture: the frame turned to RGB in a pass of its own, then drawn
// as a <Scene>'s box is), so that it is in captures, headless frames and
// every compositor. layer: the system's own layer instead, in a window of
// system layers (helder.ui.draw.CaLayers) where the node is a plain
// rectangle (no radius) and the picture upright (SampleLayer:
// AVSampleBufferDisplayLayer, the frames queued with their times on a
// timebase kept to the player's clock; Android's ScLayers: SurfaceLayer,
// MediaCodec rendering onto a SurfaceControl), clipped and moved with its
// scrollers; asked for, not the default, until its colours are measured
// on hardware (a virtual Mac's window server showed them some 30 levels
// off). While it plays the animation clock ticks it (Clock.add): the
// frame due picked, time set. The controls are the app's.
class VideoNode extends Node {
	public var player(default, null):Null<Player>;
	public var fit(default, set):ImageFit = Contain;
	// the system's layer where the window has them (else drawn by helder)
	public var layer = false;
	public var autoplay = false;
	public var loop(default, set) = false;
	public var muted(default, set) = false;
	public var volume(default, set) = 1.0;
	public var rate(default, set) = 1.0;
	// seconds: where it is, how long it is; whether it plays
	public final time:Signal<Float> = Graph.signal(0.0);
	public final duration:Signal<Float> = Graph.signal(0.0);
	public final playing:Signal<Bool> = Graph.signal(false);
	public var onLoaded:Null<Void->Void>;
	public var onEnded:Null<Void->Void>;
	public var onError:Null<String->Void>;
	// each frame it plays, and after a seek or a step: the time
	public var onTime:Null<Float->Void>;

	var texture:Null<VideoTexture>;
	var sample:Null<SampleLayer>;
	var ticking = false;
	var drawn:Null<VideoFrame>;
	var queued = -1;
	var placing = false;
	final id = -(++ids) - 4000000;

	static var ids = 0;

	public function new() {
		super("video");
	}

	// what it plays: a path (in a browser: a URL) or a ByteSource (a file's bytes: a MemorySource; null: nothing)
	public function open(src:Null<Dynamic>) {
		close();
		if (src == null) return;
		// (a path: in a browser a URL, read by Range requests)
		var source:ByteSource = Std.isOfType(src, String) ? #if (hxmc.target == "wasm32-wasi") WebSource.of(src) #else new FileSource(src) #end : src;
		var p = player = Player.open(source);
		p.loop = loop;
		p.muted = muted;
		p.volume = volume;
		p.onLoaded = () -> {
			if (p != player) return;
			duration(p.duration);
			p.rate = rate;
			markDirty();
			if (onLoaded != null) onLoaded();
			if (autoplay) play();
			tick();
		};
		p.onEnded = () -> {
			playing(false);
			if (onEnded != null) onEnded();
		};
		p.onError = e -> if (onError != null) onError(e);
		p.onFrame = tick;
	}

	public function play() {
		var p = player;
		if (p == null) return;
		p.play();
		playing(true);
		tick();
	}

	public function pause() {
		var p = player;
		if (p == null) return;
		p.pause();
		playing(false);
		tick();
	}

	// to t seconds (exact: the frame due then; else its keyframe, sooner)
	public function seek(t:Float, exact = true) {
		var p = player;
		if (p == null) return;
		p.seek(t, exact);
		if (sample != null) sample.flush();
		tick();
	}

	// a frame on (1) or back (-1), paused
	public function step(n:Int) {
		var p = player;
		if (p == null) return;
		p.step(n);
		playing(false);
		if (sample != null && n < 0) sample.flush();
		tick();
	}

	// (the clock's step: the frame due, the time; on while it plays, or a
	// seek or step is under way)
	function tick() {
		if (ticking || ui == null) return;
		ticking = true;
		helder.ui.Clock.addFor(this, _ -> {
			var p = player;
			if (p == null || ui == null) return ticking = false;
			advance(p);
			var going = p.playing || p.shown == null && p.error == null || p.shown != null && Math.abs(p.shown.time - p.time) > 1e-6 && p.time < p.duration;
			if (!going) ticking = false;
			return going;
		});
		ui.requestFrame();
	}

	function advance(p:Player) {
		if (placing) {
			placing = false;
			layerChanged();
			ui.requestFrame();
		}
		var f = sample != null ? sample.feed(p) : p.update();
		var t = p.time;
		if (time.peek() != t) {
			time(t);
			if (onTime != null) onTime(t);
		}
		if (playing.peek() != p.playing) playing(p.playing);
		if (f != drawn) {
			drawn = f;
			// (the system's layer shows it: nothing of helder's drawn again;
			// else a frame asked for: a clock's step alone paints none)
			if (sample == null) {
				layerChanged();
				ui.requestFrame();
			}
		}
	}

	function set_fit(v:ImageFit):ImageFit {
		if (v != fit && ui != null) layerChanged();
		if (sample != null) sample.fit(v);
		return fit = v;
	}

	function set_loop(v:Bool):Bool {
		if (player != null) player.loop = v;
		return loop = v;
	}

	function set_muted(v:Bool):Bool {
		if (player != null) player.muted = v;
		return muted = v;
	}

	function set_volume(v:Float):Float {
		if (player != null) player.volume = v;
		return volume = v;
	}

	function set_rate(v:Float):Float {
		if (player != null && player.loaded) player.rate = v;
		return rate = v;
	}

	// the picture's size upright (0 x 0 before it is loaded)
	public function picture():{width:Int, height:Int} {
		var p = player;
		var v = p == null ? null : p.video;
		if (v == null) return {width: 0, height: 0};
		var turned = v.rotation == 90 || v.rotation == 270;
		return {width: turned ? v.height : v.width, height: turned ? v.width : v.height};
	}

	override public function hasContent():Bool
		return true;

	override public function measureContent(engine:TextEngine, knownWidth:Float, knownHeight:Float, availWidth:Float, availHeight:Float):helder.ui.Size {
		var s = picture(), iw = s.width, ih = s.height;
		var kw = !Math.isNaN(knownWidth), kh = !Math.isNaN(knownHeight);
		if (iw == 0 || ih == 0) return new helder.ui.Size(kw ? knownWidth : 0, kh ? knownHeight : 0);
		return if (kw && kh) new helder.ui.Size(knownWidth, knownHeight) else if (kw) new helder.ui.Size(knownWidth, knownWidth * ih / iw) else if (kh)
			new helder.ui.Size(knownHeight * iw / ih, knownHeight) else new helder.ui.Size(iw, ih);
	}

	@:allow(helder.ui) override function attach(u:Null<helder.ui.Ui>) {
		if (ui != null && ui != u) {
			@:privateAccess ui.natives.remove(this);
			if (sample != null) sample.dispose();
			sample = null;
			systemLayer = null;
			if (texture != null) texture.dispose();
			texture = null;
		}
		super.attach(u);
		if (u != null && @:privateAccess u.natives.indexOf(this) < 0) @:privateAccess u.natives.push(this);
		if (u != null) tick();
	}

	// (the system's layer, where the window has them and it is a plain rectangle)
	@:allow(helder.ui) override function syncNative() {
		var want = layer && ui != null && ui.layered && style.radius == 0 && style.corners == null && player != null && player.video != null
			&& player.video.rotation == 0;
		if (!want && sample != null) {
			sample.dispose();
			sample = null;
			layerChanged();
		} else if (want && sample == null) {
			var sl = sample = SampleLayer.make(this);
			if (sl != null) {
				sl.fit(fit);
				// (the frame shown queued on it at the next tick, which asks
				// for a frame that places the slot: this one, a frame's, is done)
				drawn = null;
				placing = true;
				tick();
			}
		}
		systemLayer = sample == null ? null : sample.slot;
		if (sample != null) sample.slot.shown = visible();
	}

	// (its content box as last painted: a system layer's fit, Android's)
	@:allow(helder.media.ui) final box = [0.0, 0.0];

	override public function paintContent(canvas:Canvas, x:Float, y:Float, width:Float, height:Float) {
		box[0] = width;
		box[1] = height;
		var p = player;
		if (sample != null || p == null || width <= 0 || height <= 0) return;
		var f = p.shown;
		var g = Std.downcast(canvas, TextureCanvas), r = Renderer.of(canvas);
		if (f == null || g == null || r == null) return;
		if (texture == null) texture = new VideoTexture(r.device);
		var t = texture, rotation = p.video == null ? 0 : p.video.rotation;
		if (queued != r.frames) {
			queued = r.frames;
			if (!t.prepare(f, rotation)) return;
			r.beforePass(t.record);
		}
		var c = t.target;
		if (c == null) return;
		// (fit: contain and cover scaled, centred; cover cut by the box)
		var iw = t.width, ih = t.height;
		var k = switch fit {
			case Contain: Math.min(width / iw, height / ih);
			case Cover: Math.max(width / iw, height / ih);
			case _: 1.0;
		}
		var dw = fit == Fill ? width : iw * k, dh = fit == Fill ? height : ih * k;
		var dx = x + (width - dw) / 2, dy = y + (height - dh) / 2, cut = dw > width + 1e-6 || dh > height + 1e-6;
		if (cut) canvas.pushClip(x, y, width, height, style.radius);
		g.gpuTexture(c, id, dx, dy, dw, dh, cut ? 0 : style.radius);
		if (cut) canvas.popClip();
	}

	function close() {
		if (player != null) player.close();
		player = null;
		drawn = null;
		if (sample != null) sample.clear();
	}

	// lets go of the player and what shows it
	public function dispose() {
		close();
		if (texture != null) texture.dispose();
		texture = null;
		if (sample != null) sample.dispose();
		sample = null;
		systemLayer = null;
	}
}
