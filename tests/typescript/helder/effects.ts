// helder/scene's post effects without a GPU: an effect's options and its
// defaults (Ssao, Dof's two lenses), the selection as data (Outline.select
// on a node: its own group, 0 once deselected), an outline's groups (its
// colour a Vec4 in its options), a LUT's strip made from a grade in
// TypeScript (Lut.strip, its grade's Vec3 returned into Haxe: the
// identity's corners), the enums by name (string unions).
// (Drawn: the 3d lane's frames, tests/3d/EffectScenes.hx.)
import { World, Ssao, Dof, Outline, Lut, type ToneMap, type Antialias } from "helder/scene";
import { vec3, vec4 } from "helder/gfx";

const ao = new Ssao({radius: 0.8, samples: 6});
console.log(ao.radius, ao.intensity, ao.samples, ao.slices, ao.halfRes, ao.texture === null);

const lens = Dof.focus({distance: 6, aperture: 0.03});
console.log(lens.mode === "focus", lens.distance, lens.aperture, lens.radius);
const tilt = Dof.tiltShift({band: 0.2, strength: 0.5});
console.log(tilt.mode === "tilt-shift", tilt.band, tilt.falloff, tilt.strength, tilt.center);

const world = new World("fx");
const model = world.node("model"), part = world.node("part", model);
Outline.select(model, 2);
console.log(Outline.selected(model), Outline.selected(part));
Outline.select(model, 0);
console.log(Outline.selected(model));

const o = new Outline({width: 3, color: vec4(0.2, 0.6, 1, 1)});
o.group(2, vec4(1, 0, 0, 1), 4);
console.log(o.width, o.color.y);
o.width = 1.5;
console.log(o.width);

// (size 4: 16 x 4 texels; red across a slice, green down it, blue by slice)
const strip = Lut.strip(4, (r, g, b) => vec3(r, g, b));
console.log(strip.length, strip[0], strip[3 * 4], strip[(3 * 16 + 15) * 4 + 1], strip[(3 * 16 + 15) * 4 + 2]);

const tone: ToneMap = "agx", aa: Antialias = "fxaa";
console.log(tone, aa);
