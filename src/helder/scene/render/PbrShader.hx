package helder.scene.render;

import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.Equirect;

// The renderer's shader (Renderer): glTF's metallic-roughness model lit by
// a directional light, up to four point lights and a sky-and-ground
// ambient, in linear light,
// tone mapped (ACES, Narkowicz's fit) and encoded to sRGB for an 8-bit
// target. The specular term is Cook-Torrance: GGX's distribution, the
// height-correlated Smith visibility and Schlick's Fresnel; the ambient's
// specular part is the environment's colour along the reflection,
// weighted by an analytic fit of the split-sum's lookup (Karis'), so
// metals are not black without an environment map.
//
// It is a slot object, pbr (Slots): one shader whose variants are the
// renderer's (PbrShader; PbrNormalShader, normalMap: tangents and a normal
// map; PbrSkinnedShader, skinned: four joints a vertex; PbrInstancedShader,
// instanced: the world matrix per instance; PbrInstancedNormalShader) and
// whose slots a material replaces (MaterialShader.material): color,
// alpha, normal, roughness, metalness and emissive (the fragment's
// surface: PbrSurface), position (the vertex's point: PbrPoint), and how
// light reaches the surface: direct (the light one source adds, the sun's
// and each point or spot light's, shadowed: LightSample) and indirect (the
// ambient and the reflections: IndirectLight), each of the surface with
// the other slots' results (LitSurface). A shading model is those two
// replaced (helder.scene.render.shading: lambert, toon, phong), its
// shadows, lights, fog and normal maps kept.

// the combined vertex: a variant's attributes those it reads, in this order
// (pos, normal, uv; the tangent: x, y, z and the bitangent's sign; joints
// and weights; the instance's world matrix by columns, their w the node's
// tint less 1 in the first three, the last's 1 plus its atlas cell: an
// affine matrix's last row is 0, 0, 0, 1, so its w are free: instanceUv)
typedef PbrVertex = {
	var pos:Vec3;
	var normal:Vec3;
	var uv:Vec2;
	@:optional var tangent:Vec4;
	@:optional var joints:Vec4;
	@:optional var weights:Vec4;
	@:optional var m0:Vec4;
	@:optional var m1:Vec4;
	@:optional var m2:Vec4;
	@:optional var m3:Vec4;
}

typedef PbrVaryings = {
	var clip:Vec4;
	var world:Vec3;
	var normal:Vec3;
	var uv:Vec2;
	// (normal maps': the tangent turned to the world, the bitangent's sign)
	@:optional var tangent:Vec4;
	// the node's up (its y axis in the world: Material.ground's sphere's
	// normal) and its tint (MeshRenderer.tint: rgb times the base colour)
	var up:Vec3;
	var tint:Vec3;
}

// the vertex stage's parameters: per frame, per node (instanced: none),
// the skin (skinned: its joints' count, their matrices: Skin.update)
typedef PbrVertexParams = {
	var frame:PbrFrame;
	@:optional var object:PbrObject;
	@:optional var skin:PbrSkinInfo;
	@:optional var jointMatrices:Texture2D;
}

// the fragment stage's: per frame, the material and its textures, the
// shadow maps and the environment's (normal mapped: the normal map)
typedef PbrFragmentParams = {
	var frame:PbrFrame;
	var material:PbrMaterial;
	var baseColorTexture:Texture2D;
	var metallicRoughnessTexture:Texture2D;
	var emissiveTexture:Texture2D;
	var occlusionTexture:Texture2D;
	var shadowMap:Texture2D;
	var shadowMapFar:Texture2D;
	var environmentMap:Texture2D;
	// the screen's ambient occlusion (PostProcess.ao, Ssao: the view's
	// pixels, red; read where frame.exposure.z is 1, else a white texel)
	var aoMap:Texture2D;
	@:optional var normalTexture:Texture2D;
	// the prepass's (ViewBuffers: prepass variants only)
	@:optional var prepass:PbrPrepass;
}

@:structInit @:publicFields class PbrSkinInfo {
	var rows:Vec4; // x: the joints' count
}

// (prepass: the view buffers' variant, ViewBuffers: the view-space normal,
// roughness and selection group of the opaque surfaces, nothing lit)
typedef PbrOptions = {normalMap:Bool, skinned:Bool, instanced:Bool, prepass:Bool};

// per draw in the prepass (ViewBuffers): the camera's view (the normals
// into view space) and x the draw's selection group (Outline.select: 0 none)
@:structInit @:publicFields class PbrPrepass {
	var view:Mat4;
	var id:Vec4;
}

// what the fragment's slots read: the point in the world, its unit normal
// (normal mapped, before a double-sided face's turn), the material's uvs,
// the node's unit up, the base colour (rgb: the material's times its
// texture's, in linear light; a: their alpha)
typedef PbrSurface = {world:Vec3, normal:Vec3, uv:Vec2, up:Vec3, baseColor:Vec4};

// what the position slot reads: the vertex's point, normal and uvs (as
// the mesh has them, before skinning and the node's matrices)
typedef PbrPoint = {pos:Vec3, normal:Vec3, uv:Vec2};

// what the lighting slots (direct, indirect) read: the surface with the
// other slots' results: the point in the world, the unit normal (turned to
// the eye on a double-sided face seen from behind), the unit direction to
// the eye, the material's uvs, the node's unit up, the albedo (the color
// slot's, tinted, linear), its alpha, metalness and roughness
typedef LitSurface = {
	world:Vec3,
	normal:Vec3,
	view:Vec3,
	uv:Vec2,
	up:Vec3,
	albedo:Vec3,
	alpha:Float,
	metalness:Float,
	roughness:Float
}

// one light at a surface (the sun, a point or a spot light): color its
// colour times its intensity and attenuation (the inverse square, a spot's
// cone; the sun set on Material.ground's sphere), shadow how much of it
// reaches the point (1: lit, 0: in shadow), radiance the two multiplied,
// direction the unit direction towards it, ndotl the normal's dot with it
// (0 at least)
typedef LightSample = {
	color:Vec3,
	shadow:Float,
	radiance:Vec3,
	direction:Vec3,
	ndotl:Float
}

