package helder.ui;

import helder.story.StoryText;
import helder.test.Test;
import helder.view.Render;

// A column's item of a max-width (not stretched): its text wrapped at the
// width it gets, its height that of the wrapped lines, not of one line at
// the column's width (StoryText's characters: half the font's size wide)
function tests() {
	describe("Layout", () -> {
		function boxes(align:String):{box:Node, text:Node} {
			var ui = new Ui(new StoryText(), 400, 300);
			var dispose = Render.render(Fixture.bubble(align), ui.root);
			ui.update();
			var out = {box: ui.root.find("box"), text: ui.root.find("text")};
			dispose();
			return out;
		}
		test("a max-width item's text wrapped at its width, its height the lines'", () -> {
			for (align in ["flex-end", "flex-start", "center"]) {
				var b = boxes(align);
				equals(b.box.width, 100.0);
				equals(b.box.height, b.text.height + 16);
				equals(b.text.height > 20, true);
			}
		});
	});
}

private class Fixture implements helder.view.Markup {
	public static function bubble(align:String)
		return <view width={300}>
			<view tag="box" align-self={align} max-width={100} padding="8 10">
				<text tag="text" font-size={10}>{"aaaa bbbb cccc dddd eeee ffff gggg"}</text>
			</view>
		</view>;
}
