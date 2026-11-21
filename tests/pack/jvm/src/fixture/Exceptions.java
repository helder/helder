package fixture;

import java.io.IOException;

class Exceptions {
	static class Res implements AutoCloseable {
		final String name;
		final boolean fail;
		Res(String name, boolean fail) {
			this.name = name;
			this.fail = fail;
		}
		public void close() throws IOException {
			Main.say("exceptions: close " + name);
			if (fail) throw new IOException("close " + name);
		}
	}

	static int fin() {
		int x = 1;
		try {
			x = 2;
			return x;
		} finally {
			x = 3;
			Main.say("exceptions: finally " + x);
		}
	}

	static String multi(int k) {
		try {
			if (k == 0) throw new IllegalStateException("state");
			if (k == 1) throw new IllegalArgumentException("arg");
			if (k == 2) return "" + (10 / (k - 2));
			return "none";
		} catch (IllegalStateException | IllegalArgumentException e) {
			return "multi " + e.getMessage();
		} catch (ArithmeticException e) {
			return "arith";
		}
	}

	static void run() {
		Main.say("exceptions: fin " + fin());
		for (int k = 0; k < 4; k++)
			Main.say("exceptions: " + multi(k));
		try (Res a = new Res("a", false); Res b = new Res("b", true)) {
			throw new RuntimeException("body");
		} catch (Exception e) {
			Main.say("exceptions: caught " + e.getMessage() + " suppressed " + e.getSuppressed().length + " " + e.getSuppressed()[0].getMessage());
		}
		try {
			try {
				throw new Error("inner");
			} finally {
				Main.say("exceptions: inner finally");
			}
		} catch (Error e) {
			Main.say("exceptions: rethrown " + e.getMessage());
		}
		int[] a = new int[2];
		try {
			a[3] = 1;
		} catch (ArrayIndexOutOfBoundsException e) {
			Main.say("exceptions: bounds");
		}
		String str = null;
		try {
			str.length();
		} catch (NullPointerException e) {
			Main.say("exceptions: npe");
		}
		int depth = 0;
		while (true) {
			try {
				if (depth++ > 2) break;
				continue;
			} finally {
				Main.say("exceptions: loop " + depth);
			}
		}
	}
}
