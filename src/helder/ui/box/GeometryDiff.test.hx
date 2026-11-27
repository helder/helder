package helder.ui.box;

import helder.test.Test;
import helder.ui.box.Geometry.GeometryNode;

function tests() {
	function node(path:String, rects:Array<Array<Float>>, ?text:Array<Array<Float>>):GeometryNode
		return {path: path, rects: rects, text: text ?? []};
	function page(?width = 100.0, ?text:Array<Array<Float>>):Geometry
		return new Geometry([
			node("html", [[0, 0, 800, 60]]),
			node("html>body", [[8, 8, 784, 44]]),
			node("html>body>div[1]", [[8, 8, width, 20]]),
			node("html>body>div[1]>#text", [], text ?? [[8, 8, 40, 19, 0, 5]]),
			node("html>body>div[2]", [[8, 28, 100, 24]])
		]);

	test("a matching pair", () -> {
		var d = GeometryDiff.of(page(), page());
		equals(d.match, true);
		equals(d.compared, 5);
		equals(d.describe(), "geometry matches (5 nodes)");
	});

	test("within tolerance", () -> {
		equals(GeometryDiff.of(page(100), page(100.4)).match, true);
		equals(GeometryDiff.of(page(100), page(100.4), 0.25).match, false);
	});

	test("a width off", () -> {
		var d = GeometryDiff.of(page(100), page(104));
		equals(d.match, false);
		equals(d.differences.length, 1);
		equals(d.first.path, "html>body>div[1]");
		equals(d.first.delta, [0.0, 0, 4, 0]);
		equals(d.parentMatches, true);
		equals(GeometryDiff.line(d.first),
			"`div[1]` (html>body>div[1]): border box 4 px too wide (x 0, y 0, w +4, h 0); helder [8, 8, 104, 20], Chromium [8, 8, 100, 20]");
	});

	test("a child that moves with its parent is not the cause", () -> {
		function shifted(dy:Float):Geometry
			return new Geometry([
				node("html", [[0, 0, 800, 100]]),
				node("html>body", [[8, 8, 784, 84]]),
				node("html>body>div", [[8, 8 + dy, 100, 20]]),
				node("html>body>div>p", [[8, 8 + dy, 50, 10]]),
				node("html>body>div>p>#text", [], [[8, 8 + dy, 40, 10, 0, 4]])
			]);
		var d = GeometryDiff.of(shifted(0), shifted(6));
		equals(d.differences.length, 3);
		equals(d.first.path, "html>body>div");
		equals(d.first.delta, [0.0, 6, 0, 0]);
	});

	test("a parent too tall for its child: the child", () -> {
		function tall(h:Float):Geometry
			return new Geometry([
				node("html", [[0, 0, 800, 8 + h]]),
				node("html>body", [[8, 8, 784, h]]),
				node("html>body>div", [[8, 8, 100, h]])
			]);
		var d = GeometryDiff.of(tall(20), tall(24));
		equals(d.differences.length, 3);
		equals(d.first.path, "html>body>div");
		equals(d.parentMatches, false);
	});

	test("a missing node", () -> {
		var helder = new Geometry(page().nodes.filter(n -> n.path != "html>body>div[2]"));
		var d = GeometryDiff.of(page(), helder);
		equals(d.match, false);
		equals(d.chromiumOnly, ["html>body>div[2]"]);
		equals(d.helderOnly, []);
		equals(d.first.what, "missing");
		var e = GeometryDiff.of(helder, page());
		equals(e.helderOnly, ["html>body>div[2]"]);
		equals(e.first.what, "extra");
	});

	test("an inline split over two lines", () -> {
		var two = [[8.0, 8, 60, 19, 0, 11], [8.0, 27, 30, 19, 12, 17]];
		equals(GeometryDiff.of(page(two), page(two)).match, true);
		// (broken one word later: the first line wider, the second's range another)
		var later = [[8.0, 8, 80, 19, 0, 14], [8.0, 27, 10, 19, 15, 17]];
		var d = GeometryDiff.of(page(two), page(later));
		equals(d.first.path, "html>body>div[1]>#text");
		equals(d.first.what, "text");
		equals(d.first.index, 0);
		equals(d.first.delta, [0.0, 0, 20, 0]);
		// (on one line where Chromium has two)
		var one = [[8.0, 8, 90, 19, 0, 17]];
		var e = GeometryDiff.of(page(two), page(one));
		equals(e.first.index, -1);
		equals(GeometryDiff.line(e.first),
			"`#text` (html>body>div[1]>#text): 1 line, Chromium 2: helder [8, 8, 90, 19], Chromium [8, 8, 60, 19] [8, 27, 30, 19]");
	});

	test("fragments touching on a line are one", () -> {
		var whole = [[8.0, 8, 60, 19, 0, 11]];
		var parts = [[8.0, 8, 25, 19, 0, 5], [33.0, 8, 35, 19, 6, 11]];
		equals(GeometryDiff.of(page(whole), page(parts)).match, true);
	});

	test("a skipped subtree is not compared", () -> {
		var chromium = new Geometry(page().nodes, ["html>body>div[1]"]);
		equals(GeometryDiff.of(chromium, page(300)).match, true);
	});

	test("parsed as geometry.mjs writes it", () -> {
		var g = Geometry.parse('{"nodes":[{"path":"html","rects":[[0,0,800,600]]},{"path":"html>body>#text","rects":[],"text":[[8,8,10,19,0,3]]}],"skipped":["html>body>div"]}');
		equals(g.nodes.length, 2);
		equals(g.nodes[1].text, [[8.0, 8, 10, 19, 0, 3]]);
		equals(g.skipped, ["html>body>div"]);
		equals(Geometry.parse(g.toJson()).nodes[1].text, g.nodes[1].text);
	});
}
