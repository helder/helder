import helder.gfx.*;
import helder.gfx.shader.Vec3;
import helder.os.*;

// helder.scene's cost per feature (sizes.sh, run by hand: no lane runs it): one program, a
// window clearing its frame, with each level adding a feature on top of
// the one before (-D size_level=<n>):
//   0  gfx alone (a window, a device, a cleared frame)
//   1  + the math (Quat, MathTools: a turning matrix)
//   2  + the world (World, Node, Camera, FixedStep)
//   3  + the glTF reader (Gltf.parse of the sample scene, GltfNodes)
//   4  + the renderer (GltfScene, Renderer, PbrShader: the scene drawn)
//   5  + shadows (Shadows: a shadow map pass)
//   6  + input actions (InputMap)
//   7  + keyframe animation (AnimationClip, Animator)
//   8  + skinning (Skinning: the skinned shader)
//   9  + normal maps (NormalMaps: the normal-mapped shader)
// and, with -D size_packed at level 4, the renderer drawing the sample
// packed at build time (PackedModel: no glTF reader, no JSON); at level 4
// too, the opt-ins of DESIGN-3D.md's phase 1, each a cost only when used:
// -D size_toon (Material.toon: one shading model's shader), -D size_models
// (every Material factory: lambert, phong, toon, unlit, matcap, normals,
// depth), -D size_geometry (every Geometry generator and Curve3),
// -D size_sprites (Sprites on an unlit material); and phase 3's: -D
// size_lines (a LineRenderer and Lines), -D size_debug (DebugDraw, its
// calls and the line helpers), -D size_grid (GridHelper's infinite grid),
// -D size_raycast (world.raycast: Raycaster and Bvh), -D size_text3d
// (Text3D: helder.text's layout, canvas' outlines and boolean ops, the
// triangulator; its font read at run time, not embedded), -D
// size_debugcalls (Debug's calls alone, built with -D helder.release:
// compiled out, nothing linked); and phase 6's, the glTF material
// extensions: -D size_sheen, size_specular, size_clearcoat,
// size_transmission, size_iridescence, size_anisotropy, size_uvsets (a box
// drawn by that extension's variants alone: PhysicalShader.of), -D
// size_physical (Physical: every extension's), -D size_refraction
// (Transmission, the frame behind see-through surfaces); and phase 4's:
// -D size_clustered (ClusteredLights: the CPU's cells and the compute path's shader), -D
// size_culling (InstanceCulling: the CPU's and the compute path's), -D
// size_lod (Lod on a node: its levels, the visible ranges); phase 5's: -D
// size_prefilter (Environment.prefilter: Sh, the prefilter's two paths), -D
// size_probes (Probes, its components and variants), -D size_area
// (AreaLights: its variants, the tables), -D size_lightmaps (Lightmaps); and at level 5,
// -D size_local (Shadows' point and spot lights' tiles: LocalShadows)
class Size {
	static function main() {
		var window = new Window("Size", 320, 240);
		var device = Device.create(window.surface);
		var pass:PassDesc = {colors: [{load: Clear, clear: new Color(0.1, 0.1, 0.12)}]};
		#if (size_level >= 1)
		var q = helder.scene.math.Quat.axisAngle(new Vec3(0, 1, 0), 0.3);
		var m = helder.scene.math.MathTools.inverse(q.toMat4());
		pass.colors[0].clear = new Color(m.c0.x * 0.1, 0.1, 0.12);
		#end
		#if (size_level >= 2)
		var world = new helder.scene.World();
		var eye = world.node("eye");
		var camera = helder.scene.Camera.attach(eye, helder.scene.Camera.perspective(1, 0.1, 100));
		eye.position = new Vec3(0, 1, 5);
		eye.lookAt(new Vec3(0, 0, 0));
		var clock = new helder.scene.FixedStep();
		#end
		#if (size_level >= 3 && !size_packed)
		var doc = helder.scene.gltf.Gltf.parse(helder.asset.Asset.embed("sample.glb"));
		#end
		#if (size_level == 3)
		helder.scene.gltf.GltfNodes.build(doc, world);
		#end
		#if size_packed
		var renderer = new helder.scene.render.Renderer(device);
		helder.scene.render.PackedModel.read(helder.asset.Asset.embed("bin/3d/sample.hxm3d"), device).instantiate(world);
		#elseif (size_level >= 4)
		var renderer = new helder.scene.render.Renderer(device);
		#if (size_level >= 5 && size_local)
		renderer.use(new helder.scene.render.Shadows(device).local());
		#elseif (size_level >= 5)
		renderer.use(new helder.scene.render.Shadows(device));
		#end
		#if (size_level >= 8)
		renderer.use(new helder.scene.render.Skinning(device));
		#end
		#if (size_level >= 9)
		renderer.use(new helder.scene.render.NormalMaps(device));
		#end
		new helder.scene.gltf.GltfScene(doc, device).instantiate(world);
		#end
		#if size_toon
		helder.scene.render.MeshRenderer.attach(world.node(), helder.scene.render.Shapes.box(device, helder.scene.render.Material.toon()));
		#end
		#if size_models
		for (m in [
			helder.scene.render.Material.lambert(), helder.scene.render.Material.phong(), helder.scene.render.Material.toon(), helder.scene.render.Material.unlit(),
			helder.scene.render.Material.matcap({matcap: cast 0}), helder.scene.render.Material.normals(), helder.scene.render.Material.depth()
		])
			helder.scene.render.MeshRenderer.attach(world.node(), helder.scene.render.Shapes.box(device, m));
		#end
		#if size_geometry
		var curve = helder.scene.math.Curve3.catmullRom([new Vec3(0, 0, 0), new Vec3(1, 1, 0), new Vec3(2, 0, 1)]);
		for (g in [
			helder.scene.render.Geometry.box(), helder.scene.render.Geometry.sphere(), helder.scene.render.Geometry.cylinder(),
			helder.scene.render.Geometry.cone(), helder.scene.render.Geometry.capsule(), helder.scene.render.Geometry.torus(),
			helder.scene.render.Geometry.torusKnot(), helder.scene.render.Geometry.ring(), helder.scene.render.Geometry.circle(),
			helder.scene.render.Geometry.plane(), helder.scene.render.Geometry.lathe([new helder.gfx.shader.Vec2(0.5, 0), new helder.gfx.shader.Vec2(0.2, 1)]),
			helder.scene.render.Geometry.tube(curve, {radius: 0.1})
		])
			helder.scene.render.MeshRenderer.attach(world.node(), helder.scene.render.Shapes.of(device, g, new helder.scene.render.Material()));
		#end
		#if size_sprites
		var sprites = new helder.scene.render.Sprites(device, helder.scene.render.Material.unlit(), 16);
		helder.scene.render.Sprites.attach(world.node(), sprites);
		sprites.set(0, 0, 1, 0, 1, 1);
		#end
		#if size_lines
		renderer.use(new helder.scene.render.LineRenderer(device));
		var lines = helder.scene.render.Lines.attach(world.node(), new helder.scene.render.Lines(8, {width: 4}));
		lines.count = 2;
		lines.setPoint(1, 1, 1, 0);
		#end
		#if size_debug
		renderer.use(new helder.scene.render.DebugDraw());
		helder.scene.render.AxesHelper.attach(world.node(), 1);
		helder.scene.render.BoundsHelper.attach(world.node());
		#end
		#if size_grid
		renderer.use(new helder.scene.render.DebugDraw());
		helder.scene.render.GridHelper.attach(world.node());
		#end
		#if size_text3d
		var font = helder.text.FontFile.parse(sys.io.File.getBytes(Sys.args()[0]));
		helder.scene.render.Text3D.attach(world.node(), new helder.scene.render.Text3D(device, font, "size"));
		#end
		#if (size_sheen || size_specular || size_clearcoat || size_transmission || size_iridescence || size_anisotropy || size_uvsets)
		var layered = new helder.scene.render.Material();
		layered.shader = #if size_sheen helder.scene.render.PhysicalShader.of({sheen: true}) #elseif size_specular helder.scene.render.PhysicalShader.of({specular: true}) #elseif size_clearcoat helder.scene.render.PhysicalShader.of({clearcoat: true}) #elseif size_transmission helder.scene.render.PhysicalShader.of({transmission: true}) #elseif size_iridescence helder.scene.render.PhysicalShader.of({iridescence: true}) #elseif size_anisotropy helder.scene.render.PhysicalShader.of({anisotropy: true}) #else helder.scene.render.PhysicalShader.of({uvSets: true}) #end;
		helder.scene.render.MeshRenderer.attach(world.node(), helder.scene.render.Shapes.box(device, layered));
		#end
		#if size_physical
		renderer.use(new helder.scene.render.Physical());
		#end
		#if size_refraction
		renderer.use(new helder.scene.render.Transmission(device));
		#end
		#if size_raycast
		var hit = new helder.scene.render.Hit();
		#end
		#if size_clustered
		renderer.use(new helder.scene.render.ClusteredLights(device));
		#end
		#if size_culling
		renderer.use(new helder.scene.render.InstanceCulling(device));
		#end
		#if size_prefilter
		renderer.use(helder.scene.render.Environment.prefilter(device, 8, 4, haxe.io.Bytes.alloc(8 * 4 * 4)));
		#end
		#if size_probes
		renderer.use(new helder.scene.render.Probes(device));
		helder.scene.render.ProbeGrid.attach(world.node(), new helder.scene.render.ProbeGrid(new Vec3(4, 4, 4), 2, 2, 2));
		helder.scene.render.ReflectionProbe.attach(world.node(), new helder.scene.render.ReflectionProbe(new Vec3(4, 4, 4)));
		#end
		#if size_area
		renderer.use(new helder.scene.render.AreaLights(device));
		helder.scene.render.Light.attach(world.node(), helder.scene.render.Light.rectArea(new Vec3(1, 1, 1), 2, 1, 1));
		#end
		#if size_lightmaps
		renderer.use(new helder.scene.render.Lightmaps(device));
		#end
		#if size_lod
		var lodMesh = helder.scene.render.Shapes.box(device, new helder.scene.render.Material());
		helder.scene.render.Lod.attach(world.node(), [{mesh: lodMesh, until: 0.1}, {mesh: lodMesh}]);
		#end
		#if (size_level >= 6)
		var actions = new helder.scene.input.InputMap().bind("turn", KeyAxis(0xFF51, 0xFF53));
		#end
		#if (size_level >= 7)
		var made = [];
		helder.scene.gltf.GltfNodes.build(doc, world, null, null, null, null, made);
		var animator = new helder.scene.anim.Animator(made);
		animator.play(helder.scene.anim.AnimationClip.fromGltf(doc, 0));
		#end
		App.run(() -> {
			#if (size_level >= 2)
			clock.advance(1 / 60, dt -> {
				eye.position = eye.position + new Vec3(0, 0, dt * 0.01);
				#if (size_level >= 6)
				actions.step();
				eye.position = eye.position + new Vec3(actions.axis("turn") * dt, 0, 0);
				#end
				#if (size_level >= 7)
				animator.update(dt);
				#end
			});
			#end
			#if (size_debug || size_debugcalls)
			helder.scene.render.Debug.line(new Vec3(0, 0, 0), eye.position, 0xFF0000);
			helder.scene.render.Debug.sphere(new Vec3(0, 0, 0), 1);
			#end
			#if size_raycast
			if (world.raycast(eye.position, eye.position * -1, hit)) eye.position = hit.point;
			#end
			var enc = device.beginFrame();
			if (enc == null) return;
			#if (size_level >= 4)
			renderer.draw(enc, world, camera);
			#else
			enc.beginPass(pass);
			enc.endPass();
			#end
			device.endFrame();
		}, e -> {
			#if (size_level >= 6)
			actions.event(e);
			#end
			if (e.kind == Close) window.close();
		});
	}
}
