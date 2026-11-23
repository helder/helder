// helder.scene's standard material for TypeScript: pbr, the slot object of
// src/helder/scene/render/PbrShader.hx in TypeScript (the same stages,
// slots, options, structs and functions, helder/gfx's operators as methods),
// so that a program's material(pbr.with({...})) compiles with the
// program: its variants are the renderer's (plain, normal mapped, skinned,
// instanced, instanced and normal mapped) and draw what Haxe's draw
// (tests/3d's ts-glow frame is glow.png). Keep it in step with
// PbrShader.hx: what one changes the other does.
import {
	slots, position, vec2, vec3, vec4, mat4, sample, sampleLevel, dot, cross, normalize, reflect, mix, clamp, smoothstep, pow, min, max, abs,
	sqrt, floor, fract, step, discard, length, exp, cos, sin, log, inversesqrt, type Vec2, type Vec3, type Vec4, type Mat4, type Texture2D, type UniformArray,
} from "helder/gfx";

// the combined vertex: a variant's attributes those it reads, in this order
export type PbrVertex = {
	pos: Vec3, normal: Vec3, uv: Vec2,
	tangent?: Vec4, joints?: Vec4, weights?: Vec4, m0?: Vec4, m1?: Vec4, m2?: Vec4, m3?: Vec4, uv1?: Vec2,
};

export type PbrVaryings = {
	clip: Vec4, world: Vec3, normal: Vec3, uv: Vec2, tangent?: Vec4, up: Vec3, tint: Vec3, uv1?: Vec2, lights0: Vec4, lights1: Vec4,
	ambient?: Vec4, probeA?: Vec4, extentA?: Vec4, probeB?: Vec4, extentB?: Vec4, probeAtlas?: Vec4, lightmapUv?: Vec4,
};

// per frame: the camera and the lights (PbrShader.hx's PbrFrame)
export type PbrFrame = {
	viewProj: Mat4, eye: Vec4, lightDir: Vec4, lightColor: Vec4, sky: Vec4, ground: Vec4, exposure: Vec4, lightViewProj: Mat4, shadow: Vec4,
	lightViewProjFar: Mat4, shadowFar: Vec4, shadowRect: Vec4, shadowRectFar: Vec4, shadowAtlas: Vec4, environment: Vec4, rim: Vec4,
	fog: Vec4, fogShape: Vec4, shadowSoft: Vec4, clusters: Vec4, clusterDepth: Vec4, clusterAxis: Vec4,
};

// per draw: the node's matrices, its light list
export type PbrObject = {model: Mat4, normalMatrix: Mat4, tint: Vec4, lights0: Vec4, lights1: Vec4};

// per draw: the material
export type PbrMaterial = {
	baseColor: Vec4, params: Vec4, emissive: Vec4, ground: Vec4, air: Vec4, uvU: Vec4, uvV: Vec4, layers: Vec4, model: Vec4, shadeColor: Vec4,
	// (the glTF extensions')
	sheen: Vec4, specular: Vec4, coat: Vec4, transmission: Vec4, attenuation: Vec4, iridescence: Vec4, anisotropy: Vec4, maps0: Vec4, maps1: Vec4, maps2: Vec4,
	uvMetallicRoughnessU: Vec4, uvMetallicRoughnessV: Vec4, uvNormalU: Vec4, uvNormalV: Vec4, uvOcclusionU: Vec4, uvOcclusionV: Vec4, uvEmissiveU: Vec4,
	uvEmissiveV: Vec4,
};

export type PbrSkinInfo = {rows: Vec4};

// per draw, the probes' (PbrShader.hx's PbrProbes)
export type PbrProbes = {sh: UniformArray<Vec4, 7>, probeA: Vec4, extentA: Vec4, probeB: Vec4, extentB: Vec4, atlas: Vec4};

// per draw, a lightmap's (PbrShader.hx's PbrLightmap)
export type PbrLightmap = {rect: Vec4, params: Vec4};

export type PbrVertexParams = {frame: PbrFrame, object?: PbrObject, probes?: PbrProbes, lightmap?: PbrLightmap, skin?: PbrSkinInfo, jointMatrices?: Texture2D};

export type PbrFragmentParams = {
	frame: PbrFrame, object?: PbrObject, material: PbrMaterial, lights: Texture2D, baseColorTexture: Texture2D, metallicRoughnessTexture: Texture2D,
	emissiveTexture: Texture2D, occlusionTexture: Texture2D, shadowMap: Texture2D, clusterMap: Texture2D, environmentMap: Texture2D, aoMap: Texture2D,
	normalTexture?: Texture2D, ltcMap?: Texture2D, lightMap?: Texture2D, probesMap?: Texture2D, prepass?: PbrPrepass, layerMap0?: Texture2D, layerMap1?: Texture2D, transmissionMap?: Texture2D,
};

// (prepass: the view buffers' variant, ViewBuffers; the glTF extensions,
// each a layer of the surface; uvSets: each core map its own uvs; sunOnly:
// no local lights' loop; untiled: the local lights unshadowed; probes,
// area, lightmap: Probes', AreaLights', Lightmap's)
export type PbrOptions = {
	normalMap: boolean, skinned: boolean, instanced: boolean, prepass: boolean, sheen: boolean, specular: boolean, clearcoat: boolean,
	transmission: boolean, iridescence: boolean, anisotropy: boolean, uvSets: boolean, sunOnly: boolean, untiled: boolean,
	probes: boolean, area: boolean, lightmap: boolean,
};

// per draw in the prepass (ViewBuffers): the camera's view, x the selection group
export type PbrPrepass = {view: Mat4, id: Vec4};

// what the fragment's slots read: the point in the world, its unit normal,
// the material's uvs, the node's unit up, the base colour (linear)
export type PbrSurface = {world: Vec3, normal: Vec3, uv: Vec2, up: Vec3, baseColor: Vec4, uvMetallicRoughness?: Vec2, uvEmissive?: Vec2};

// what the position slot reads: the vertex's point, normal and uvs
export type PbrPoint = {pos: Vec3, normal: Vec3, uv: Vec2};

// the slot object (the stages' third parameter): its options, its slots
export type Pbr = {
	options: PbrOptions,
	color: (s: PbrSurface, p: PbrFragmentParams) => Vec3,
	alpha: (s: PbrSurface, p: PbrFragmentParams) => number,
	normal: (s: PbrSurface, p: PbrFragmentParams) => Vec3,
	roughness: (s: PbrSurface, p: PbrFragmentParams) => number,
	metalness: (s: PbrSurface, p: PbrFragmentParams) => number,
	emissive: (s: PbrSurface, p: PbrFragmentParams) => Vec3,
	direct: (s: LitSurface, l: LightSample, p: PbrFragmentParams) => Vec3,
	indirect: (s: LitSurface, env: IndirectLight, p: PbrFragmentParams) => Vec3,
	position: (v: PbrPoint, p: PbrVertexParams) => Vec3,
};

// what the lighting slots (direct, indirect) read: the surface with the
// other slots' results (PbrShader.hx's LitSurface)
export type LitSurface = {
	world: Vec3, normal: Vec3, view: Vec3, uv: Vec2, up: Vec3, albedo: Vec3, alpha: number, metalness: number, roughness: number,
	// (the glTF extensions' layers, filled by a variant with them)
	sheen?: number, sheenColor?: Vec3, sheenRoughness?: number, specular?: number, specularColor?: Vec3, specularWeight?: number, coat?: number,
	coatRoughness?: number, coatNormal?: Vec3, transmission?: number, thickness?: number, iridescence?: number, iridescenceFresnel?: Vec3,
	anisotropy?: number, anisotropyDirection?: Vec3, anisotropyBitangent?: Vec3,
};

// one light at a surface: its colour times its intensity and attenuation,
// its shadow (1: lit), the two multiplied, the direction towards it, n.l
export type LightSample = {color: Vec3, shadow: number, radiance: Vec3, direction: Vec3, ndotl: number};

// the light around a surface: the ambient along its normal, the
// environment's along its reflection, the material's occlusion
export type IndirectLight = {irradiance: Vec3, radiance: Vec3, occlusion: number};

// a vertex's uvs as the material's textures read them (KHR_texture_transform)
export function uvOf(material: PbrMaterial, uv: Vec2): Vec2 {
	return vec2(dot(material.uvU.xy, uv) + material.uvU.z, dot(material.uvV.xy, uv) + material.uvV.z);
}

// the slots' defaults
export function pbrColor(s: PbrSurface, p: {}): Vec3 {
	return s.baseColor.xyz;
}

export function pbrAlpha(s: PbrSurface, p: {}): number {
	return s.baseColor.w;
}

export function pbrNormal(s: PbrSurface, p: {}): Vec3 {
	return s.normal;
}

export function pbrMetalness(s: PbrSurface, p: {material: PbrMaterial, metallicRoughnessTexture: Texture2D}): number {
	return clamp(p.material.params.x * sample(p.metallicRoughnessTexture, s.uv).z, 0, 1);
}

export function pbrRoughness(s: PbrSurface, p: {material: PbrMaterial, metallicRoughnessTexture: Texture2D}): number {
	return clamp(mix(p.material.params.y * sample(p.metallicRoughnessTexture, s.uv).y, 0.07, p.material.ground.z), 0.04, 1);
}

export function pbrEmissive(s: PbrSurface, p: {material: PbrMaterial, emissiveTexture: Texture2D}): Vec3 {
	return p.material.emissive.xyz.mul(pow(sample(p.emissiveTexture, s.uv).xyz, vec3(2.2)));
}

export function pbrPosition(v: PbrPoint, p: {}): Vec3 {
	return v.pos;
}

