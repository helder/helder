package fixture;

import java.util.Arrays;

class Arrays2 {
	static void run() {
		int[][] grid = new int[3][4];
		grid[2][3] = 9;
		long[][][] cube = new long[2][2][2];
		cube[1][1][1] = 5L;
		String[][] names = new String[2][];
		names[1] = new String[] {"x", "y"};
		Main.say("arrays: " + grid.length + "x" + grid[0].length + " " + grid[2][3] + " " + cube[1][1][1] + " " + names[1][1] + " " + (names[0] == null));
		boolean[] bs = new boolean[3];
		bs[1] = true;
		byte[] by = {1, -2, 3};
		by[0] += by[1];
		char[] cs = "abc".toCharArray();
		cs[1]++;
		short[] ss = {300};
		float[] fs = {1.5f};
		double[] ds = {2.25};
		Main.say("arrays: " + bs[1] + bs[0] + " " + by[0] + " " + new String(cs) + " " + ss[0] + " " + fs[0] + " " + ds[0]);
		Object[] objs = new String[1];
		try {
			objs[0] = 1;
		} catch (ArrayStoreException e) {
			Main.say("arrays: store");
		}
		int[] copy = new int[] {3, 1, 2}.clone();
		Arrays.sort(copy);
		Main.say("arrays: " + Arrays.toString(copy) + " " + Arrays.deepToString(new int[2][2]));
		long[] ls = new long[2];
		ls[1]++;
		ls[0] = ls[1]++ + 10;
		Main.say("arrays: " + ls[0] + " " + ls[1]);
		boolean[][] flags = new boolean[2][2];
		flags[1][0] = !flags[1][0];
		Main.say("arrays: " + flags[1][0] + " " + flags.getClass().getName());
	}
}
