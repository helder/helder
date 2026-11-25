package viewer;

import helder.async.Async;
import helder.media.Player;
import helder.story.StoryText;
import helder.test.Test;
import helder.ui.Clock;
import helder.ui.Ui;
import helder.view.Render;

// Video and audio in the viewer, headless (tests/fixtures/media: two
// silent Vorbis files, helder's own decoder, a picture and a PDF between
// them), on the desktop's shell and the phone's: over a sequence of
// moves (opened, the next, the previous, closed, another folder, another
// file, a PDF), after each at most one player plays, and one that plays
// is the shown file's, in a window, full size. None plays unseen.
function tests() {
	describe("Media", () -> {
		var dir = "tests/fixtures/media";
		for (shell in [{name: "desktop", width: 1100.0, height: 700.0}, {name: "phone", width: 390.0, height: 844.0}])
			test('${shell.name}: at most one plays, the file shown', async(() -> {
				helder.media.VorbisDecoder.link();
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
					return [for (p in @:privateAccess Player.live) if (p.playing) p];
				// (after a move: the invariant; plays: the shown file's player playing once it loaded)
				@:coroutine function step(what:String, plays:Bool) {
					frame();
					var t0 = haxe.Timer.stamp();
					while (haxe.Timer.stamp() - t0 < (plays ? 3 : 0.3) && !(plays && playing().length > 0)) {
						Async.delay(0.01);
						frame();
					}
					var on = playing(), v = MediaView.current;
					assert(on.length <= 1, '$what: ${on.length} playing');
					if (plays) equals(on.length, 1);
					if (on.length == 1)
						assert(x.full.value && v != null && v.player == on[0] && v.ui != null && viewer.media.peek() == viewer.folder.current,
							'$what: playing, not the file shown (${viewer.folder.current}, media "${viewer.media.peek()}", full ${x.full.value})');
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
			})).timeout(30);
	});
}
