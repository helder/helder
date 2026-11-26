package helder.async.http;

import haxe.io.Bytes;
import helder.async.http.Client.Reply;

// A screen's HTTP answers (a scenario's http, MSW's way): each request its
// rule's answer, none of them going out. A rule's pattern is a url without
// its scheme, * any run of characters ("api.open-meteo.com/v1/*"), a method
// first when it matters ("POST api.example.com/todos"); its answer a status
// (503: an empty body), a file's path ending in .json or .txt read from dir
// (the project's: "fixtures/forecast.json", 200), or any other value its JSON
// (200). The first rule that matches answers; a request none matches is an
// error (strict: a still makes no live call), told to missed too.
@:noCompletion class Fixtures {
	final rules:Array<{method:Null<String>, re:EReg, answer:Dynamic}> = [];
	final dir:String;
	final missed:(method:String, url:String) -> Void;

	public function new(given:haxe.DynamicAccess<Dynamic>, dir:String, missed:(method:String, url:String) -> Void) {
		this.dir = dir;
		this.missed = missed;
		for (key => answer in given) {
			var space = key.indexOf(" ");
			var method = space > 0 ? key.substr(0, space).toUpperCase() : null;
			var pattern = space > 0 ? key.substr(space + 1) : key;
			rules.push({method: method, re: glob(pattern), answer: answer});
		}
	}

	// the answer to method url, else an error (and missed told)
	public function answer(method:String, url:String):Reply {
		var at = url.indexOf("://"), bare = at < 0 ? url : url.substr(at + 3);
		for (r in rules)
			if ((r.method == null || r.method == method) && r.re.match(bare)) return reply(r.answer);
		missed(method, url);
		throw new haxe.Exception('no http fixture for $method $url (a scenario\'s http: {"${pattern(bare)}": 200 | {...} | "fixtures/x.json"})');
	}

	function reply(a:Dynamic):Reply {
		if (Std.isOfType(a, Int)) return new Reply(a, new Map(), Bytes.alloc(0));
		if (Std.isOfType(a, String) && (StringTools.endsWith(a, ".json") || StringTools.endsWith(a, ".txt"))) {
			var path = haxe.io.Path.isAbsolute(a) ? a : haxe.io.Path.join([dir, a]);
			#if sys
			var body = try sys.io.File.getBytes(path) catch (e:Dynamic) throw new haxe.Exception('http fixture file not found: $path');
			#else
			var body:Bytes = throw new haxe.Exception('http fixture files need a native program: $path');
			#end
			return new Reply(200, ["content-type" => StringTools.endsWith(a, ".json") ? "application/json" : "text/plain"], body);
		}
		return new Reply(200, ["content-type" => "application/json"], Bytes.ofString(haxe.Json.stringify(a)));
	}

	// (a pattern's regular expression: * any run, the rest as written, the whole url)
	static function glob(p:String):EReg
		return new EReg("^" + [for (part in p.split("*")) EReg.escape(part)].join(".*") + "$", "");

	// (a pattern to suggest for a url: its host and path, the query a *)
	static function pattern(bare:String):String {
		var q = bare.indexOf("?");
		return q < 0 ? bare : bare.substr(0, q) + "*";
	}
}
