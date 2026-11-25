import haxe.io.Bytes;
import helder.asset.Asset;
import helder.gfx.*;
import helder.gfx.shader.Vec2;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.scene.*;
import helder.scene.render.*;

// Physical material reference frames: the glTF material
// extensions, lit by a prefiltered studio (studio-ibl.png) and a sun (Scenes):
//   physical        materials made in code, drawn by Physical (every
//                   extension's variants): sheen (KHR_materials_sheen) on a
//                   dark cloth, smooth and rough; a clear coat over red
//                   metal; a thin film (iridescence); a yellow specular
//                   colour at a higher ior; brushed copper (anisotropy),
//                   along and across; a gradient read at its second uvs,
//                   turned (each map its own uvs: TEXCOORD_1); its probe
//                   checks a frame allocates nothing
//   transmission    glass in front of a checker wall, in HDR: what is behind
//                   refracted through it (Transmission's copy of the opaque
//                   frame, mip-mapped): a thin pane, a clear ball, a rough
//                   one, a ball absorbing towards green (KHR_materials_volume);
//                   its probe checks the pass was split once
//   khrspecular, khriridescence, khrvolume  Khronos' SpecularTest (CC BY 4.0
//                   Ed Mackey), CompareIridescence (CC0 Eric Chadwick and
//                   DGG) and AttenuationTest (CC BY 4.0 Ed Mackey) through
//                   Model.of: the sets of extensions their materials use
//                   compiled when compiling (PhysicalShader), no Physical;
//                   AttenuationTest in HDR, through Transmission
class PhysicalScenes {
	public static final NAMES = ["physical", "transmission", "khrspecular", "khriridescence", "khrvolume"];

