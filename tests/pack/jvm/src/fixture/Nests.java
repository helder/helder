package fixture;

class Nests {
	private int hidden = 4;
	private static String label = "label";

	private int bump(int by) {
		return hidden += by;
	}

	class Inner {
		private int own = 2;
		int peek() {
			return hidden + bump(1) + own;
		}
	}

	static class Nested {
		private final String v;
		private Nested(String v) {
			this.v = v;
		}
		private static Nested of(String v) {
			return new Nested(v + label);
		}
	}

	static void run() {
		Nests n = new Nests();
		Inner in = n.new Inner();
		Main.say("nests: " + in.peek() + " " + n.hidden + " " + in.own);
		Main.say("nests: " + Nested.of("x").v);
		Runnable r = new Runnable() {
			public void run() {
				Main.say("nests: anonymous " + n.bump(10));
			}
		};
		r.run();
	}
}
