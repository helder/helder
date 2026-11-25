// helder/math for TypeScript programs: writes src/helder/math/index.ts, the
// math types as TypeScript itself (CPU code, compiled with the program), as
// helder.math's VecBuild writes Haxe's: each vector's componentwise add,
// sub, mul and div (a vector or a number), neg and swizzles of 2 to 4
// components; Mat4's mul (a matrix or a vector); Quat's.
//   node src/helder/math/typescript.mjs [--check]
import fs from 'node:fs';

const XYZW = ['x', 'y', 'z', 'w'];
const out = [];
const w = (s) => out.push(s);
w(`// helder/math for TypeScript: written by src/helder/math/typescript.mjs (do not edit).
//
// helder.math's types, the same names: immutable values (Haxe's are
// @:hxmc.struct values; helder's API copies them both ways). The operators
// are methods (a.mul(b), a.add(1); a number's side second: x.mul(2), as
// Haxe's 2 * x prints). helder/gfx's builtins (vec3, dot, normalize, ...)
// build and take them.
`);

function vecClass(n) {
	const self = `Vec${n}`, c = XYZW.slice(0, n);
	const each = (f) => `new ${self}(${c.map((k) => f(k)).join(', ')})`;
	w(`export class ${self} {`);
	w(`\tconstructor(${c.map((k) => `readonly ${k}: number`).join(', ')}) {}`);
	for (const [name, op] of [['add', '+'], ['sub', '-'], ['mul', '*'], ['div', '/']])
		w(`\t${name}(b: ${self} | number): ${self} {\n\t\treturn typeof b === "number" ? ${each((k) => `this.${k} ${op} b`)} : ${each((k) => `this.${k} ${op} b.${k}`)};\n\t}`);
	w(`\tneg(): ${self} {\n\t\treturn ${each((k) => `-this.${k}`)};\n\t}`);
	const sw = (prefix, len) => {
		if (prefix.length === len) {
			w(`\tget ${prefix}(): Vec${len} {\n\t\treturn new Vec${len}(${[...prefix].map((k) => `this.${k}`).join(', ')});\n\t}`);
			return;
		}
		for (const k of c) sw(prefix + k, len);
	};
	for (let len = 2; len <= 4; len++) sw('', len);
	w(`}\n`);
}
for (const n of [2, 3, 4]) vecClass(n);
w(`export class Mat4 {
	constructor(readonly c0: Vec4, readonly c1: Vec4, readonly c2: Vec4, readonly c3: Vec4) {}
	mul(b: Mat4): Mat4;
	mul(b: Vec4): Vec4;
	mul(b: Mat4 | Vec4): Mat4 | Vec4 {
		if (b instanceof Vec4) return this.c0.mul(b.x).add(this.c1.mul(b.y)).add(this.c2.mul(b.z)).add(this.c3.mul(b.w));
		return new Mat4(this.mul(b.c0), this.mul(b.c1), this.mul(b.c2), this.mul(b.c3));
	}
}

// a rotation as a unit quaternion (helder.math.Quat: x, y, z the
// vector part, w the scalar one), an immutable value; a.mul(b) rotates by
// b first, then by a; angles in radians, right-handed (as Mat4's)
export class Quat {
	constructor(readonly x: number, readonly y: number, readonly z: number, readonly w: number) {}
	static identity(): Quat {
		return new Quat(0, 0, 0, 1);
	}
	// a turn by angle about axis (of any length but zero)
	static axisAngle(axis: Vec3, angle: number): Quat {
		const l = Math.sqrt(axis.x * axis.x + axis.y * axis.y + axis.z * axis.z);
		const s = Math.sin(angle / 2) / l;
		return new Quat(axis.x * s, axis.y * s, axis.z * s, Math.cos(angle / 2));
	}
	// the turns about x, then y, then z
	static fromEuler(x: number, y: number, z: number): Quat {
		return Quat.axisAngle(new Vec3(0, 0, 1), z).mul(Quat.axisAngle(new Vec3(0, 1, 0), y)).mul(Quat.axisAngle(new Vec3(1, 0, 0), x));
	}
	mul(b: Quat): Quat {
		const a = this;
		return new Quat(a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y, a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
			a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w, a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z);
	}
}
`);
const text = out.join('\n');
const file = new URL('./index.ts', import.meta.url);
if (process.argv.includes('--check')) {
	if (fs.readFileSync(file, 'utf8') !== text) {
		console.error('src/helder/math/index.ts is not as typescript.mjs writes it: node src/helder/math/typescript.mjs');
		process.exit(1);
	}
} else fs.writeFileSync(file, text);
