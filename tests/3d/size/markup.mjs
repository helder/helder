// helder.scene.view's markup links what it names alone (MarkupSize.hx; the
// 3d lane, Linux): Tiny (a mesh of <boxGeometry> in <standardMaterial>) holds
// no other geometry generator, shading model or material factory; All
// (every geometry and material tag) holds each, so the check checks
// something; and what Tiny's markup adds over the same mesh made in code
// (Code) is within its budget, natively and as wasm32 (a tag's factories
// linked by any markup use was 0.9 MB natively, 1.2 MB as wasm32). Sizes
// reported (bin/3d/size/markup.md).
//
//   node tests/3d/size/markup.mjs <dir with tiny, tiny-sym, all, all-sym, code (and each .wasm but the -sym ones)>
import { execFileSync } from "node:child_process";
import { statSync, writeFileSync } from "node:fs";

const dir = process.argv[2];
// (what markup may add over code: helder.view's runtime, SceneRenderer, the tags' props; measured 204 KB natively, 177 KB as wasm32)
const BUDGET = { native: 256 * 1024, wasm: 256 * 1024 };
const symbols = f => execFileSync("nm", [f], { encoding: "utf8", maxBuffer: 1 << 28 }).split("\n").map(l => l.split(" ").pop());
// (each a symbol prefix of hxmc's: what Tiny leaves out, All has; not the
// sphere's and the plane's: a <mesh>'s shape prop, box | sphere | plane,
// is a value known when run, so any mesh links those three)
const unused = {};
for (const g of ["cylinder", "cone", "capsule", "torus", "torusKnot", "ring", "circle", "lathe", "tube"])
	unused[`Geometry.${g}`] = `helder_scene_render_Geometry_${g}`;
unused["Curve3"] = "helder_scene_math_Curve3";
for (const m of ["lambert", "phong", "toon", "unlit", "matcap", "normals", "depth"])
	unused[`Material.${m}`] = `helder_scene_render_Material_${m}`;
for (const s of ["Lambert", "Phong", "Toon", "Unlit", "Matcap", "Normals", "Depth"])
	unused[`shading's ${s}`] = `helder_scene_render_shading_${s}`;

const t = symbols(`${dir}/tiny-sym`), a = symbols(`${dir}/all-sym`);
// (a prefix and the next character not a name's: Geometry_torus is not Geometry_torusKnot)
const has = (list, prefix) => list.filter(s => { const i = s.indexOf(prefix); return i >= 0 && !/[A-Za-z0-9]/.test(s.charAt(i + prefix.length)); });
let bad = 0;
const rows = [];
for (const [what, prefix] of Object.entries(unused)) {
	const inTiny = has(t, prefix), inAll = has(a, prefix).length > 0;
	if (inTiny.length > 0) { bad++; console.log(`markup size: Tiny keeps ${what}: ${inTiny.slice(0, 3).join(", ")}`); }
	if (!inAll) { bad++; console.log(`markup size: All has no ${what} (${prefix}): the check checks nothing`); }
	rows.push(`| ${what} | ${inTiny.length === 0 ? "left out" : "KEPT"} | ${inAll ? "kept" : "-"} |`);
}
const size = p => statSync(p).size, kb = n => Math.round(n / 1024);
const lines = [];
for (const [kind, ext] of [["native", ""], ["wasm", ".wasm"]]) {
	const tiny = size(`${dir}/tiny${ext}`), all = size(`${dir}/all${ext}`), code = size(`${dir}/code${ext}`), over = tiny - code;
	lines.push(`${kind}: Tiny ${kb(tiny)} KB, All ${kb(all)} KB, Code ${kb(code)} KB; markup over code ${kb(over)} KB (budget ${kb(BUDGET[kind])} KB)`);
	if (over > BUDGET[kind]) { bad++; console.log(`markup size: Tiny's markup adds ${kb(over)} KB over Code ${kind}, over its budget of ${kb(BUDGET[kind])} KB`); }
}
const report = [...lines, "", "| | Tiny | All |", "| --- | --- | --- |", ...rows].join("\n");
writeFileSync(`${dir}/markup.md`, report + "\n");
console.log(report);
if (bad > 0) process.exit(1);
