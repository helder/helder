// title: GPU particles
// summary: A fountain of sparks moved by the GPU: each written once when it is emitted, then moved by the vertex shader under gravity and drag, a burst on a tap
// tags: 3d, particles, docs
// demo: canvas 640x400
import helder.gfx.*;
import helder.math.Vec3;
import helder.math.Vec4;
import helder.os.*;
import helder.scene.*;
import helder.scene.math.*;
import helder.scene.render.*;

// GpuParticles is a renderer feature: emit writes a particle once into a
// ring (its start, velocity, colour, size over its life), and the GPU
// moves it from then on from the feature's clock (advance), so a frame
// costs only the particles born in it. Colours are linear light: above 1
// they are brighter than white (heat whitens the young ones).
//
//   helder run docs/examples/scene-particles
class Sparks {
	static function main() {
		var window = new Window({title: "GPU particles", width: 640, height: 400});
		var device = Device.create(window.surface);
		var fx = new GpuParticles(device, 32768);   // the ring: the oldest written over when full
		fx.gravity = new Vec3(0, -4, 0);
		fx.drag = 0.4;
		var renderer = new Renderer(device).use(fx);
		renderer.clearColor = new Vec4(0.02, 0.02, 0.03, 1);
		renderer.sky = new Vec3(0.06, 0.06, 0.08);
		renderer.ground = new Vec3(0.03, 0.03, 0.03);

		var world = new World("sparks");
		var floor = world.node("floor");
		MeshRenderer.attach(floor, Shapes.plane(device, new Material("floor", new Vec4(0.2, 0.2, 0.22, 1), 0, 0.6), 12));
		var nozzle = world.node("nozzle");
		nozzle.position = new Vec3(0, 0.15, 0);
		MeshRenderer.attach(nozzle, Shapes.box(device, new Material("nozzle", new Vec4(0.3, 0.3, 0.32, 1), 1, 0.3), 0.3, 0.3, 0.3));
		var eye = world.node("eye");
		var camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 100));
		eye.position = new Vec3(0, 2.2, 7);
		eye.lookAt(new Vec3(0, 1.3, 0));

		var seed = 7;
		function rand():Float {
			seed = (seed * 1103515245 + 12345) & 0x7fffffff;
			return seed / 0x7fffffff;
		}
		var last = -1.0, owed = 0.0, burst = 0;
		App.run(() -> {
			var now = App.frame.time;
			var dt = last < 0 ? 0 : Math.min(now - last, 0.1);
			last = now;
			fx.advance(dt);
			// 3,000 a second up out of the nozzle, a burst of 4,000 when asked
			owed += dt * 3000;
			var n = Std.int(owed);
			owed -= n;
			for (i in 0...n) {
				var a = rand() * Math.PI * 2, s = 0.6 + rand() * 0.8;
				fx.emit(0, 0.3, 0, Math.cos(a) * s, 4 + rand() * 1.2, Math.sin(a) * s,   // where, how fast
					3, 1.3 + rand(), 0.4, 1,                                           // linear colour, opacity
					0.03, 0.01, 1.5 + rand(),                                          // size at birth and death, life (s)
					0.03, 0.8);                                                        // a streak of 0.03 s, hot when young
			}
			for (i in 0...burst) {
				var a = rand() * Math.PI * 2, u = rand() * 2 - 1, s = 3 + rand() * 3, r = Math.sqrt(1 - u * u);
				fx.emit(0, 2.5, 0, Math.cos(a) * r * s, u * s, Math.sin(a) * r * s, 0.6, 1.2, 3, 1, 0.04, 0.0, 1 + rand(), 0.04, 1);
			}
			burst = 0;
			var enc = device.beginFrame();
			if (enc == null) return;
			renderer.draw(enc, world, camera);
			device.endFrame();
		}, e -> switch e.kind {
			case Close: window.close();
			case KeyDown if (e.key == 0xFF1B): window.close();
			case PointerDown | KeyDown: burst = 4000;
			case _:
		});
	}
}
