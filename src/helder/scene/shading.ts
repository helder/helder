// helder.scene's shading models for TypeScript: the slot objects of
// src/helder/scene/render/shading/*.hx in TypeScript (the same slots,
// options, structs and functions, helder/gfx's operators as methods), so
// that a program's material(toon.with({...})) or material(unlit.with({...}))
// compiles with the program. Keep it in step with those files: what one
// changes the other does (tests/typescript/definitions/shading.ts checks
// their text is the same). Material's factories (Material.toon(...)) are
// Haxe's, these are for a material of one's own on a model.
import {
	slots, position, vec2, vec3, vec4, mat4, sample, dot, cross, normalize, mix, clamp, smoothstep, pow, min, max, floor, discard,
	type Vec2, type Vec3, type Vec4, type Texture2D,
} from "helder/gfx";
import {
	pbr, pbrColor, pbrAlpha, pbrPosition, reflectance, uvOf, fogAmount, display, joint, instanceNormal, instanceUv, type PbrVertex, type PbrVaryings,
	type PbrVertexParams, type PbrFragmentParams, type PbrSurface, type PbrPoint, type PbrFrame, type PbrMaterial, type LitSurface, type LightSample,
	type IndirectLight,
} from "./pbr";

// --- Lambert (Lambert.hx): a light's diffuse alone, the ambient's diffuse alone

export function lambertDirect(s: LitSurface, l: LightSample, p: {}): Vec3 {
	return s.albedo.mul(l.radiance).mul(l.ndotl / 3.14159265);
}

export function lambertIndirect(s: LitSurface, env: IndirectLight, p: {}): Vec3 {
	return env.irradiance.mul(s.albedo).mul(env.occlusion);
}

export const lambert = pbr.with({direct: lambertDirect, indirect: lambertIndirect});

// --- toon (Toon.hx): each light's n.l times its shadow in steps bands, the shade away from it

export function toonDirect(s: LitSurface, l: LightSample, p: {material: PbrMaterial}): Vec3 {
	return s.albedo.mul(l.color).mul(ramp(l.ndotl * l.shadow, p.material.model.x) / 3.14159265);
}

export function toonIndirect(s: LitSurface, env: IndirectLight, p: {material: PbrMaterial}): Vec3 {
	return s.albedo.mul(p.material.shadeColor.xyz).mul(env.occlusion);
}

export function ramp(x: number, steps: number): number {
	const n = max(steps, 1);
	const t = clamp(x, 0, 1) * n;
	const band = floor(t);
	return min((band + smoothstep(0, 0.0625, t - band)) / n, 1);
}

export const toon = pbr.with({direct: toonDirect, indirect: toonIndirect});

// --- Blinn-Phong (Phong.hx): Lambert's diffuse and a Blinn-Phong highlight, its shininess from the roughness

export function phongDirect(s: LitSurface, l: LightSample, p: {material: PbrMaterial}): Vec3 {
	const h = normalize(l.direction.add(s.view));
	const nh = max(dot(s.normal, h), 0);
	const vh = max(dot(s.view, h), 0);
	const shininess = phongShininess(s.roughness);
	const f0 = reflectance(s, p.material);
	const fresnel = f0.add(vec3(1).sub(f0).mul(pow(1 - vh, 5)));
	const highlight = fresnel.mul(0.25 * (shininess * 0.5 + 1) / 3.14159265 * pow(nh, shininess));
	return s.albedo.mul(1 - s.metalness).div(3.14159265).add(highlight).mul(l.radiance).mul(l.ndotl);
}

export function phongShininess(roughness: number): number {
	const a = roughness * roughness;
	return clamp(2 / max(a * a, 0.0001) - 2, 1, 4096);
}

export const phong = pbr.with({direct: phongDirect});

// --- unlit (Unlit.hx): no light; matcap, normals and depth its colour slot replaced

export type UnlitOptions = {skinned: boolean, instanced: boolean};

export type Unlit = {
	options: UnlitOptions,
	color: (s: PbrSurface, p: PbrFragmentParams) => Vec3,
	alpha: (s: PbrSurface, p: PbrFragmentParams) => number,
	position: (v: PbrPoint, p: PbrVertexParams) => Vec3,
};

// a direction in the camera's view space, its axes from the view-projection's rows
export function toView(frame: PbrFrame, d: Vec3): Vec3 {
	const vp = frame.viewProj;
	const right = normalize(vec3(vp.c0.x, vp.c1.x, vp.c2.x));
	const up = normalize(vec3(vp.c0.y, vp.c1.y, vp.c2.y));
	const back = normalize(vec3(vp.c0.z, vp.c1.z, vp.c2.z)).neg();
	return vec3(dot(d, right), dot(d, up), dot(d, back));
}

