package fixture;

// Compiled for Java 8 (build.sh): inner access through access$ methods,
// concatenation by StringBuilder, invokespecial of private methods
class Old {
	private int secret = 41;

	private int next() {
		return ++secret;
	}

	class In {
		int get() {
			return next() + secret;
		}
	}

	static void run() {
		Old o = new Old();
		In in = o.new In();
		Main.say("old: " + in.get() + " " + o.secret);
		java.util.function.IntSupplier s = o::next;
		Main.say("old: " + s.getAsInt());
	}
}
