import helder.asset.Asset;
import helder.media.MemorySource;
import helder.media.ui.VideoNode;
import helder.ui.Clock;
import helder.ui.UiWindow;
import helder.ui.UiWindow.Surface;
import helder.view.*;
import hxmc.unsafe.*;

// A <video> on Android (android.sh): quads.mp4's flat quadrants in a box,
// drawn by helder or, with debug.helder.video=layer (setprop), on its
// system layer (MediaCodec onto a SurfaceControl; late: asked for once
// paused, as a slow device's layers start); played until six frames
// were shown, then sought to 0.25 s and paused for the script's
// screencap, its box in pixels and whether the system layer showed it
// said (still.mjs reads the quadrants' centres there).
@:hxmc.unsafe(gc)
class VideoStillCheck implements Markup {
	static inline var FRAMES = 6;

	static function say(s:String)
		Sys.println("VideoStillCheck: " + s);

	static function main() {
		var v = Mem.stack(96);
		Props.__system_property_get(Mem.cstr("debug.helder.video"), v);
		var mode = (cast v : CString).toString(), late = mode == "late", layer = mode == "layer";
		// (debug.helder.layers: HELDER_SYSTEM_LAYERS, 0 the textured compositor)
		Props.__system_property_get(Mem.cstr("debug.helder.layers"), v);
		if ((cast v : CString).toString() != "") Props.setenv(Mem.cstr("HELDER_SYSTEM_LAYERS"), v, 1);
		var node:Null<VideoNode> = null, shown = 0, last = -1.0, phase = 0, at = 0.0, ticks = 0;
		// (whether its system layer shows the frames: a slow emulator's
		// layers start late, the node drawing them until then)
		function onLayer(n:VideoNode):Bool {
			var s = @:privateAccess n.sample;
			return s != null && s.showing;
		}
		// (whether a system layer may come: asked for, in a window of them)
		function wants(n:VideoNode):Bool
			return layer && @:privateAccess n.ui.layered;
		// (each frame: played until FRAMES were shown (and, asked for, its
		// layer shows them), sought and paused, the frame at 0.2 shown for a
		// few frames, said; by frames, not time: CI's emulator draws a few a second)
		function step(_:Float):Bool {
			var n = node, now = haxe.Timer.stamp();
			var p = n == null ? null : n.player;
			if (p == null || !p.loaded()) return true;
			var f = p.shown;
			switch phase {
				case 0:
					n.play();
					at = now;
					phase = 1;
				case 1:
					if (f != null && f.time != last) {
						last = f.time;
						shown++;
					}
					if (shown >= FRAMES && (!wants(n) || onLayer(n) || now - at > 10) || now - at > 30) {
						say('played: $shown frames shown in ${Math.round((now - at) * 10) / 10} s, on the system layer ${onLayer(n)}');
						n.pause();
						n.seek(0.25);
						// (late: the layer asked for once paused, as a slow device's starts)
						if (late) {
							n.layer = layer = true;
							@:privateAccess n.syncNative();
						}
						phase = 2;
						ticks = 0;
						at = now;
					}
				case 2:
					// (the frame at 0.2 shown, where it is shown, for a few frames)
					if (f != null && f.time == 0.2 && (!wants(n) || onLayer(n) || now - at > 10)) ticks++ else ticks = 0;
					if (ticks >= 10 || now - at > 30) {
						var k = n.ui.scale;
						say('box at ${Math.round(n.absX * k)} ${Math.round(n.absY * k)} ${Math.round(n.width * k)} ${Math.round(n.height * k)}, time ${f == null ? -1 : f.time}, on the system layer ${onLayer(n)}');
						say("still");
						at = now;
						phase = 3;
					}
				case 3 if (now - at > 3):
					say("done");
					Sys.exit(0);
				case _:
			}
			n.ui.requestFrame();
			return true;
		}
		UiWindow.run(<Surface title="VideoStillCheck" width={480} height={800} background="#333333">
			<view flexGrow={1} paddingTop={200} paddingLeft={40} overflow="scroll">
				<video src={new MemorySource(Asset.embed("tests/media/apple/quads.mp4"))} width={320} height={240} layer={layer} muted={true} loop={true}
					onError={e -> say('error $e')} ref={v -> {
						node = v;
						Clock.addFor(v, step);
					}}/>
			</view>
		</Surface>);
	}
}

@:hxmc.c @:hxmc.fast extern class Props {
	static function __system_property_get(name:Ptr, value:Ptr):Int;
	static function setenv(name:Ptr, value:Ptr, overwrite:Int):Int;
}