// the light around a surface: irradiance the ambient arriving along its
// normal (the sky and the ground, a hemisphere light's, or the
// environment's), radiance the environment's along its reflection at its
// roughness, occlusion the material's ambient occlusion (0 to 1)
typedef IndirectLight = {irradiance:Vec3, radiance:Vec3, occlusion:Float};

// the slot object (the stages' third parameter): its options, its slots
typedef Pbr = {
	options:PbrOptions,
	color:(PbrSurface, PbrFragmentParams) -> Vec3,
	alpha:(PbrSurface, PbrFragmentParams) -> Float,
	normal:(PbrSurface, PbrFragmentParams) -> Vec3,
	roughness:(PbrSurface, PbrFragmentParams) -> Float,
	metalness:(PbrSurface, PbrFragmentParams) -> Float,
	emissive:(PbrSurface, PbrFragmentParams) -> Vec3,
	direct:(LitSurface, LightSample, PbrFragmentParams) -> Vec3,
	indirect:(LitSurface, IndirectLight, PbrFragmentParams) -> Vec3,
	position:(PbrPoint, PbrVertexParams) -> Vec3
}

// per frame: the camera and the lights
@:structInit @:publicFields class PbrFrame {
	var viewProj:Mat4;
	var eye:Vec4; // xyz: the camera's position
	var lightDir:Vec4; // xyz: towards the light, normalized
	var lightColor:Vec4; // rgb: colour times intensity
	var sky:Vec4; // the ambient from above, rgb
	var ground:Vec4; // the ambient from below, rgb
	var exposure:Vec4; // x: exposure; y: 1 for a linear, HDR target (Renderer.hdr: tone mapped later, PostProcess); z: 1 the screen's ambient occlusion read (aoMap)
	var lightViewProj:Mat4; // the shadow map's view-projection (Shadows)
	var shadow:Vec4; // x: strength (0: no shadows), y: bias, z: a texel of the map
	// up to four point lights: position (w: range, 0 for none), colour times intensity
	var point0:Vec4;
	var point1:Vec4;
	var point2:Vec4;
	var point3:Vec4;
	var pointColor0:Vec4;
	var pointColor1:Vec4;
	var pointColor2:Vec4;
	var pointColor3:Vec4;
	// spot lights: the direction they shine (xyz) and the cosine of the outer
	// cone (w; below -1 for a point light); pointColor's w the inner cone's
	var spot0:Vec4;
	var spot1:Vec4;
	var spot2:Vec4;
	var spot3:Vec4;
	// the second shadow cascade (Shadows with two: the whole scene's map,
	// read where the first, near the camera, does not reach; else the first's)
	var lightViewProjFar:Mat4;
	var shadowFar:Vec4;
	// the environment's light (Environment): x its intensity (0: none, the
	// sky and the ground instead), y its map's mip levels below the first;
	// a prefiltered atlas's (Environment.prefiltered): z its levels of
	// roughness (0: a mip-mapped image), w half a texel of a row
	var environment:Vec4;
	// a rim light (Renderer.rim): rgb its colour times intensity, w the
	// falloff's power; the silhouette's edge lit from the light's side
	var rim:Vec4;
	// the fog (Renderer.fog, Fog.colorOf and shapeOf): rgb its colour, w its
	// density (0: none); x its start, y its falloff, z its height, w the most
	var fog:Vec4;
	var fogShape:Vec4;
	// the soft shadow filter (Shadows.soft): x its taps (0: the 3x3
	// filter), y and z a uv's depth in the first and the second cascade's
	// maps (their width over their depth: a slope's change of depth across
	// a uv), w the penumbra's spread a metre from the caster (0: the
	// radius alone, no blocker search); shadow.w and shadowFar.w each
	// cascade's widest radius, in its uv
	var shadowSoft:Vec4;
}

// per draw: the node's matrices
@:structInit @:publicFields class PbrObject {
	var model:Mat4;
	var normalMatrix:Mat4;
	var tint:Vec4; // rgb: the node's tint (MeshRenderer.tint)
}

// per draw: the material
@:structInit @:publicFields class PbrMaterial {
	var baseColor:Vec4;
	var params:Vec4; // x: metallic, y: roughness, z: the normal map's scale, w: 1 double-sided
	var emissive:Vec4; // rgb; w: its share emitted on the night side only (Material.emissiveNight)
	var ground:Vec4; // x: Material.ground, y: the air's strength (Material.air's w), z: Material.crystal, w: 1 fogged (Material.fog)
	var air:Vec4; // rgb: the air's colour (Material.air)
	// the textures' uv transform (Material.uvOffset, uvRotation, uvScale):
	// u = dot(uvU.xy, uv) + uvU.z, v likewise by uvV; uvV.w 1: added
	// (Material.blending Additive), its colour times its alpha
	var uvU:Vec4;
	var uvV:Vec4;
	// x: Material.clearcoat, y: its roughness, z: Material.transmission, w: Material.alphaCutoff
	var layers:Vec4;
	// the shading models' (helder.scene.render.shading): x the toon's steps
	// (Material.steps), y 1 tone mapped (Material.toneMapped; 0: shown as it
	// is, encoded), z and w the depth's near and far (Material.depthNear, depthFar)
	var model:Vec4;
	// rgb: the toon's shade (Material.shade: the albedo's share away from the light)
	var shadeColor:Vec4;
}

// a material's block (PbrMaterial) as the renderer writes it
function materialOf(m:Material):PbrMaterial {
	var z = new Vec4(0, 0, 0, 0);
	return materialInto(m, {baseColor: z, params: z, emissive: z, ground: z, air: z, uvU: z, uvV: z, layers: z, model: z, shadeColor: z});
}

