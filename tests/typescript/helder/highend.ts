// helder/scene's phase 7 without a GPU: the high end's effects' options and
// their defaults (Ssr, MotionBlur, GodRays, Taa, Smaa), a node marked for
// occlusion culling (Occlusion.test: data on the node, no query made: no
// device linked). (Drawn: the 3d lane's
// ssr, taa, smaa, motionblur, godrays and occlusion frames,
// tests/3d/HighEndScenes.hx.)
import { World, Ssr, MotionBlur, GodRays, Taa, Smaa, Occlusion } from "helder/scene";

const ssr = new Ssr({maxDistance: 12, steps: 24});
console.log(ssr.intensity, ssr.maxDistance, ssr.thickness, ssr.steps, ssr.maxRoughness, ssr.halfRes, ssr.texture === null);
ssr.halfRes = false;
console.log(ssr.halfRes);

const blur = new MotionBlur({strength: 0.75, objects: true});
console.log(blur.strength, blur.samples, blur.max, blur.objects);
const camera = new MotionBlur();
console.log(camera.strength, camera.objects);

const rays = new GodRays({intensity: 0.25, samples: 48});
console.log(rays.intensity, rays.density, rays.decay, rays.samples, rays.falloff, rays.texture === null);

const world = new World("high");
const wall = world.node("wall");
console.log(Occlusion.tested(wall));
Occlusion.test(wall);
console.log(Occlusion.tested(wall));
Occlusion.untest(wall);
console.log(Occlusion.tested(wall));
world.dispose();

const taa = new Taa();
const smaa = new Smaa({threshold: 0.05});
console.log(taa.blend, smaa.threshold);
