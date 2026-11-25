package helder.ui.nav;

import helder.view.View;
import helder.view.graph.Graph;
import helder.view.graph.Read;
import helder.view.graph.Signal;

// Screens by path, kept as a stack (helder.ui.Stack shows it): routes are
// matched in the order they were added, a segment ":name" taking any one
// segment (its value given to the route, decoded), the fallback any path
// none matched. go pushes, back pops (false at the root; backTo several),
// replace swaps the top, reset starts a new stack, open a link's (a full
// URL or a path): the root and the matched route. Each entry's screen is
// made once, when it is pushed. Haxe's helder.ui.Router types a route's params by its path.
class Router {
	// the top's path (without its query), how many entries are above the root, the top's query
	public final path:Read<String>;
	public final depth:Read<Int>;
	@:typescript.type("Read<Record<string, string>>") public final query:Read<Dynamic>;
	@:noCompletion public final queries:Read<Map<String, String>>;
	@:noCompletion public final entries:Signal<Array<Entry>>;
	final routes:Array<Route> = [];
	var missing:Null<String->View> = null;
	var stack:Array<Entry> = [];

	public function new() {
		entries = Graph.signalOf(([] : Array<Entry>), {ownedWrite: true});
		path = () -> top()?.path ?? "/";
		depth = () -> Std.int(Math.max(0, entries().length - 1));
		query = () -> top()?.fields ?? {};
		queries = () -> top()?.query ?? new Map();
	}

	// a route: render given its params (an object of the path's names, each a string)
	@:typescript.type("<P extends string>(path: P, render: (params: RouteParams<P>) => View) => Router")
	public function route(path:String, render:Dynamic->View):Router {
		var names = [for (p in segments(path)) if (p.charAt(0) == ":") p.substr(1)];
		return add(path, values -> {
			var o:Dynamic = {};
			for (i => n in names)
				Reflect.setField(o, n, values[i]);
			render(o);
		});
	}

	// a route given its params' values in the path's order (Haxe's route, typed)
	@:noCompletion public function add(path:String, render:Array<String>->View):Router {
		var parts = segments(path);
		for (p in parts)
			if (p == ":" || p.indexOf("*") >= 0 || p.indexOf("?") >= 0) throw 'Router: no such segment as $p in $path';
		routes.push({parts: parts, render: render});
		return this;
	}

	// what a path no route matches shows (else go throws)
	public function fallback(render:(path:String)->View):Router {
		missing = render;
		return this;
	}

	public function go(path:String) {
		begin();
		commit(stack.concat([entry(path)]));
	}

	public function back():Bool {
		if (stack.length <= 1) return false;
		commit(stack.slice(0, -1));
		return true;
	}

	// pops to the entry depth entries above the root (0: the root): whether it moved
	public function backTo(depth:Int):Bool {
		if (depth < 0 || depth >= stack.length - 1) return false;
		commit(stack.slice(0, depth + 1));
		return true;
	}

	public function replace(path:String) {
		begin();
		commit(stack.slice(0, -1).concat([entry(path)]));
	}

	public function reset(path:String)
		commit([entry(path)]);

	public function open(url:String) {
		var p = local(url);
		var at = entry(p);
		commit(at.path == "/" ? [at] : [entry("/"), at]);
	}

	// (the root, made when the stack is first used)
	@:noCompletion public function begin()
		if (stack.length == 0) commit([entry("/")]);

	function top():Null<Entry> {
		var es = entries();
		return es.length == 0 ? null : es[es.length - 1];
	}

	function commit(next:Array<Entry>) {
		stack = next;
		entries(next);
	}

	function entry(url:String):Entry {
		var q = url.indexOf("?"), h = url.indexOf("#");
		var end = h < 0 ? url.length : h;
		var path = q < 0 || q > end ? url.substring(0, end) : url.substring(0, q);
		var query = new Map<String, String>(), fields:Dynamic = {};
		if (q >= 0 && q < end)
			for (pair in url.substring(q + 1, end).split("&")) {
				if (pair == "") continue;
				var i = pair.indexOf("=");
				var k = decode(i < 0 ? pair : pair.substr(0, i)), v = i < 0 ? "" : decode(pair.substr(i + 1));
				query.set(k, v);
				Reflect.setField(fields, k, v);
			}
		if (path == "") path = "/";
		var view = match(path);
		if (view == null) throw 'Router: no route for $path';
		return new Entry(path, path + (q >= 0 && q < end ? url.substring(q, end) : ""), query, fields, view);
	}

	function match(path:String):Null<View> {
		var parts = segments(path);
		for (r in routes) {
			var values = matches(r.parts, parts);
			if (values != null) return r.render(values);
		}
		return missing == null ? null : missing(path);
	}

	// (the values of a route's params for a path's segments, null when it does not match)
	static function matches(route:Array<String>, parts:Array<String>):Null<Array<String>> {
		if (route.length != parts.length) return null;
		var values = [];
		for (i => r in route)
			if (r.charAt(0) == ":") values.push(StringTools.urlDecode(parts[i])) else if (r != parts[i]) return null;
		return values;
	}

	static function segments(path:String):Array<String>
		return [for (p in path.split("/")) if (p != "") p];

	static function decode(s:String):String
		return StringTools.urlDecode(StringTools.replace(s, "+", " "));

	// the path and query of a URL (myapp://host/a/b?c: /a/b?c), a path as it is
	@:noCompletion public static function local(url:String):String {
		var scheme = url.indexOf("://");
		if (scheme < 0) return url == "" ? "/" : url.charAt(0) == "/" ? url : "/" + url;
		var rest = url.substr(scheme + 3);
		var slash = rest.indexOf("/"), q = rest.indexOf("?");
		if (slash < 0 || (q >= 0 && q < slash)) return q < 0 ? "/" : "/" + rest.substr(q);
		return rest.substr(slash);
	}
}

// One screen of a router's stack: its path, its URL (path and query), what it shows
@:noCompletion class Entry {
	public final path:String;
	public final url:String;
	public final query:Map<String, String>;
	public final fields:Dynamic;
	public final view:View;

	public function new(path:String, url:String, query:Map<String, String>, fields:Dynamic, view:View) {
		this.path = path;
		this.url = url;
		this.query = query;
		this.fields = fields;
		this.view = view;
	}
}

@:noCompletion typedef Route = {parts:Array<String>, render:Array<String>->View};

// (a route's params as its path names them: "/product/:id" gives {id: string})
@:typescript.type("P extends `${string}:${infer K}/${infer R}` ? {[k in K]: string} & RouteParams<`/${R}`> : P extends `${string}:${infer K}` ? {[k in K]: string} : {}")
typedef RouteParams<P> = Dynamic;
