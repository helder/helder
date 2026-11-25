package viewer;

import helder.media.ui.VideoNode;
import helder.ui.Event;
import helder.ui.ImageNode;
import helder.ui.Node;
import helder.ui.TextNode;
import helder.view.graph.Graph.*;

// A video or audio file in the viewer (Viewer.media): the picture filling
// the window as an image does (contained), its controls along the bottom:
// in the look's colours: play and pause, the scrub bar (Scrub: a drag
// seeks to keyframes as it goes and exactly where it ends; a thumbnail of
// the keyframe under the pointer above it: Thumbs), the time and the
// duration, mute and the volume.
// Space plays and pauses, , and . (and Left and Right) step a frame, M
// mutes (ViewerActions' media context). Nodes of its own set as the
// player goes (onTime), not markup: a reactive tree of them cost the
// program some 30 KB more.
class MediaView {
	// the node shown (the shell's actions reach it), null while none
	public static var current(default, null):Null<VideoNode>;

	public static function make(viewer:Viewer, files:Files):Node {
		// (the look's colours: light or dark as the window)
		var t = helder.ui.controls.Look.ref;
		var root = box({position: Absolute, left: 0, top: 0, right: 0, bottom: 0});
		var video = current = new VideoNode(), thumbs:Null<Thumbs> = null;
		video.autoplay = true;
		video.style.set({position: Absolute, left: 0, top: 0, right: 0, bottom: 0});
		root.append(video);
		// (an audio file: its name where the picture would be)
		var name = new TextNode("");
		name.style.set({fontSize: 17, color: t.fg3});
		var audio = box({position: Absolute, left: 0, top: 0, right: 0, bottom: 0, alignItems: Center, justify: Center, pointerEvents: None, display: None});
		audio.append(name);
		root.append(audio);
		var bar = box({position: Absolute, left: 0, right: 0, bottom: 0, padding: [6, 12, 10, 12], rowGap: 6, background: t.raised, borderColor: t.line,
			borders: [1, 0, 0, 0]});
		var scrub = new Scrub((at, exact) -> {
			video.seek(at, exact);
			if (refresh != null) refresh();
		});
		var thumb = box({position: Absolute, bottom: 18, padding: 3, radius: 6, background: t.raised, borderWidth: 1, borderColor: t.edge,
			pointerEvents: None, alignItems: Center, rowGap: 2, display: None});
		var picture = new ImageNode();
		picture.style.set({width: Thumbs.WIDTH, radius: 3});
		var at = new TextNode("");
		at.style.set({color: t.fg2, fontSize: 11});
		thumb.append(picture);
		thumb.append(at);
		scrub.node.append(thumb);
		var play = new MediaIcon("play"), mute = new MediaIcon("sound"), clockText = new TextNode("0:00 / 0:00");
		clockText.style.color = t.fg2;
		var volume = box({width: 80, height: 14, justify: Center}), levels = box({height: 4, radius: 2, background: t.fill});
		var level = box({height: 4, radius: 2, background: t.fg, width: 80});
		levels.append(level);
		volume.append(levels);
		var row = box({direction: Row, alignItems: Center, columnGap: 10});
		row.append(button(play, "Play", toggle));
		row.append(clockText);
		row.append(box({grow: 1}));
		row.append(button(mute, "Mute", toggleMute));
		row.append(volume);
		bar.append(scrub.node);
		bar.append(row);
		root.append(bar);

		// (what the controls show, as the player goes: its time, not the
		// signal's, whose write lands after onTime)
		function shown() {
			var p = video.player, d = p == null ? 0.0 : p.duration, t = p == null ? 0.0 : p.time;
			scrub.duration = d;
			scrub.show(t);
			clockText.text = clock(scrub.time) + " / " + clock(d);
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
			thumbs = path == "" ? null : new Thumbs(() -> files.open(path));
			name.text = haxe.io.Path.withoutDirectory(path);
			video.open(path == "" ? null : files.open(path));
		});
		// (made again each time a file is shown (Show's children): the one
		// left lets go of its player, which else plays on unseen)
		onCleanup(() -> {
			video.dispose();
			if (thumbs != null) thumbs.close();
			thumbs = null;
			if (current == video) current = null;
		});

		// (the thumbnail where the pointer is)
		scrub.hover = k -> {
			var p = video.player, th = thumbs;
			if (p == null || p.video == null || th == null) return;
			thumb.style.left = scrub.node.width * k - Thumbs.WIDTH / 2 - 3;
			th.at(k * p.duration, img -> {
				picture.image = img;
				at.text = clock(k * p.duration);
				thumb.style.display = img == null ? None : Flex;
			});
		};
		scrub.node.onPointerLeave = _ -> thumb.style.display = None;
		var dragging = false;
		function ratio(e:Event):Float
			return volume.width <= 0 ? 0 : Math.max(0, Math.min(1, e.localX / volume.width));
		volume.onPointerDown = e -> {
			volume.capture();
			dragging = true;
			setVolume(ratio(e));
		};
		volume.onPointerMove = e -> if (dragging) setVolume(ratio(e));
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
		icon.style.set({width: 18, height: 18, color: helder.ui.controls.Look.ref.fg});
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
