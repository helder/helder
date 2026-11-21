package fixture;

import java.io.Serializable;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.List;
import java.util.function.*;

class Lambdas {
	int base = 10;
	private String secret(String s) {
		return "secret " + s + base;
	}
	private Lambdas() {}
	private static Lambdas make() {
		return new Lambdas();
	}

	interface Tri {
		long apply(int a, long b, double c);
	}

	static void run() {
		Runnable r = () -> Main.say("lambdas: runnable");
		r.run();
		int k = 5;
		String s = "cap";
		Function<String, Integer> f = x -> x.length() + k;
		Main.say("lambdas: function " + f.apply("abc") + " " + s);
		Lambdas l = make();
		Supplier<Integer> fromThis = () -> l.base * 2;
		Main.say("lambdas: this " + fromThis.get());
		Function<String, String> priv = l::secret;
		Main.say("lambdas: private " + priv.apply("x"));
		Supplier<Lambdas> ctor = Lambdas::new;
		Main.say("lambdas: ctor " + ctor.get().base);
		Supplier<List<String>> list = ArrayList::new;
		List<String> names = list.get();
		names.add("b");
		names.add("a");
		names.add("c");
		names.sort(Comparator.naturalOrder());
		Main.say("lambdas: sorted " + names);
		Function<String, Integer> len = String::length;
		Main.say("lambdas: unbound " + len.apply("four"));
		IntBinaryOperator add = (a, b) -> a + b;
		Main.say("lambdas: prims " + add.applyAsInt(3, 4));
		Tri tri = (a, b, c) -> a + b + (long) c;
		Main.say("lambdas: wide " + tri.apply(1, 2L, 3.5));
		ToLongFunction<Integer> widen = Integer::intValue;
		Main.say("lambdas: widen " + widen.applyAsLong(7));
		BiFunction<Integer, Integer, Integer> boxed = Math::max;
		Main.say("lambdas: boxed " + boxed.apply(3, 9));
		Runnable both = (Runnable & Serializable) () -> Main.say("lambdas: serializable");
		both.run();
		Main.say("lambdas: marker " + (both instanceof Serializable));
		int[] counter = {0};
		Arrays.asList(1, 2, 3).forEach(x -> counter[0] += x);
		Main.say("lambdas: forEach " + counter[0]);
		Predicate<String> empty = String::isEmpty;
		Main.say("lambdas: negate " + empty.negate().test(""));
		Function<Integer, int[]> arr = int[]::new;
		Main.say("lambdas: array ctor " + arr.apply(3).length);
	}
}
