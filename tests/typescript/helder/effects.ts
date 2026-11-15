// helder/scene's post effects without a GPU: an effect's options and its
// defaults (Ssao, Dof's two lenses), the selection as data (Outline.select
// on a node: its own group, 0 once deselected), an outline's groups (its
// colour a Vec4 in its options), a LUT's strip made from a grade in
// TypeScript (lutStrip, for Lut.fromBytes: the identity's corners; a Vec3
// a TypeScript function returns does not cross into Haxe yet, so not
// Lut.of's grade), the enums by name.
// (Drawn: the 3d lane's frames, tests/3d/EffectScenes.hx.)
import { World, Ssao, Dof, Outline, ToneMap, Antialias, DofMode, lutStrip } from "helder/scene";
import { vec4 } from "helder/gfx";

const ao = new Ssao({radius: 0.8, samples: 6});
console.log(ao.radius, ao.intensity, ao.samples, ao.slices, ao.halfRes, ao.texture === null);

const lens = Dof.focus({distance: 6, aperture: 0.03});
console.log(lens.mode === DofMode.Focus, lens.distance, lens.aperture, lens.radius);
const tilt = Dof.tiltShift({band: 0.2, strength: 0.5});
console.log(tilt.mode === DofMode.TiltShift, tilt.band, tilt.falloff, tilt.strength, tilt.center);

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
const strip = lutStrip(4, (r, g, b) => [r, g, b]);
console.log(strip.length, strip[0], strip[3 * 4], strip[(3 * 16 + 15) * 4 + 1], strip[(3 * 16 + 15) * 4 + 2]);

console.log(ToneMap.AgX, ToneMap.Aces, Antialias.None, Antialias.Fxaa);
