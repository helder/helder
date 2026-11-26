package helder.scenario;

import haxe.PosInfos;

// Scenarios: the real program at a moment. A `Foo.scenario.hx`
// (`*.scenario.tsx`) file's module-level values made by scenario({...}),
// each a screen of the studio's preview host (helder.story.Host). The
// program's main runs once, as always; in the host UiWindow.run keeps its
// root (helder.ui.Hosting), and each scenario renders it in a screen with a
// context and a store of its own (helder.view.graph.Atoms: every signal's
// and memo's value per store), boot run there first: it writes the app's
// signals, calls the app's own functions:
//
//   final won = scenario({name: "Pong/You win", boot: () -> { Game.score([7, 5]); Game.over(true); }});
//   final moving = scenario({name: "Pong/In motion", loop: 3});
//
// time: its start instant (an ISO date, "2026-11-26T09:00" local or with
// its zone, or ms since 1970) on its clock, which stands at the moment
// (play: seconds of it run to the moment first; loop: run live from it
// while hovered, as a story's); seed: Math.random's; size: [width, height]
// in points (else its <Surface>'s); dark.
function scenario(def:ScenarioDef, ?pos:PosInfos):Scenario
	return new Scenario(def, pos);

class Scenario {
	public final name:String;
	public final boot:Null<Void->Void>;
	// ms since 1970 (null: the system's clock)
	public final time:Null<Float>;
	public final seed:Int;
	public final width:Null<Int>;
	public final height:Null<Int>;
	public final dark:Null<Bool>;
	public final loop:Null<Float>;
	public final play:Null<Float>;
	public final pos:Null<PosInfos>;

	public function new(def:ScenarioDef, ?pos:PosInfos) {
		name = def.name;
		boot = def.boot;
		time = instant(def.time);
		seed = def.seed ?? 1;
		var size:Null<Array<Int>> = def.size;
		width = size == null ? null : size[0];
		height = size == null ? null : size[1];
		dark = def.dark;
		loop = def.loop;
		play = def.play;
		this.pos = pos;
	}

	// (an ISO date's ms: local without a zone; a number as it is)
	public static function instant(t:Dynamic):Null<Float> {
		if (t == null) return null;
		if (!Std.isOfType(t, String)) return (t : Float);
		var re = ~/^(\d{4})-(\d\d)-(\d\d)(?:[T ](\d\d):(\d\d)(?::(\d\d))?)?(Z|[+-]\d\d:?\d\d)?$/;
		if (!re.match(t)) throw 'helder.scenario: time "$t" is not an ISO date (2026-11-26T09:00, +01:00 or Z for its zone)';
		inline function n(i:Int):Int
			return Std.parseInt(re.matched(i) ?? "0") ?? 0;
		var zone = re.matched(7);
		if (zone == null) return new Date(n(1), n(2) - 1, n(3), n(4), n(5), n(6)).getTime();
		var utc = days(n(1), n(2), n(3)) * 86400000.0 + ((n(4) * 60 + n(5)) * 60 + n(6)) * 1000.0;
		if (zone == "Z") return utc;
		var z = zone.split(":").join(""), sign = z.charAt(0) == "-" ? -1 : 1;
		var off = (Std.parseInt(z.substr(1, 2)) ?? 0) * 60 + (Std.parseInt(z.substr(3, 2)) ?? 0);
		return utc - sign * off * 60000.0;
	}

	// (days since 1970-01-01 of a civil date: Howard Hinnant's)
	static function days(y:Int, m:Int, d:Int):Float {
		if (m <= 2) y--;
		var era = Math.floor(y / 400), yoe = y - era * 400;
		var doy = Std.int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1;
		var doe = yoe * 365 + Std.int(yoe / 4) - Std.int(yoe / 100) + doy;
		return era * 146097.0 + doe - 719468;
	}

	// (TypeScript's scenario({...}): helder/scenario)
	public static function define(def:ScenarioDef):Scenario
		return new Scenario(def);

	// a file name of its name (Pong/You win: Pong-You-win)
	public function slug():String
		return ~/[^A-Za-z0-9_-]+/g.replace(name, "-");
}

// scenario({...})'s fields (TypeScript's helder/scenario the same)
typedef ScenarioDef = {
	var name:String;
	// run first in its screen, its store current: the app's signals written, its own functions called
	@:optional var boot:Void->Void;
	@:optional @:typescript.type("string | number") var time:Dynamic;
	@:optional var seed:Int;
	@:optional var size:Array<Int>;
	@:optional var dark:Bool;
	@:optional var loop:Float;
	@:optional var play:Float;
}
