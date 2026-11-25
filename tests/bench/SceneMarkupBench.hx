import haxe.Timer;
import helder.math.Vec3;
import helder.scene.Camera;
import helder.scene.Node;
import helder.scene.World;
import helder.scene.render.Material;
import helder.scene.render.Mesh;
import helder.scene.render.MeshRenderer;
import helder.scene.render.VertexData;
import helder.scene.view.SceneRenderer;
import helder.view.*;
import helder.view.graph.Graph;
import helder.view.graph.Signal;

// The same scene built in code and in markup (DESIGN-MARKUP.md 9.1), at n
// nodes: each a mesh of one shared geometry and material (one instanced
// draw), on a grid. Variants:
//
//   code        world.node, MeshRenderer.attach; a loop writes the positions
//   constant    markup, nothing bound (the positions set once); the same loop
//               writes the nodes markup made (their refs)
//   signals     each mesh's position bound to a signal of its own, each
//               written every frame, then a flush (the worst case)
//   steps       each mesh's own clock step writing its signal (examples/
//               planets' pattern: helder.ui.Clock.add per node)
//
// Measured, each variant in a process of its own: mounting (ms, GC bytes),
// FRAMES frames with every node moving (the markup's share: the writes, the
// clock and the flush; then the renderer's recorded pass; ms and GC bytes
// each, the mean of the frames: wasm32's clock is too coarse for one), IDLE idle frames (those asking for a redraw: SceneRenderer.changed
// called, or a clock still stepping), unmounting (ms, the world's nodes left over the
// count before mounting). wasm32-wasi has no GPU: its nodes are bare (no
// mesh, no pass recorded).
//
//   SceneMarkupBench <variant> <n>
//
// One line:
//
//   scene-markup <variant> <n> <mount ms> <mount KB> <frame ms> <frame B> <pass ms> <pass B> <idle frames drawing> <unmount ms> <nodes left>
class SceneMarkupBench implements Markup {
	static inline var FRAMES = 200;
	static inline var WARM = 20;
	static inline var IDLE = 100;

	static var world:World;
	static var geometry:VertexData;
	static var material:Material;
	static var mesh:Null<Mesh>;
	static var asks = 0;
	#if (hxmc.target != "wasm32-wasi")
	static var device:helder.gfx.Device;
	static var renderer:helder.scene.render.Renderer;
	#end
	static var camera:Camera;

