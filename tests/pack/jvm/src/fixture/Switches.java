package fixture;

class Switches {
	enum Color { RED, GREEN, BLUE }

	static String table(int k) {
		switch (k) {
			case -1: return "minus";
			case 0: return "zero";
			case 1: return "one";
			case 2: return "two";
			case 3: return "three";
			default: return "other";
		}
	}

	static String lookup(int k) {
		switch (k) {
			case -100000: return "low";
			case 7: return "seven";
			case 1000: return "thousand";
			case 1 << 30: return "big";
			default: return "none";
		}
	}

	static String strings(String s) {
		switch (s) {
			case "Aa": return "Aa";
			case "BB": return "BB";
			case "hello": return "hi";
			default: return "?";
		}
	}

	static int colors(Color c) {
		switch (c) {
			case RED: return 1;
			case BLUE: return 3;
			default: return 0;
		}
	}

	static void run() {
		StringBuilder b = new StringBuilder();
		for (int k = -2; k < 5; k++) b.append(table(k)).append(' ');
		Main.say("switches: " + b.toString().trim());
		Main.say("switches: " + lookup(-100000) + " " + lookup(7) + " " + lookup(1000) + " " + lookup(1 << 30) + " " + lookup(8));
		Main.say("switches: " + strings("Aa") + " " + strings("BB") + " " + strings("hello") + " " + strings("x"));
		Main.say("switches: " + colors(Color.RED) + colors(Color.GREEN) + colors(Color.BLUE) + " " + Color.valueOf("GREEN").ordinal());
	}
}
