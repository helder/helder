package fixture;

class Sync {
	private int count;
	private static int total;

	synchronized void inc() {
		count++;
	}

	static synchronized void add(int k) {
		total += k;
	}

	synchronized int failing() {
		if (count > 0) throw new IllegalStateException("held");
		return 0;
	}

	static void run() {
		Sync s = new Sync();
		Thread[] ts = new Thread[4];
		for (int i = 0; i < ts.length; i++) {
			ts[i] = new Thread(() -> {
				for (int k = 0; k < 1000; k++) {
					s.inc();
					add(1);
				}
			});
			ts[i].start();
		}
		for (Thread t : ts) {
			try {
				t.join();
			} catch (InterruptedException e) {}
		}
		Main.say("sync: " + s.count + " " + total);
		try {
			s.failing();
		} catch (IllegalStateException e) {
			Main.say("sync: " + e.getMessage() + " " + Thread.holdsLock(s));
		}
		Object lock = new Object();
		synchronized (lock) {
			Main.say("sync: block " + Thread.holdsLock(lock));
		}
		Main.say("sync: released " + Thread.holdsLock(lock));
	}
}
