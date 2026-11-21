package fixture;

class Concat {
	static void run() {
		int i = -3;
		long j = 1L << 40;
		char c = 'q';
		double d = 2.5;
		float f = 1.25f;
		boolean b = true;
		byte by = 7;
		short sh = -9;
		Object o = null;
		String s = "str";
		Main.say("concat: " + i + "," + j + "," + c + "," + d + "," + f + "," + b + "," + by + "," + sh + "," + o + "," + s);
		Main.say("concat: " + i + j + c);
		Main.say("concat: \u0001 and \u0002 " + s);
		Main.say("concat: é ünïcode " + s + " 😀");
		Main.say("concat: " + new StringBuilder("sb").append(1));
		String n = "nul\0in";
		Main.say("concat: " + n.length() + " " + (int) n.charAt(3));
	}
}