// materialOf into a block kept (the renderer's: nothing allocated per draw)
function materialInto(m:Material, out:PbrMaterial):PbrMaterial {
	var c = Math.cos(m.uvRotation), s = Math.sin(m.uvRotation);
	out.baseColor = m.baseColor;
	out.params = new Vec4(m.metallic, m.roughness, m.normalScale, m.doubleSided ? 1 : 0);
	out.emissive = new Vec4(m.emissive.x, m.emissive.y, m.emissive.z, m.emissiveNight);
	out.ground = new Vec4(m.ground, m.air.w, m.crystal, m.fog ? 1 : 0);
	out.air = m.air;
	out.uvU = new Vec4(c * m.uvScale.x, s * m.uvScale.y, m.uvOffset.x, 0);
	out.uvV = new Vec4(-s * m.uvScale.x, c * m.uvScale.y, m.uvOffset.y, m.blend && m.blending == Additive ? 1 : 0);
	out.layers = new Vec4(m.clearcoat, m.clearcoatRoughness, m.transmission, m.alphaCutoff);
	out.model = new Vec4(m.steps, m.toneMapped ? 1 : 0, m.depthNear, m.depthFar);
	out.shadeColor = new Vec4(m.shade.x, m.shade.y, m.shade.z, 0);
	return out;
}

// a vertex's uvs as the material's textures read them (KHR_texture_transform)
function uvOf(material:PbrMaterial, uv:Vec2):Vec2
	return vec2(dot(material.uvU.xy, uv) + material.uvU.z, dot(material.uvV.xy, uv) + material.uvV.z);

// the fragment's colour at a point of the world with a unit normal n, the
// node's unit up and its tint, uv already the material's (uvOf), from the
// material's own terms (the slots' defaults: CPU code, Material.test), as
// pbr's fragment stage shades it
function shadeAt(facing:Vec3, world:Vec3, uv:Vec2, up:Vec3, tint:Vec3, frame:PbrFrame, material:PbrMaterial, baseColorTexture:Texture2D,
		metallicRoughnessTexture:Texture2D, emissiveTexture:Texture2D, occlusionTexture:Texture2D, shadowMap:Texture2D, shadowMapFar:Texture2D, environmentMap:Texture2D,
		aoMap:Texture2D):Vec4 {
	var texel = sample(baseColorTexture, uv);
	var s:PbrSurface = {world: world, normal: facing, uv: uv, up: up, baseColor: vec4(material.baseColor.xyz * pow(texel.xyz, vec3(2.2)), material.baseColor.w * texel.w)};
	var p:PbrFragmentParams = {
		frame: frame,
		material: material,
		baseColorTexture: baseColorTexture,
		metallicRoughnessTexture: metallicRoughnessTexture,
		emissiveTexture: emissiveTexture,
		occlusionTexture: occlusionTexture,
		shadowMap: shadowMap,
		shadowMapFar: shadowMapFar,
		environmentMap: environmentMap,
		aoMap: aoMap
	};
	var lit = litSurface(pbrNormal(s, p), world, uv, up, pbrColor(s, p) * tint, pbrAlpha(s, p), pbrMetalness(s, p), pbrRoughness(s, p), frame, material);
	var direct = pbrDirect(lit, sunLight(lit, frame, material, shadowMap, shadowMapFar), p);
	if (frame.point0.w > 0) direct += pbrDirect(lit, pointLight(lit, frame.point0, frame.pointColor0, frame.spot0), p);
	if (frame.point1.w > 0) direct += pbrDirect(lit, pointLight(lit, frame.point1, frame.pointColor1, frame.spot1), p);
	if (frame.point2.w > 0) direct += pbrDirect(lit, pointLight(lit, frame.point2, frame.pointColor2, frame.spot2), p);
	if (frame.point3.w > 0) direct += pbrDirect(lit, pointLight(lit, frame.point3, frame.pointColor3, frame.spot3), p);
	var env = ambientAt(lit, frame, material, occlusionTexture, environmentMap, aoMap);
	return shade(lit, direct, pbrIndirect(lit, env, p), env, pbrEmissive(s, p), frame, material, shadowMap, shadowMapFar, environmentMap);
}

// the slots' defaults: the base colour (the texture's sRGB decoded: the
// surface's), its alpha, the normal as it is, metalness and roughness
// (glTF's: roughness in green, metallic in blue, linear; a crystal
// polished whatever its roughness), the emitted light (sRGB decoded), the
// vertex's point as it is
function pbrColor(s:PbrSurface, p:{}):Vec3
	return s.baseColor.xyz;

function pbrAlpha(s:PbrSurface, p:{}):Float
	return s.baseColor.w;

function pbrNormal(s:PbrSurface, p:{}):Vec3
	return s.normal;

function pbrMetalness(s:PbrSurface, p:{material:PbrMaterial, metallicRoughnessTexture:Texture2D}):Float
	return clamp(p.material.params.x * sample(p.metallicRoughnessTexture, s.uv).z, 0, 1);

function pbrRoughness(s:PbrSurface, p:{material:PbrMaterial, metallicRoughnessTexture:Texture2D}):Float
	return clamp(mix(p.material.params.y * sample(p.metallicRoughnessTexture, s.uv).y, 0.07, p.material.ground.z), 0.04, 1);

function pbrEmissive(s:PbrSurface, p:{material:PbrMaterial, emissiveTexture:Texture2D}):Vec3
	return p.material.emissive.xyz * pow(sample(p.emissiveTexture, s.uv).xyz, vec3(2.2));

function pbrPosition(v:PbrPoint, p:{}):Vec3
	return v.pos;

// the direct slot's default: one light's Lambert diffuse and Cook-Torrance
// specular (GGX, height-correlated Smith, Schlick)
function pbrDirect(s:LitSurface, l:LightSample, p:{material:PbrMaterial}):Vec3 {
	var a = s.roughness * s.roughness;
	return brdf(s.normal, s.view, l.direction, s.albedo, s.metalness, a * a, reflectance(s, p.material)) * l.radiance;
}

// the indirect slot's default: the irradiance's diffuse share and the
// environment's reflection weighted by an analytic fit of the split sum's
// lookup (Karis'), so metals are not black without an environment map;
// both darkened by the occlusion
function pbrIndirect(s:LitSurface, env:IndirectLight, p:{material:PbrMaterial}):Vec3 {
	var nv = max(dot(s.normal, s.view), 0.0001);
	var c0 = vec4(-1, -0.0275, -0.572, 0.022);
	var c1 = vec4(1, 0.0425, 1.04, -0.04);
	var rr = c0 * s.roughness + c1;
	var a004 = min(rr.x * rr.x, pow(2, -9.28 * nv)) * rr.x + rr.y;
	var ab = vec2(-1.04, 1.04) * a004 + rr.zw;
	return (env.irradiance * s.albedo * (1 - s.metalness) + env.radiance * (reflectance(s, p.material) * ab.x + ab.y)) * env.occlusion;
}