	static function main() {
		var args = Sys.args();
		var variant = args[0], n = Std.parseInt(args[1]);
		world = new World("bench");
		var eye = world.node("eye");
		camera = Camera.attach(eye, Camera.perspective(1.0, 0.1, 500));
		eye.position = new Vec3(0, 60, 120);
		eye.lookAt(new Vec3(0, 0, 0));
		geometry = helder.scene.render.Geometry.box({width: 0.5, height: 0.5, depth: 0.5});
		material = Material.standard({});
		#if (hxmc.target != "wasm32-wasi")
		device = helder.gfx.Device.create(helder.os.Surface.headless(64, 64));
		renderer = new helder.scene.render.Renderer(device);
		SceneRenderer.device = device;
		mesh = helder.scene.render.Shapes.of(device, geometry, material);
		#end
		SceneRenderer.changed = () -> asks++;
		var root = SceneRenderer.root(world);
		var before = world.count;

		// --- mount
		var nodes:Array<Node> = [];
		var signals:Array<Signal<Vec3>> = [for (k in 0...n) helder.view.graph.Graph.signal(start(k, n))];
		var dispose:Void->Void = () -> {};
		Graph.flush();
		var b0 = GcStats.bytes(), t0 = Timer.stamp();
		switch variant {
			case "code":
				for (k in 0...n) {
					var x = world.node("m");
					x.position = start(k, n);
					if (mesh != null) MeshRenderer.attach(x, mesh);
					nodes.push(x);
				}
				dispose = () -> for (x in nodes) x.dispose();
			case "constant":
				var ps = [for (k in 0...n) start(k, n)];
				#if (hxmc.target != "wasm32-wasi")
				dispose = Render.render(<node>{[for (k in 0...n) <mesh position={ps[k]} geometry={geometry} material={material} ref={s -> nodes.push(s.node)}/>]}</node>, root);
				#else
				dispose = Render.render(<node>{[for (k in 0...n) <node position={ps[k]} ref={s -> nodes.push(s.node)}/>]}</node>, root);
				#end
			case "signals" | "steps":
				#if (hxmc.target != "wasm32-wasi")
				dispose = Render.render(<node>{[for (k in 0...n) <mesh position={signals[k]} geometry={geometry} material={material}/>]}</node>, root);
				#else
				dispose = Render.render(<node>{[for (k in 0...n) <node position={signals[k]}/>]}</node>, root);
				#end
				if (variant == "steps")
					for (k in 0...n) {
						var s = signals[k];
						helder.ui.Clock.add(t -> {
							s(moved(k, n, t));
							true;
						});
					}
			case _:
				throw 'SceneMarkupBench: no variant $variant (code, constant, signals, steps)';
		}
		Graph.flush();
		var mountMs = (Timer.stamp() - t0) * 1000, mountBytes = GcStats.bytes() - b0;

		// --- frames, every node moving
		var frameMs = 0.0, frameBytes = 0.0, passMs = 0.0, passBytes = 0.0;
		var t = 0.0;
		for (f in 0...WARM + FRAMES) {
			t += 1 / 60;
			var b1 = GcStats.bytes(), t1 = Timer.stamp();
			switch variant {
				case "code" | "constant":
					for (k in 0...n)
						nodes[k].position = moved(k, n, t);
				case "signals":
					for (k in 0...n)
						signals[k](moved(k, n, t));
					Graph.flush();
				case "steps":
					helder.ui.Clock.tick(t);
					Graph.flush();
				case _:
			}
			var t2 = Timer.stamp(), b2 = GcStats.bytes();
			#if (hxmc.target != "wasm32-wasi")
			var enc = device.beginFrame();
			if (enc != null) renderer.draw(enc, world, camera, 16 / 9);
			#else
			// (no pass: the world's matrices, as a pass reads them)
			touch(world.root);
			#end
			var t3 = Timer.stamp(), b3 = GcStats.bytes();
			#if (hxmc.target != "wasm32-wasi")
			device.endFrame();
			#end
			if (f >= WARM) {
				frameMs += (t2 - t1) * 1000;
				frameBytes += b2 - b1;
				passMs += (t3 - t2) * 1000;
				passBytes += b3 - b2;
			}
		}

		// --- idle frames: nothing changes
		var idle = 0;
		for (_ in 0...IDLE) {
			asks = 0;
			// (the steps go on: each writes its signal again)
			if (variant == "steps") helder.ui.Clock.tick(t);
			Graph.flush();
			if (asks > 0 || helder.ui.Clock.active) idle++;
		}

		// --- unmount
		var t4 = Timer.stamp();
		dispose();
		Graph.flush();
		var unmountMs = (Timer.stamp() - t4) * 1000;
		var left = world.count - before;
		inline function r(v:Float):String
			return Std.string(Math.round(v * 1000) / 1000);
		Sys.println([
			"scene-markup", variant, Std.string(n), r(mountMs), r(mountBytes / 1024), r(frameMs / FRAMES), Std.string(Math.round(frameBytes / FRAMES)), r(passMs / FRAMES),
			Std.string(Math.round(passBytes / FRAMES)), Std.string(idle), r(unmountMs), Std.string(left)
		].join(" "));
		Sys.exit(0);
	}

	// (every node's world matrix, under n)
	static function touch(n:Node)
		for (c in n.children()) {
			c.worldMatrix();
			touch(c);
		}

	// (node k of n on a square grid, 1.5 apart)
	static inline function start(k:Int, n:Int):Vec3 {
		var side = Math.ceil(Math.sqrt(n));
		return new Vec3((k % side) * 1.5 - side * 0.75, 0, Std.int(k / side) * 1.5 - side * 0.75);
	}

	static inline function moved(k:Int, n:Int, t:Float):Vec3 {
		var side = Math.ceil(Math.sqrt(n));
		return new Vec3((k % side) * 1.5 - side * 0.75, Math.sin(t * 2 + k * 0.1), Std.int(k / side) * 1.5 - side * 0.75);
	}

}
