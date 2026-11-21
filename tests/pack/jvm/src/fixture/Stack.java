package fixture;

class Stack {
	long wide;
	int narrow;
	static long swide;

	static void run() {
		Stack s = new Stack();
		int a, b;
		a = b = 7;
		long w = s.wide++;
		long v = ++s.wide;
		int n = s.narrow++ + ++s.narrow;
		swide += 5;
		long t = swide++;
		long[] arr = {1, 2};
		long u = arr[1]++;
		int[] ia = {5};
		int z = ia[0]--;
		Main.say("stack: " + a + b + " " + w + " " + v + " " + n + " " + t + " " + swide + " " + u + " " + arr[1] + " " + z + " " + ia[0]);
		double[] d = {1.5};
		double e = d[0] *= 2;
		Main.say("stack: " + e + " " + d[0]);
	}
}