// a surface's reflectance at normal incidence: a dielectric's 0.04, a
// metal's its albedo, a crystal's (Material.crystal) a gem's, higher than glass's
function reflectance(s:LitSurface, material:PbrMaterial):Vec3
	return mix(mix(vec3(0.04), s.albedo, s.metalness), vec3(0.12), material.ground.z);

// the lighting slots' surface (LitSurface) from the other slots' results:
// a double-sided face seen from behind lit by its normal turned to the
// eye, not by its front's (a model's inward walls lit as walls)
function litSurface(facing:Vec3, world:Vec3, uv:Vec2, up:Vec3, albedo:Vec3, alpha:Float, metalness:Float, roughness:Float, frame:PbrFrame,
		material:PbrMaterial):LitSurface {
	var v = normalize(frame.eye.xyz - world);
	var n = material.params.w > 0.5 && dot(facing, v) < 0 ? -facing : facing;
	return {
		world: world,
		normal: n,
		view: v,
		uv: uv,
		up: up,
		albedo: albedo,
		alpha: alpha,
		metalness: metalness,
		roughness: roughness
	};
}

// how much of the sun reaches a surface standing on Material.ground's
// sphere (its up the sphere's normal under it): the sun set there as on the
// ground around it, faded across the terminator as the planet's own light is
function daylight(s:LitSurface, frame:PbrFrame, material:PbrMaterial):Float
	return mix(1.0, smoothstep(-0.08, 0.22, dot(s.up, frame.lightDir.xyz)), material.ground.x);

// the sun (the frame's directional light) at a surface, shadowed by the maps
function sunLight(s:LitSurface, frame:PbrFrame, material:PbrMaterial, shadowMap:Texture2D, shadowMapFar:Texture2D):LightSample {
	var l = frame.lightDir.xyz;
	var c = frame.lightColor.xyz * daylight(s, frame, material);
	var lit = shadowed(frame, shadowMap, shadowMapFar, s.world, s.normal);
	return {
		color: c,
		shadow: lit,
		radiance: c * lit,
		direction: l,
		ndotl: max(dot(s.normal, l), 0)
	};
}

// a point or spot light at pos.xyz (pos.w: its range, above 0) at a
// surface: the inverse square falloff windowed to reach 0 at the range
// (glTF's KHR_lights_punctual), a spot's cone (spot.w above -1.5: the
// outer cone's cosine, color.w the inner's); unshadowed
function pointLight(s:LitSurface, pos:Vec4, color:Vec4, spot:Vec4):LightSample {
	var d = pos.xyz - s.world;
	var dist2 = max(dot(d, d), 0.0001);
	var dist = sqrt(dist2);
	var q = dist / pos.w;
	var window = clamp(1 - q * q * q * q, 0, 1);
	// (a spot light: full inside the inner cone, nothing outside the outer)
	var cone = 1.0;
	if (spot.w > -1.5) cone = smoothstep(spot.w, color.w, dot(-d / dist, spot.xyz));
	var l = d / dist;
	var c = color.xyz * (window * window / dist2 * cone);
	return {
		color: c,
		shadow: 1.0,
		radiance: c,
		direction: l,
		ndotl: max(dot(s.normal, l), 0)
	};
}

// the light around a surface (IndirectLight): the sky and the ground (a
// hemisphere light's, else the renderer's) blended by the normal, or the
// environment's along it (its small levels; a prefiltered atlas's last
// row, the irradiance); the environment's along the reflection, else the
// sky and the ground by its height; the material's occlusion (red), times
// the screen's (aoMap, at the point's pixel: Ssao) where it is read.
// Standing on a sphere (Material.ground): below its horizon (about up) it
// reflects the sphere's dark ground, not the sky beyond it, gets less of
// the sky's light the more it faces down, and on the night side the sky it
// reflects half the dark ground's
function ambientAt(s:LitSurface, frame:PbrFrame, material:PbrMaterial, occlusionTexture:Texture2D, environmentMap:Texture2D, aoMap:Texture2D):IndirectLight {
	var n = s.normal;
	var above = n.y * 0.5 + 0.5;
	var irradiance = mix(frame.ground.xyz, frame.sky.xyz, above);
	var r = reflect(-s.view, n);
	var env = reflected(frame, environmentMap, r, s.roughness);
	if (frame.environment.x > 0) {
		var top = frame.environment.y;
		irradiance = pow(sampleLevel(environmentMap, equirect(n), max(top - 2, 0)).xyz, vec3(2.2)) * frame.environment.x;
		if (frame.environment.z > 0) {
			var rows = frame.environment.z;
			irradiance = pow(atlas(environmentMap, equirect(n), rows, rows, frame.environment.w), vec3(2.2)) * frame.environment.x;
		}
	}
	var day = daylight(s, frame, material);
	var horizon = smoothstep(-0.2, 0.2, dot(r, s.up));
	var occlusion = sample(occlusionTexture, s.uv).x;
	if (frame.exposure.z > 0.5) {
		// (the screen's ambient occlusion (Ssao): the point's pixel)
		var sc = frame.viewProj * vec4(s.world, 1);
		occlusion = occlusion * sampleLevel(aoMap, vec2(sc.x / sc.w * 0.5 + 0.5, 0.5 - sc.y / sc.w * 0.5), 0).x;
	}
	return {
		irradiance: irradiance * mix(1.0, 0.55 + 0.45 * smoothstep(-0.6, 0.6, dot(n, s.up)), material.ground.x),
		radiance: env * mix(1.0, mix(0.12, 1, horizon) * (0.45 + 0.55 * day), material.ground.x),
		occlusion: occlusion
	};
}