	public static function make(name:String, device:Device):Encoder->Void {
		Images.decode = Images.common;
		var hdr = name == "transmission" || name == "khrvolume";
		var r = new Renderer(device, hdr, 1, hdr).use(new NormalMaps(device));
		Scenes.renderer = r;
		var env = Environment.prefiltered(device, "image/png", Asset.embed("studio-ibl.png"), 6);
		env.intensity = 6.055;
		env.background = false;
		r.use(env);
		r.clearColor = new Vec4(0.02, 0.02, 0.025, 1);
		r.sunDirection = new Vec3(-0.5, 0.7, 0.6);
		r.sunColor = new Vec3(1.5, 1.45, 1.4);
		var world = new World();
		var eye = world.node("eye");
		var camera = Camera.attach(eye, Camera.perspective(0.8, 0.01, 100));
		switch name {
			case "physical":
				r.use(new Physical());
				var sphere = Geometry.sphere({radius: 0.42, widthSegments: 48, heightSegments: 24, tangents: true});
				function ball(x:Float, y:Float, m:Material) {
					var n = world.node(m.name);
					MeshRenderer.attach(n, Shapes.of(device, sphere, m));
					n.position = new Vec3(x, y, 0);
				}
				var velvet = new Material("velvet", new Vec4(0.05, 0.02, 0.06, 1), 0, 0.8);
				velvet.sheenColor = new Vec3(0.9, 0.3, 0.6);
				velvet.sheenRoughness = 0.3;
				ball(-1, 1, velvet);
				var rough = new Material("rough velvet", new Vec4(0.05, 0.02, 0.06, 1), 0, 0.8);
				rough.sheenColor = new Vec3(0.9, 0.3, 0.6);
				rough.sheenRoughness = 0.8;
				ball(0, 1, rough);
				var coated = new Material("coated", new Vec4(0.7, 0.05, 0.05, 1), 1, 0.6);
				coated.clearcoat = 1;
				coated.clearcoatRoughness = 0.05;
				ball(1, 1, coated);
				var film = new Material("film", new Vec4(0.02, 0.02, 0.03, 1), 0, 0.15);
				film.iridescence = 1;
				film.iridescenceIor = 1.6;
				film.iridescenceThicknessMaximum = 450;
				ball(-1, 0, film);
				var yellow = new Material("yellow", new Vec4(0.05, 0.05, 0.1, 1), 0, 0.25);
				yellow.ior = 1.8;
				yellow.specularColor = new Vec3(1, 0.85, 0.1);
				ball(0, 0, yellow);
				var along = new Material("brushed", new Vec4(0.95, 0.6, 0.45, 1), 1, 0.45);
				along.anisotropy = 0.9;
				ball(1, 0, along);
				var across = new Material("brushed across", new Vec4(0.95, 0.6, 0.45, 1), 1, 0.45);
				across.anisotropy = 0.9;
				across.anisotropyRotation = Math.PI / 2;
				ball(-1, -1, across);
				// (a gradient at its second uvs, turned a quarter: the first uvs'
				// u is the second's v; red across the map's u, green down its v)
				var quad = Geometry.plane({width: 0.8, height: 0.8});
				var checked = new Material("second uvs", new Vec4(1, 1, 1, 1), 0, 0.6);
				checked.baseColorTexture = gradient(device);
				checked.textureTransforms = [
					new Material.UvTransform(new Vec2(0, 1), Math.PI / 2, new Vec2(1, 1), 1), new Material.UvTransform(), new Material.UvTransform(),
					new Material.UvTransform(), new Material.UvTransform()
				];
				var mesh = Shapes.of(device, quad, checked);
				var p = mesh.primitives[0];
				var b = Bytes.alloc(quad.vertexCount * 8);
				for (k in 0...quad.vertexCount) {
					var uv = quad.uv(k);
					b.setFloat(8 * k, uv.y);
					b.setFloat(8 * k + 4, uv.x);
				}
				p.uv1 = device.createBuffer({size: b.length, usage: Vertex, data: b});
				var n = world.node("second uvs");
				MeshRenderer.attach(n, mesh);
				n.position = new Vec3(0, -1, 0);
				eye.position = new Vec3(0, 0, 4.4);
				eye.lookAt(new Vec3(0, 0, 0));
				var draw = enc -> r.draw(enc, world, camera);
				Scenes.probe = () -> allocated(device, draw);
				return draw;
			case "transmission":
				r.use(new Physical()).use(new Transmission(device));
				var wall = world.node("wall");
				var paper = new Material("wall", new Vec4(1, 1, 1, 1), 0, 0.7);
				paper.baseColorTexture = checker(device, 8, [230, 230, 230], [30, 30, 40]);
				paper.uvScale = new Vec2(1, 0.75);
				MeshRenderer.attach(wall, Shapes.of(device, Geometry.plane({width: 6, height: 4}), paper));
				wall.position = new Vec3(0, 0, -1.2);
				var sphere = Geometry.sphere({radius: 0.42, widthSegments: 48, heightSegments: 24});
				function glass(x:Float, roughness:Float, thickness:Float, ?absorbs:Vec3):Material {
					var m = new Material("glass", new Vec4(1, 1, 1, 1), 0, roughness);
					m.transmission = 1;
					m.thickness = thickness;
					m.blend = Premultiplied;
					m.castShadows = false;
					if (absorbs != null) {
						m.attenuationColor = absorbs;
						m.attenuationDistance = 0.4;
					}
					var n = world.node("glass");
					MeshRenderer.attach(n, thickness == 0 ? Shapes.of(device, Geometry.plane({width: 0.8, height: 0.8}), m) : Shapes.of(device, sphere, m));
					n.position = new Vec3(x, 0, 0);
					return m;
				}
				glass(-1.5, 0, 0);
				glass(-0.5, 0, 0.84);
				glass(0.5, 0.35, 0.84);
				glass(1.5, 0, 0.84, new Vec3(0.2, 0.8, 0.3));
				eye.position = new Vec3(0, 0.3, 4.6);
				eye.lookAt(new Vec3(0, 0, 0));
				var draw = offscreen(device, r, world, camera);
				Scenes.probe = () -> r.splits == 1 ? null : 'transmission: the pass split ${r.splits} times (1 expected)';
				return draw;
			case _:
				r.sunColor = new Vec3(0, 0, 0);
				if (name == "khrvolume") r.use(new Transmission(device));
				switch name {
					case "khrspecular": Model.of("SpecularTest.glb").instantiate(world, device);
					case "khriridescence": Model.of("CompareIridescence.glb").instantiate(world, device);
					case _: Model.of("AttenuationTest.glb").instantiate(world, device);
				}
				var b = helder.scene.math.Aabb.empty(), meshes = world.store(MeshRenderer.KIND);
				for (k in 0...meshes.length)
					b = b.union(meshes.valueAt(k).bounds.transform(meshes.nodeAt(k).worldMatrix()));
				var c = (b.min + b.max) * 0.5, d = b.max - b.min, t = Math.tan(0.4);
				// (CompareIridescence's two balls: the frame's centre on the iridescent one)
				if (name == "khriridescence") c = c + new Vec3(d.x * 0.25, 0, 0);
				eye.position = c + new Vec3(0, 0, Math.max(d.x * 0.5 / (t * device.width / device.height), d.y * 0.5 / t) * 1.1 + d.z * 0.5);
				eye.lookAt(c);
				return hdr ? offscreen(device, r, world, camera) : enc -> r.draw(enc, world, camera);
		}
	}