// the direct slot's default: one light's Lambert diffuse and Cook-Torrance specular
export function pbrDirect(s: LitSurface, l: LightSample, p: {material: PbrMaterial}): Vec3 {
	const a = s.roughness * s.roughness;
	return brdf(s.normal, s.view, l.direction, s.albedo, s.metalness, a * a, reflectance(s, p.material)).mul(l.radiance);
}

// the indirect slot's default: the irradiance's diffuse share and the
// environment's reflection (Karis' fit of the split sum), occluded
export function pbrIndirect(s: LitSurface, env: IndirectLight, p: {material: PbrMaterial}): Vec3 {
	const nv = max(dot(s.normal, s.view), 0.0001);
	const c0 = vec4(-1, -0.0275, -0.572, 0.022);
	const c1 = vec4(1, 0.0425, 1.04, -0.04);
	const rr = c0.mul(s.roughness).add(c1);
	const a004 = min(rr.x * rr.x, pow(2, -9.28 * nv)) * rr.x + rr.y;
	const ab = vec2(-1.04, 1.04).mul(a004).add(rr.zw);
	return env.irradiance.mul(s.albedo).mul(1 - s.metalness).add(env.radiance.mul(reflectance(s, p.material).mul(ab.x).add(ab.y))).mul(env.occlusion);
}

// a surface's reflectance at normal incidence (a dielectric's, a metal's, a crystal's)
export function reflectance(s: LitSurface, material: PbrMaterial): Vec3 {
	return mix(mix(vec3(0.04), s.albedo, s.metalness), vec3(0.12), material.ground.z);
}

// the lighting slots' surface from the other slots' results
export function litSurface(facing: Vec3, world: Vec3, uv: Vec2, up: Vec3, albedo: Vec3, alpha: number, metalness: number, roughness: number, frame: PbrFrame,
		material: PbrMaterial): LitSurface {
	const v = normalize(frame.eye.xyz.sub(world));
	const n = material.params.w > 0.5 && dot(facing, v) < 0 ? facing.neg() : facing;
	return {world: world, normal: n, view: v, uv: uv, up: up, albedo: albedo, alpha: alpha, metalness: metalness, roughness: roughness};
}

// how much of the sun reaches a surface standing on Material.ground's sphere
export function daylight(s: LitSurface, frame: PbrFrame, material: PbrMaterial): number {
	return mix(1.0, smoothstep(-0.08, 0.22, dot(s.up, frame.lightDir.xyz)), material.ground.x);
}

// the sun at a surface, shadowed by its cascades
export function sunLight(s: LitSurface, frame: PbrFrame, material: PbrMaterial, shadowMap: Texture2D): LightSample {
	const l = frame.lightDir.xyz;
	const c = frame.lightColor.xyz.mul(daylight(s, frame, material));
	const lit = shadowed(frame, shadowMap, s.world, s.normal);
	return {color: c, shadow: lit, radiance: c.mul(lit), direction: l, ndotl: max(dot(s.normal, l), 0)};
}

// where a point's local lights are listed: ClusteredLights' cell, else the draw's list (PbrShader.hx's clusterCell)
export function clusterCell(viewProj: Mat4, eye: Vec4, clusters: Vec4, clusterDepth: Vec4, clusterAxis: Vec4, clusterMap: Texture2D, world: Vec3): Vec3 {
	let cell = vec3(0, 0, 8);
	if (clusters.x > 0) {
		const sc = viewProj.mul(vec4(world, 1));
		const x = clamp(floor((sc.x / sc.w * 0.5 + 0.5) * clusters.x), 0, clusters.x - 1);
		const y = clamp(floor((0.5 - sc.y / sc.w * 0.5) * clusters.y), 0, clusters.y - 1);
		const depth = max(dot(world.sub(eye.xyz), clusterAxis.xyz), clusterDepth.x);
		const z = clamp(floor(log(depth / clusterDepth.x) * clusterDepth.y), 0, clusters.z - 1);
		const column = x * (clusters.w + 1);
		const row = y + z * clusters.y;
		cell = vec3(column, row, mapTexel(clusterMap, column, row, clusterDepth));
	}
	return cell;
}

// the k-th light a point's list names, a row of the frame's lights; -1: none (PbrShader.hx's lightIndex)
export function lightIndex(clusters: Vec4, clusterDepth: Vec4, lights0: Vec4, lights1: Vec4, clusterMap: Texture2D, cell: Vec3, k: number): number {
	let index = -1.0;
	if (clusters.x > 0) index = mapTexel(clusterMap, cell.x + 1 + k, cell.y, clusterDepth);
	else {
		const four = k < 4 ? lights0 : lights1;
		const j = k < 4 ? k : k - 4;
		index = floor((j < 0.5 ? four.x : j < 1.5 ? four.y : j < 2.5 ? four.z : four.w) + 0.5);
	}
	return index;
}

// texel (x, y) of an R32F map of size.z by size.w texels
function mapTexel(t: Texture2D, x: number, y: number, size: Vec4): number {
	return sampleLevel(t, vec2((x + 0.5) / size.z, (y + 0.5) / size.w), 0).x;
}

// four texels of light k's row of the cluster map, from column x
function lightRow(t: Texture2D, x: number, k: number, clusterAxis: Vec4, clusterDepth: Vec4): Vec4 {
	const v = (clusterAxis.w + k + 0.5) / clusterDepth.w;
	const w = clusterDepth.z;
	return vec4(sampleLevel(t, vec2((x + 0.5) / w, v), 0).x, sampleLevel(t, vec2((x + 1.5) / w, v), 0).x, sampleLevel(t, vec2((x + 2.5) / w, v), 0).x,
		sampleLevel(t, vec2((x + 3.5) / w, v), 0).x);
}

// texel x of row y of the frame's lights and their shadow tiles (RGBA32F, 6 by 44: a row a light, its
// position, colour and cone; from row 32 a row a tile, its view-projection's columns, rect and filter; PbrShader.hx's lightTexel)
function lightTexel(t: Texture2D, x: number, y: number): Vec4 {
	return sampleLevel(t, vec2((x + 0.5) / 6, (y + 0.5) / 44), 0);
}

// a tile's view-projection (lightTexel's row)
function tileMatrix(t: Texture2D, row: number): Mat4 {
	return mat4(lightTexel(t, 0, row), lightTexel(t, 1, row), lightTexel(t, 2, row), lightTexel(t, 3, row));
}

// a local light at a surface from its three vectors, its lit share (PbrShader.hx's localLight)
export function localLight(world: Vec3, normal: Vec3, pos: Vec4, color: Vec4, cone: Vec4, shadow: number): LightSample {
	const d = pos.xyz.sub(world);
	const dist2 = max(dot(d, d), 0.0001);
	const dist = sqrt(dist2);
	const q = dist / pos.w;
	const window = clamp(1 - q * q * q * q, 0, 1);
	const l = d.div(dist);
	const t = clamp(dot(l.neg(), cone.xyz) + cone.w, 0, 1);
	const c = color.xyz.mul(window * window / dist2 * (t * t * (3 - 2 * t)));
	return {color: c, shadow: shadow, radiance: c.mul(shadow), direction: l, ndotl: max(dot(normal, l), 0)};
}

// where a surface's point is looked up in a local light's tiles (PbrShader.hx's shadowPoint)
function shadowPoint(world: Vec3, normal: Vec3, light: Vec3, params: Vec4): Vec3 {
	const d = light.sub(world);
	const dist = max(length(d), 0.0001);
	return world.add(d.mul(params.y)).add(normal.mul(params.z * dist));
}

// the face of a point light's tiles a moved point is in (PbrShader.hx's tileFace)
function tileFace(at: Vec3, light: Vec3, point: boolean): number {
	let face = 0.0;
	if (point) {
		const d = at.sub(light);
		const a = abs(d);
		face = a.x >= a.y && a.x >= a.z ? (d.x > 0 ? 0 : 1) : a.y >= a.z ? (d.y > 0 ? 2 : 3) : (d.z > 0 ? 4 : 5);
	}
	return face;
}

// a local light's lit share at a moved point from a tile of the atlas (PbrShader.hx's tileShadow)
function tileShadow(map: Texture2D, viewProj: Mat4, rect: Vec4, params: Vec4, inv: Vec4, at: Vec3): number {
	const c = viewProj.mul(vec4(at, 1));
	const p = c.xyz.div(c.w);
	const uv = vec2(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5);
	let result = 1.0;
	if (c.w > 0 && uv.x > 0 && uv.x < 1 && uv.y > 0 && uv.y < 1 && p.z < 1) {
		const t = inv.x / rect.z;
		let lit = 0.0;
		if (params.w > 0) lit = disc(map, uv, rect, inv, p.z, params.w, t);
		else
			lit = grid(map, uv, rect, inv, p.z, t);
		result = 1 - params.x * (1 - lit);
	}
	return result;
}

// the 3x3 filter's lit share, a loop of its nine taps (PbrShader.hx's grid)
function grid(map: Texture2D, uv: Vec2, rect: Vec4, inv: Vec4, depth: number, t: number): number {
	let sum = 0.0;
	let k = 0.0;
	while (k < 9) {
		const row = floor(k / 3);
		sum += tap(map, uv, rect, inv, depth, (k - row * 3 - 1) * t, (row - 1) * t);
		k += 1;
	}
	return sum / 9;
}

// a tile's uv in the atlas, held inside the tile's edge texels (PbrShader.hx's atlasUv)
function atlasUv(uv: Vec2, rect: Vec4, inv: Vec4): Vec2 {
	return clamp(rect.xy.add(uv.mul(rect.zw)), rect.xy.add(inv.xy.mul(0.5)), rect.xy.add(rect.zw).sub(inv.xy.mul(0.5)));
}

