package helder.os;

import helder.test.Test;
import helder.ui.ScreenContext;

// (a path that is not there: a seal that did not hold would trash nothing)
private final NOWHERE = "/helder-seal-test/not-there";

function tests() {
	test("a sealed screen's trash, places and store files refused, thrown and kept; outside it nothing", () -> {
		var c = new ScreenContext("sealed", true), seal = new Seal("a test's screen");
		c.seal = seal;
		var thrown = [];
		c.run(() -> {
			var effects:Array<Void->Void> = [() -> Trash.move(NOWHERE), () -> Places.user(), () -> Places.volumes(), () -> Store.open("sealed-test", "bin/test/seal")];
			for (f in effects)
				try f() catch (e:Seal.SealError) thrown.push(e.message.split(" refused")[0]);
			// (its own stores: in memory, not refused)
			Store.open("sealed-test").set("a", "1");
		});
		equals(thrown, ['helder.os.Trash.move("$NOWHERE")', "helder.os.Places.user()", "helder.os.Places.volumes()", 'helder.os.Store.open("sealed-test", "bin/test/seal")']);
		equals(seal.refused.length, 4);
		equals(Seal.current, null);
		equals(sys.FileSystem.exists("bin/test/seal/sealed-test.json"), false);
	});
}