export function unlitShade(color: Vec3, baseAlpha: number, world: Vec3, frame: PbrFrame, material: PbrMaterial): Vec4 {
	let c = color.mul(frame.exposure.x);
	const mist = fogAmount(frame.fog, frame.fogShape, frame.eye.xyz, world) * material.ground.w;
	c = mix(c, material.uvV.w > 0 ? vec3(0) : frame.fog.xyz.mul(frame.exposure.x), mist);
	let shown = display(c, frame, material);
	let alpha = baseAlpha;
	if (material.layers.w > 0) {
		if (alpha < material.layers.w) discard();
		alpha = 1;
	}
	if (material.uvV.w > 0) shown = shown.mul(alpha);
	return vec4(shown, alpha);
}

export const unlit = slots({
	options: {skinned: false, instanced: false},
	vertex: (v: PbrVertex, p: PbrVertexParams, m: Unlit): PbrVaryings => {
		let pos = m.position({pos: v.pos, normal: v.normal, uv: v.uv}, p);
		let nr = v.normal;
		if (m.options.skinned) {
			const j0 = joint(p.jointMatrices!, v.joints!.x, p.skin!.rows.x), j1 = joint(p.jointMatrices!, v.joints!.y, p.skin!.rows.x);
			const j2 = joint(p.jointMatrices!, v.joints!.z, p.skin!.rows.x), j3 = joint(p.jointMatrices!, v.joints!.w, p.skin!.rows.x);
			const q = vec4(pos, 1), n4 = vec4(v.normal, 0);
			pos = j0.mul(q).mul(v.weights!.x).add(j1.mul(q).mul(v.weights!.y)).add(j2.mul(q).mul(v.weights!.z)).add(j3.mul(q).mul(v.weights!.w)).xyz;
			nr = j0.mul(n4).mul(v.weights!.x).add(j1.mul(n4).mul(v.weights!.y)).add(j2.mul(n4).mul(v.weights!.z)).add(j3.mul(n4).mul(v.weights!.w)).xyz;
		}
		const model = m.options.instanced ? mat4(vec4(v.m0!.xyz, 0), vec4(v.m1!.xyz, 0), vec4(v.m2!.xyz, 0), vec4(v.m3!.xyz, 1)) : p.object!.model;
		const world = model.mul(vec4(pos, 1));
		return {
			clip: position(p.frame.viewProj.mul(world)),
			world: world.xyz,
			normal: m.options.instanced ? instanceNormal(v.m0!.xyz, v.m1!.xyz, v.m2!.xyz, nr) : p.object!.normalMatrix.mul(vec4(nr, 0)).xyz,
			uv: m.options.instanced ? instanceUv(v.uv, v.m3!.w) : v.uv,
			up: m.options.instanced ? v.m1!.xyz : model.mul(vec4(0, 1, 0, 0)).xyz,
			tint: m.options.instanced ? vec3(1 + v.m0!.w, 1 + v.m1!.w, 1 + v.m2!.w) : p.object!.tint.xyz,
			lights0: vec4(-1),
			lights1: vec4(-1),
		};
	},
	fragment: (i: PbrVaryings, p: PbrFragmentParams, m: Unlit): Vec4 => {
		const uv = uvOf(p.material, i.uv);
		const texel = sample(p.baseColorTexture, uv);
		const s: PbrSurface = {
			world: i.world,
			normal: normalize(i.normal),
			uv: uv,
			up: normalize(i.up),
			baseColor: vec4(p.material.baseColor.xyz.mul(pow(texel.xyz, vec3(2.2))), p.material.baseColor.w * texel.w),
		};
		return unlitShade(m.color(s, p).mul(i.tint), m.alpha(s, p), i.world, p.frame, p.material);
	},
	color: pbrColor,
	alpha: pbrAlpha,
	position: pbrPosition,
});

// (Matcap.hx) a lit sphere's picture by the normal as the eye sees it (the material's emissiveTexture)
export function matcapColor(s: PbrSurface, p: {frame: PbrFrame, emissiveTexture: Texture2D}): Vec3 {
	const n = normalize(toView(p.frame, s.normal));
	const e = normalize(toView(p.frame, p.frame.eye.xyz.sub(s.world)));
	const x = normalize(vec3(e.z, 0, -e.x));
	const y = cross(e, x);
	const at = vec2(dot(x, n), dot(y, n)).mul(0.495).add(0.5);
	return s.baseColor.xyz.mul(pow(sample(p.emissiveTexture, vec2(at.x, 1 - at.y)).xyz, vec3(2.2)));
}

export const matcap = unlit.with({color: matcapColor});

// (Normals.hx) the normal in view space as a colour
export function normalsColor(s: PbrSurface, p: {frame: PbrFrame}): Vec3 {
	return normalize(toView(p.frame, s.normal)).mul(0.5).add(0.5);
}

export const normals = unlit.with({color: normalsColor});

// (Depth.hx) the depth along the view as a grey, white at near, black at far
export function depthColor(s: PbrSurface, p: {frame: PbrFrame, material: PbrMaterial}): Vec3 {
	const d = -toView(p.frame, s.world.sub(p.frame.eye.xyz)).z;
	const near = p.material.model.z;
	const far = p.material.model.w;
	return vec3(1 - clamp((d - near) / max(far - near, 0.0001), 0, 1));
}

export const depth = unlit.with({color: depthColor});