// a disc of 12 taps out to radius in the tile's uv (PbrShader.hx's disc)
function disc(map: Texture2D, uv: Vec2, rect: Vec4, inv: Vec4, depth: number, radius: number, texel: number): number {
	const cell = fract(floor(uv.div(texel)).div(64)).mul(64);
	const h = fract(52.9829189 * fract(dot(cell, vec2(0.06711056, 0.00583715))));
	const t = 2 * fract(2 * h) - 1;
	let dir = vec2(1 - t * t, 2 * t).mul((h < 0.5 ? 1 : -1) / (1 + t * t));
	const c = -0.7373688;
	const s = 0.6754903;
	let sum = 0.0;
	let k = 0.0;
	while (k < 12) {
		const off = dir.mul(sqrt((k + 0.5) / 12) * radius);
		sum += step(depth, sampleLevel(map, atlasUv(uv.add(off), rect, inv), 0).x);
		dir = vec2(dir.x * c - dir.y * s, dir.x * s + dir.y * c);
		k += 1;
	}
	return sum / 12;
}

// the light around a surface (IndirectLight)
export function ambientAt(s: LitSurface, frame: PbrFrame, material: PbrMaterial, occlusionTexture: Texture2D, environmentMap: Texture2D, aoMap: Texture2D): IndirectLight {
	const n = s.normal;
	const above = n.y * 0.5 + 0.5;
	let irradiance = mix(frame.ground.xyz, frame.sky.xyz, above);
	const r = reflect(s.view.neg(), n);
	const env = reflected(frame, environmentMap, r, s.roughness);
	if (frame.environment.x > 0) {
		const top = frame.environment.y;
		irradiance = pow(sampleLevel(environmentMap, equirect(n), max(top - 2, 0)).xyz, vec3(2.2)).mul(frame.environment.x);
		if (frame.environment.z > 0) {
			const rows = frame.environment.z;
			irradiance = pow(atlas(environmentMap, equirect(n), rows, rows, frame.environment.w), vec3(2.2)).mul(frame.environment.x);
		}
	}
	const day = daylight(s, frame, material);
	const horizon = smoothstep(-0.2, 0.2, dot(r, s.up));
	let occlusion = sample(occlusionTexture, s.uv).x;
	if (frame.exposure.z > 0.5) {
		const sc = frame.viewProj.mul(vec4(s.world, 1));
		occlusion = occlusion * sampleLevel(aoMap, vec2(sc.x / sc.w * 0.5 + 0.5, 0.5 - sc.y / sc.w * 0.5), 0).x;
	}
	return {
		irradiance: irradiance.mul(mix(1.0, 0.55 + 0.45 * smoothstep(-0.6, 0.6, dot(n, s.up)), material.ground.x)),
		radiance: env.mul(mix(1.0, mix(0.12, 1, horizon) * (0.45 + 0.55 * day), material.ground.x)),
		occlusion: occlusion,
	};
}

// (Equirect.hx's)
function equirect(d: Vec3): Vec2 {
	return vec2(arcTan2(d.x, -d.z) * 0.15915494 + 0.5, arcCos(clamp(d.y, -1, 1)) * 0.31830989);
}

function atlas(t: Texture2D, uv: Vec2, row: number, levels: number, edge: number): Vec3 {
	return sampleLevel(t, vec2(uv.x, (row + clamp(uv.y, edge, 1 - edge)) / (levels + 1)), 0).xyz;
}

function arcTan2(y: number, x: number): number {
	const ax = abs(x), ay = abs(y);
	const a = min(ax, ay) / max(max(ax, ay), 0.000001);
	const s = a * a;
	let r = a * (0.999866 + s * (-0.3302995 + s * (0.180141 + s * (-0.085133 + s * 0.0208351))));
	if (ay > ax) r = 1.5707964 - r;
	if (x < 0) r = 3.1415927 - r;
	if (y < 0) r = -r;
	return r;
}

function arcCos(x: number): number {
	const ax = abs(x);
	let r = sqrt(1 - ax) * (1.5707288 + ax * (-0.2121144 + ax * (0.074261 - 0.0187293 * ax)));
	if (x < 0) r = 3.1415927 - r;
	return r;
}

// the fragment's colour from its surface, the direct light summed, the
// indirect slot's and the light it emits (PbrShader.hx's shade)
function shade(s: LitSurface, lights: Vec3, indirect: Vec3, env: IndirectLight, emissive: Vec3, frame: PbrFrame, material: PbrMaterial, shadowMap: Texture2D,
		environmentMap: Texture2D): Vec4 {
	const crystal = material.ground.z;
	const n = s.normal;
	const v = s.view;
	const base = s.albedo;
	const metallic = s.metalness;
	const l = frame.lightDir.xyz;
	const nv = max(dot(n, v), 0.0001);
	const f0 = reflectance(s, material);
	const day = daylight(s, frame, material);
	const sunUp = dot(s.up, l);
	let direct = lights;
	const r = reflect(v.neg(), n);
	let ambient = indirect;
	let emitted = emissive;
	emitted = emitted.mul(mix(1.0, smoothstep(0.12, -0.18, dot(n, l)), material.emissive.w));
	const edge = 1 - nv;
	const rim = frame.rim.xyz.mul(pow(edge, frame.rim.w) * smoothstep(-0.25, 0.5, dot(n, l)) * day);
	direct = direct.add(rim.mul(mix(vec3(1), base, 0.5)));
	let alpha = s.alpha;
	const coat = material.layers.x;
	if (coat > 0) {
		const cr = clamp(material.layers.y, 0.04, 1);
		const ca = cr * cr;
		const fc = (0.04 + 0.96 * pow(1 - nv, 5)) * coat;
		const lit = shadowed(frame, shadowMap, s.world, n) * day;
		const layer = coatLobe(n, v, l, ca * ca).mul(frame.lightColor.xyz).mul(lit * coat).add(reflected(frame, environmentMap, r, cr).mul(fc));
		direct = direct.mul(1 - fc);
		ambient = ambient.mul(1 - fc).add(layer);
	}
	if (crystal > 0) {
		const fres = pow(edge, 3);
		const glow = mix(material.emissive.xyz, vec3(dot(material.emissive.xyz, vec3(0.3, 0.4, 0.3))).mul(1.6).add(material.emissive.xyz.mul(0.4)), 0.22);
		const inner = glow.mul(0.35 + 0.65 * nv * nv).mul(0.75 + 0.25 * day);
		const through = frame.lightColor.xyz.mul(base).mul(pow(max(dot(v, l.neg()), 0), 6) * 0.6 * day);
		const sheen = env.radiance.mul(1.4).add(frame.rim.xyz.mul(day)).mul(f0.add(vec3(1).sub(f0).mul(fres))).mul(fres);
		emitted = mix(emitted, inner.add(through), crystal).add(sheen.mul(crystal));
		alpha = mix(alpha, 1, fres * crystal);
	}
	const transmission = max(material.layers.z, 0) * (1 - metallic);
	if (transmission > 0) {
		const diffuse = env.irradiance.mul(base).mul(1 - metallic).mul(env.occlusion);
		ambient = ambient.sub(diffuse.mul(transmission));
		direct = direct.mul(1 - transmission * 0.9);
	}
	let color = direct.add(ambient).add(emitted).mul(frame.exposure.x);
	const limb = 1 - max(dot(s.up, v), 0);
	const haze = material.ground.y * limb * limb;
	color = mix(color, material.air.xyz.mul(0.12 + 0.88 * smoothstep(-0.2, 0.35, sunUp)).mul(frame.exposure.x), haze);
	const mist = fogAmount(frame.fog, frame.fogShape, frame.eye.xyz, s.world) * material.ground.w;
	color = mix(color, material.uvV.w > 0 ? vec3(0) : frame.fog.xyz.mul(frame.exposure.x), mist);
	let shown = display(color, frame, material);
	if (material.layers.w > 0) {
		if (alpha < material.layers.w) discard();
		alpha = 1;
	}
	if (transmission > 0) {
		shown = shown.mul(alpha);
		alpha = alpha * (1 - transmission);
	}
	if (material.layers.z < 0) {
		const through = -material.layers.z * (1 - metallic) * alpha;
		const filter = mix(vec3(1), base, through * (1 - mist));
		shown = frame.exposure.y > 0.5 ? filter : encode(filter);
		alpha = 1;
	}
	if (material.uvV.w > 0) shown = shown.mul(alpha);
	return vec4(shown, alpha);
}

// the light from the environment along a reflection r at a roughness
function reflected(frame: PbrFrame, environmentMap: Texture2D, r: Vec3, rough: number): Vec3 {
	let env = mix(frame.ground.xyz, frame.sky.xyz, smoothstep(-0.2, 0.2, r.y));
	if (frame.environment.x > 0) {
		const top = frame.environment.y;
		env = pow(sampleLevel(environmentMap, equirect(r), rough * max(top - 1, 0)).xyz, vec3(2.2)).mul(frame.environment.x);
		if (frame.environment.z > 0) {
			const rows = frame.environment.z;
			const edge = frame.environment.w;
			const at = rough * (rows - 1);
			const r0 = floor(at);
			const ru = equirect(r);
			const lo = atlas(environmentMap, ru, r0, rows, edge);
			const hi = atlas(environmentMap, ru, min(r0 + 1, rows - 1), rows, edge);
			env = pow(mix(lo, hi, at - r0), vec3(2.2)).mul(frame.environment.x);
		}
	}
	return env;
}

