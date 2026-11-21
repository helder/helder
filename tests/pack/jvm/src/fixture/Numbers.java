package fixture;

class Numbers {
	static long fact(int n) {
		long r = 1;
		for (int i = 2; i <= n; i++) r *= i;
		return r;
	}

	static void run() {
		Main.say("numbers: " + fact(20) + " " + (fact(20) >>> 3) + " " + (fact(20) >> 60) + " " + (-fact(20) >> 3) + " " + (1L << 63));
		long a = Long.MIN_VALUE, b = -1;
		Main.say("numbers: " + (a / b) + " " + (a % b) + " " + (-7 % 3) + " " + (-7 / 2) + " " + (7L % -3L));
		double nan = Double.NaN;
		Main.say("numbers: " + (nan < 1) + " " + (nan > 1) + " " + (nan == nan) + " " + Double.compare(nan, 1) + " " + (0.1 + 0.2));
		float f = 3.7f;
		Main.say("numbers: " + (int) f + " " + (long) -f + " " + (int) 1e20 + " " + (long) Double.NEGATIVE_INFINITY + " " + (int) nan);
		Main.say("numbers: " + (byte) 300 + " " + (short) 70000 + " " + (char) 65 + " " + (int) (char) -1 + " " + (float) (1L << 40));
		int x = Integer.MAX_VALUE;
		x++;
		Main.say("numbers: " + x + " " + (x >>> 1) + " " + (x >> 1) + " " + (x << 1) + " " + Integer.toHexString(~x) + " " + (5 & 3 | 8 ^ 2));
		long m = 0x123456789abcdefL;
		Main.say("numbers: " + Long.toHexString(m) + " " + (m & 0xffff) + " " + (m | 1) + " " + (m ^ -1L) + " " + Long.bitCount(m));
		try {
			Main.say("numbers: " + (1 / (x - x)));
		} catch (ArithmeticException e) {
			Main.say("numbers: div by zero");
		}
		double d = 1e300;
		Main.say("numbers: " + d * 1e10 + " " + (float) d + " " + Math.sqrt(2) + " " + (5.5 % 2) + " " + (-0.0 == 0.0));
		int lcmp = Long.compare(5L, 3L) + Long.compare(-5L, 3L);
		Main.say("numbers: " + lcmp + " " + (100000 * 100000) + " " + (100000L * 100000));
	}
}
