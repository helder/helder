package viewer;

import helder.media.ui.VideoNode;
import helder.ui.Event;
import helder.ui.ImageNode;
import helder.ui.Node;
import helder.ui.TextNode;
import helder.view.graph.Graph.*;

// A video or audio file in the viewer (Viewer.media): the picture filling
// the window as an image does (contained), its controls along the bottom:
// play and pause, the scrub bar (a drag seeks to keyframes as it goes and
// exactly where it ends; a thumbnail of the keyframe under the pointer
// above it: Thumbs), the time and the duration, mute and the volume.
// Space plays and pauses, , and . (and Left and Right) step a frame, M
// mutes (ViewerActions' media context). Nodes of its own set as the
// player goes (onTime), not markup: a reactive tree of them cost the
// program some 30 KB more.
class MediaView {
	// the node shown (the shell's actions reach it), null while none
	public static var current(default, null):Null<VideoNode>;
	static var thumbs:Null<Thumbs>;

	public static function make(viewer:Viewer):Node {
		var root = box({position: Absolute, left: 0, top: 0, right: 0, bottom: 0});
		var video = current = new VideoNode();
		video.autoplay = true;
		video.style.set({position: Absolute, left: 0, top: 0, right: 0, bottom: 0});
		root.append(video);
		// (an audio file: its name where the picture would be)
		var name = new TextNode("");
		name.style.set({fontSize: 17, color: 0xFFA1A1AA});
		var audio = box({position: Absolute, left: 0, top: 0, right: 0, bottom: 0, alignItems: Center, justify: Center, pointerEvents: None, display: None});
		audio.append(name);
		root.append(audio);
		var bar = box({position: Absolute, left: 0, right: 0, bottom: 0, padding: [6, 12, 10, 12], rowGap: 6, background: 0xB3000000});
		var scrub = box({height: 14, justify: Center}), track = box({height: 4, radius: 2, background: 0xFF3F3F46});
		var done = box({height: 4, radius: 2, background: 0xFFE4E4E7, width: 0});
		track.append(done);
		scrub.append(track);
		var thumb = box({position: Absolute, bottom: 18, padding: 3, radius: 6, background: 0xFF232326, borderWidth: 1, borderColor: 0xFF3F3F46,
			pointerEvents: None, alignItems: Center, rowGap: 2, display: None});
		var picture = new ImageNode();
		picture.style.set({width: Thumbs.WIDTH, radius: 3});
		var at = new TextNode("");
		at.style.set({color: 0xFFD4D4D8, fontSize: 11});
		thumb.append(picture);
		thumb.append(at);
		scrub.append(thumb);
		var play = new MediaIcon("play"), mute = new MediaIcon("sound"), clockText = new TextNode("0:00 / 0:00");
		clockText.style.color = 0xFFD4D4D8;
		var volume = box({width: 80, height: 14, justify: Center}), levels = box({height: 4, radius: 2, background: 0xFF3F3F46});
		var level = box({height: 4, radius: 2, background: 0xFFE4E4E7, width: 80});
		levels.append(level);
		volume.append(levels);
		var row = box({direction: Row, alignItems: Center, columnGap: 10});
		row.append(button(play, "Play", toggle));
		row.append(clockText);
		row.append(box({grow: 1}));
		row.append(button(mute, "Mute", toggleMute));
		row.append(volume);
		bar.append(scrub);
		bar.append(row);
		root.append(bar);

		// (what the controls show, as the player goes)
		function shown() {
			var p = video.player, d = p == null ? 0.0 : p.duration, t = video.time.peek();
			done.style.width = d > 0 ? scrub.width * Math.min(1, t / d) : 0;
			clockText.text = clock(t) + " / " + clock(d);
			play.kind = video.playing.peek() ? "pause" : "play";
			mute.kind = video.muted ? "muted" : "sound";
			level.style.width = video.muted ? 0 : 80 * video.volume;
		}
		refresh = shown;
		video.onTime = _ -> shown();
		video.onLoaded = () -> {
			var p = video.player, v = p.video, a = p.audio, s = video.picture();
			audio.style.display = v == null ? Flex : None;
			viewer.described(v == null ? clock(p.duration) : '${s.width}×${s.height} · ${clock(p.duration)}',
				[for (t in [v, a]) if (t != null) Std.string(t.codec)].join(" · "));
			shown();
		};
		video.onError = e -> viewer.described("", e);
		effect(() -> video.playing(), _ -> shown());
		renderEffect(() -> viewer.media(), path -> {
			if (thumbs != null) thumbs.close();
			thumbs = path == "" ? null : new Thumbs(path);
			name.text = haxe.io.Path.withoutDirectory(path);
			video.open(path == "" ? null : path);
		});

		// (the scrub bar: a drag seeks to keyframes, its end exactly; the thumbnail where the pointer is)
		var dragging = false;
		function ratio(e:Event, n:Node):Float
			return n.width <= 0 ? 0 : Math.max(0, Math.min(1, e.localX / n.width));
		function seek(e:Event, exact:Bool) {
			var p = video.player;
			if (p != null) video.seek(ratio(e, scrub) * p.duration, exact);
		}
		scrub.onPointerDown = e -> {
			scrub.capture();
			dragging = true;
			seek(e, false);
		};
		scrub.onPointerUp = e -> {
			dragging = false;
			seek(e, true);
		};
		scrub.onPointerMove = e -> {
			if (dragging) seek(e, false);
			var p = video.player, th = thumbs, k = ratio(e, scrub);
			if (p == null || p.video == null || th == null) return;
			thumb.style.left = scrub.width * k - Thumbs.WIDTH / 2 - 3;
			th.at(k * p.duration, img -> {
				picture.image = img;
				at.text = clock(k * p.duration);
				thumb.style.display = img == null ? None : Flex;
			});
		};
		scrub.onPointerLeave = _ -> thumb.style.display = None;
		volume.onPointerDown = e -> {
			volume.capture();
			dragging = true;
			setVolume(ratio(e, volume));
		};
		volume.onPointerMove = e -> if (dragging) setVolume(ratio(e, volume));
		volume.onPointerUp = _ -> dragging = false;
		return root;
	}

	static var refresh:Null<Void->Void>;

	static function clock(t:Float):String {
		var s = Std.int(Math.max(0, t)), m = Std.int(s / 60), h = Std.int(m / 60);
		var ss = StringTools.lpad(Std.string(s % 60), "0", 2);
		return h > 0 ? '$h:${StringTools.lpad(Std.string(m % 60), "0", 2)}:$ss' : '$m:$ss';
	}

	static function box(s:helder.ui.StyleProps):Node {
		var n = new Node();
		n.style.set(s);
		return n;
	}

	static function button(icon:MediaIcon, label:String, press:Void->Void):Node {
		var b = box({width: 28, height: 28, radius: 6, alignItems: Center, justify: Center});
		b.semantics = {role: helder.ui.access.Role.Button, label: label};
		b.focusable = true;
		b.onActivate = _ -> press();
		icon.style.set({width: 18, height: 18, color: 0xFFE4E4E7});
		b.append(icon);
		return b;
	}

	static function setVolume(v:Float) {
		var n = current;
		if (n == null) return;
		n.volume = v;
		n.muted = false;
		if (refresh != null) refresh();
	}

	// (the media context's actions: the shell's)
	public static function toggle() {
		var n = current;
		if (n == null) return;
		if (n.playing.peek()) n.pause() else n.play();
	}

	public static function step(k:Int)
		if (current != null) current.step(k);

	public static function toggleMute() {
		var n = current;
		if (n == null) return;
		n.muted = !n.muted;
		if (refresh != null) refresh();
	}
}