// an area light at a surface by linearly transformed cosines (PbrShader.hx's areaLight)
function areaLight(world: Vec3, n: Vec3, v: Vec3, rough: number, albedo: Vec3, metalness: number, f0: Vec3, pos: Vec4, color: Vec4, cone: Vec4, ltc: Texture2D): Vec3 {
	const c = pos.xyz;
	const packed = cone.w - 4194304;
	const qu = floor(packed / 2048);
	const qv = packed - qu * 2048;
	const ln = octDirection(vec2(qu, qv).div(2047).mul(2).sub(1));
	let result = vec3(0);
	if (dot(ln, world.sub(c)) > 0) {
		const right = cone.xyz;
		const r = normalize(right);
		const up = cross(ln, r);
		const rect = color.w < -0.75;
		const count = rect ? 4.0 : 8.0;
		const radius = length(right) * 1.0539889;
		const ru = rect ? right.mul(1.4142136) : r.mul(radius);
		const uu = rect ? up.mul((-1 - color.w) * 1.4142136) : up.mul(radius);
		const nv = clamp(dot(n, v), 0, 1);
		const uv = vec2(rough, sqrt(1 - nv)).mul(0.984375).add(0.0078125);
		const t1 = sampleLevel(ltc, vec2(uv.x, uv.y * 0.5), 0);
		const t2 = sampleLevel(ltc, vec2(uv.x, uv.y * 0.5 + 0.5), 0);
		const tx = normalize(v.sub(n.mul(dot(v, n))).add(vec3(0.0001, 0, 0)));
		const ty = cross(n, tx).neg();
		const rel = c.sub(world);
		const spec = ltcPolygon(rel, ru, uu, count, tx, ty, n, vec3(t1.x, 0, t1.y), vec3(t1.z, 0, t1.w));
		const diff = ltcPolygon(rel, ru, uu, count, tx, ty, n, vec3(1, 0, 0), vec3(0, 0, 1));
		const fresnel = f0.mul(t2.x).add(vec3(1).sub(f0).mul(t2.y));
		const q = length(rel) / pos.w;
		const window = clamp(1 - q * q * q * q, 0, 1);
		result = color.xyz.mul(albedo.mul((1 - metalness) * diff).add(fresnel.mul(spec))).mul(window * window);
	}
	return result;
}

function ltcPolygon(rel: Vec3, ru: Vec3, uu: Vec3, count: number, tx: Vec3, ty: Vec3, n: Vec3, m0: Vec3, m2: Vec3): number {
	const step = 6.2831853 / count;
	let a = ltcVertex(rel, ru, uu, 0.5 * step, tx, ty, n, m0, m2);
	let sum = vec3(0);
	let k = 1.0;
	while (k <= count) {
		const b = ltcVertex(rel, ru, uu, (k + 0.5) * step, tx, ty, n, m0, m2);
		sum = sum.add(edgeFormFactor(a, b));
		a = b;
		k += 1;
	}
	const l = length(sum);
	return max((l * l + sum.z) / (l + 1), 0);
}

function ltcVertex(rel: Vec3, ru: Vec3, uu: Vec3, angle: number, tx: Vec3, ty: Vec3, n: Vec3, m0: Vec3, m2: Vec3): Vec3 {
	const p = rel.add(ru.mul(cos(angle))).add(uu.mul(sin(angle)));
	const y = vec3(dot(tx, p), dot(ty, p), dot(n, p));
	return normalize(m0.mul(y.x).add(vec3(0, y.y, 0)).add(m2.mul(y.z)));
}

function edgeFormFactor(a: Vec3, b: Vec3): Vec3 {
	const x = dot(a, b);
	const y = abs(x);
	const fa = 0.8543985 + (0.4965155 + 0.0145206 * y) * y;
	const fb = 3.417594 + (4.1616724 + y) * y;
	const v = fa / fb;
	const t = x > 0 ? v : 0.5 * inversesqrt(max(1 - x * x, 0.000001)) - v;
	return cross(a, b).mul(t);
}

// (Equirect.hx's octDirection)
function octDirection(p: Vec2): Vec3 {
	let uv = p;
	if (abs(uv.x) > 1) uv = vec2((uv.x > 0 ? 2.0 : -2.0) - uv.x, -uv.y);
	if (abs(uv.y) > 1) uv = vec2(-uv.x, (uv.y > 0 ? 2.0 : -2.0) - uv.y);
	let n = vec3(uv.x, 1 - abs(uv.x) - abs(uv.y), uv.y);
	if (n.y < 0) {
		const f = vec2(1).sub(abs(vec2(n.z, n.x))).mul(vec2(n.x >= 0 ? 1.0 : -1.0, n.z >= 0 ? 1.0 : -1.0));
		n = vec3(f.x, n.y, f.y);
	}
	return normalize(n);
}

// the light around a surface with probes (PbrShader.hx's probeLight)
function probeLight(env: IndirectLight, world: Vec3, n: Vec3, v: Vec3, rough: number, ambient: Vec4, probeA: Vec4, extentA: Vec4, probeB: Vec4, extentB: Vec4,
		t: Texture2D, e: Vec4): IndirectLight {
	let irradiance = env.irradiance;
	if (ambient.w > 0.5) irradiance = ambient.xyz;
	let radiance = env.radiance;
	if (probeA.w > 0.5) {
		const r = reflect(v.neg(), n);
		let b = env.radiance;
		if (probeB.w > 0.5) b = boxReflected(t, world, r, rough, probeB, extentB, e);
		radiance = mix(b, boxReflected(t, world, r, rough, probeA, extentA, e), extentA.w);
	}
	return {irradiance: irradiance, radiance: radiance, occlusion: env.occlusion};
}

// a reflection probe's light along r from a point, parallax-corrected by its box
function boxReflected(t: Texture2D, world: Vec3, r: Vec3, rough: number, probe: Vec4, extent: Vec4, e: Vec4): Vec3 {
	const rr = r.add(vec3(0.000001));
	const a = probe.xyz.sub(extent.xyz).sub(world).div(rr);
	const b = probe.xyz.add(extent.xyz).sub(world).div(rr);
	const far = max(a, b);
	const dist = min(min(far.x, far.y), far.z);
	return probeAtlas(t, world.add(r.mul(max(dist, 0))).sub(probe.xyz), rough, probe.w - 1, e);
}

// a probe's light along a direction at a roughness: its column of the probes' atlas, two rows by it, blended
function probeAtlas(t: Texture2D, d: Vec3, rough: number, column: number, e: Vec4): Vec3 {
	const rows = e.y;
	const at = rough * (rows - 1);
	const r0 = floor(at);
	const uv = equirect(d);
	const u = (column + clamp(uv.x, e.z, 1 - e.z)) / e.x;
	const v = clamp(uv.y, e.w, 1 - e.w);
	const lo = sampleLevel(t, vec2(u, (r0 + v) / (rows + 1)), 0).xyz;
	const hi = sampleLevel(t, vec2(u, (min(r0 + 1, rows - 1) + v) / (rows + 1)), 0).xyz;
	return pow(mix(lo, hi, at - r0), vec3(2.2));
}

// (Equirect.hx's shIrradiance)
function shIrradiance(sh0: Vec4, sh1: Vec4, sh2: Vec4, sh3: Vec4, sh4: Vec4, sh5: Vec4, sh6: Vec4, n: Vec3): Vec3 {
	const n4 = vec4(n, 1);
	const b = vec4(n.x * n.y, n.y * n.z, n.z * n.z, n.z * n.x);
	const c = n.x * n.x - n.y * n.y;
	const e = vec3(dot(sh0, n4), dot(sh1, n4), dot(sh2, n4)).add(vec3(dot(sh3, b), dot(sh4, b), dot(sh5, b))).add(sh6.xyz.mul(c));
	return max(e, vec3(0));
}


// a clear coat's specular lobe
function coatLobe(n: Vec3, v: Vec3, l: Vec3, a2: number): Vec3 {
	const h = normalize(l.add(v));
	const nl = max(dot(n, l), 0);
	const nv = max(dot(n, v), 0.0001);
	const nh = max(dot(n, h), 0);
	const fresnel = 0.04 + 0.96 * pow(1 - max(dot(v, h), 0), 5);
	const dd = nh * nh * (a2 - 1) + 1;
	const visibility = 0.5 / max(nl * sqrt(nv * nv * (1 - a2) + a2) + nv * sqrt(nl * nl * (1 - a2) + a2), 0.0001);
	return vec3(fresnel * a2 / (3.14159265 * dd * dd) * visibility * nl);
}

// Lambert's diffuse and Cook-Torrance's specular, times n.l
function brdf(n: Vec3, v: Vec3, l: Vec3, base: Vec3, metallic: number, a2: number, f0: Vec3): Vec3 {
	const h = normalize(l.add(v));
	const nl = max(dot(n, l), 0);
	const nv = max(dot(n, v), 0.0001);
	const nh = max(dot(n, h), 0);
	const vh = max(dot(v, h), 0);
	const fresnel = f0.add(vec3(1).sub(f0).mul(pow(1 - vh, 5)));
	const dd = nh * nh * (a2 - 1) + 1;
	const distribution = a2 / (3.14159265 * dd * dd);
	const visibility = 0.5 / max(nl * sqrt(nv * nv * (1 - a2) + a2) + nv * sqrt(nl * nl * (1 - a2) + a2), 0.0001);
	const diffuse = vec3(1).sub(fresnel).mul(1 - metallic).mul(base).div(3.14159265);
	return diffuse.add(fresnel.mul(distribution * visibility)).mul(nl);
}

