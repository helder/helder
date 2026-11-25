// helder/scene's phase 3 without a GPU: rays cast at a world's triangles
// (meshes of data alone: Shapes.cpu), the nearest's node,
// distance, normal and uv, every hit nearest first, options (bounds alone,
// backs, a distance), a primitive's tree (Bvh) and its bytes read back;
// lines' points as uploaded (a polyline's neighbours padded, its distances
// along), their enums by name; DebugDraw's calls into its ring, helpers on
// nodes. (Drawn: the 3d lane's lines, debugdraw, helpers and text3d frames,
// tests/3d/LineScenes.hx.)
import { World, Shapes, Geometry, Material, MeshRenderer, Hit, HitList, RaycastOptions, Raycaster, Bvh, Lines, DebugDraw,
	AxesHelper, BoundsHelper, Helper } from "helder/scene";
import { vec3, Quat } from "helder/gfx";

const world = new World("pick");
const box = world.node("box");
MeshRenderer.attach(box, Shapes.cpu(Geometry.box({width: 2, height: 2, depth: 2}), Material.lambert()));
const ball = world.node("ball");
ball.position = vec3(0, 0, -5);
MeshRenderer.attach(ball, Shapes.cpu(Geometry.sphere({radius: 1, widthSegments: 32, heightSegments: 16}), Material.lambert()));

const hit = new Hit();
console.log(world.raycast(vec3(0.5, -0.5, 5), vec3(0, 0, -1), hit), hit.node.equals(box), hit.distance.toFixed(3), hit.normal.z, hit.uv.x.toFixed(2), hit.uv.y.toFixed(2), hit.front);
box.rotation = Quat.axisAngle(vec3(0, 1, 0), Math.PI / 4);
world.raycast(vec3(0, 0, 5), vec3(0, 0, -1), hit);
console.log(hit.distance.toFixed(4), hit.point.z.toFixed(4));
box.visible = false;
world.raycast(vec3(0, 0, 5), vec3(0, 0, -1), hit);
console.log(hit.node.equals(ball), hit.distance.toFixed(2));
box.visible = true;

const hits = new HitList();
console.log(world.raycastAll(vec3(0, 0, 5), vec3(0, 0, -1), hits, new RaycastOptions({backfaces: true})), hits.get(0).node.equals(box), hits.get(3).node.equals(ball));
console.log(world.raycast(vec3(0, 0, 5), vec3(0, 0, -1), hit, new RaycastOptions({maxDistance: 2})), world.raycast(vec3(3, 3, 0), vec3(-1, -1, 0), hit, new RaycastOptions({triangles: false})), hit.triangle);
Raycaster.setLayers(ball, 2);
console.log(Raycaster.layersOf(ball), Raycaster.layersOf(box));

const tree = Bvh.build(Geometry.torusKnot());
const again = Bvh.read(tree.bytes());
console.log(tree.triangleCount, again.nodeCount === tree.nodeCount, tree.intersect(vec3(0, 0, 5), vec3(0, 0, -1), 100, false) === again.intersect(vec3(0, 0, 5), vec3(0, 0, -1), 100, false));

const path = new Lines(8, {width: 4, join: "round", cap: "square", widthUnits: "world", dash: 0.2, gap: 0.1});
path.count = 3;
path.setPoint(0, 0, 0, 0);
path.setPoint(1, 3, 0, 0, 1, 0.5, 0);
path.setPoint(2, 3, 4, 0);
path.prepare();
const records = new DataView(path.data.buffer, path.data.byteOffset, path.data.byteLength);
console.log(path.drawn, records.getFloat32(96 + 12, true), path.join === "round", path.widthUnits, path.get(1, 4));

DebugDraw.line(vec3(0, 0, 0), vec3(1, 1, 1), 0xFF0000);
DebugDraw.sphere(vec3(0, 0, 0), 1);
DebugDraw.axes(box.worldMatrix(), 0.5);
console.log(DebugDraw.capacity, DebugDraw.dropped);

const axes = AxesHelper.attach(box, 0.5);
const bounds = BoundsHelper.attach(box, 0x00FF00);
console.log(axes.size, bounds.color === 0x00FF00, axes.visible, bounds.ofParent);
Helper.clear(box);