// the fragment's colour from its surface (LitSurface), the direct light
// summed (the direct slot's, each light's), the indirect slot's (of env)
// and the light it emits: then the rim light, a clear coat, a crystal's
// light, transmission, the air, the fog, the target's encoding and the
// alpha's modes
function shade(s:LitSurface, lights:Vec3, indirect:Vec3, env:IndirectLight, emissive:Vec3, frame:PbrFrame, material:PbrMaterial, shadowMap:Texture2D,
		shadowMapFar:Texture2D, environmentMap:Texture2D):Vec4 {
	var crystal = material.ground.z;
	var n = s.normal;
	var v = s.view;
	var base = s.albedo;
	var metallic = s.metalness;
	var l = frame.lightDir.xyz;
	var nv = max(dot(n, v), 0.0001);
	var f0 = reflectance(s, material);
	var day = daylight(s, frame, material);
	var sunUp = dot(s.up, l);
	var direct = lights;
	var r = reflect(-v, n);
	var ambient = indirect;
	var emitted = emissive;
	// (city lights: on the night side, faded in past the terminator)
	emitted = emitted * mix(1.0, smoothstep(0.12, -0.18, dot(n, l)), material.emissive.w);
	// (the rim: grazing views, on the light's side and a little past it)
	var edge = 1 - nv;
	var rim = frame.rim.xyz * (pow(edge, frame.rim.w) * smoothstep(-0.25, 0.5, dot(n, l)) * day);
	direct += rim * mix(vec3(1), base, 0.5);
	var alpha = s.alpha;
	var coat = material.layers.x;
	if (coat > 0) {
		// (a clear coat (Material.clearcoat): a polished dielectric's
		// reflection of the sun and the environment over the base, which
		// it dims by its Fresnel)
		var cr = clamp(material.layers.y, 0.04, 1);
		var ca = cr * cr;
		var fc = (0.04 + 0.96 * pow(1 - nv, 5)) * coat;
		var lit = shadowed(frame, shadowMap, shadowMapFar, s.world, n) * day;
		var layer = coatLobe(n, v, l, ca * ca) * frame.lightColor.xyz * (lit * coat) + reflected(frame, environmentMap, r, cr) * fc;
		direct = direct * (1 - fc);
		ambient = ambient * (1 - fc) + layer;
	}
	if (crystal > 0) {
		// (a crystal (Material.crystal): the environment's reflection
		// stronger at grazing angles (Fresnel); light from inside, its
		// emissive colour lifted towards white where it is seen through
		// most (facing the eye: a fake subsurface), and the sun through it
		// from behind; its edges opaque and bright, its middle see-through
		// by the base colour's alpha (with Material.blend))
		var fres = pow(edge, 3);
		var glow = mix(material.emissive.xyz, vec3(dot(material.emissive.xyz, vec3(0.3, 0.4, 0.3))) * 1.6 + material.emissive.xyz * 0.4, 0.22);
		var inner = glow * (0.35 + 0.65 * nv * nv) * (0.75 + 0.25 * day);
		var through = frame.lightColor.xyz * base * (pow(max(dot(v, -l), 0), 6) * 0.6 * day);
		var sheen = (env.radiance * 1.4 + frame.rim.xyz * day) * (f0 + (1 - f0) * fres) * fres;
		emitted = mix(emitted, inner + through, crystal) + sheen * crystal;
		alpha = mix(alpha, 1, fres * crystal);
	}
	var transmission = max(material.layers.z, 0) * (1 - metallic);
	if (transmission > 0) {
		// (transmission (Material.transmission): the diffuse light let
		// through, what is behind showing instead (premultiplied: the
		// reflections over it as they are))
		var diffuse = (env.irradiance * base * (1 - metallic)) * env.occlusion;
		ambient = ambient - diffuse * transmission;
		direct = direct * (1 - transmission * 0.9);
	}
	var color = (direct + ambient + emitted) * frame.exposure.x;
	// (the air (Material.air): towards its sphere's limb, as seen through
	// more of the atmosphere, its colour lit by the sun over the ground)
	var limb = 1 - max(dot(s.up, v), 0);
	var haze = material.ground.y * limb * limb;
	color = mix(color, material.air.xyz * (0.12 + 0.88 * smoothstep(-0.2, 0.35, sunUp)) * frame.exposure.x, haze);
	// (the fog: light added (Additive) fades rather than turning its colour)
	var mist = fogAmount(frame.fog, frame.fogShape, frame.eye.xyz, s.world) * material.ground.w;
	color = mix(color, material.uvV.w > 0 ? vec3(0) : frame.fog.xyz * frame.exposure.x, mist);
	var shown = display(color, frame, material);
	// (alphaMode MASK: below the cutoff dropped, else opaque)
	if (material.layers.w > 0) {
		if (alpha < material.layers.w) discard();
		alpha = 1;
	}
	if (transmission > 0) {
		shown = shown * alpha;
		alpha = alpha * (1 - transmission);
	}
	if (material.layers.z < 0) {
		// (a transmitting surface's first draw (Renderer, Multiply): what
		// is behind times its colour, where the light goes through; an
		// 8-bit target's colours encoded)
		var through = -material.layers.z * (1 - metallic) * alpha;
		var filter = mix(vec3(1), base, through * (1 - mist));
		shown = frame.exposure.y > 0.5 ? filter : encode(filter);
		alpha = 1;
	}
	// (added to what is behind (Material.blending Additive): faded by its
	// alpha here, the blend adds as it is)
	if (material.uvV.w > 0) shown = shown * alpha;
	return vec4(shown, alpha);
}

// the light from the environment along a reflection r at a roughness:
// a prefiltered atlas's two rows by it, blended, a mip-mapped image's
// level by it, else the sky and the ground blended by r's height
function reflected(frame:PbrFrame, environmentMap:Texture2D, r:Vec3, rough:Float):Vec3 {
	var env = mix(frame.ground.xyz, frame.sky.xyz, smoothstep(-0.2, 0.2, r.y));
	if (frame.environment.x > 0) {
		var top = frame.environment.y;
		env = pow(sampleLevel(environmentMap, equirect(r), rough * max(top - 1, 0)).xyz, vec3(2.2)) * frame.environment.x;
		if (frame.environment.z > 0) {
			var rows = frame.environment.z;
			var edge = frame.environment.w;
			var at = rough * (rows - 1);
			var r0 = floor(at);
			var ru = equirect(r);
			var lo = atlas(environmentMap, ru, r0, rows, edge);
			var hi = atlas(environmentMap, ru, min(r0 + 1, rows - 1), rows, edge);
			env = pow(mix(lo, hi, at - r0), vec3(2.2)) * frame.environment.x;
		}
	}
	return env;
}