// the sun's share at a point (1: lit) from its cascades' tiles of the atlas (n: the surface's unit normal)
function shadowed(frame: PbrFrame, map: Texture2D, world: Vec3, n: Vec3): number {
	const strength = frame.shadow.x;
	let result = 1.0;
	if (strength > 0) {
		const nl = max(dot(n, frame.lightDir.xyz), 0);
		let lit = cascade(map, frame.lightViewProj, frame.shadow, frame.shadowRect, frame.shadowAtlas, frame.shadowSoft, frame.shadowSoft.y, world, n, nl);
		if (lit < 0)
			lit = cascade(map, frame.lightViewProjFar, frame.shadowFar, frame.shadowRectFar, frame.shadowAtlas, frame.shadowSoft, frame.shadowSoft.z, world, n, nl);
		if (lit >= 0) result = 1 - strength * (1 - lit);
	}
	return result;
}

// a cascade's lit share (0 to 1) at a point, or -1 where its tile does not reach
function cascade(map: Texture2D, viewProj: Mat4, params: Vec4, rect: Vec4, inv: Vec4, soft: Vec4, deep: number, world: Vec3, n: Vec3, nl: number): number {
	let result = -1.0;
	const ls = viewProj.mul(vec4(world, 1));
	const p = ls.xyz.div(ls.w);
	const uv = vec2(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5);
	if (uv.x > 0 && uv.x < 1 && uv.y > 0 && uv.y < 1 && p.z < 1) {
		const depth = p.z - params.y * (1 + 2 * (1 - nl));
		const t = params.z;
		if (soft.x > 0 && params.w > 0) result = softly(map, uv, rect, inv, depth, params.w, t, soft, deep, plane(viewProj, n, deep));
		else
			result = (tap(map, uv, rect, inv, depth, -t, -t) + tap(map, uv, rect, inv, depth, 0, -t) + tap(map, uv, rect, inv, depth, t, -t)
				+ tap(map, uv, rect, inv, depth, -t, 0) + tap(map, uv, rect, inv, depth, 0, 0) + tap(map, uv, rect, inv, depth, t, 0)
				+ tap(map, uv, rect, inv, depth, -t, t) + tap(map, uv, rect, inv, depth, 0, t) + tap(map, uv, rect, inv, depth, t, t)) / 9;
	}
	return result;
}

// 1 where the tile's depth at uv + (dx, dy) is not nearer than depth
function tap(map: Texture2D, uv: Vec2, rect: Vec4, inv: Vec4, depth: number, dx: number, dy: number): number {
	return step(depth, sampleLevel(map, atlasUv(uv.add(vec2(dx, dy)), rect, inv), 0).x);
}

// how the depth of the surface's plane changes across the map, a uv (PbrShader.hx's plane)
function plane(viewProj: Mat4, n: Vec3, deep: number): Vec2 {
	const t1 = normalize(cross(n, abs(n.y) < 0.9 ? vec3(0, 1, 0) : vec3(1, 0, 0)));
	const t2 = cross(n, t1);
	const a = viewProj.mul(vec4(t1, 0)).xyz;
	const b = viewProj.mul(vec4(t2, 0)).xyz;
	const au = vec2(a.x * 0.5, -a.y * 0.5);
	const bu = vec2(b.x * 0.5, -b.y * 0.5);
	const det = au.x * bu.y - au.y * bu.x;
	let g = vec2(0);
	if (abs(det) > 0.000001) g = vec2(a.z * bu.y - b.z * au.y, au.x * b.z - bu.x * a.z).div(det);
	const most = deep * 4;
	const len = length(g);
	if (len > most) g = g.mul(most / len);
	return g;
}

// the soft filter's lit share (Shadows.soft; PbrShader.hx's softly)
function softly(map: Texture2D, uv: Vec2, rect: Vec4, inv: Vec4, depth: number, widest: number, texel: number, soft: Vec4, deep: number, g: Vec2): number {
	const n = soft.x;
	const margin = depth;
	const cell = fract(floor(uv.div(texel)).div(64)).mul(64);
	const h = fract(52.9829189 * fract(dot(cell, vec2(0.06711056, 0.00583715))));
	const t = 2 * fract(2 * h) - 1;
	const start = vec2(1 - t * t, 2 * t).mul((h < 0.5 ? 1 : -1) / (1 + t * t));
	const c = -0.7373688;
	const s = 0.6754903;
	let radius = widest;
	let lit = -1.0;
	if (soft.w > 0) {
		const m = max(floor(n * 0.5), 4);
		let dir = start;
		let sum = 0.0;
		let found = 0.0;
		let k = 0.0;
		while (k < m) {
			const off = dir.mul(sqrt((k + 0.5) / m) * widest);
			const d = sampleLevel(map, atlasUv(uv.add(off), rect, inv), 0).x;
			const at = dot(g, off);
			if (d < margin + at) {
				sum += margin + at - d;
				found += 1;
			}
			dir = vec2(dir.x * c - dir.y * s, dir.x * s + dir.y * c);
			k += 1;
		}
		if (found > 0) radius = clamp(sum / found * soft.w / max(deep, 0.0001), texel * 1.5, widest);
		else lit = 1;
	}
	if (lit < 0) {
		let dir = start;
		let sum = 0.0;
		let k = 0.0;
		while (k < n) {
			const off = dir.mul(sqrt((k + 0.5) / n) * radius);
			sum += step(margin + dot(g, off), sampleLevel(map, atlasUv(uv.add(off), rect, inv), 0).x);
			dir = vec2(dir.x * c - dir.y * s, dir.x * s + dir.y * c);
			k += 1;
		}
		lit = sum / n;
	}
	return lit;
}

// how much of the fog lies between the eye and a point (PbrShader.hx's fogAmount)
export function fogAmount(fog: Vec4, shape: Vec4, eye: Vec3, at: Vec3): number {
	const d = at.sub(eye);
	const dist = max(length(d), 0.0001);
	const through = max(dist - shape.x, 0);
	const y = eye.y + d.y * min(shape.x / dist, 1);
	const k = clamp(shape.y * d.y / dist * through, -30, 30);
	const mean = abs(k) > 0.0001 ? (1 - exp(-k)) / k : 1 - 0.5 * k;
	const depth = fog.w * exp(clamp(shape.y * (shape.z - y), -30, 30)) * through * mean;
	return min(1 - exp(-depth), shape.w);
}

// a colour in linear light as the target takes it
export function output(c: Vec3, hdr: number): Vec3 {
	let result = c;
	if (hdr < 0.5) result = encode(aces(c));
	return result;
}

// a material's colour as the target takes it, or, not tone mapped (Material.toneMapped false), only encoded
export function display(c: Vec3, frame: PbrFrame, material: PbrMaterial): Vec3 {
	let result = output(c, frame.exposure.y);
	if (material.model.y < 0.5 && frame.exposure.y < 0.5) result = encode(c);
	return result;
}

// ACES filmic tone mapping (Narkowicz's fit), to 0..1
function aces(x: Vec3): Vec3 {
	return clamp(x.mul(x.mul(2.51).add(0.03)).div(x.mul(x.mul(2.43).add(0.59)).add(0.14)), 0, 1);
}

// linear to sRGB
export function encode(c: Vec3): Vec3 {
	return pow(c, vec3(1 / 2.2));
}

// a unit vector in two components 0..1 (octahedral)
function octEncode(n: Vec3): Vec2 {
	const a = n.div(abs(n.x) + abs(n.y) + abs(n.z));
	let e = a.xy;
	if (a.z < 0) e = vec2((1 - abs(a.y)) * (a.x >= 0 ? 1 : -1), (1 - abs(a.x)) * (a.y >= 0 ? 1 : -1));
	return e.mul(0.5).add(0.5);
}

// roughness and metalness in one channel (4 bits each: the view buffers' z,
// screen-space reflections' Fresnel and gloss)
function packRoughMetal(r: number, m: number): number {
	return (floor(clamp(r, 0, 1) * 15 + 0.5) * 16 + floor(clamp(m, 0, 1) * 15 + 0.5)) / 255;
}

// joint k's matrix from its row of the texture
export function joint(t: Texture2D, k: number, rows: number): Mat4 {
	const y = (k + 0.5) / rows;
	return mat4(vec4(texel(t, 0, y), texel(t, 1, y), texel(t, 2, y), texel(t, 3, y)), vec4(texel(t, 4, y), texel(t, 5, y), texel(t, 6, y), texel(t, 7, y)),
		vec4(texel(t, 8, y), texel(t, 9, y), texel(t, 10, y), texel(t, 11, y)),
		vec4(texel(t, 12, y), texel(t, 13, y), texel(t, 14, y), texel(t, 15, y)));
}

function texel(t: Texture2D, x: number, y: number): number {
	return sampleLevel(t, vec2((x + 0.5) / 16, y), 0).x;
}

// an instance's uvs moved to its cell of an atlas (Sprites): the matrix's
// last w is 1 plus the cell, its column plus 256 times its row (PbrShader.hx's instanceUv)
export function instanceUv(uv: Vec2, w: number): Vec2 {
	const cell = w - 1;
	const row = floor(cell / 256);
	return uv.add(vec2(cell - row * 256, row));
}

// a normal turned to the world by an instance's matrix (its columns): by
// its cofactors, the inverse transpose times the determinant, with the
// determinant's sign (PbrShader.hx's instanceNormal)
export function instanceNormal(c0: Vec3, c1: Vec3, c2: Vec3, n: Vec3): Vec3 {
	const x = cross(c1, c2);
	const turned = x.mul(n.x).add(cross(c2, c0).mul(n.y)).add(cross(c0, c1).mul(n.z));
	return dot(c0, x) < 0 ? turned.neg() : turned;
}

// --- the glTF extensions' layers (PbrShader.hx's: PbrOptions' sheen,
// specular, clearcoat, transmission, iridescence and anisotropy; uvSets) ---

