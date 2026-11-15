// helder/scene's phase 4 without a GPU: a light's shadow (castShadows, its
// options as an object literal), its kind by name; levels of detail (Lod:
// a sphere's share of the view's height, a level held within its band of
// hysteresis, a node's mesh by its distance, a visible range); the view's
// cells and the lights reaching them on the CPU (Clusters, as
// ClusteredLights assigns them without compute). (Drawn: the 3d lane's
// lights8, clustered, spotshadow, pointshadow, shadowatlas and lod frames,
// tests/3d/LightScenes.hx.)
import { World, Light, LightKind, Lod, Clusters, Shapes, Geometry, Material, type LodLevel } from "helder/scene";
import { vec3, vec4, mat4 } from "helder/gfx";

const world = new World("lights");
const lamp = world.node("lamp");
const spot = Light.attach(lamp, Light.spot(vec3(1, 0.8, 0.6), 30, 12, 0.3, 0.5));
const sun = Light.attach(world.node("sun"), Light.directional(vec3(1, 1, 1), 2));
console.log(spot.kind === LightKind.Spot, spot.castShadows, sun.castShadows, spot.shadow === null);
spot.castShadows = true;
spot.shadow = {size: 512, bias: 0.002, radius: 1.5};
console.log(spot.castShadows, spot.shadow.size, spot.shadow.bias, spot.shadow.radius);

// (a camera at the origin looking down -z, 90 degrees, 0.1 to 500 m: Mat4.perspective's)
const near = 0.1, far = 500, r = far / (near - far);
const vp = mat4(vec4(1, 0, 0, 0), vec4(0, 1, 0, 0), vec4(0, 0, r, -1), vec4(0, 0, near * r, 0));
console.log(Lod.coverageOf(vp, 0, 0, -10, 1).toFixed(4), Lod.coverageOf(vp, 3, 0, -20, 2).toFixed(4));

const bands = new Lod([{mesh: Shapes.cpu(Geometry.box(), Material.lambert()), until: 0.2}, {mesh: Shapes.cpu(Geometry.box(), Material.lambert())}], 0.1);
console.log(bands.choose(0.21), bands.choose(0.195), bands.choose(0.189), bands.choose(0.205), bands.choose(0.211));

const hi = Shapes.cpu(Geometry.sphere({radius: 0.5}), Material.lambert()), lo = Shapes.cpu(Geometry.box(), Material.lambert());
const levels: LodLevel[] = [{mesh: hi, until: 0.15}, {mesh: lo, until: 0.01}];
const tree = world.node("tree");
const lod = Lod.attach(tree, levels);
const eye = vec3(0, 0, 0);
tree.position = vec3(0, 0, -2);
console.log(Lod.meshOf(tree, hi, vp, eye) === hi, lod.level);
tree.position = vec3(0, 0, -20);
console.log(Lod.meshOf(tree, hi, vp, eye) === lo, lod.level, lod.coverage.toFixed(4));
tree.position = vec3(0, 0, -200);
console.log(Lod.meshOf(tree, hi, vp, eye) === null, lod.level);
Lod.range(tree, 0, 50);
tree.position = vec3(0, 0, -2);
console.log(Lod.meshOf(tree, hi, vp, eye) === hi, Lod.meshOf(tree, hi, vp, eye) !== null);
tree.position = vec3(0, 0, -60);
console.log(Lod.meshOf(tree, hi, vp, eye) === null);

// (a grid of 4 by 3 tiles and 6 slices, a light 8 m ahead reaching 1 m, one
// to its right, one behind the camera)
const cells = new Clusters(4, 3, 6, 8);
cells.lens(vp, near, 100);
const view = mat4(1);
cells.assign(view, [0, 6, 0], [0, 0, 0], [-8, -8, 5], [1, 1, 1], 3);
let listed = 0, both = 0;
for (let z = 0; z < 6; z++)
	for (let y = 0; y < 3; y++)
		for (let x = 0; x < 4; x++) {
			const n = cells.count(x, y, z);
			listed += n;
			if (n === 2) both++;
		}
console.log(cells.width, cells.height, listed, both, cells.overflow, cells.reaches(1, 1, 3, 0, 0, -8, 1));
world.dispose();
