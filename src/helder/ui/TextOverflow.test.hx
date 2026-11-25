package helder.ui;

import helder.story.StoryText;
import helder.test.Test;
import helder.view.Render;

// text-overflow: middle: a text too long for its lines keeps its start and
// its end ("…" between, the extension and four characters before it), its
// start as long as fits; one that fits whole, whole; one line by default
// (StoryText's characters: half the font's size wide)
function tests() {
	describe("TextOverflow", () -> {
		// (what a text node shows at a width, line by line)
		function shown(text:String, width:Float, lines:Int):String {
			var ui = new Ui(new StoryText(), 400, 300);
			var dispose = Render.render(Fixture.text(text, width, lines), ui.root);
			ui.update();
			var n:TextNode = cast ui.root.find("name");
			var out = new Map<Int, String>();
			for (r in n.laidOut().runs(width, Left))
				for (i in 0...r.text.length) {
					var y = Math.round(r.y[i]);
					out.set(y, (out.get(y) ?? "") + r.text[i]);
				}
			var keys = [for (k in out.keys()) k];
			keys.sort(Reflect.compare);
			dispose();
			return [for (k in keys) out.get(k)].join("|");
		}
		test("the start and the end kept, in two lines", () -> {
			equals(shown("E07-uitzonderingenregister.xlsx", 60, 2), "E07-uitzonde|ri…ster.xlsx");
			equals(shown("E07-uitzonderingenregister.xlsx", 60, 1), "E0\u2026ster.xlsx");
		});
		test("whole when it fits; no extension: its last six", () -> {
			equals(shown("photo.jpg", 60, 2), "photo.jpg");
			equals(shown("a-very-long-name-without-a-dot", 60, 1), "a-ver\u2026-a-dot");
		});
	});
}

private class Fixture implements helder.view.Markup {
	public static function text(s:String, width:Float, lines:Int)
		return <view><text tag="name" width={width} font-size={10} max-lines={lines} text-overflow="middle">{s}</text></view>;
}