// a map's uvs (uvSets): TEXCOORD_0 or _1 (u.w), moved by its transform's rows
export function uvSetOf(u: Vec4, v: Vec4, uv0: Vec2, uv1: Vec2): Vec2 {
	const t = u.w > 0.5 ? uv1 : uv0;
	return vec2(dot(u.xy, t) + u.z, dot(v.xy, t) + v.z);
}

// a map of a layer (1 or 2 its image, layerMap0 or 1; 0 none: fallback)
export function layerMap(slot: number, uv: Vec2, fallback: Vec4, t0: Texture2D, t1: Texture2D): Vec4 {
	let c = fallback;
	if (slot > 0.5) c = slot < 1.5 ? sample(t0, uv) : sample(t1, uv);
	return c;
}

// a dielectric's reflectance at normal incidence from its index of refraction
export function iorF0(ior: number): number {
	const r = (ior - 1) / (ior + 1);
	return r * r;
}

// the metalness, roughness and emissive slots of a variant whose maps have their own uvs (uvSets)
export function physicalMetalness(s: PbrSurface, p: {material: PbrMaterial, metallicRoughnessTexture: Texture2D}): number {
	return clamp(p.material.params.x * sample(p.metallicRoughnessTexture, s.uvMetallicRoughness!).z, 0, 1);
}

export function physicalRoughness(s: PbrSurface, p: {material: PbrMaterial, metallicRoughnessTexture: Texture2D}): number {
	return clamp(mix(p.material.params.y * sample(p.metallicRoughnessTexture, s.uvMetallicRoughness!).y, 0.07, p.material.ground.z), 0.04, 1);
}

export function physicalEmissive(s: PbrSurface, p: {material: PbrMaterial, emissiveTexture: Texture2D}): Vec3 {
	return p.material.emissive.xyz.mul(pow(sample(p.emissiveTexture, s.uvEmissive!).xyz, vec3(2.2)));
}

// the physical direct slot: one light's diffuse and specular with the layers
export function physicalDirect(s: LitSurface, l: LightSample, p: {material: PbrMaterial}): Vec3 {
	const n = s.normal;
	const v = s.view;
	const d = l.direction;
	const h = normalize(d.add(v));
	const nl = max(dot(n, d), 0);
	const nv = max(dot(n, v), 0.0001);
	const nh = max(dot(n, h), 0);
	const vh = max(dot(v, h), 0);
	let f0 = reflectance(s, p.material);
	let f90 = 1.0;
	if (s.specular! > 0) {
		f0 = s.specularColor!;
		f90 = s.specularWeight!;
	}
	let fresnel = f0.add(vec3(f90).sub(f0).mul(pow(1 - vh, 5)));
	if (s.iridescence! > 0) fresnel = mix(fresnel, s.iridescenceFresnel!, s.iridescence!);
	const a = s.roughness * s.roughness;
	const a2 = a * a;
	const dd = nh * nh * (a2 - 1) + 1;
	let lobe = a2 / (3.14159265 * dd * dd) * (0.5 / max(nl * sqrt(nv * nv * (1 - a2) + a2) + nv * sqrt(nl * nl * (1 - a2) + a2), 0.0001));
	if (s.anisotropy! > 0) lobe = anisotropic(s, d, h, a, nl, nv, nh);
	let diffuse = vec3(1).sub(fresnel).mul(s.albedo).mul((1 - s.metalness) / 3.14159265);
	if (s.transmission! > 0) diffuse = diffuse.mul(1 - s.transmission!);
	let c = diffuse.add(fresnel.mul(lobe)).mul(nl);
	if (s.sheen! > 0) c = c.mul(1 - 0.157 * s.sheen!).add(s.sheenColor!.mul(charlie(s.sheenRoughness!, nh) * neubelt(nv, nl) * nl));
	if (s.coat! > 0) {
		const cn = s.coatNormal!;
		const cr = s.coatRoughness! * s.coatRoughness!;
		const fc = (0.04 + 0.96 * pow(1 - max(dot(cn, v), 0), 5)) * s.coat!;
		c = c.mul(1 - fc).add(coatLobe(cn, v, d, cr * cr).mul(s.coat!));
	}
	return c.mul(l.radiance);
}

// the physical indirect slot: the ambient and the reflections with the layers
export function physicalIndirect(s: LitSurface, env: IndirectLight,
		p: {material: PbrMaterial, frame: PbrFrame, environmentMap: Texture2D, transmissionMap: Texture2D}): Vec3 {
	const n = s.normal;
	const v = s.view;
	const nv = max(dot(n, v), 0.0001);
	const c0 = vec4(-1, -0.0275, -0.572, 0.022);
	const c1 = vec4(1, 0.0425, 1.04, -0.04);
	const rr = c0.mul(s.roughness).add(c1);
	const a004 = min(rr.x * rr.x, pow(2, -9.28 * nv)) * rr.x + rr.y;
	const ab = vec2(-1.04, 1.04).mul(a004).add(rr.zw);
	let f0 = reflectance(s, p.material);
	let f90 = 1.0;
	if (s.specular! > 0) {
		f0 = s.specularColor!;
		f90 = s.specularWeight!;
	}
	let specular = f0.mul(ab.x).add(vec3(f90 * ab.y));
	if (s.iridescence! > 0) {
		const k = pow(1 - nv, 5);
		const fi = clamp(s.iridescenceFresnel!.sub(vec3(k)).div(max(1 - k, 0.0001)), 0, 1);
		specular = mix(specular, fi.mul(ab.x).add(vec3(f90 * ab.y)), s.iridescence!);
	}
	let radiance = env.radiance;
	if (s.anisotropy! > 0) {
		let bent = normalize(cross(cross(s.anisotropyBitangent!, v), s.anisotropyBitangent!));
		let w = 1 - s.anisotropy! * (1 - s.roughness);
		w = w * w;
		bent = normalize(mix(bent, n, w * w));
		radiance = reflected(p.frame, p.environmentMap, reflect(v.neg(), bent), s.roughness);
	}
	let diffuse = env.irradiance.mul(s.albedo).mul(1 - s.metalness);
	if (s.transmission! > 0)
		diffuse = mix(diffuse, transmitted(s, p.material, p.frame, p.environmentMap, p.transmissionMap).mul(vec3(1).sub(specular)), s.transmission! * (1 - s.metalness));
	let c = diffuse.add(radiance.mul(specular)).mul(env.occlusion);
	if (s.sheen! > 0) c = c.mul(1 - 0.157 * s.sheen!).add(env.irradiance.mul(s.sheenColor!).mul(sheenAlbedo(nv, s.sheenRoughness!) * env.occlusion));
	if (s.coat! > 0) {
		const cn = s.coatNormal!;
		const fc = (0.04 + 0.96 * pow(1 - max(dot(cn, v), 0), 5)) * s.coat!;
		c = c.mul(1 - fc).add(reflected(p.frame, p.environmentMap, reflect(v.neg(), cn), s.coatRoughness!).mul(fc * env.occlusion));
	}
	return c;
}

// the light through a transmitting surface, refracted through its volume
function transmitted(s: LitSurface, layers: PbrMaterial, frame: PbrFrame, environmentMap: Texture2D, transmissionMap: Texture2D): Vec3 {
	const ior = layers.coat.w;
	const i = s.view.neg();
	const eta = 1 / ior;
	const ni = dot(s.normal, i);
	const k = max(1 - eta * eta * (1 - ni * ni), 0);
	const r = normalize(i.mul(eta).sub(s.normal.mul(eta * ni + sqrt(k))));
	const exit = s.world.add(r.mul(s.thickness!));
	const rough = s.roughness * clamp(ior * 2 - 2, 0, 1);
	let light = vec3(0);
	if (layers.transmission.w > 0) {
		const c = frame.viewProj.mul(vec4(exit, 1));
		const uv = vec2(c.x / c.w * 0.5 + 0.5, 0.5 - c.y / c.w * 0.5);
		light = sampleLevel(transmissionMap, uv, rough * layers.transmission.w).xyz;
		if (frame.exposure.y < 0.5) light = pow(light, vec3(2.2));
		light = light.div(max(frame.exposure.x, 0.0001));
	} else
		light = reflected(frame, environmentMap, s.thickness! > 0 ? r : i, rough);
	let absorbed = vec3(1);
	if (layers.transmission.z > 0) absorbed = pow(max(layers.attenuation.xyz, vec3(0.0001)), vec3((s.thickness!) / layers.transmission.z));
	return light.mul(absorbed).mul(s.albedo);
}

// Charlie's sheen distribution at a roughness
function charlie(roughness: number, nh: number): number {
	const a = max(roughness * roughness, 0.0049);
	const inv = 1 / a;
	const sin2 = max(1 - nh * nh, 0.0001);
	return (2 + inv) * pow(sin2, inv * 0.5) / 6.2831853;
}

// Neubelt's visibility for the sheen
function neubelt(nv: number, nl: number): number {
	return clamp(1 / (4 * (nl + nv - nl * nv)), 0, 1);
}

// a sheen's directional albedo under an even light
function sheenAlbedo(nv: number, roughness: number): number {
	const r2 = roughness * roughness;
	const a = roughness < 0.25 ? -339.2 * r2 + 161.4 * roughness - 25.9 : -8.48 * r2 + 14.3 * roughness - 9.95;
	const b = roughness < 0.25 ? 44 * r2 - 23.7 * roughness + 3.26 : 1.97 * r2 - 3.27 * roughness + 0.72;
	const dg = exp(a * nv + b) + (roughness < 0.25 ? 0 : 0.1 * (roughness - 0.25));
	return clamp(dg / 3.14159265, 0, 1);
}

