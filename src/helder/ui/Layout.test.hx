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
		test("a scroller held by its column's item at its content's height: told once, and not when it scrolls", () -> {
			var told = [], before = Layout.warnings;
			Layout.warnings = s -> told.push(s);
			function lay(minHeight:Null<Float>):Node {
				var ui = new Ui(new StoryText(), 400, 300);
				var dispose = Render.render(Fixture.trapped(minHeight), ui.root);
				ui.update();
				ui.root.find("list").markDirty();
				ui.update();
				var list = ui.root.find("list");
				dispose();
				return list;
			}
			try {
				equals(lay(null).height, 1000.0);
				equals(told.length, 1);
				equals(told[0].indexOf("<view>") > 0 && told[0].indexOf("minHeight 0") > 0, true);
				told = [];
				equals(lay(0).height, 160.0);
				equals(told, []);
			} catch (e:Dynamic) {
				Layout.warnings = before;
				throw e;
			}
			Layout.warnings = before;
		});
	});
}

private class Fixture implements helder.view.Markup {
	public static function trapped(minHeight:Null<Float>)
		return <view height={200}>
			<view height={40} flexShrink={0}/>
			<view flexGrow={1} minHeight={minHeight}>
				<view tag="list" flexGrow={1} overflowY="scroll">
					<view height={1000}/>
				</view>
			</view>
		</view>;

	public static function bubble(align:String)
		return <view width={300}>
			<view tag="box" alignSelf={align} maxWidth={100} padding="8 10">
				<text tag="text" fontSize={10}>{"aaaa bbbb cccc dddd eeee ffff gggg"}</text>
			</view>
		</view>;
}
