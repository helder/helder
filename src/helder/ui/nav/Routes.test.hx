package helder.ui.nav;

import helder.test.Test;
import helder.view.graph.Graph;

// Routes: paths matched in order, params typed by the path, the query, the
// fallback; go, back, replace, reset and open on the stack
function tests() {
	function nav():Routes {
		return new Routes()
			.route("/", _ -> <text>home</text>)
			.route("/product/:id", p -> {
				var id:String = p.id;
				<text>{"product " + id}</text>;
			})
			.route("/a/:x/b/:y", p -> <text>{p.x + p.y}</text>)
			.fallback(path -> <text>{"missing " + path}</text>);
	}
	function paths(r:Routes):String
		return [for (e in (r : helder.ui.nav.Router).entries.peek()) e.path].join(" ");
	describe("Routes", () -> {
		test("paths, params and the query", () -> {
			var r = nav();
			r.go("/product/3?tab=specs&q=a%20b");
			Graph.flush();
			equals(r.path(), "/product/3");
			equals(r.depth(), 1);
			equals(r.query().get("tab"), "specs");
			equals(r.query().get("q"), "a b");
			r.go("/a/1/b/2");
			Graph.flush();
			equals(r.path(), "/a/1/b/2");
			r.go("/nowhere/x");
			Graph.flush();
			equals(paths(r), "/ /product/3 /a/1/b/2 /nowhere/x");
		});
		test("no route and no fallback: an error", () -> {
			var r = new Routes().route("/", _ -> <text>home</text>);
			equals(try {
				r.go("/x");
				"";
			} catch (e:Dynamic) Std.string(e), "Router: no route for /x");
		});
		test("go, back, replace, reset", () -> {
			var r = nav();
			equals(r.back(), false);
			r.go("/product/1");
			r.go("/product/2");
			r.replace("/product/3");
			Graph.flush();
			equals(paths(r), "/ /product/1 /product/3");
			equals(r.back(), true);
			equals(r.back(), true);
			equals(r.back(), false);
			Graph.flush();
			equals(r.depth(), 0);
			r.go("/product/4");
			r.reset("/product/5");
			Graph.flush();
			equals(paths(r), "/product/5");
			equals(r.depth(), 0);
		});
		test("open: the root and the matched route, from a URL or a path", () -> {
			var r = nav();
			r.open("myapp://host/product/7?x=1");
			Graph.flush();
			equals(paths(r), "/ /product/7");
			equals(r.query().get("x"), "1");
			r.open("https://example.com/");
			Graph.flush();
			equals(paths(r), "/");
			r.open("/a/1/b/2");
			Graph.flush();
			equals(paths(r), "/ /a/1/b/2");
			equals(helder.ui.nav.Router.local("myapp://host"), "/");
			equals(helder.ui.nav.Router.local("myapp://host?a=1"), "/?a=1");
			equals(helder.ui.nav.Router.local("product/2"), "/product/2");
		});
	});
}