// the anisotropic GGX lobe, its distribution times visibility
function anisotropic(s: LitSurface, d: Vec3, h: Vec3, a: number, nl: number, nv: number, nh: number): number {
	const t = s.anisotropyDirection!;
	const b = s.anisotropyBitangent!;
	const at = mix(a, 1, s.anisotropy! * s.anisotropy!);
	const ab = max(a, 0.0001);
	const th = dot(t, h);
	const bh = dot(b, h);
	const a2 = at * ab;
	const f = vec3(ab * th, at * bh, a2 * nh);
	const w2 = a2 / max(dot(f, f), 0.0001);
	const dist = a2 * w2 * w2 / 3.14159265;
	const vv = nl * length(vec3(at * dot(t, s.view), ab * dot(b, s.view), nv));
	const vl = nv * length(vec3(at * dot(t, d), ab * dot(b, d), nl));
	return dist * clamp(0.5 / max(vv + vl, 0.0001), 0, 1);
}

// a thin film's reflectance (Belcour and Barla's, the sample viewer's)
export function iridescent(filmIor: number, c1: number, thickness: number, f0: Vec3): Vec3 {
	const film = mix(1, filmIor, smoothstep(0, 0.03, thickness));
	const sin2 = (1 / (film * film)) * (1 - c1 * c1);
	const cos2sq = 1 - sin2;
	let result = vec3(1);
	if (cos2sq >= 0) {
		const c2 = sqrt(cos2sq);
		const r0 = iorF0(film);
		const r12 = r0 + (1 - r0) * pow(1 - c1, 5);
		const t121 = 1 - r12;
		const phi12 = film < 1 ? 3.14159265 : 0;
		const phi21 = 3.14159265 - phi12;
		const root = sqrt(clamp(f0, vec3(0), vec3(0.9999)));
		const baseIor = vec3(1).add(root).div(vec3(1).sub(root));
		const q = baseIor.sub(vec3(film)).div(baseIor.add(vec3(film)));
		const r1 = q.mul(q);
		const r23 = r1.add(vec3(1).sub(r1).mul(pow(1 - c2, 5)));
		const phi23 = vec3(baseIor.x < film ? 3.14159265 : 0, baseIor.y < film ? 3.14159265 : 0, baseIor.z < film ? 3.14159265 : 0);
		const opd = 2 * film * thickness * c2;
		const phi = vec3(phi21).add(phi23);
		const r123 = clamp(r23.mul(r12), vec3(0.0001), vec3(0.9999));
		const amp = sqrt(r123);
		const rs = r23.mul(t121 * t121).div(vec3(1).sub(r123));
		let cm = rs.sub(vec3(t121)).mul(amp);
		let sum = vec3(r12).add(rs).add(cm.mul(sensitivity(opd, phi).mul(2)));
		cm = cm.mul(amp);
		sum = sum.add(cm.mul(sensitivity(opd * 2, phi.mul(2)).mul(2)));
		result = max(sum, vec3(0));
	}
	return result;
}

// the film's interference at an optical path (nm) and phase shift, in linear sRGB
function sensitivity(opd: number, shift: Vec3): Vec3 {
	const phase = 6.2831853 * opd * 0.001;
	const xyz = vec3(0.84659, 1.0002219, 1.0011225).mul(cos(vec3(1.681, 1.7953, 2.2084).mul(phase).add(shift))).mul(exp(vec3(-0.0043278, -0.0093046, -0.0066121).mul(phase * phase)));
	const x = xyz.x + 0.1538683 * cos(2.2399 * phase + shift.x) * exp(-0.0045282 * phase * phase);
	return vec3(3.2404542 * x - 1.5371385 * xyz.y - 0.4985314 * xyz.z, -0.969266 * x + 1.8760108 * xyz.y + 0.041556 * xyz.z,
		0.0556434 * x - 0.2040259 * xyz.y + 1.0572252 * xyz.z);
}

