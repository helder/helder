package fixture;

class Statics {
	static final String TEXT = "constant ünï";
	static final int INT = -123456;
	static final long LONG = 1234567890123L;
	static final double DOUBLE = -2.5e-3;
	static final float FLOAT = 0.1f;
	static final char CHAR = 'Z';
	static final boolean BOOL = true;
	static final byte BYTE = -5;
	static final short SHORT = 1234;
	static final String NUL = "a\0b";
	static int counter;
	static final int[] TABLE;

	static {
		TABLE = new int[] {1, 2, 3};
		counter = TABLE.length;
	}

	static void run() {
		Object[] all = {TEXT, INT, LONG, DOUBLE, FLOAT, CHAR, BOOL, BYTE, SHORT, NUL.length(), counter};
		StringBuilder b = new StringBuilder("statics:");
		for (Object o : all) b.append(' ').append(o);
		Main.say(b.toString());
		try {
			Object f = Statics.class.getDeclaredField("LONG").get(null);
			Main.say("statics: reflected " + f);
		} catch (Exception e) {
			Main.say("statics: " + e);
		}
	}
}
