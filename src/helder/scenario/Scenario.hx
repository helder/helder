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
// time: its start instant (an ISO date, "2026-11-26T09:00" in its zone or
// with a zone of its own, or ms since 1970) on its clock, which stands at
// the moment (play: seconds of it run to the moment first; loop: run live
// from it while hovered, as a story's); zone: its time zone, "UTC" or a
// fixed offset ("+05:30"); locale: its language ("nl-BE"); settings: the
// system's settings it sees (textScale, reducedMotion,
// reducedTransparency, contrast, orientation); seed: Math.random's, its
// own; http: its requests' answers, strict (helder.async.http.Fixtures: a
// request none matches fails its screen, none goes out); steps: what a user
// does after boot, before the still (tap, type, press, scroll, drag,
// waitFor: helder.scenario.Steps); size: [width,
// height] in points (else its <Surface>'s); dark.
// Nothing of the machine it runs on: zone UTC, locale en-US and settings
// at rest unless given, TypeScript's timers on its clock.
function scenario(def:ScenarioDef, ?pos:PosInfos):Scenario
	return new Scenario(def, pos);

class Scenario {
	public final name:String;
	public final boot:Null<Void->Void>;
	// ms since 1970 (null: the system's clock)
	public final time:Null<Float>;
	public final seed:Int;
	// minutes east of UTC
	public final zone:Int;
	public final locale:String;
	public final settings:helder.os.Settings.SettingsOverride;
	// its requests' answers by url pattern (helder.async.http.Fixtures)
	public final http:Null<haxe.DynamicAccess<Dynamic>>;
	// what a user does after boot, before the still (helder.scenario.Steps)
	public final steps:Array<Steps.Step>;
	public final width:Null<Int>;
	public final height:Null<Int>;
	public final dark:Null<Bool>;
	public final loop:Null<Float>;
	public final play:Null<Float>;
	public final pos:Null<PosInfos>;

	public function new(def:ScenarioDef, ?pos:PosInfos) {
		name = def.name;
		boot = def.boot;
		var z:Null<String> = def.zone;
		zone = z == null ? 0 : helder.os.Now.parseZone(z) ?? throw 'helder.scenario: zone "$z" is not UTC or a fixed offset (+05:30): a named zone\'s rules are not carried';
		time = instant(def.time, zone);
		var l:Null<String> = def.locale;
		locale = l == null ? "en-US" : helder.os.locale.LocaleTag.normalize(l) ?? throw 'helder.scenario: locale "$l" is not a language tag (nl-BE)';
		var given:helder.os.Settings.SettingsOverride = def.settings ?? {};
		settings = {
			textScale: given.textScale ?? 1.0,
			reducedMotion: given.reducedMotion ?? false,
			reducedTransparency: given.reducedTransparency ?? false,
			contrast: given.contrast ?? Normal,
			orientation: given.orientation
		};
		seed = def.seed ?? 1;
		http = def.http;
		steps = def.steps ?? [];
		var size:Null<Array<Int>> = def.size;
		width = size == null ? null : size[0];
		height = size == null ? null : size[1];
		dark = def.dark;
		loop = def.loop;
		play = def.play;
		this.pos = pos;
	}

	// (an ISO date's ms: in zone (minutes east of UTC) without one of its own; a number as it is)
	public static function instant(t:Dynamic, zone = 0):Null<Float> {
		if (t == null) return null;
		if (!Std.isOfType(t, String)) return (t : Float);
		var re = ~/^(\d{4})-(\d\d)-(\d\d)(?:[T ](\d\d):(\d\d)(?::(\d\d))?)?(Z|[+-]\d\d:?\d\d)?$/;
		if (!re.match(t)) throw 'helder.scenario: time "$t" is not an ISO date (2026-11-26T09:00, +01:00 or Z for its zone)';
		inline function n(i:Int):Int
			return Std.parseInt(re.matched(i) ?? "0") ?? 0;
		var given = re.matched(7);
		var utc = days(n(1), n(2), n(3)) * 86400000.0 + ((n(4) * 60 + n(5)) * 60 + n(6)) * 1000.0;
		if (given == null) return utc - zone * 60000.0;
		if (given == "Z") return utc;
		var z = given.split(":").join(""), sign = z.charAt(0) == "-" ? -1 : 1;
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

	// (TypeScript's scenario({...}): helder/scenario; its position this file's, none)
	public static function define(def:ScenarioDef):Scenario
		return new Scenario(def, null);


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
	// "UTC" or a fixed offset ("+05:30"); UTC unless given
	@:optional var zone:String;
	// a language tag ("nl-BE"); en-US unless given
	@:optional var locale:String;
	@:optional var settings:helder.os.Settings.SettingsOverride;
	// its requests' answers, strict (a request none matches fails its screen):
	// url pattern ("api.example.com/v1/*", "POST host/path") to a status, a
	// JSON value or a file's path ("fixtures/forecast.json")
	@:optional @:typescript.type("Record<string, number | string | object>") var http:haxe.DynamicAccess<Dynamic>;
	// what a user does after boot, before the still: tap, type, press, scroll, drag, waitFor (helder.scenario.Steps)
	@:optional var steps:Array<Steps.Step>;
	@:optional var size:Array<Int>;
	@:optional var dark:Bool;
	@:optional var loop:Float;
	@:optional var play:Float;
}
