import Sim;

// The levels checked, natively, without drawing: each played with no orders
// (it must be lost), then every single order the hints know (Sim.candidates:
// each blue squad and prop, at moments through the battle, to a grid of
// places) played out: how many win, by which squad or prop, the best.
//
//   bun run helder build examples/rewind-regiment/Solve.hx && bin/<target>/Solve [level...]
class Solve {
	static function main() {
		var args = Sys.args();
		var quick = args.remove("quick");
		var none = args.remove("none");
		var only = [for (a in args) Std.parseInt(a)];
		for (n in 0...Levels.levels.length) {
			if (only.length > 0 && only.indexOf(n + 1) < 0) continue;
			var level = Levels.levels[n];
			var sim = new Sim(level);
			sim.start();
			var t0 = Sys.time();
			var base = sim.play([]);
			var length = sim.step;
			if (none) {
				Sys.println('${n + 1}. ${level.name}: no orders ${base.won ? "WON" : "lost"} (${base.blue} v ${base.red}, ${Math.round(length / 6) / 10}s) ${Math.round((Sys.time() - t0) * 1e6 / length) / 1000}ms/step, ${sim.bodies.length} bodies');
				continue;
			}
			// (moments: from the start to just before the end of the lost battle)
			var steps = quick ? 4 : 7;
			var moments = [for (k in 0...steps) Std.int(length * k / steps / Sim.KEY) * Sim.KEY];
			var tried = 0, wins = 0, by = new Map<String, Int>(), best = "", bestLeft = -1;
			var list = sim.candidates(moments);
			if (quick) list = [for (i in 0...list.length) if (i % 2 == 0) list[i]];
			for (o in list) {
				var r = sim.play([o]);
				tried++;
				if (r.won) {
					wins++;
					var who = o.who >= Sim.PROP ? propName(level.props[o.who - Sim.PROP].type) : 'squad ${String.fromCharCode(65 + o.who)}';
					by.set(who, (by.get(who) ?? 0) + 1);
					if (r.blue > bestLeft) {
						bestLeft = r.blue;
						best = '$who at ${Math.round(o.step / 6) / 10}s to (${o.x}, ${o.z})';
					}
				}
			}
			var share = Math.round(wins / tried * 1000) / 10;
			Sys.println('${n + 1}. ${level.name}: no orders ${base.won ? "WON" : "lost"} (${base.blue} v ${base.red}, ${Math.round(length / 6) / 10}s); $wins/$tried win ($share%) '
				+ [for (k => v in by) '$k $v'].join(", ") + (wins > 0 ? '; best $best, ${bestLeft} left' : "") + ' [${Math.round((Sys.time() - t0) * 10) / 10}s]');
		}
	}

	static function propName(t:Int):String
		return ["marble", "dominoes", "train", "jack", "tower", "catapult", "top"][t];
}