// a clear coat's specular lobe towards v from a unit light along l,
// times n.l (GGX, height-correlated Smith, a dielectric's Fresnel)
function coatLobe(n:Vec3, v:Vec3, l:Vec3, a2:Float):Vec3 {
	var h = normalize(l + v);
	var nl = max(dot(n, l), 0);
	var nv = max(dot(n, v), 0.0001);
	var nh = max(dot(n, h), 0);
	var fresnel = 0.04 + 0.96 * pow(1 - max(dot(v, h), 0), 5);
	var dd = nh * nh * (a2 - 1) + 1;
	var visibility = 0.5 / max(nl * sqrt(nv * nv * (1 - a2) + a2) + nv * sqrt(nl * nl * (1 - a2) + a2), 0.0001);
	return vec3(fresnel * a2 / (3.14159265 * dd * dd) * visibility * nl);
}

// the light reflected towards v from a unit light along l, times n.l:
// Lambert's diffuse and Cook-Torrance's specular (GGX, height-correlated
// Smith, Schlick)
function brdf(n:Vec3, v:Vec3, l:Vec3, base:Vec3, metallic:Float, a2:Float, f0:Vec3):Vec3 {
	var h = normalize(l + v);
	var nl = max(dot(n, l), 0);
	var nv = max(dot(n, v), 0.0001);
	var nh = max(dot(n, h), 0);
	var vh = max(dot(v, h), 0);
	var fresnel = f0 + (1 - f0) * pow(1 - vh, 5);
	var dd = nh * nh * (a2 - 1) + 1;
	var distribution = a2 / (3.14159265 * dd * dd);
	var visibility = 0.5 / max(nl * sqrt(nv * nv * (1 - a2) + a2) + nv * sqrt(nl * nl * (1 - a2) + a2), 0.0001);
	var diffuse = (1 - fresnel) * (1 - metallic) * base / 3.14159265;
	return (diffuse + fresnel * (distribution * visibility)) * nl;
}

// the direct light's share at a point (1: lit) from the shadow maps: the
// first cascade's where it reaches, else the second's; a 3x3
// percentage-closer filter, or the soft one (Shadows.soft); 1 outside
// them or without shadows (n: the surface's unit normal)
function shadowed(frame:PbrFrame, map:Texture2D, far:Texture2D, world:Vec3, n:Vec3):Float {
	var strength = frame.shadow.x;
	var result = 1.0;
	if (strength > 0) {
		var nl = max(dot(n, frame.lightDir.xyz), 0);
		var lit = cascade(map, frame.lightViewProj, frame.shadow, frame.shadowSoft, frame.shadowSoft.y, world, n, nl);
		if (lit < 0) lit = cascade(far, frame.lightViewProjFar, frame.shadowFar, frame.shadowSoft, frame.shadowSoft.z, world, n, nl);
		if (lit >= 0) result = 1 - strength * (1 - lit);
	}
	return result;
}

// a cascade's lit share (0 to 1) at a point, or -1 where its map does not
// reach (params: y the bias, z a texel of the map, w the soft filter's
// widest radius in its uv; soft and deep: shadowSoft's, this map's depth
// a uv)
function cascade(map:Texture2D, viewProj:Mat4, params:Vec4, soft:Vec4, deep:Float, world:Vec3, n:Vec3, nl:Float):Float {
	var result = -1.0;
	var ls = viewProj * vec4(world, 1);
	var p = ls.xyz / ls.w;
	var uv = vec2(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5);
	if (uv.x > 0 && uv.x < 1 && uv.y > 0 && uv.y < 1 && p.z < 1) {
		// (more bias where the light grazes the surface)
		var depth = p.z - params.y * (1 + 2 * (1 - nl));
		var t = params.z;
		if (soft.x > 0 && params.w > 0) result = softly(map, uv, depth, params.w, t, soft, deep, plane(viewProj, n, deep));
		else
			result = (tap(map, uv, depth, -t, -t) + tap(map, uv, depth, 0, -t) + tap(map, uv, depth, t, -t) + tap(map, uv, depth, -t, 0)
				+ tap(map, uv, depth, 0, 0) + tap(map, uv, depth, t, 0) + tap(map, uv, depth, -t, t) + tap(map, uv, depth, 0, t)
				+ tap(map, uv, depth, t, t)) / 9;
	}
	return result;
}

// 1 where the map's depth at uv + (dx, dy) is not nearer than depth
function tap(map:Texture2D, uv:Vec2, depth:Float, dx:Float, dy:Float):Float
	return step(depth, sampleLevel(map, uv + vec2(dx, dy), 0).x);

// how the depth of the surface's plane (unit normal n) changes across the
// map, a uv (an orthographic light's viewProj: two directions along the
// plane, their change of uv and depth, solved for it), its length at most
// four times deep (the plane seen from the light at a slant of 76 degrees:
// past it, no surface that is lit much)
function plane(viewProj:Mat4, n:Vec3, deep:Float):Vec2 {
	var t1 = normalize(cross(n, abs(n.y) < 0.9 ? vec3(0, 1, 0) : vec3(1, 0, 0)));
	var t2 = cross(n, t1);
	var a = (viewProj * vec4(t1, 0)).xyz;
	var b = (viewProj * vec4(t2, 0)).xyz;
	var au = vec2(a.x * 0.5, -a.y * 0.5);
	var bu = vec2(b.x * 0.5, -b.y * 0.5);
	var det = au.x * bu.y - au.y * bu.x;
	var g = vec2(0);
	if (abs(det) > 0.000001) g = vec2(a.z * bu.y - b.z * au.y, au.x * b.z - bu.x * a.z) / det;
	var most = deep * 4;
	var len = length(g);
	if (len > most) g = g * (most / len);
	return g;
}

