package helder.scene.view;

import helder.scene.World;
import helder.scene.view.SceneRenderer.SceneNode;

// What markup on one world shares (DESIGN-MARKUP.md 2.4, 3.3, 3.4): the
// device its meshes are made on (the first box drawing it sets it; the
// meshes made before then wait), its frame's stages (onFrame, Frame.on),
// and whether it changed (each box drawing it drawn again). One per world
// (of), none of it static: two <Scene>s of two worlds, or on two windows'
// devices, are apart.
class SceneScope {
	public final world:World;
	// the device its meshes are made on (null: none yet, they wait)
	public var device(default, set):Null<helder.gfx.Device> = null;
	// its frame's work (onFrame and Frame.on: Update; the others by name)
	public final stages = new helder.scene.Stages();
	// (the boxes drawing it, asked to draw again when it changes)
	@:allow(helder.scene.view) final boxes:Array<SceneBox> = [];
	// (the meshes waiting for a device)
	@:allow(helder.scene.view) final pending:Array<SceneNode> = [];
	// (the frame callbacks registered: while any is, its boxes draw every frame)
	var frames = 0;
	var steppedAt = -1.0;
	// the changes asked since it was last drawn (a box's demand drawing; a
	// test's or a benchmark's count)
	public var changes(default, null) = 0;

	function new(world:World) {
		this.world = world;
	}

	static final scopes = new Map<Int, SceneScope>();

	// the scope of world (made once)
	public static function of(world:World):SceneScope {
		var k = @:privateAccess world.index;
		var s = scopes.get(k);
		if (s == null || s.world != world) scopes.set(k, s = new SceneScope(world));
		return s;
	}

	function set_device(d:Null<helder.gfx.Device>) {
		device = d;
		if (d != null) {
			for (n in pending)
				if (n.node.valid) n.remesh();
			pending.resize(0);
		}
		return d;
	}

	// something in its world changed: each box drawing it draws again
	public function invalidate() {
		changes++;
		for (b in boxes)
			b.changed();
	}

	// f run in stage each frame while its owner lives (Graph.onCleanup);
	// its boxes drawing every frame meanwhile
	public function on(stage:helder.scene.Stages.Stage, f:Float->Void) {
		var off = stages.on(stage, f);
		frames++;
		wake();
		var removed = false;
		var remove = () -> if (!removed) {
			removed = true;
			off();
			frames--;
		};
		if (helder.view.graph.Graph.getOwner() != null) helder.view.graph.Graph.onCleanup(remove);
		return remove;
	}

	// (the meshes to make again, once each, when the commit settles: their
	// make props and parts all set, not one mesh a prop)
	final stale:Array<SceneNode> = [];

	@:allow(helder.scene.view) function remake(n:SceneNode) {
		stale.push(n);
		if (stale.length == 1) helder.view.graph.Graph.root(dispose -> helder.view.graph.Graph.onSettled(() -> {
			settle();
			dispose();
		}));
	}

	// the meshes waiting made now (a program's, a test's: without a flush)
	public function settle() {
		var k = 0;
		while (k < stale.length) {
			var n = stale[k++];
			if (@:privateAccess n.queued && n.node.valid) n.remesh();
		}
		stale.resize(0);
	}

	// whether it has frame callbacks (its boxes draw every frame)
	public var active(get, never):Bool;

	inline function get_active():Bool
		return frames > 0;

	// one frame of its stages at time t (seconds; once per t, whichever of
	// its boxes asks first): false when it has none left
	public function frame(t:Float):Bool {
		if (t == steppedAt) return frames > 0;
		var dt = steppedAt < 0 ? 0 : Math.min(0.1, t - steppedAt);
		steppedAt = t;
		if (frames == 0) return false;
		stages.frame(dt);
		invalidate();
		return frames > 0;
	}

	// (its boxes' clocks stepping it, while it has frame callbacks)
	function wake()
		for (b in boxes)
			b.step();
}
