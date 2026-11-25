// Audit G 10: the math types in their own package, helder.math: Vec2, Vec3,
// Vec4 and Mat4 out of helder.gfx.shader, Quat out of helder.scene.math.
// helder.gfx.shader keeps what only shaders have (ShaderMath's builtins,
// the textures, storage, uniforms) and imports helder.math.
import { edit, move, addImport, hx, done } from "./lib.mjs";

const TYPES = ["Vec2", "Vec3", "Vec4", "Mat4"];
for (const t of TYPES) move(`src/helder/gfx/shader/${t}.hx`, `src/helder/math/${t}.hx`);
move("src/helder/scene/math/Quat.hx", "src/helder/math/Quat.hx");

const USES = /\b(Vec[234]|Mat4)\b/;
edit(() => true, (s, f) => {
	s = s
		.replace(/\bhelder\.gfx\.shader\.(Vec[234]|Mat4)(Data)?\b/g, "helder.math.$1$2")
		.replace(/\bhelder\.scene\.math\.Quat\b/g, "helder.math.Quat")
		.replace(/\bhelder\.gfx\.shader\.VecBuild\.vector\b/g, "helder.math.VecBuild.vector")
		.replace(/\bhelder\.gfx\.shader\.VecBuild\.builtins\b/g, "helder.gfx.shader.ShaderMathBuild.builtins")
		.replace(/\bsrc\/helder\/gfx\/shader\/(Vec[234]|Mat4)\.hx\b/g, "src/helder/math/$1.hx")
		.replace(/\bsrc\/helder\/scene\/math\/Quat\.hx\b/g, "src/helder/math/Quat.hx");
	// (the shader macros' own names for the math types' package)
	if (f === "src/helder/gfx/shader/Soft.hx") s = s.replace(/\bSHADER\b/g, "MATH").replace('static final MATH = ["helder", "gfx", "shader"];', 'static final MATH = ["helder", "math"];');
	if (f === "src/helder/gfx/shader/Lower.hx") s = s.replace(/\[SHADER_PACK, "(Vec[234]|Mat4)(Data)?"\]/g, '[MATH_PACK, "$1$2"]');
	if (f.startsWith("src/helder/gfx/"))
		s = s.replace(/\{pack: \["helder", "gfx", "shader"\], name: ('Vec\$\{?\w+\}?'|'Vec\$n'|"Mat4")/g, '{pack: ["helder", "math"], name: $1');
	if (!hx(f)) return splitTs(s);
	if (f.startsWith("src/helder/math/")) s = s.replace(/^package [\w.]+;/m, "package helder.math;");
	const pack = /^package ([\w.]*);/m.exec(s)?.[1] ?? "";
	if (pack === "helder.math") {
		// (the moved files: their own package now)
		s = s.replace(/^import helder\.math\.[\w*]+;\r?\n/gm, "").replace(/^(package helder\.math;\r?\n)(\r?\n)+/m, "$1\n");
		return s;
	}
	// (a wildcard of the shader package, or that package itself, gave the types)
	if (USES.test(s) && (/^import helder\.gfx\.shader\.\*;/m.test(s) || pack === "helder.gfx.shader"))
		s = addImport(s, "import helder.math.*;");
	if (/\bQuat\b/.test(s) && (/^import helder\.scene\.math\.\*;/m.test(s) || pack === "helder.scene.math") && !/^import helder\.math\.\*;/m.test(s))
		s = addImport(s, "import helder.math.Quat;");
	return s;
});
// TypeScript (and its samples in Markdown): the math types imported from
// helder/math, the rest of an import of helder/gfx where it was
function splitTs(s) {
	const MATH = new Set(["Vec2", "Vec3", "Vec4", "Mat4", "Quat"]);
	return s.replace(/^([ \t]*)import (type )?\{([^}]*)\} from (["'])helder\/gfx\4;?/gm, (all, indent, typeOnly, names, q) => {
		// (the segments between commas, their whitespace kept: a multi-line import stays one)
		const segs = names.split(",");
		const name = (p) => p.trim().replace(/^type\s+/, "").split(/\s+as\s+/)[0];
		const math = segs.filter((p) => MATH.has(name(p))).map((p) => p.trim());
		if (math.length === 0) return all;
		let rest = segs.filter((p) => !MATH.has(name(p)));
		if (!/^\s/.test(segs[0]) && rest.length) rest[0] = rest[0].replace(/^[ \t]+/, "");
		if (rest.length) rest[rest.length - 1] = rest[rest.length - 1].replace(/\s*$/, /\s*$/.exec(segs[segs.length - 1])[0]);
		const kept = rest.filter((p) => p.trim()).length > 0;
		const semi = all.trimEnd().endsWith(";") ? ";" : "";
		const sp = /^\s/.test(names) ? " " : "";
		const from = (mod) => ` from ${q}${mod}${q}${semi}`;
		const mathLine = `${indent}import ${typeOnly ?? ""}{${sp}${math.join(", ")}${sp}}${from("helder/math")}`;
		return (kept ? `${indent}import ${typeOnly ?? ""}{${rest.join(",")}}${from("helder/gfx")}\n` : "") + mathLine;
	});
}
done("10-math");
