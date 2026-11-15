// tests/3d's phase 1 frames in TypeScript, node for node as Scenes.hx's
// (the same goldens): every Geometry generator flat and smooth
// (primitives.png), toon shading under a soft shadow and a point light
// (toon.png). Each a draw of the frame, its renderer made on device.
import {
	World, Camera, Light, Renderer, Material, MeshRenderer, Shapes, Geometry, Curve3, Shadows, type Device, type Encoder, type VertexData,
} from "helder/scene";
import { vec2, vec3, vec4, Quat } from "helder/gfx";

export function primitives(device: Device): (enc: Encoder) => void {
	const r = new Renderer(device);
	const world = new World();
	const points = [];
	for (let k = 0; k < 9; k++) points.push(vec3(Math.cos(k * 1.4) * 0.22, -0.3 + k * 0.075, Math.sin(k * 1.4) * 0.22));
	const helix = Curve3.catmullRom(points);
	const vase = [vec2(0.01, -0.3), vec2(0.22, -0.28), vec2(0.3, -0.1), vec2(0.18, 0.12), vec2(0.14, 0.24), vec2(0.22, 0.32)];
	const shapes = (flat: boolean): VertexData[] => [
		Geometry.box({width: 0.5, height: 0.5, depth: 0.5, flat}),
		Geometry.sphere({radius: 0.32, widthSegments: flat ? 12 : 32, heightSegments: flat ? 8 : 16, flat}),
		Geometry.cylinder({radiusTop: 0.22, radiusBottom: 0.28, height: 0.6, radialSegments: flat ? 8 : 32, flat}),
		Geometry.cone({radius: 0.3, height: 0.65, radialSegments: flat ? 8 : 32, flat}),
		Geometry.capsule({radius: 0.2, height: 0.3, capSegments: flat ? 3 : 6, radialSegments: flat ? 8 : 16, flat}),
		Geometry.torus({radius: 0.24, tube: 0.1, radialSegments: flat ? 6 : 12, tubularSegments: flat ? 16 : 48, flat}),
		Geometry.torusKnot({radius: 0.2, tube: 0.06, tubularSegments: flat ? 48 : 96, radialSegments: flat ? 5 : 8, flat}),
		Geometry.ring({innerRadius: 0.14, outerRadius: 0.32, thetaSegments: flat ? 10 : 32, flat}),
		Geometry.circle({radius: 0.32, segments: flat ? 8 : 32, flat}),
		Geometry.plane({width: 0.55, height: 0.55, widthSegments: 2, heightSegments: 2, flat}),
		Geometry.lathe(vase, {segments: flat ? 8 : 24, flat}),
		Geometry.tube(helix, {tubularSegments: flat ? 24 : 64, radius: 0.06, radialSegments: flat ? 5 : 8, flat}),
	];
	const normals = Material.normals({doubleSided: true});
	const clay = Material.lambert({color: vec4(0.85, 0.62, 0.4, 1), doubleSided: true});
	for (const flat of [false, true]) {
		const all = shapes(flat);
		for (let i = 0; i < all.length; i++) {
			const n = world.node();
			n.position = vec3(-2.25 + (i % 6) * 0.9, (flat ? -0.55 : 1.45) - Math.floor(i / 6) * 0.95, 0);
			n.rotation = Quat.fromEuler(0.35, i < 7 ? 0.5 : 0.2, 0);
			MeshRenderer.attach(n, Shapes.of(device, all[i], flat ? clay : normals));
		}
	}
	const sun = world.node("sun");
	Light.attach(sun, Light.directional(vec3(1, 0.97, 0.92), 2.6));
	sun.rotation = Quat.fromEuler(-0.7, 0.5, 0);
	Light.attach(world.node("sky"), Light.hemisphere(vec3(0.35, 0.4, 0.5), vec3(0.12, 0.1, 0.08)));
	const eye = world.node("eye");
	const camera = Camera.attach(eye, Camera.perspective(0.9, 0.1, 50));
	eye.position = vec3(0.45, 0.45, 5);
	eye.lookAt(vec3(0.45, 0.45, 0));
	return enc => r.draw(enc, world, camera);
}

export function toon(device: Device): (enc: Encoder) => void {
	const shadows = new Shadows(device, 1024);
	shadows.soft(0.12, 12, 0.08);
	const r = new Renderer(device).use(shadows);
	const world = new World();
	const floor = world.node("floor");
	MeshRenderer.attach(floor, Shapes.of(device, Geometry.plane({width: 10, height: 10}).rotated(-Math.PI / 2, 0, 0),
		Material.toon({color: vec4(0.45, 0.75, 0.35, 1), steps: 2, shade: vec3(0.22, 0.3, 0.45)})));
	const red = Material.toon({color: vec4(0.9, 0.2, 0.15, 1), steps: 3, shade: vec3(0.12, 0.12, 0.3)});
	const gold = Material.toon({color: vec4(0.95, 0.7, 0.2, 1), steps: 4, shade: vec3(0.15, 0.12, 0.28)});
	const blue = Material.toon({color: vec4(0.25, 0.45, 0.95, 1), steps: 2, shade: vec3(0.15, 0.15, 0.35)});
	const put = (g: VertexData, m: Material, x: number, y: number, z: number) => {
		const n = world.node();
		n.position = vec3(x, y, z);
		MeshRenderer.attach(n, Shapes.of(device, g, m));
		return n;
	};
	put(Geometry.sphere({radius: 0.6}), red, -1.4, 0.6, 0);
	put(Geometry.torusKnot({radius: 0.45, tube: 0.16, tubularSegments: 128, radialSegments: 12}), gold, 0.2, 0.85, -0.3).rotation = Quat.fromEuler(0.3, 0.4, 0);
	put(Geometry.cylinder({radiusTop: 0.35, radiusBottom: 0.45, height: 1.4}), blue, 1.6, 0.7, 0.2);
	put(Geometry.box({width: 0.6, height: 0.6, depth: 0.6}), blue, -0.4, 0.3, 1.1).rotation = Quat.fromEuler(0, 0.6, 0);
	const sun = world.node("sun");
	Light.attach(sun, Light.directional(vec3(1, 0.96, 0.88), 3));
	sun.rotation = Quat.fromEuler(-0.85, 0.9, 0);
	const lamp = world.node("lamp");
	lamp.position = vec3(0.9, 0.5, 1.4);
	Light.attach(lamp, Light.pointLight(vec3(1, 0.55, 0.2), 3, 2.5));
	const eye = world.node("eye");
	const camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 50));
	eye.position = vec3(0, 2.6, 5.2);
	eye.lookAt(vec3(0, 0.5, 0));
	return enc => r.draw(enc, world, camera);
}
