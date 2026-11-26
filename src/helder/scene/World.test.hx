package helder.scene;

import helder.scene.view.SceneTags.*;
import helder.test.Gen;
import helder.test.Test;
import helder.ui.Ui;
import helder.view.Render;

// Worlds' slots (16 a process: a node's id's 4 bits) under random
// lifetimes (a stateful property, headless, no device): worlds made and
// disposed (some twice), <Scene>s mounted and unmounted, of their own
// world and of one given them. After each step the worlds alive are those
// the steps hold: a <Scene>'s own world let go with it, a given one kept;
// a second dispose frees nothing (its slot may be another's); at the end,
// none left. (A <Scene>'s own world was kept after it: main's test lane,
// after its 16th, "more than 16 worlds alive")
function tests() {
	test("worlds alive: those held, in any order of making and letting go", () -> stateful({
		setup: () -> new Fixture(),
		steps: [
			{name: "a world", run: (f, _) -> f.world(), when: f -> f.room() > 0},
			{name: "a world disposed", run: (f, c) -> f.dispose(c.draw(int(0, 15)), c.draw(bool())), when: f -> f.worlds.length > 0},
			{name: "a <Scene> of its own", run: (f, _) -> f.scene(-1), when: f -> f.room() > 0},
			{name: "a <Scene> of a world given", run: (f, c) -> f.scene(c.draw(int(0, 15))), when: f -> f.worlds.length > 0},
			{name: "a <Scene> unmounted", run: (f, c) -> f.unmount(c.draw(int(0, 15))), when: f -> f.scenes.length > 0}
		],
		check: f -> f.check(),
		teardown: f -> f.teardown()
	}, {cases: 100, steps: 40}));
	test("the 17th world alive refused; one let go, its slot taken again", () -> {
		var base = World.alive(), made = [for (_ in base...16) new World()];
		equals(World.alive(), 16);
		throws(() -> {
			new World();
		});
		made.pop().dispose();
		made.push(new World());
		equals(World.alive(), 16);
		for (w in made)
			w.dispose();
		equals(World.alive(), base);
	});
}

private class Fixture {
	final ui = new Ui(null, 100, 100);
	// (those of other files' tests alive when it began: not its own)
	final base = World.alive();
	public final worlds:Array<World> = [];
	// (each mounted: its unmount, the world given it, else null, and its box's)
	public final scenes:Array<{unmount:() -> Void, given:Null<World>, own:Null<World>}> = [];

	public function new() {}

	// (slots left: of 16)
	public function room():Int
		return 16 - World.alive();

	public function world()
		worlds.push(new World());

	// worlds[i] disposed (twice: the second frees nothing); a <Scene> given it unmounted first
	public function dispose(i:Int, twice:Bool) {
		var w = worlds.splice(i % worlds.length, 1)[0];
		for (s in [for (s in scenes) if (s.given == w) s])
			unmount(scenes.indexOf(s));
		w.dispose();
		if (twice) w.dispose();
	}

	// a <Scene> mounted: of worlds[i] (i < 0: of its own)
	public function scene(i:Int) {
		var given = i < 0 ? null : worlds[i % worlds.length], box:Null<helder.scene.view.SceneBox> = null;
		var unmount = Render.render(Markup.scene(given, b -> box = b), ui.root);
		ui.update();
		scenes.push({unmount: unmount, given: given, own: given == null ? box.world : null});
	}

	public function unmount(i:Int) {
		var s = scenes.splice(i % scenes.length, 1)[0];
		s.unmount();
		// (a given world kept)
		if (s.given != null) equals(s.given.count >= 1 && World.all.indexOf(s.given) >= 0, true, "the world given a <Scene> kept after it");
	}

	public function check() {
		var own = [for (s in scenes) if (s.own != null) s.own];
		equals(World.alive(), base + worlds.length + own.length, "the worlds alive: those held");
		for (w in worlds.concat(own))
			equals(World.all.indexOf(w) >= 0, true, "a world held alive");
	}

	public function teardown() {
		while (scenes.length > 0)
			unmount(0);
		for (w in worlds)
			w.dispose();
		worlds.resize(0);
		equals(World.alive(), base, "none left");
	}
}

private class Markup implements helder.view.Markup {
	public static function scene(world:Null<World>, ref:helder.scene.view.SceneBox->Void)
		return <view width={100} height={100}>
			<Scene world={world} ref={ref} flexGrow={1}/>
		</view>;
}
