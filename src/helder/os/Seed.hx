package helder.os;

// Math.random's (and Std.random's) sequence started again from n: hxmc's
// xoshiro256** state, splitmix64 of the seed, as hxmc seeds it from the
// time. A headless run's (--seed), a story's as it is built (helder.story.Host:
// its stills and loops the same each time); elsewhere nothing
class Seed {
	public static function random(n:Int) {
		#if (target.name == "hxmc" && !macro)
		var x:hxmc.I64 = n;
		@:privateAccess {
			hxmc.rt.Random.s0 = splitmix(x = x + hxmc.rt.Random.k(0x9E3779B9, 0x7F4A7C15));
			hxmc.rt.Random.s1 = splitmix(x = x + hxmc.rt.Random.k(0x9E3779B9, 0x7F4A7C15));
			hxmc.rt.Random.s2 = splitmix(x = x + hxmc.rt.Random.k(0x9E3779B9, 0x7F4A7C15));
			hxmc.rt.Random.s3 = splitmix(x = x + hxmc.rt.Random.k(0x9E3779B9, 0x7F4A7C15));
		}
		#end
	}

	#if (target.name == "hxmc" && !macro)
	// (splitmix64's output for its state z, hxmc.rt.Random's)
	static function splitmix(z:hxmc.I64):hxmc.I64 {
		@:privateAccess {
			z = (z ^ (z >>> 30)) * hxmc.rt.Random.k(0xBF58476D, 0x1CE4E5B9);
			z = (z ^ (z >>> 27)) * hxmc.rt.Random.k(0x94D049BB, 0x133111EB);
		}
		return z ^ (z >>> 31);
	}
	#end
}
