import helder.os.audio.Sfx;

// The game's sounds, made here procedurally (no files), mixed by helder.os's
// Sfx (desktop and the web; silent where there is no audio back end): a
// plastic clack for a blow, a foam pellet's pop, a soldier toppling, a
// rocket's whoosh and a bang, the marble's roll, a domino's tock, the
// train's whistle, the jack-in-the-box's boing, the tape-like whir of the
// timeline dragged back, a fanfare for a victory and a sag for a defeat.
// Kept soft and short; the same sound not again within a few hundredths of
// a second, its pitch a little different each time.
class Sounds {
	public static var silent = false;
	// (quiet for now: the battle behind the title plays without them)
	public static var muted = false;
	static var sfx:Null<Sfx>;
	static var ids:Map<String, Int> = [];
	static var seed = 4242;
	static var last:Map<String, Float> = [];

	public static function start() {
		if (sfx != null || silent) return;
		var s = Sfx.open();
		sfx = s;
		if (!s.playing) return;
		var tau = 2 * Math.PI;
		ids["clack"] = s.add(make(0.07, t -> 0.5 * Math.sin(tau * 2300 * t) * Math.exp(-t * 120) + 0.45 * noise() * Math.exp(-t * 260)));
		ids["pop"] = s.add(make(0.09, t -> {
			var b = 0.5 * Math.sin(tau * (900 - 5000 * t) * t) * Math.exp(-t * 70);
			b + 0.3 * noise() * Math.exp(-t * 180);
		}));
		var lp = 0.0;
		ids["topple"] = s.add(make(0.16, t -> {
			lp += (noise() - lp) * 0.2;
			0.4 * Math.sin(tau * 420 * t) * Math.exp(-t * 45) + 0.5 * lp * Math.exp(-t * 30) + (t > 0.06 ? 0.3 * Math.sin(tau * 650 * (t - 0.06)) * Math.exp(-(t - 0.06) * 80) : 0);
		}));
		var low = 0.0;
		ids["boom"] = s.add(make(0.7, t -> {
			low += (noise() - low) * (0.12 - 0.12 * Math.min(1, t * 2));
			1.6 * low * Math.exp(-t * 5) + 0.5 * Math.sin(tau * (90 - 40 * t) * t) * Math.exp(-t * 7);
		}));
		var w = 0.0;
		ids["whoosh"] = s.add(make(0.4, t -> {
			w += (noise() - w) * (0.05 + 0.25 * t);
			1.2 * w * Math.sin(Math.PI * t / 0.4);
		}));
		var r = 0.0;
		ids["roll"] = s.add(make(1.4, t -> {
			r += (noise() - r) * 0.015;
			var env = Math.min(1, t * 6) * Math.exp(-t * 1.2);
			2.4 * r * env + 0.08 * Math.sin(tau * 55 * t) * env;
		}));
		ids["tock"] = s.add(make(0.1, t -> 0.6 * Math.sin(tau * 1350 * t) * Math.exp(-t * 70) + 0.25 * Math.sin(tau * 2700 * t) * Math.exp(-t * 110)));
		ids["whistle"] = s.add(make(0.7, t -> {
			var env = Math.min(1, t * 20) * (t > 0.55 ? Math.max(0, 1 - (t - 0.55) / 0.15) : 1);
			0.22 * env * (Math.sin(tau * 880 * t) + 0.7 * Math.sin(tau * 1108 * t) + 0.5 * Math.sin(tau * 1318 * t)) + 0.05 * noise() * env;
		}));
		var ph = 0.0;
		ids["boing"] = s.add(make(0.45, t -> {
			ph += tau * (300 + 340 * Math.exp(-t * 10) + 40 * Math.sin(t * 55)) / Sfx.RATE;
			0.55 * Math.sin(ph) * Math.exp(-t * 7);
		}));
		var wp = 0.0;
		ids["whir"] = s.add(make(0.25, t -> {
			wp += tau * (600 + 900 * Math.sin(t * 40)) / Sfx.RATE;
			0.12 * Math.sin(wp) * Math.sin(Math.PI * t / 0.25) + 0.08 * noise() * Math.sin(Math.PI * t / 0.25);
		}));
		ids["tick"] = s.add(make(0.04, t -> 0.4 * Math.sin(tau * 2600 * t) * Math.exp(-t * 160)));
		ids["fanfare"] = s.add(make(1.6, t -> {
			var v = 0.0;
			var notes = [523.25, 659.25, 783.99, 1046.5, 1046.5];
			var times = [0.0, 0.12, 0.24, 0.36, 0.62];
			for (k in 0...notes.length) {
				var at = t - times[k];
				if (at > 0) v += 0.16 * (Math.sin(tau * notes[k] * at) + 0.4 * Math.sin(tau * notes[k] * 2 * at) + 0.2 * Math.sin(tau * notes[k] * 3 * at)) * Math.exp(-at * (k == 4 ? 2.2 : 6));
			}
			v;
		}));
		ids["sag"] = s.add(make(1.1, t -> {
			var v = 0.0;
			var notes = [392.0, 349.23, 311.13];
			for (k in 0...3) {
				var at = t - k * 0.22;
				if (at > 0) v += 0.18 * (Math.sin(tau * notes[k] * at) + 0.3 * Math.sin(tau * notes[k] * 2 * at)) * Math.exp(-at * 4);
			}
			v;
		}));
	}

	static function make(seconds:Float, f:Float->Float):Array<Float>
		return [for (i in 0...Std.int(seconds * Sfx.RATE)) f(i / Sfx.RATE)];

	static function noise():Float {
		seed = (seed * 1103515245 + 12345) & 0x7fffffff;
		return seed / 0x3fffffff - 1;
	}

	public static function play(name:String, gain:Float, ?rate:Float) {
		if (silent || muted) return;
		start();
		var s = sfx;
		var id = ids.get(name);
		if (s == null || id == null) return;
		var now = helder.ui.Ui.now();
		var at = last.get(name);
		if (at != null && now - at < 0.035) return;
		last.set(name, now);
		s.play(id, gain, rate ?? (0.9 + 0.2 * ((noise() + 1) / 2)));
	}
}