export const pbr = slots({
	options: {
		normalMap: false, skinned: false, instanced: false, prepass: false, sheen: false, specular: false, clearcoat: false, transmission: false,
		iridescence: false, anisotropy: false, uvSets: false, sunOnly: false, untiled: false, probes: false, area: false, lightmap: false,
	},
	vertex: (v: PbrVertex, p: PbrVertexParams, m: Pbr): PbrVaryings => {
		let pos = m.position({pos: v.pos, normal: v.normal, uv: v.uv}, p);
		let nr = v.normal;
		if (m.options.skinned) {
			const j0 = joint(p.jointMatrices!, v.joints!.x, p.object!.tint.w), j1 = joint(p.jointMatrices!, v.joints!.y, p.object!.tint.w);
			const j2 = joint(p.jointMatrices!, v.joints!.z, p.object!.tint.w), j3 = joint(p.jointMatrices!, v.joints!.w, p.object!.tint.w);
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
			uv1: m.options.uvSets ? v.uv1! : vec2(0),
			tangent: m.options.normalMap ? vec4(model.mul(vec4(v.tangent!.xyz, 0)).xyz, v.tangent!.w) : vec4(0),
			up: m.options.instanced ? v.m1!.xyz : model.mul(vec4(0, 1, 0, 0)).xyz,
			tint: m.options.instanced ? vec3(1 + v.m0!.w, 1 + v.m1!.w, 1 + v.m2!.w) : p.object!.tint.xyz,
			// (the prepass lights nothing: its instanced variants bind no PbrObject)
			lights0: m.options.prepass ? vec4(-1) : p.object!.lights0,
			lights1: m.options.prepass ? vec4(-1) : p.object!.lights1,
			ambient: m.options.probes ? vec4(shIrradiance(p.probes!.sh[0], p.probes!.sh[1], p.probes!.sh[2], p.probes!.sh[3], p.probes!.sh[4], p.probes!.sh[5],
				p.probes!.sh[6], normalize(m.options.instanced ? instanceNormal(v.m0!.xyz, v.m1!.xyz, v.m2!.xyz, nr) : p.object!.normalMatrix.mul(vec4(nr, 0)).xyz)),
				p.probes!.extentB.w) : vec4(0),
			probeA: m.options.probes ? p.probes!.probeA : vec4(0),
			extentA: m.options.probes ? p.probes!.extentA : vec4(0),
			probeB: m.options.probes ? p.probes!.probeB : vec4(0),
			extentB: m.options.probes ? p.probes!.extentB : vec4(0),
			probeAtlas: m.options.probes ? p.probes!.atlas : vec4(0),
			lightmapUv: m.options.lightmap ? vec4(v.uv1!.mul(p.lightmap!.rect.zw).add(p.lightmap!.rect.xy), p.lightmap!.params.x, p.lightmap!.params.y) : vec4(0),
		};
	},
	fragment: (i: PbrVaryings, p: PbrFragmentParams, m: Pbr): Vec4 => {
		const ng = normalize(i.normal);
		let uv = uvOf(p.material, i.uv);
		// (uvSets: each core map at its own uvs)
		let uvNormal = uv;
		let uvOcclusion = uv;
		let uvMr = uv;
		let uvEm = uv;
		if (m.options.uvSets) {
			uv = uvSetOf(p.material.uvU, p.material.uvV, i.uv, i.uv1!);
			uvNormal = uvSetOf(p.material.uvNormalU, p.material.uvNormalV, i.uv, i.uv1!);
			uvOcclusion = uvSetOf(p.material.uvOcclusionU, p.material.uvOcclusionV, i.uv, i.uv1!);
			uvMr = uvSetOf(p.material.uvMetallicRoughnessU, p.material.uvMetallicRoughnessV, i.uv, i.uv1!);
			uvEm = uvSetOf(p.material.uvEmissiveU, p.material.uvEmissiveV, i.uv, i.uv1!);
		}
		let n = ng;
		let t = vec3(0);
		let b = vec3(0);
		if (m.options.normalMap) {
			t = normalize(i.tangent!.xyz.sub(ng.mul(dot(ng, i.tangent!.xyz))));
			b = cross(ng, t).mul(i.tangent!.w);
			const mapped = sample(p.normalTexture!, m.options.uvSets ? uvNormal : uv).xyz.mul(2).sub(1);
			const scale = p.material.params.z;
			n = normalize(t.mul(mapped.x * scale).add(b.mul(mapped.y * scale)).add(ng.mul(mapped.z)));
		}
		const texel = sample(p.baseColorTexture, uv);
		const s: PbrSurface = {
			world: i.world,
			normal: n,
			uv: uv,
			up: normalize(i.up),
			baseColor: vec4(p.material.baseColor.xyz.mul(pow(texel.xyz, vec3(2.2))), p.material.baseColor.w * texel.w),
			uvMetallicRoughness: m.options.uvSets ? uvMr : vec2(0),
			uvEmissive: m.options.uvSets ? uvEm : vec2(0),
		};
		let out = vec4(0);
		if (m.options.prepass) {
			const a = m.alpha(s, p);
			if (p.material.layers.w > 0 && a < p.material.layers.w) discard();
			let f = m.normal(s, p);
			if (p.material.params.w > 0.5 && dot(f, p.frame.eye.xyz.sub(s.world)) < 0) f = f.neg();
			const vn = normalize(p.prepass!.view.mul(vec4(f, 0)).xyz);
			out = vec4(octEncode(vn), packRoughMetal(m.roughness(s, p), m.metalness(s, p)), p.prepass!.id.x / 255);
		} else {
			let lit = litSurface(m.normal(s, p), s.world, m.options.uvSets ? uvOcclusion : uv, s.up, m.color(s, p).mul(i.tint), m.alpha(s, p), m.metalness(s, p),
				m.roughness(s, p), p.frame, p.material);
			if (m.options.sheen || m.options.specular || m.options.clearcoat || m.options.transmission || m.options.iridescence || m.options.anisotropy) {
				// (the glTF extensions' layers of the surface, the variant's options')
				const x = p.material;
				if (!m.options.normalMap) {
					t = normalize(cross(ng, abs(ng.y) < 0.9 ? vec3(0, 1, 0) : vec3(1, 0, 0)));
					b = cross(ng, t);
				}
				let sheenColor = vec3(0);
				let sheenRoughness = 0.0;
				if (m.options.sheen) {
					sheenColor = x.sheen.xyz.mul(pow(layerMap(x.maps0.x, uv, vec4(1), p.layerMap0!, p.layerMap1!).xyz, vec3(2.2)));
					sheenRoughness = clamp(x.sheen.w * layerMap(x.maps0.y, uv, vec4(1), p.layerMap0!, p.layerMap1!).w, 0, 1);
				}
				let f0 = vec3(0);
				let f90 = 1.0;
				if (m.options.specular) {
					const weight = x.specular.w * layerMap(x.maps0.z, uv, vec4(1), p.layerMap0!, p.layerMap1!).w;
					const tint = x.specular.xyz.mul(pow(layerMap(x.maps0.w, uv, vec4(1), p.layerMap0!, p.layerMap1!).xyz, vec3(2.2)));
					f0 = mix(min(vec3(iorF0(x.coat.w)).mul(tint), vec3(1)).mul(weight), lit.albedo, lit.metalness);
					f90 = mix(weight, 1, lit.metalness);
				}
				let coat = 0.0;
				let coatRoughness = 0.0;
				let coatNormal = ng;
				if (m.options.clearcoat) {
					coat = x.coat.x * layerMap(x.maps1.x, uv, vec4(1), p.layerMap0!, p.layerMap1!).x;
					coatRoughness = clamp(x.coat.y * layerMap(x.maps1.y, uv, vec4(1), p.layerMap0!, p.layerMap1!).y, 0.04, 1);
					if (x.maps1.z > 0.5) {
						const cm = layerMap(x.maps1.z, uv, vec4(0.5, 0.5, 1, 1), p.layerMap0!, p.layerMap1!).xyz.mul(2).sub(1);
						coatNormal = normalize(t.mul(cm.x * x.coat.z).add(b.mul(cm.y * x.coat.z)).add(ng.mul(cm.z)));
					}
					if (p.material.params.w > 0.5 && dot(coatNormal, lit.view) < 0) coatNormal = coatNormal.neg();
				}
				let transmission = 0.0;
				let thickness = 0.0;
				if (m.options.transmission) {
					transmission = x.transmission.x * layerMap(x.maps1.w, uv, vec4(1), p.layerMap0!, p.layerMap1!).x;
					thickness = x.transmission.y * layerMap(x.maps2.x, uv, vec4(1), p.layerMap0!, p.layerMap1!).y * length(i.up);
				}
				let iridescence = 0.0;
				let iridescenceFresnel = vec3(0);
				if (m.options.iridescence) {
					iridescence = x.iridescence.x * layerMap(x.maps2.y, uv, vec4(1), p.layerMap0!, p.layerMap1!).x;
					const film = mix(x.iridescence.z, x.iridescence.w, layerMap(x.maps2.z, uv, vec4(1), p.layerMap0!, p.layerMap1!).y);
					if (film <= 0) iridescence = 0;
					const base = m.options.specular ? f0 : reflectance(lit, p.material);
					iridescenceFresnel = iridescent(x.iridescence.y, max(dot(lit.normal, lit.view), 0.0001), film, base);
				}
				let anisotropy = 0.0;
				let direction = vec3(0);
				let across = vec3(0);
				if (m.options.anisotropy) {
					const am = layerMap(x.maps2.w, uv, vec4(1, 0.5, 1, 1), p.layerMap0!, p.layerMap1!);
					const dir = am.xy.mul(2).sub(1);
					const turned = vec2(x.anisotropy.y * dir.x - x.anisotropy.z * dir.y, x.anisotropy.z * dir.x + x.anisotropy.y * dir.y);
					anisotropy = x.anisotropy.x * am.z;
					const ta = t.mul(turned.x).add(b.mul(turned.y));
					direction = normalize(ta.sub(lit.normal.mul(dot(lit.normal, ta))));
					across = cross(lit.normal, direction);
				}
				const layered: LitSurface = {
					world: lit.world,
					normal: lit.normal,
					view: lit.view,
					uv: lit.uv,
					up: lit.up,
					albedo: lit.albedo,
					alpha: lit.alpha,
					metalness: lit.metalness,
					roughness: lit.roughness,
					sheen: m.options.sheen ? max(max(sheenColor.x, sheenColor.y), sheenColor.z) : lit.sheen,
					sheenColor: m.options.sheen ? sheenColor : lit.sheenColor,
					sheenRoughness: m.options.sheen ? sheenRoughness : lit.sheenRoughness,
					specular: m.options.specular ? 1.0 : lit.specular,
					specularColor: m.options.specular ? f0 : lit.specularColor,
					specularWeight: m.options.specular ? f90 : lit.specularWeight,
					coat: m.options.clearcoat ? coat : lit.coat,
					coatRoughness: m.options.clearcoat ? coatRoughness : lit.coatRoughness,
					coatNormal: m.options.clearcoat ? coatNormal : lit.coatNormal,
					transmission: m.options.transmission ? transmission : lit.transmission,
					thickness: m.options.transmission ? thickness : lit.thickness,
					iridescence: m.options.iridescence ? iridescence : lit.iridescence,
					iridescenceFresnel: m.options.iridescence ? iridescenceFresnel : lit.iridescenceFresnel,
					anisotropy: m.options.anisotropy ? anisotropy : lit.anisotropy,
					anisotropyDirection: m.options.anisotropy ? direction : lit.anisotropyDirection,
					anisotropyBitangent: m.options.anisotropy ? across : lit.anisotropyBitangent,
				};
				lit = layered;
			}
			// (the sun, then each local light the draw's list or the pixel's cell names: the direct slot's, summed)
			let direct = m.direct(lit, sunLight(lit, p.frame, p.material, p.shadowMap), p);
			if (!m.options.sunOnly) {
				const cell = clusterCell(p.frame.viewProj, p.frame.eye, p.frame.clusters, p.frame.clusterDepth, p.frame.clusterAxis, p.clusterMap, s.world);
				// (a list ends at its first -1: a draw lit by none loops not at all)
				let k = 0.0;
				let index = lightIndex(p.frame.clusters, p.frame.clusterDepth, i.lights0, i.lights1, p.clusterMap, cell, k);
				while (k < cell.z && index >= 0) {
					// (the light's row, its shadow: read here, the arrays not passed on)
					let pos = vec4(0);
					let color = vec4(0);
					let cone = vec4(0);
					if (p.frame.clusters.x > 0) {
						pos = lightRow(p.clusterMap, 0, index, p.frame.clusterAxis, p.frame.clusterDepth);
						color = lightRow(p.clusterMap, 4, index, p.frame.clusterAxis, p.frame.clusterDepth);
						cone = lightRow(p.clusterMap, 8, index, p.frame.clusterAxis, p.frame.clusterDepth);
					} else {
						pos = lightTexel(p.lights, 0, index);
						color = lightTexel(p.lights, 1, index);
						cone = lightTexel(p.lights, 2, index);
					}
					let shadow = 1.0;
					// (untiled: no local light casts this frame, no tile read)
					if (!m.options.untiled) {
						if (color.w > 0.5) {
							// (its first tile's row: 32 on, colour's w 1 plus the tile)
							const first = 31 + color.w;
							const params = lightTexel(p.lights, 5, first);
							const at = shadowPoint(lit.world, lit.normal, pos.xyz, params);
							const tile = first + tileFace(at, pos.xyz, dot(cone.xyz, cone.xyz) < 0.0001);
							shadow = tileShadow(p.shadowMap, tileMatrix(p.lights, tile), lightTexel(p.lights, 4, tile), params, p.frame.shadowAtlas, at);
						}
					}
					if (m.options.area && color.w < -0.25) direct = direct.add(areaLight(lit.world, lit.normal, lit.view, lit.roughness, lit.albedo, lit.metalness,
						reflectance(lit, p.material), pos, color, cone, p.ltcMap!));
					else direct = direct.add(m.direct(lit, localLight(lit.world, lit.normal, pos, color, cone, shadow), p));
					k += 1;
					index = lightIndex(p.frame.clusters, p.frame.clusterDepth, i.lights0, i.lights1, p.clusterMap, cell, k);
				}
			}
			let env = ambientAt(lit, p.frame, p.material, p.occlusionTexture, p.environmentMap, p.aoMap);
			if (m.options.probes) env = probeLight(env, lit.world, lit.normal, lit.view, lit.roughness, i.ambient!, i.probeA!, i.extentA!, i.probeB!, i.extentB!,
				p.probesMap!, i.probeAtlas!);
			if (m.options.lightmap) {
				let baked = sample(p.lightMap!, i.lightmapUv!.xy).xyz;
				if (i.lightmapUv!.w > 1.5) baked = pow(baked, vec3(2.2));
				env = {irradiance: baked.mul(i.lightmapUv!.z), radiance: env.radiance, occlusion: env.occlusion};
				const mode = floor(i.lightmapUv!.w + 0.5);
				if (mode - floor(mode * 0.5) * 2 > 0.5) direct = vec3(0);
			}
			out = shade(lit, direct, m.indirect(lit, env, p), env, m.emissive(s, p), p.frame, p.material, p.shadowMap, p.environmentMap);
		}
		return out;
	},
	color: pbrColor,
	alpha: pbrAlpha,
	normal: pbrNormal,
	roughness: pbrRoughness,
	metalness: pbrMetalness,
	emissive: pbrEmissive,
	direct: pbrDirect,
	indirect: pbrIndirect,
	position: pbrPosition,
});
