package helder.ui;

import helder.test.Test;
import helder.ui.draw.DrawText;
import helder.view.Render;

// A glow on text is text-shadow's (Style.textShadow): the glyphs' shapes,
// blurred, around the letters alone; shadow is the box's (CSS's
// box-shadow), on a text its line's whole box (the studio's guide says so:
// apps/studio/guide/ui.md)
function tests() {
	describe("Shadow", () -> {
		#if (target.name == "hxmc")
		// (its cyan channel, 240 by 60 on black: the text's own white is cyan too)
		function cyan(kind:Int):Array<Int> {
			var ui = new Ui(new DrawText(), 240, 60);
			var dispose = Render.render(kind == 0 ? Fixture.plain() : kind == 1 ? Fixture.textShadow() : Fixture.boxShadow(), ui.root);
			ui.update();
			var c = new helder.ui.draw.soft.SoftCanvas();
			c.begin(240, 60, 0xFF000000);
			ui.paint(c);
			dispose();
			return [for (i in 0...240 * 60) c.frame.pixels.get(i * 4 + 2)];
		}
		test("text-shadow glows around the glyphs; shadow is the box's", () -> {
			var plain = cyan(0), text = cyan(1), box = cyan(2);
			// (where each lit what the plain text did not: x of the pixels)
			function lit(px:Array<Int>):Array<Int>
				return [for (i in 0...px.length) if (px[i] > plain[i] + 20) i % 240];
			var t = lit(text), b = lit(box);
			assert(t.length > 20, 'a glow: ${t.length} pixels');
			// ("Hi" from x 12 to about 28: its glow within 8 of it; the box's along its whole width)
			equals(Lambda.fold(t, Math.max, 0) < 50, true);
			equals(Lambda.fold(b, Math.max, 0) > 200, true);
		});
		#end
	});
}

private class Fixture implements helder.view.Markup {
	public static function plain()
		return <view width={240} height={60} padding="20 12" background="#000000">
			<text color="#ffffff" font-size={16}>Hi</text>
		</view>;

	public static function textShadow()
		return <view width={240} height={60} padding="20 12" background="#000000">
			<text color="#ffffff" font-size={16} text-shadow="0 0 8 #22d3ee">Hi</text>
		</view>;

	public static function boxShadow()
		return <view width={240} height={60} padding="20 12" background="#000000">
			<text color="#ffffff" font-size={16} shadow="0 0 8 #22d3ee">Hi</text>
		</view>;
}
