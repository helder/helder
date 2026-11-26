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
	// (world matrices kept by epoch and inTree by the tree's shape: after
	// any steps, each node's as a walk up to the root makes it)
	test("world matrices and inTree: as walked, after any moves and reparenting", () -> stateful({
		setup: () -> new Tree(),
		steps: [
			{name: "a node", run: (t, c) -> t.add(c.draw(int(0, 99)))},
			{name: "moved", run: (t, c) -> t.move(c.draw(int(0, 99)), c.draw(int(0, 3)), c.draw(float(-2, 2))), when: t -> t.nodes.length > 0},
			{name: "under another", run: (t, c) -> t.reparent(c.draw(int(0, 99)), c.draw(int(0, 99))), when: t -> t.nodes.length > 1},
			{name: "detached", run: (t, c) -> t.detach(c.draw(int(0, 99))), when: t -> t.nodes.length > 0},
			{name: "disposed", run: (t, c) -> t.dispose(c.draw(int(0, 99))), when: t -> t.nodes.length > 0},
			{name: "asked", run: (t, c) -> t.ask(c.draw(int(0, 99))), when: t -> t.nodes.length > 0}
		],
		check: t -> t.check(),
		teardown: t -> t.world.dispose()
	}, {cases: 60, steps: 40}));
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

private class Tree {
	public final world = new World();
	public final nodes:Array<Node> = [];

	public function new() {}

	inline function at(i:Int):Node
		return nodes[i % nodes.length];

	public function add(i:Int)
		nodes.push(world.node("", nodes.length == 0 || i % 3 == 0 ? null : at(i)));

	// (one of position, rotation, scale, or the same position again)
	public function move(i:Int, what:Int, v:Float) {
		var n = at(i);
		switch what {
			case 0: n.position = new helder.math.Vec3(v, v * 0.5, -v);
			case 1: n.rotation = helder.math.Quat.axisAngle(new helder.math.Vec3(0, 1, 0), v);
			case 2: n.scale = new helder.math.Vec3(1 + v * 0.1, 1, 1);
			case _: n.position = n.position;
		}
	}

	public function reparent(i:Int, j:Int) {
		var c = at(i), p = at(j), a = p;
		while (!a.isNone) {
			if (a == c) return;
			a = a.parent;
		}
		p.add(c);
	}

	public function detach(i:Int)
		at(i).detach();

	public function dispose(i:Int) {
		at(i).dispose();
		var left = [for (n in nodes) if (n.valid) n];
		nodes.resize(0);
		for (n in left)
			nodes.push(n);
	}

	public function ask(i:Int)
		at(i).worldMatrix();

	public function check()
		for (n in nodes) {
			var m = n.localMatrix(), p = n.parent, rooted = false;
			while (!p.isNone) {
				m = p.localMatrix() * m;
				if (p == world.root) rooted = true;
				p = p.parent;
			}
			equals(helder.scene.math.MathTools.near(n.worldMatrix(), m, 1e-9), true, "a world matrix as walked");
			equals(world.inTree(n), rooted, "inTree as walked");
		}
}