	// (drawn in HDR into a target of the frame's size, then tone mapped into the frame)
	static function offscreen(device:Device, r:Renderer, world:World, camera:Camera):Encoder->Void {
		var post = new PostProcess(device, RGBA8, true);
		post.bloom = 0;
		r.post = post;
		var w = device.width, h = device.height;
		var light = device.createTexture({width: w, height: h, format: RGBA16F, renderTarget: true});
		var depth = device.createTexture({width: w, height: h, format: Depth32F});
		return enc -> {
			r.drawInto(enc, world, camera, light, depth, w, h);
			post.run(enc, light, null, w, h);
		};
	}

	// a checker of n squares a side (sRGB colours), 64 texels wide
	static function checker(device:Device, n:Int, a:Array<Int>, b:Array<Int>):Texture {
		var w = 64, rgba = Bytes.alloc(w * w * 4);
		for (y in 0...w)
			for (x in 0...w) {
				var c = (Std.int(x * n / w) + Std.int(y * n / w)) & 1 == 0 ? a : b;
				var p = 4 * (y * w + x);
				rgba.set(p, c[0]);
				rgba.set(p + 1, c[1]);
				rgba.set(p + 2, c[2]);
				rgba.set(p + 3, 255);
			}
		return Images.mipmapped(device, w, w, rgba);
	}

	// red across u, green down v, 64 texels a side
	static function gradient(device:Device):Texture {
		var w = 64, rgba = Bytes.alloc(w * w * 4);
		for (y in 0...w)
			for (x in 0...w) {
				var p = 4 * (y * w + x);
				rgba.set(p, Std.int(x * 255 / (w - 1)));
				rgba.set(p + 1, Std.int(y * 255 / (w - 1)));
				rgba.set(p + 2, 60);
				rgba.set(p + 3, 255);
			}
		return Images.mipmapped(device, w, w, rgba);
	}

	// (the frame drawn again: once warm, nothing allocated by a frame)
	static function allocated(device:Device, draw:Encoder->Void):Null<String> {
		for (_ in 0...3) {
			var enc = device.beginFrame();
			draw(enc);
			device.endFrame();
		}
		#if (target.name == "hxmc")
		var before = hxmc.GcStats.bytesAllocated();
		for (_ in 0...4) {
			var enc = device.beginFrame();
			draw(enc);
			device.endFrame();
		}
		var bytes = hxmc.GcStats.bytesAllocated() - before;
		Sys.println('PhysicalScenes: $bytes bytes allocated by 4 frames');
		if (bytes != 0) return 'physical: $bytes bytes allocated by 4 frames (none expected)';
		#end
		return null;
	}
}