// the soft filter's lit share (Shadows.soft): soft.x taps on a golden-angle
// spiral (Vogel's disc) out to a radius, turned at each of the map's
// texels by interleaved gradient noise (of the whole texel modulo 64,
// exact in floats: the same turn on every GPU); with a spread (soft.w),
// first a blocker search over the widest radius with half as many taps,
// the radius then the penumbra's at the blockers' mean distance (PCSS:
// sharp where the shadow meets its caster, softer away from it), a texel
// and a half at least; none found: lit. Each tap compared with the
// surface's own depth there (its plane in the light's view, g: plane),
// less a texel's change of it (the nearest texel's reach), so a tilted
// surface does not shadow itself and what stands on it still does
function softly(map:Texture2D, uv:Vec2, depth:Float, widest:Float, texel:Float, soft:Vec4, deep:Float, g:Vec2):Float {
	var n = soft.x;
	var margin = depth;
	var cell = fract(floor(uv / texel) / 64) * 64;
	var h = fract(52.9829189 * fract(dot(cell, vec2(0.06711056, 0.00583715))));
	// (the turn without trigonometry, whose precision GPUs differ in: a half
	// turn's direction from t = tan(angle / 2), the other half its opposite)
	var t = 2 * fract(2 * h) - 1;
	var start = vec2(1 - t * t, 2 * t) * ((h < 0.5 ? 1.0 : -1.0) / (1 + t * t));
	// (the golden angle's turn, a tap to the next)
	var c = -0.7373688;
	var s = 0.6754903;
	var radius = widest;
	var lit = -1.0;
	if (soft.w > 0) {
		var m = max(floor(n * 0.5), 4);
		var dir = start;
		var sum = 0.0;
		var found = 0.0;
		var k = 0.0;
		while (k < m) {
			var off = dir * (sqrt((k + 0.5) / m) * widest);
			var d = sampleLevel(map, uv + off, 0).x;
			var at = dot(g, off);
			if (d < margin + at) {
				// (the blocker's distance above the surface there)
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
		var dir = start;
		var sum = 0.0;
		var k = 0.0;
		while (k < n) {
			var off = dir * (sqrt((k + 0.5) / n) * radius);
			sum += step(margin + dot(g, off), sampleLevel(map, uv + off, 0).x);
			dir = vec2(dir.x * c - dir.y * s, dir.x * s + dir.y * c);
			k += 1;
		}
		lit = sum / n;
	}
	return lit;
}

// how much of the fog (Fog: colour and density, shape) lies between the
// eye and a point, 0 to its most: 1 - e^(-the density summed along the
// view past its start), the density e^(-falloff (y - height)) times its
// own (the sum's closed form: the density where the fog begins times the
// mean of the exponential over the climb)
function fogAmount(fog:Vec4, shape:Vec4, eye:Vec3, at:Vec3):Float {
	var d = at - eye;
	var dist = max(length(d), 0.0001);
	var through = max(dist - shape.x, 0);
	var y = eye.y + d.y * min(shape.x / dist, 1);
	var k = clamp(shape.y * d.y / dist * through, -30, 30);
	var mean = abs(k) > 0.0001 ? (1 - exp(-k)) / k : 1 - 0.5 * k;
	var depth = fog.w * exp(clamp(shape.y * (shape.z - y), -30, 30)) * through * mean;
	return min(1 - exp(-depth), shape.w);
}

// a colour in linear light as the target takes it: as it is into an HDR
// target (hdr 1: a half-float one, tone mapped by a PostProcess), else
// tone mapped and encoded for an 8-bit one (the shaders that draw into
// a Renderer's targets end with it)
function output(c:Vec3, hdr:Float):Vec3 {
	var result = c;
	if (hdr < 0.5) result = encode(aces(c));
	return result;
}

// a material's colour as the target takes it (output), or, not tone mapped
// (Material.toneMapped false: a debug view's), only encoded for an 8-bit one
function display(c:Vec3, frame:PbrFrame, material:PbrMaterial):Vec3 {
	var result = output(c, frame.exposure.y);
	if (material.model.y < 0.5 && frame.exposure.y < 0.5) result = encode(c);
	return result;
}

// ACES filmic tone mapping (Narkowicz's fit), to 0..1
function aces(x:Vec3):Vec3
	return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0, 1);

// linear to sRGB (the 2.2 power: the frame's format is not an sRGB one)
function encode(c:Vec3):Vec3
	return pow(c, vec3(1 / 2.2));

// a unit vector in two components 0..1 (octahedral: Cigolle et al. 2014)
function octEncode(n:Vec3):Vec2 {
	var a = n / (abs(n.x) + abs(n.y) + abs(n.z));
	var e = a.xy;
	if (a.z < 0) e = vec2((1 - abs(a.y)) * (a.x >= 0 ? 1.0 : -1.0), (1 - abs(a.x)) * (a.y >= 0 ? 1.0 : -1.0));
	return e * 0.5 + 0.5;
}

// roughness and metalness in one channel (4 bits each: the view buffers' z,
// screen-space reflections' Fresnel and gloss)
function packRoughMetal(r:Float, m:Float):Float
	return (floor(clamp(r, 0, 1) * 15 + 0.5) * 16 + floor(clamp(m, 0, 1) * 15 + 0.5)) / 255;

// joint k's matrix from its row of the texture (rows of them: 16 R32F texels a joint)
function joint(t:Texture2D, k:Float, rows:Float):Mat4 {
	var y = (k + 0.5) / rows;
	return mat4(vec4(texel(t, 0, y), texel(t, 1, y), texel(t, 2, y), texel(t, 3, y)), vec4(texel(t, 4, y), texel(t, 5, y), texel(t, 6, y), texel(t, 7, y)),
		vec4(texel(t, 8, y), texel(t, 9, y), texel(t, 10, y), texel(t, 11, y)),
		vec4(texel(t, 12, y), texel(t, 13, y), texel(t, 14, y), texel(t, 15, y)));
}

function texel(t:Texture2D, x:Float, y:Float):Float
	return sampleLevel(t, vec2((x + 0.5) / 16, y), 0).x;

// an instance's uvs moved to its cell of an atlas (Sprites): the matrix's
// last column's w is 1 plus the cell, its column plus 256 times its row
// (whole numbers, exact in a float), the uvs then the material's
// (uvScale: a cell's share of the image); 1, the first cell, as they are
function instanceUv(uv:Vec2, w:Float):Vec2 {
	var cell = w - 1;
	var row = floor(cell / 256);
	return uv + vec2(cell - row * 256, row);
}

// a normal n turned to the world by an instance's matrix (its columns
// c0, c1, c2): by the inverse transpose of its upper 3x3, as the object's
// normalMatrix turns it, here as its cofactors (the columns' cross
// products, the inverse transpose times the determinant) with the
// determinant's sign: exact for any scale, uneven or mirrored, and shear,
// the length the fragment's normalize takes away
function instanceNormal(c0:Vec3, c1:Vec3, c2:Vec3, n:Vec3):Vec3 {
	var x = cross(c1, c2);
	var turned = x * n.x + cross(c2, c0) * n.y + cross(c0, c1) * n.z;
	return dot(c0, x) < 0 ? -turned : turned;
}

final pbr = slots({
	options: {normalMap: false, skinned: false, instanced: false, prepass: false},
	vertex: function(v:PbrVertex, p:PbrVertexParams, m:Pbr):PbrVaryings {
		var pos = m.position({pos: v.pos, normal: v.normal, uv: v.uv}, p);
		var nr = v.normal;
		if (m.options.skinned) {
			// (moved by its four joints' matrices, weighted)
			var j0 = joint(p.jointMatrices, v.joints.x, p.skin.rows.x), j1 = joint(p.jointMatrices, v.joints.y, p.skin.rows.x);
			var j2 = joint(p.jointMatrices, v.joints.z, p.skin.rows.x), j3 = joint(p.jointMatrices, v.joints.w, p.skin.rows.x);
			var q = vec4(pos, 1), n4 = vec4(v.normal, 0);
			pos = ((j0 * q) * v.weights.x + (j1 * q) * v.weights.y + (j2 * q) * v.weights.z + (j3 * q) * v.weights.w).xyz;
			nr = ((j0 * n4) * v.weights.x + (j1 * n4) * v.weights.y + (j2 * n4) * v.weights.z + (j3 * n4) * v.weights.w).xyz;
		}
		var model = m.options.instanced ? mat4(vec4(v.m0.xyz, 0), vec4(v.m1.xyz, 0), vec4(v.m2.xyz, 0), vec4(v.m3.xyz, 1)) : p.object.model;
		var world = model * vec4(pos, 1);
		return {
			clip: position(p.frame.viewProj * world),
			world: world.xyz,
			normal: m.options.instanced ? instanceNormal(v.m0.xyz, v.m1.xyz, v.m2.xyz, nr) : (p.object.normalMatrix * vec4(nr, 0)).xyz,
			uv: m.options.instanced ? instanceUv(v.uv, v.m3.w) : v.uv,
			tangent: m.options.normalMap ? vec4((model * vec4(v.tangent.xyz, 0)).xyz, v.tangent.w) : vec4(0),
			up: m.options.instanced ? v.m1.xyz : (model * vec4(0, 1, 0, 0)).xyz,
			tint: m.options.instanced ? vec3(1 + v.m0.w, 1 + v.m1.w, 1 + v.m2.w) : p.object.tint.xyz
		};
	},
	fragment: function(i:PbrVaryings, p:PbrFragmentParams, m:Pbr):Vec4 {
		var ng = normalize(i.normal);
		var uv = uvOf(p.material, i.uv);
		var n = ng;
		if (m.options.normalMap) {
			// (the tangent made at right angles to the interpolated normal;
			// the map's x and y scaled by the material's normal scale, the
			// bitangent n x t times the sign, green up the image: glTF's)
			var t = normalize(i.tangent.xyz - ng * dot(ng, i.tangent.xyz));
			var b = cross(ng, t) * i.tangent.w;
			var mapped = sample(p.normalTexture, uv).xyz * 2 - 1;
			var scale = p.material.params.z;
			n = normalize(t * (mapped.x * scale) + b * (mapped.y * scale) + ng * mapped.z);
		}
		var texel = sample(p.baseColorTexture, uv);
		var s:PbrSurface = {
			world: i.world,
			normal: n,
			uv: uv,
			up: normalize(i.up),
			baseColor: vec4(p.material.baseColor.xyz * pow(texel.xyz, vec3(2.2)), p.material.baseColor.w * texel.w)
		};
		var out = vec4(0);
		if (m.options.prepass) {
			// (the view buffers' texel: the normal in view space (turned to
			// the eye on a double-sided face), roughness, the selection
			// group; alphaMode MASK cut out as the frame's pass cuts it)
			var a = m.alpha(s, p);
			if (p.material.layers.w > 0 && a < p.material.layers.w) discard();
			var f = m.normal(s, p);
			if (p.material.params.w > 0.5 && dot(f, p.frame.eye.xyz - s.world) < 0) f = -f;
			var vn = normalize((p.prepass.view * vec4(f, 0)).xyz);
			out = vec4(octEncode(vn), packRoughMetal(m.roughness(s, p), m.metalness(s, p)), p.prepass.id.x / 255);
		} else {
			var lit = litSurface(m.normal(s, p), s.world, uv, s.up, m.color(s, p) * i.tint, m.alpha(s, p), m.metalness(s, p), m.roughness(s, p), p.frame,
				p.material);
			// (the sun, then each point or spot light there is: the direct slot's, summed)
			var direct = m.direct(lit, sunLight(lit, p.frame, p.material, p.shadowMap, p.shadowMapFar), p);
			if (p.frame.point0.w > 0) direct += m.direct(lit, pointLight(lit, p.frame.point0, p.frame.pointColor0, p.frame.spot0), p);
			if (p.frame.point1.w > 0) direct += m.direct(lit, pointLight(lit, p.frame.point1, p.frame.pointColor1, p.frame.spot1), p);
			if (p.frame.point2.w > 0) direct += m.direct(lit, pointLight(lit, p.frame.point2, p.frame.pointColor2, p.frame.spot2), p);
			if (p.frame.point3.w > 0) direct += m.direct(lit, pointLight(lit, p.frame.point3, p.frame.pointColor3, p.frame.spot3), p);
			var env = ambientAt(lit, p.frame, p.material, p.occlusionTexture, p.environmentMap, p.aoMap);
			out = shade(lit, direct, m.indirect(lit, env, p), env, m.emissive(s, p), p.frame, p.material, p.shadowMap, p.shadowMapFar, p.environmentMap);
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
	position: pbrPosition
});

// the standard material, its plain variant
final PbrShader = pbr.variant();
