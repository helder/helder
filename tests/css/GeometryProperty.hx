import helder.test.Gen;
import helder.test.Runner;
import helder.test.Test;

// helder.ui.box's block layout against Chromium's, as a property:
// generated nested blocks (widths, heights, margins, padding, borders,
// lines of Ahem) laid out by both (Chromium), each box within 0.5 px. A
// failure is shrunk to its smallest page and shows where it differs.
class GeometryProperty {
	static function main() {
		Runner.add("tests/css/GeometryProperty.hx", "tests/css/GeometryProperty.hx", () -> {
			test("nested blocks against Chromium", () -> property(block(3), b -> {
				var html = page(b);
				var d = Chromium.compare(html);
				assert(d.compared >= 3, 'nothing compared:\n$html');
				assert(d.match, '${d.describe()}\n$html');
			}, {cases: 100, seconds: 60}));
			afterAll(Chromium.close);
		});
		Runner.run([]);
	}

	static function block(depth:Int):Gen<Block> {
		var edges = array(int(0, 12), 4, 4);
		var kids = depth > 0 ? array(block(depth - 1), 0, 3) : constant([]);
		return c -> {
			width: c.draw(oneOf([constant(-1), int(0, 300)])),
			height: c.draw(oneOf([constant(-1), int(0, 80)])),
			margin: c.draw(array(int(-6, 16), 4, 4)),
			padding: c.draw(edges),
			border: c.draw(int(0, 4)),
			words: c.draw(int(0, 12)),
			kids: c.draw(kids)
		};
	}

	static function page(b:Block):String
		return '<!doctype html><body style="margin: 0; font: 10px/10px Ahem">${div(b)}</body>';

	static function div(b:Block):String {
		var px = (a:Array<Int>) -> [for (v in a) '${v}px'].join(" ");
		var style = ['margin: ${px(b.margin)}', 'padding: ${px(b.padding)}', 'border: ${b.border}px solid'];
		if (b.width >= 0) style.push('width: ${b.width}px');
		if (b.height >= 0) style.push('height: ${b.height}px');
		var text = [for (i in 0...b.words) "xxxxx".substr(0, 1 + i % 5)].join(" ");
		return '<div style="${style.join("; ")}">$text${[for (k in b.kids) div(k)].join("")}</div>';
	}
}

private typedef Block = {width:Int, height:Int, margin:Array<Int>, padding:Array<Int>, border:Int, words:Int, kids:Array<Block>};
