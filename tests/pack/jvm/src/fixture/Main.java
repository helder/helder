package fixture;

import java.util.ArrayList;
import java.util.List;

// Each part prints its lines; tests/pack/jvm/expected.txt is what a JVM
// prints (java -cp classes fixture.Main), the emulator's must match it.
public class Main {
	static final List<String> out = new ArrayList<>();

	static void say(String s) {
		System.out.println(s);
	}

	public static void main(String[] args) {
		run("lambdas", Lambdas::run);
		run("concat", Concat::run);
		run("exceptions", Exceptions::run);
		run("switches", Switches::run);
		run("numbers", Numbers::run);
		run("arrays", Arrays2::run);
		run("interfaces", Interfaces::run);
		run("nests", Nests::run);
		run("sync", Sync::run);
		run("stack", Stack::run);
		run("statics", Statics::run);
		run("old", Old::run);
		run("kotlin", KotlinUse::run);
		say("done");
	}

	static void run(String name, Runnable r) {
		try {
			r.run();
		} catch (Throwable t) {
			say(name + ": FAILED " + t);
		}
	}
}
