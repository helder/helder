package helder.ui.flow;

import helder.css.CssTerm;
import helder.ui.Grid.Track;
import helder.ui.Grid.TrackSize;
import helder.ui.box.BoxStyle;
import helder.ui.box.Len;

// A grid-template-columns or -rows (Grid 1 §7.2) from its computed terms:
// the tracks, the names of the lines between them, and an auto-fill or
// auto-fit repeat repeated as many times as fit the room (§7.2.3.2): its
// max, else the size it must reach, else once.
class GridTemplate {
	public final tracks:Array<Track> = [];
	// (each line's names, one more than the tracks)
	public final names:Array<Array<String>> = [[]];
	// (auto-fit's tracks: the first and how many; empty ones collapse, §7.2.3.2)
	public var fitFrom(default, null) = -1;
	public var fitCount(default, null) = 0;

	function new() {}

	public static final NONE = new GridTemplate();

	// room: the content box's size on the axis or its max (NaN: none), least: its min
	public static function parse(st:BoxStyle, p:String, room:Float, least:Float, gap:Float):GridTemplate {
		var r = st.rare;
		var terms = switch p {
			case "grid-template-columns": r.gridTemplateColumns;
			case "grid-template-rows": r.gridTemplateRows;
			case "grid-auto-columns": r.gridAutoColumns;
			case _: r.gridAutoRows;
		}
		switch terms {
			case [] | [Keyword("none" | "subgrid" | "masonry")]: return NONE;
			case _:
		}
		var before = [], after = [], unit:Null<Array<CssTerm>> = null, fit = false;
		for (term in terms) switch term {
			case Func("repeat", args):
				var at = 0;
				while (at < args.length && !args[at].match(Delim(","))) at++;
				var inner = args.slice(at + 1);
				switch args[0] {
					case Number(n, _): for (_ in 0...Std.int(Math.min(n, MAX))) for (x in inner) (unit == null ? before : after).push(x);
					case Keyword(k):
						unit = inner;
						fit = k == "auto-fit";
					case _:
				}
			case _:
				(unit == null ? before : after).push(term);
		}
		var t = new GridTemplate();
		t.add(before, room);
		if (unit == null) return t;
		var from = t.tracks.length, times = repetitions(before.concat(after), unit, room, least, gap);
		for (_ in 0...times) t.add(unit, room);
		if (fit) {
			t.fitFrom = from;
			t.fitCount = t.tracks.length - from;
		}
		t.add(after, room);
		return t;
	}

	// (as many as fit the room with the other tracks, the gaps between; or as few as reach least; at least one)
	static function repetitions(others:Array<CssTerm>, unit:Array<CssTerm>, room:Float, least:Float, gap:Float):Int {
		var o = new GridTemplate(), u = new GridTemplate();
		o.add(others, room);
		u.add(unit, room);
		var rest = -gap, each = 0.0;
		for (t in o.tracks) rest += fixed(t, room) + gap;
		for (t in u.tracks) each += fixed(t, room) + gap;
		if (each <= 0) return 1;
		var times = if (!Math.isNaN(room)) Math.floor((room - rest + 1e-6) / each) else if (!Math.isNaN(least)) Math.ceil((least - rest - 1e-6) / each) else 1;
		return Std.int(Math.max(1, Math.min(times, MAX / Math.max(1, u.tracks.length))));
	}

	function add(terms:Array<CssTerm>, room:Float) {
		for (term in terms) switch term {
			case Brackets(_, idents):
				var line = names[names.length - 1];
				for (i in idents) switch i {
					case Ident(n): line.push(n);
					case _:
				}
			case _:
				tracks.push(track(term, room));
				names.push([]);
		}
	}

	static function track(term:CssTerm, room:Float):Track
		return switch term {
			case Func("minmax", [a, _, b]): new Track(size(a, room), size(b, room));
			case Func("fit-content", [a]): new FitTrack(size(a, room));
			case t: Track.of(size(t, room));
		}

	static function size(term:CssTerm, room:Float):TrackSize
		return switch term {
			case Keyword("min-content"): MinContent;
			case Keyword("max-content"): MaxContent;
			case Dimension(v, "fr"): Fr(v);
			case Dimension(v, _) | Number(v, _): Px(v);
			case Percentage(v): Percent(v);
			case Calc(n, _, _):
				var v = Lens.resolve(Calc(n), room, Math.NaN);
				Math.isNaN(v) ? Auto : Px(v);
			case _: Auto;
		}

	// (a track's size for the repeat's count: its max if fixed, else its min if fixed, else none)
	static function fixed(t:Track, room:Float):Float {
		var v = of(t.max, room);
		if (Math.isNaN(v)) v = of(t.min, room);
		return Math.isNaN(v) ? 0 : v;
	}

	static function of(s:TrackSize, room:Float):Float
		return switch s {
			case Px(v): v;
			case Percent(p) if (!Math.isNaN(room)): room * p / 100;
			case _: Math.NaN;
		}

	// (as many tracks as placement has lines for)
	static inline var MAX = 65535;
}

// fit-content(limit): minmax(auto, max-content), its growth no more than the limit (§7.2.4)
class FitTrack extends Track {
	public final limit:TrackSize;

	public function new(limit:TrackSize) {
		super(Auto, MaxContent);
		this.limit = limit;
	}
}
