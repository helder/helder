// helder/scene's phase 5 without a GPU: spherical harmonics (Sh: a sky over a
// ground, a light from above, blended), a grid of light probes sampled
// trilinearly and written and read back (ProbeGrid), the light probes'
// light at a point (Probes.lightAt: a grid holding it, else the nearest
// LightProbes), how much of a draw's bounds a reflection probe's box holds
// (ReflectionProbe.weight), area lights' kinds (Light.rectArea, discArea)
// and a lightmap's modes. (Drawn: the 3d lane's sh, probes, arealight and
// lightmap frames, tests/3d/IndirectScenes.hx.)
import { World, Light, Sh, ProbeGrid, LightProbe, ReflectionProbe, Probes, type LightmapMode } from "helder/scene";
import { vec3 } from "helder/gfx";

const up = vec3(0, 1, 0), down = vec3(0, -1, 0), side = vec3(1, 0, 0);
const hemi = Sh.ofHemisphere(vec3(1, 1, 1), vec3(0, 0, 0));
console.log(hemi.irradiance(up).x > 0.8, hemi.irradiance(down).x < 0.2, hemi.irradiance(side).x.toFixed(2));
const sun = new Sh().addDirectional(up, vec3(1, 1, 1));
console.log(sun.irradiance(up).x.toFixed(4), sun.coefficients.length);
const mixed = new Sh().setLerp(hemi, sun, 0.5);
console.log(mixed.irradiance(up).x.toFixed(3) === ((hemi.irradiance(up).x + sun.irradiance(up).x) / 2).toFixed(3));

const grid = new ProbeGrid(vec3(4, 2, 2), 2, 2, 2);
grid.fill((p) => Sh.ofHemisphere(p.x < 0 ? vec3(1, 0, 0) : vec3(0, 0, 1), vec3(0, 0, 0)));
const out = new Sh();
console.log(grid.sample(vec3(-2, 0, 0), out).irradiance(up).x > 0.5, grid.sample(vec3(0, 0, 0), out).irradiance(up).x.toFixed(2), grid.holds(vec3(3, 0, 0)));
const back = ProbeGrid.read(grid.write());
console.log(back.nx, back.ny, back.nz, back.sample(vec3(2, 0, 0), out).irradiance(up).z > 0.5);

const world = new World("indirect");
const gi = world.node("gi");
ProbeGrid.attach(gi, grid);
const lamp = world.node("probe");
lamp.position = vec3(10, 0, 0);
LightProbe.attach(lamp, new LightProbe(Sh.ofHemisphere(vec3(0, 1, 0), vec3(0, 0, 0)), 3));
console.log(Probes.lightAt(world, vec3(-1, 0, 0), out), out.irradiance(up).x > 0.5);
console.log(Probes.lightAt(world, vec3(11, 0, 0), out), out.irradiance(up).y > 0.5);
console.log(Probes.lightAt(world, vec3(20, 0, 0), out));

const hall = world.node("hall");
hall.position = vec3(0, 2, 0);
const box = ReflectionProbe.attach(hall, new ReflectionProbe(vec3(8, 4, 6), 0));
console.log(box.weight(0, 1, 0, 0.5, 0.5, 0.5), box.weight(0, 10, 0, 0.5, 0.5, 0.5), box.weight(4, 1, 0, 1, 0.5, 0.5).toFixed(3), box.captured);

const rect = Light.rectArea(vec3(1, 0.8, 0.6), 6, 2, 1);
const disc = Light.discArea(vec3(1, 1, 1), 4, 0.5);
console.log(rect.kind === "rect-area", disc.kind === "disc-area", rect.area, rect.local, rect.castShadows, rect.width, rect.height, disc.width);
const modes: LightmapMode[] = ["indirect", "all"];
console.log(...modes);
world.dispose();
