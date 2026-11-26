package viewer;

import helder.async.Async;
import helder.media.Player;
import helder.story.StoryText;
import helder.test.Test;
import helder.ui.Clock;
import helder.ui.Ui;
import helder.view.Render;

// Video and audio in the viewer, headless (tests/fixtures/media: two
// silent Vorbis files, helder's own decoder and no audio output: they
// play on every system, libavcodec or a sound device or none; a picture
// and a PDF between them), on the desktop's shell and the phone's: over a sequence of
// moves (opened, the next, the previous, closed, another folder, another
// file, a PDF), after each at most one player plays, and one that plays
// is the shown file's, in a window, full size. None plays unseen.
function tests() {
	describe("Media", () -> {
		var dir = "tests/fixtures/media";
		for (shell in [{name: "desktop", width: 1100.0, height: 700.0}, {name: "phone", width: 390.0, height: 844.0}])
			test('${shell.name}: at most one plays, the file shown', async(() -> {
				// (helder's own Vorbis decoder, no output: they play on every system, a sound device or none)
				helder.media.VorbisDecoder.link();
				@:privateAccess Player.quiet = true;
				var x = Fixtures.explorer([dir, "tests/fixtures/folder"]), viewer = x.viewer;
				var ui = new Ui(new StoryText(), shell.width, shell.height);
				ui.scrollDuration = 0;
				Render.render(Shell.view(x), ui.root);
				Shell.attach(ui.root, x);
				function frame() {
					for (_ in 0...2) {
						helder.view.graph.Graph.flush();
						ui.update();
						Clock.finish();
					}
				}
				function playing():Array<Player>
					return [for (p in @:privateAccess Player.live) if (p.playing()) p];
				// (after a move: the invariant; plays: the shown file's player playing once it loaded)
				// (waiting for it to play, given up once its player failed)
				function failed():Bool {
					var p = viewer.video?.player;
					return p != null && p.error() != null;
				}
				@:coroutine function step(what:String, plays:Bool) {
					frame();
					var t0 = haxe.Timer.stamp();
					while (haxe.Timer.stamp() - t0 < (plays ? 3 : 0.3) && !(plays && (playing().length > 0 || failed()))) {
						Async.delay(0.01);
						frame();
					}
					if (plays && failed()) assert(false, '$what: ${viewer.video.player.error()}');
					var on = playing(), v = viewer.video;
					assert(on.length <= 1, '$what: ${on.length} playing');
					if (plays) equals(on.length, 1);
					if (on.length == 1)
						assert(x.full.value && v != null && v.player == on[0] && v.ui != null && viewer.media.peek() == viewer.folder.current,
							'$what: playing, not the file shown (${viewer.folder.current}, media "${viewer.media.peek()}", full ${x.full.value})');
				}
				// (where they are no media here (no system decoder, Vorbis's not linked): none plays, nothing more)
				if (!FolderModel.isMedia("a.webm")) {
					x.start('$dir/a.webm');
					frame();
					assert(playing().length == 0, "no media here: none plays");
					@:privateAccess Player.quiet = false;
					return;
				}
				x.start('$dir/a.webm');
				step("a.webm opened", true);
				x.perform(Next);
				equals(viewer.folder.name, "b.png");
				step("the next, a picture", false);
				x.perform(Previous);
				equals(viewer.folder.name, "a.webm");
				step("the previous, a.webm again", true);
				x.perform(Close);
				equals(x.full.value, false);
				step("closed", false);
				x.start('$dir/a.webm');
				step("a.webm once more", true);
				x.browser.go("tests/fixtures/folder");
				step("another folder", false);
				x.start('$dir/c.mka');
				step("another media file", true);
				x.perform(Next);
				equals(viewer.folder.name, "d.pdf");
				step("a PDF", false);
				x.perform(Close);
				step("closed", false);
				equals(playing().length, 0);
				@:privateAccess Player.quiet = false;
			})).timeout(30);
		// (the media bar, a PDF's column and a picture above the status line, not under it, at any size; the status line off: the bar at the window's foot)
		for (size in [{width: 1100.0, height: 700.0}, {width: 800.0, height: 500.0}, {width: 1600.0, height: 1000.0}, {width: 390.0, height: 844.0}])
			test('${size.width}x${size.height}: the media bar, a PDF and a picture clear of the status line', () -> {
				helder.media.VorbisDecoder.link();
				@:privateAccess Player.quiet = true;
				var x = Fixtures.explorer([dir]), viewer = x.viewer;
				var ui = new Ui(new StoryText(), size.width, size.height);
				ui.scrollDuration = 0;
				Render.render(Shell.view(x), ui.root);
				Shell.attach(ui.root, x);
				function frame() {
					for (_ in 0...2) {
						helder.view.graph.Graph.flush();
						ui.update();
						Clock.finish();
					}
				}
				function clear(what:String, tag:String) {
					for (on in [false, true]) {
						viewer.statusOn(on);
						frame();
						var n = ui.root.find(tag), s = ui.root.find("status");
						assert(n != null, '$what: no $tag');
						var b = n.windowBounds();
						assert(b.height > 0 && b.y + b.height <= size.height + 0.5, '$what: $tag at ${b.y}, ${b.height} high');
						if (!on) {
							assert(s == null, '$what: a status line, off');
							continue;
						}
						assert(s != null, '$what: no status line');
						var t = s.windowBounds();
						assert(b.y + b.height <= t.y + 0.5, '$what, the status line on: $tag to ${b.y + b.height}, the status line from ${t.y}');
					}
				}
				x.start('$dir/a.webm');
				frame();
				if (FolderModel.isMedia("a.webm")) clear("a.webm", "media-bar");
				x.start('$dir/d.pdf');
				frame();
				clear("d.pdf", "pdf-scroll");
				x.start('$dir/b.png');
				frame();
				clear("b.png", "photo");
				viewer.statusOn(false);
				x.perform(Close);
				frame();
				@:privateAccess Player.quiet = false;
			});
	});
}
