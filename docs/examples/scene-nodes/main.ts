// title: World and nodes (TypeScript)
// summary: Nodes.hx in TypeScript: a planet orbiting its sun and a moon orbiting the planet, each a node turned under its parent
// tags: 3d, docs, typescript
// demo: canvas 640x400
//
// helder/scene from TypeScript, node for node as Nodes.hx: the same World,
// nodes and renderer, Vec3 and Quat values.
//
//   helder run docs/examples/scene-nodes/main.ts
import { Window, Device, App, World, Camera, Light, Material, MeshRenderer, Shapes, Renderer, FixedStep } from "helder/scene";
import { vec3, vec4, Quat } from "helder/gfx";

const window = new Window("World and nodes", 640, 400);
const device = Device.create(window.surface);
const renderer = new Renderer(device);
renderer.sky = vec3(0.05, 0.06, 0.1);
renderer.ground = vec3(0.02, 0.02, 0.03);

const world = new World("nodes");
const sun = world.node("sun");
MeshRenderer.attach(sun, Shapes.sphere(device, new Material("sun", vec4(1, 0.8, 0.4, 1), 0, 1, vec3(1.6, 1.1, 0.4)), 0.6));
Light.attach(sun, Light.pointLight(vec3(1, 0.85, 0.6), 30, 20));

const orbit = world.node("orbit", sun);              // a pivot: turns, draws nothing
const planet = world.node("planet", orbit);
planet.position = vec3(2.6, 0, 0);                   // relative to the orbit
MeshRenderer.attach(planet, Shapes.sphere(device, new Material("planet", vec4(0.2, 0.45, 0.9, 1), 0, 0.6), 0.32));

const moonOrbit = world.node("moonOrbit", planet);
const moon = world.node("moon", moonOrbit);
moon.position = vec3(0.7, 0, 0);
MeshRenderer.attach(moon, Shapes.sphere(device, new Material("moon", vec4(0.7, 0.7, 0.68, 1), 0, 0.9), 0.1));

const eye = world.node("eye");
const camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 100));
eye.position = vec3(0, 3.2, 6.4);
eye.lookAt(vec3(0, 0, 0));

const clock = new FixedStep(1 / 60);
App.run(() => {
	clock.advance(1 / 60, () => {
		orbit.rotation = Quat.axisAngle(vec3(0, 1, 0), clock.time * 0.5);
		planet.rotation = Quat.axisAngle(vec3(0, 1, 0), clock.time * 2);   // its spin turns the moon's pivot too
		moonOrbit.rotation = Quat.axisAngle(vec3(0.2, 1, 0), clock.time * 1.5);
	});
	const enc = device.beginFrame();
	if (enc === null) return;
	renderer.draw(enc, world, camera);
	device.endFrame();
}, e => {
	if (e.kind === "close") window.close();
});
