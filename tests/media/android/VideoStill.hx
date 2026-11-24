import helder.asset.Asset;
import helder.media.MemorySource;
import helder.media.ui.MediaTags.*;
import helder.media.ui.VideoNode;
import helder.ui.Clock;
import helder.ui.draw.UiWindow;
import helder.ui.draw.UiWindow.Surface;
import helder.view.*;
import hxmc.unsafe.*;

// A <Video> on Android (android.sh): quads.mp4's flat quadrants in a box,
// drawn by helder or, with debug.helder.video=layer (setprop), on its
// system layer (MediaCodec onto a SurfaceControl); played for a second and
// a half (the frames it showed counted), then sought to 0.25 s and paused
// for the script's screencap, its box in pixels said (still.mjs reads the
// quadrants' centres there).
@:hxmc.unsafe(gc)
class VideoStill implements Markup {
	static function say(s:String)
		Sys.println("VideoStill: " + s);

	static function main() {
		var v = Mem.stack(96);
		Props.__system_property_get(Mem.cstr("debug.helder.video"), v);
		var layer = (cast v : CString).toString() == "layer";
		// (debug.helder.layers: HELDER_SYSTEM_LAYERS, 0 the textured compositor)
		Props.__system_property_get(Mem.cstr("debug.helder.layers"), v);
		if ((cast v : CString).toString() != "") Props.setenv(Mem.cstr("HELDER_SYSTEM_LAYERS"), v, 1);
		var node:Null<VideoNode> = null, shown = 0, last = -1.0, phase = 0, at = 0.0;
		// (each frame, by the monotonic clock: played, sought and paused, said)
		function step(_:Float):Bool {
			var n = node, now = haxe.Timer.stamp();
			var p = n == null ? null : n.player;
			if (p == null || !p.loaded) return true;
			var f = p.shown;
			if (phase == 1 && f != null && f.time != last) {
				last = f.time;
				shown++;
			}
			switch phase {
				case 0:
					n.play();
					at = now;
					phase = 1;
				case 1 if (now - at > 1.5):
					n.pause();
					n.seek(0.25);
					say('played: $shown frames shown in 1.5 s, on the system layer ${@:privateAccess n.sample != null}');
					at = now;
					phase = 2;
				case 2 if (now - at > 1):
					var k = n.ui.scale;
					say('box at ${Math.round(n.absX * k)} ${Math.round(n.absY * k)} ${Math.round(n.width * k)} ${Math.round(n.height * k)}, time ${f == null ? -1 : f.time}');
					say("still");
					at = now;
					phase = 3;
				case 3 if (now - at > 3):
					say("done");
					Sys.exit(0);
				case _:
			}
			return true;
		}
		UiWindow.run(<Surface title="VideoStill" width={480} height={800} background="#333333">
			<view grow={1} padding-top={200} padding-left={40} overflow="scroll">
				<Video src={new MemorySource(Asset.embed("tests/media/apple/quads.mp4"))} width={320} height={240} layer={layer} muted={true} loop={true}
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
