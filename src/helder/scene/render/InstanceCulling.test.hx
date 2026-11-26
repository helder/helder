package helder.scene.render;

import helder.gfx.Device;
import helder.math.Vec3;
import helder.math.Vec4;
import helder.os.Surface;
import helder.scene.Camera;
import helder.scene.World;
import helder.test.Test;

// InstanceCulling on the CPU beside one on the GPU, on one device: the CPU
// one's buffers its own (`bench light`'s culled then culled-cpu: the GPU
// one made the sets' copies storage buffers, and the CPU one, asking the
// device, culled into bytes it never allocated: OutsideBounds)
function tests() {
	describe("InstanceCulling", () -> {
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		test("on the CPU after one on the GPU: a frame culls into its own bytes", () -> {
			var device = Device.create(Surface.headless(64, 64));
			var stone = Material.lambert({color: new Vec4(0.6, 0.6, 0.6, 1)});
			var mesh = Shapes.of(device, Geometry.box({width: 1, height: 1, depth: 1}), stone);
			function frame(gpu:Bool):InstanceCulling {
				var world = new World(), r = new Renderer(device);
				var eye = world.node("eye");
				eye.position = new Vec3(0, 0, 10);
				var camera = Camera.attach(eye, Camera.perspective(0.9, 0.1, 80));
				var field = new InstancedMesh(mesh, 8);
				for (i in 0...8)
					field.setTransform(i, i < 4 ? i * 2 - 3 : 500, 0, 0, 0, 0, 0, 1, 1);
				InstancedMesh.attach(world.node("field"), field);
				var c = new InstanceCulling(device, gpu);
				r.use(c);
				var enc = device.beginFrame();
				r.draw(enc, world, camera, 1);
				device.endFrame();
				r.dispose();
				return c;
			}
			frame(true);
			var cpu = frame(false);
			equals([cpu.kept, cpu.culled], [4, 4]);
			device.dispose();
		});
		#end
	});
}
