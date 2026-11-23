package helder.scene.render;

import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.Equirect;

// The renderer's shader (Renderer): glTF's metallic-roughness model lit by
// a directional light (its cascades: tiles of Shadows' atlas), the frame's
// point and spot lights (a draw's eight from its list, PbrObject's, or a
// pixel's cell's: ClusteredLights; shadowed by their tiles of the atlas)
// and a sky-and-ground ambient, in linear light,
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
//
// The glTF material extensions are its options (sheen, specular, clearcoat,
// transmission, iridescence, anisotropy: KHR_materials_*), folded at build
// time: a variant with one fills that layer of its surface (LitSurface's
// optional fields, from PbrMaterial's and its maps) between the surface's slots
// and the lights, and its direct and indirect slots are the physical ones
// (physicalDirect, physicalIndirect: PhysicalShader), which read the layers
// filled. A layer a variant does not fill reads as nothing, and the code
// that reads it folds away (helder.gfx's Prune): a variant without sheen has
// no sheen in its text.

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
	// (uvSets: TEXCOORD_1, a buffer of its own)
	@:optional var uv1:Vec2;
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
	// (uvSets: the second uvs)
	@:optional var uv1:Vec2;
	// the draw's lights (PbrObject's lists, passed on: a fragment stage that
	// reads PbrObject crashes Android's emulator's GL, its host SwiftShader)
	var lights0:Vec4;
	var lights1:Vec4;
	// (probes: the light probes' irradiance along the vertex's normal, w 1
	// when it has some; the draw's two reflection probes, PbrProbes')
	@:optional var ambient:Vec4;
	@:optional var probeA:Vec4;
	@:optional var extentA:Vec4;
	@:optional var probeB:Vec4;
	@:optional var extentB:Vec4;
	@:optional var probeAtlas:Vec4;
	// (lightmap: xy the lightmap's uvs, z its intensity, w its mode: 1 the
	// lights baked too, plus 2 its colours sRGB-encoded)
	@:optional var lightmapUv:Vec4;
}

// the vertex stage's parameters: per frame, per node (instanced: its light
// list alone, passed on to the fragment), the skin (skinned: its joints'
// count, their matrices: Skin.update)
typedef PbrVertexParams = {
	var frame:PbrFrame;
	@:optional var object:PbrObject;
	@:optional var probes:PbrProbes;
	@:optional var lightmap:PbrLightmap;
	@:optional var skin:PbrSkinInfo;
	@:optional var jointMatrices:Texture2D;
}

// the fragment stage's: per frame, the object (shadeAt's; the stages'
// read its light list from the varyings), the material and its textures,
// the frame's lights and their shadow tiles, the shadow atlas,
// ClusteredLights' map, the environment's (normal mapped: the normal map)
typedef PbrFragmentParams = {
	var frame:PbrFrame;
	@:optional var object:PbrObject;
	var material:PbrMaterial;
	// the frame's lights and the local lights' shadow tiles (lightTexel's)
	var lights:Texture2D;
	var baseColorTexture:Texture2D;
	var metallicRoughnessTexture:Texture2D;
	var emissiveTexture:Texture2D;
	var occlusionTexture:Texture2D;
	// the shadow atlas (Shadows: the sun's cascades' tiles and the local
	// lights'; R32F, each texel its depth from its light)
	var shadowMap:Texture2D;
	// ClusteredLights' (a 1x1 texel without): R32F, its cells' lists (a row
	// a tile's row and slice, a cell its count then its lights' rows), then
	// the frame's lights, a row each (12 texels: a light's three vectors, lightTexel's)
	var clusterMap:Texture2D;
	var environmentMap:Texture2D;
	// the screen's ambient occlusion (PostProcess.ao, Ssao: the view's
	// pixels, red; read where frame.exposure.z is 1, else a white texel)
	var aoMap:Texture2D;
	@:optional var normalTexture:Texture2D;
	// (area: AreaLights' linearly transformed cosines' two tables, 64 x 64
	// each, one above the other: RGBA16F)
	@:optional var ltcMap:Texture2D;
	// (lightmap: the node's baked light, Lightmap's)
	@:optional var lightMap:Texture2D;
	// (probes: the reflection probes' atlas, Probes')
	@:optional var probesMap:Texture2D;
	// the prepass's (ViewBuffers: prepass variants only)
	@:optional var prepass:PbrPrepass;
	// the glTF extensions' (a variant with one: their factors the
	// material's): the two images their maps are read from (PbrMaterial's
	// maps: which map in which), and the opaque frame behind a transmitting
	// surface (Transmission: mip-mapped, refracted through it; a black texel
	// without)
	@:optional var layerMap0:Texture2D;
	@:optional var layerMap1:Texture2D;
	@:optional var transmissionMap:Texture2D;
}

@:structInit @:publicFields class PbrSkinInfo {
	var rows:Vec4; // x: the joints' count
}

// (prepass: the view buffers' variant, ViewBuffers: the view-space normal,
// roughness and selection group of the opaque surfaces, nothing lit)
// (the glTF extensions, each a layer of the surface: KHR_materials_sheen,
// _specular and _ior, _clearcoat, _transmission and _volume, _iridescence,
// _anisotropy, their maps with them; uvSets: each core map its own uvs,
// TEXCOORD_0 or _1, and KHR_texture_transform)
typedef PbrOptions = {
	normalMap:Bool,
	skinned:Bool,
	instanced:Bool,
	prepass:Bool,
	sheen:Bool,
	specular:Bool,
	clearcoat:Bool,
	transmission:Bool,
	iridescence:Bool,
	anisotropy:Bool,
	uvSets:Bool,
	// (the sun alone: no local lights' loop; the renderer's, a frame without them)
	sunOnly:Bool,
	// (the local lights unshadowed: no tile read; the renderer's, a frame none of whose local lights casts)
	untiled:Bool,
	// (the draw's light probes and reflection probes: Probes', PbrProbes)
	probes:Bool,
	// (area lights shaded with LTC: AreaLights')
	area:Bool,
	// (a baked lightmap at the second uvs: Lightmap's)
	lightmap:Bool
};

// per draw, the probes' (Probes; the probes variants' vertex stage): the
// light probes' irradiance at its centre (Sh.pack's seven vectors), and its
// two reflection probes, each its box's centre (xyz; w its column of the
// atlas plus 1, 0 none) and half size (xyz); extentA.w A's share against B
// (or the environment), extentB.w 1 when sh holds light probes' light;
// atlas the probes' atlas (probesMap): x its columns, y its rows of
// roughness, z and w half a texel of a cell across and down
// per draw, a lightmap's (Lightmaps; the lightmap variant's vertex stage):
// rect its place in its texture (xy the second uvs' offset, zw their scale),
// params x its intensity, y its mode (1: the lights baked too, plus 2: its
// colours sRGB-encoded)
@:structInit @:publicFields class PbrLightmap {
	var rect:Vec4;
	var params:Vec4;
}

@:structInit @:publicFields class PbrProbes {
	@:length(7) var sh:Array<Vec4>;
	var probeA:Vec4;
	var extentA:Vec4;
	var probeB:Vec4;
	var extentB:Vec4;
	var atlas:Vec4;
}

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
// (uvSets: the metallic-roughness and emissive maps' own uvs)
typedef PbrSurface = {
	world:Vec3,
	normal:Vec3,
	uv:Vec2,
	up:Vec3,
	baseColor:Vec4,
	?uvMetallicRoughness:Vec2,
	?uvEmissive:Vec2
};

// what the position slot reads: the vertex's point, normal and uvs (as
// the mesh has them, before skinning and the node's matrices)
typedef PbrPoint = {pos:Vec3, normal:Vec3, uv:Vec2};

// what the lighting slots (direct, indirect) read: the surface with the
// other slots' results: the point in the world, the unit normal (turned to
// the eye on a double-sided face seen from behind), the unit direction to
// the eye, the material's uvs, the node's unit up, the albedo (the color
// slot's, tinted, linear), its alpha, metalness and roughness; then the glTF
// extensions' layers, filled by a variant with them (its options), read as
// nothing by one without (each layer's first field its weight, 0: none):
//   sheen            its colour's largest share; sheenColor (linear), sheenRoughness
//   specular         1; specularColor the reflectance at normal incidence (f0:
//                    the ior's and the specular colour's, a metal's albedo),
//                    specularWeight at grazing angles (f90)
//   coat             the clear coat's share; coatRoughness, coatNormal (unit)
//   transmission     the light's share let through; thickness (0: thin)
//   iridescence      the thin film's share; iridescenceFresnel its reflectance
//                    seen from the eye
//   anisotropy       its strength; anisotropyDirection, the unit tangent the
//                    highlight stretches along, anisotropyBitangent across it
typedef LitSurface = {
	world:Vec3,
	normal:Vec3,
	view:Vec3,
	uv:Vec2,
	up:Vec3,
	albedo:Vec3,
	alpha:Float,
	metalness:Float,
	roughness:Float,
	?sheen:Float,
	?sheenColor:Vec3,
	?sheenRoughness:Float,
	?specular:Float,
	?specularColor:Vec3,
	?specularWeight:Float,
	?coat:Float,
	?coatRoughness:Float,
	?coatNormal:Vec3,
	?transmission:Float,
	?thickness:Float,
	?iridescence:Float,
	?iridescenceFresnel:Vec3,
	?anisotropy:Float,
	?anisotropyDirection:Vec3,
	?anisotropyBitangent:Vec3
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
	var lightViewProj:Mat4; // the first cascade's view-projection (Shadows)
	var shadow:Vec4; // x: strength (0: no shadows), y: bias, z: a texel of the map
	// the second shadow cascade (Shadows with two: the whole scene's map,
	// read where the first, near the camera, does not reach; else the first's)
	var lightViewProjFar:Mat4;
	var shadowFar:Vec4;
	// the cascades' tiles in the atlas: xy their corner, z and w their share
	// of its width and height; shadowAtlas: x and y a texel of the atlas
	var shadowRect:Vec4;
	var shadowRectFar:Vec4;
	var shadowAtlas:Vec4;
	// the environment's light (Environment): x its intensity (0: none, the
	// sky and the ground instead), y its map's mip levels below the first;
	// a prefiltered atlas's (Environment.prefiltered): z its levels of
	// roughness (0: a mip-mapped image), w half a texel of a row (helder's
	// own prefilter, Environment.prefilter, writes one too)
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
	// ClusteredLights' grid (x 0: the draws' lists instead): x its tiles
	// across the view, y down it, z its depth slices, w a cell's lights at
	// most; clusterDepth: x the first slice's near depth, y slices a unit of
	// log depth, z and w the cluster map's width and height; clusterAxis: xyz
	// the camera's forward, w the map's first row of lights
	var clusters:Vec4;
	var clusterDepth:Vec4;
	var clusterAxis:Vec4;
}

// per draw: the node's matrices, its light list (instanced: the run's,
// the matrices unread)
@:structInit @:publicFields class PbrObject {
	var model:Mat4;
	var normalMatrix:Mat4;
	var tint:Vec4; // rgb: the node's tint (MeshRenderer.tint); w: skinned, its joints' count (else 1)
	// the draw's lights (Renderer: the eight that light its bounds most),
	// rows of the frame's lights (lightTexel's), -1 after the last
	var lights0:Vec4;
	var lights1:Vec4;
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
	// the glTF extensions' (Material's fields of their names; read by the
	// variants with them: PhysicalShader)
	var sheen:Vec4; // rgb: sheenColor (linear), a: sheenRoughness
	var specular:Vec4; // rgb: specularColor (linear), a: specularFactor
	var coat:Vec4; // x: clearcoat, y: clearcoatRoughness, z: clearcoatNormalScale, w: ior
	// x: transmission, y: thickness, z: attenuationDistance (0: none), w: the
	// opaque frame's mip levels behind it (Transmission, the renderer's; 0:
	// none, the environment seen through instead)
	var transmission:Vec4;
	var attenuation:Vec4; // rgb: attenuationColor (linear)
	var iridescence:Vec4; // x: iridescence, y: iridescenceIor, z and w: its thickness' range (nm)
	var anisotropy:Vec4; // x: anisotropy (strength), y and z: its rotation's cosine and sine
	// the maps' images (1 or 2: layerMap0 or 1, 0: none): sheenColorTexture,
	// sheenRoughnessTexture, specularTexture, specularColorTexture;
	// clearcoatTexture, clearcoatRoughnessTexture, clearcoatNormalTexture,
	// transmissionTexture; thicknessTexture, iridescenceTexture,
	// iridescenceThicknessTexture, anisotropyTexture (the renderer's)
	var maps0:Vec4;
	var maps1:Vec4;
	var maps2:Vec4;
	// the core maps' own uvs (uvSets: Material.textureTransforms): the
	// metallic-roughness, normal, occlusion and emissive maps', as uvU and
	// uvV are the base colour's (the extensions' maps read the base
	// colour's); U.w 1: TEXCOORD_1 (uvU.w the base colour's)
	var uvMetallicRoughnessU:Vec4;
	var uvMetallicRoughnessV:Vec4;
	var uvNormalU:Vec4;
	var uvNormalV:Vec4;
	var uvOcclusionU:Vec4;
	var uvOcclusionV:Vec4;
	var uvEmissiveU:Vec4;
	var uvEmissiveV:Vec4;
}

// a material's block (PbrMaterial) as the renderer writes it
function materialOf(m:Material):PbrMaterial {
	var z = new Vec4(0, 0, 0, 0);
	return materialInto(m, {
		baseColor: z,
		params: z,
		emissive: z,
		ground: z,
		air: z,
		uvU: z,
		uvV: z,
		layers: z,
		model: z,
		shadeColor: z,
		sheen: z,
		specular: z,
		coat: z,
		transmission: z,
		attenuation: z,
		iridescence: z,
		anisotropy: z,
		maps0: z,
		maps1: z,
		maps2: z,
		uvMetallicRoughnessU: z,
		uvMetallicRoughnessV: z,
		uvNormalU: z,
		uvNormalV: z,
		uvOcclusionU: z,
		uvOcclusionV: z,
		uvEmissiveU: z,
		uvEmissiveV: z
	});
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
	// (the glTF extensions' fields and each map's uvs: a physical shader's, PhysicalLayers.block)
	return out;
}

// a map's uvs (uvSets): TEXCOORD_0 or _1 (u.w), moved by its transform's rows
function uvSetOf(u:Vec4, v:Vec4, uv0:Vec2, uv1:Vec2):Vec2 {
	var t = u.w > 0.5 ? uv1 : uv0;
	return vec2(dot(u.xy, t) + u.z, dot(v.xy, t) + v.z);
}

// a vertex's uvs as the material's textures read them (KHR_texture_transform)
function uvOf(material:PbrMaterial, uv:Vec2):Vec2
	return vec2(dot(material.uvU.xy, uv) + material.uvU.z, dot(material.uvV.xy, uv) + material.uvV.z);

// the fragment's colour at a point of the world with a unit normal n, the
// node's unit up and its tint, uv already the material's (uvOf), from the
// material's own terms (the slots' defaults: CPU code, Material.test), as
// pbr's fragment stage shades it
function shadeAt(facing:Vec3, world:Vec3, uv:Vec2, up:Vec3, tint:Vec3, frame:PbrFrame, object:PbrObject, material:PbrMaterial, lights:Texture2D,
		baseColorTexture:Texture2D, metallicRoughnessTexture:Texture2D, emissiveTexture:Texture2D, occlusionTexture:Texture2D, shadowMap:Texture2D,
		clusterMap:Texture2D, environmentMap:Texture2D, aoMap:Texture2D):Vec4 {
	var texel = sample(baseColorTexture, uv);
	var s:PbrSurface = {world: world, normal: facing, uv: uv, up: up, baseColor: vec4(material.baseColor.xyz * pow(texel.xyz, vec3(2.2)), material.baseColor.w * texel.w)};
	var p:PbrFragmentParams = {
		frame: frame,
		object: object,
		material: material,
		lights: lights,
		baseColorTexture: baseColorTexture,
		metallicRoughnessTexture: metallicRoughnessTexture,
		emissiveTexture: emissiveTexture,
		occlusionTexture: occlusionTexture,
		shadowMap: shadowMap,
		clusterMap: clusterMap,
		environmentMap: environmentMap,
		aoMap: aoMap
	};
	var lit = litSurface(pbrNormal(s, p), world, uv, up, pbrColor(s, p) * tint, pbrAlpha(s, p), pbrMetalness(s, p), pbrRoughness(s, p), frame, material);
	var direct = pbrDirect(lit, sunLight(lit, frame, material, shadowMap), p);
	var cell = clusterCell(frame.viewProj, frame.eye, frame.clusters, frame.clusterDepth, frame.clusterAxis, clusterMap, world);
	var k = 0.0;
	var index = lightIndex(frame.clusters, frame.clusterDepth, object.lights0, object.lights1, clusterMap, cell, k);
	while (k < cell.z && index >= 0) {
	// (the light's row, its shadow: read here, the arrays not passed on)
	var pos = vec4(0);
	var color = vec4(0);
	var cone = vec4(0);
	if (frame.clusters.x > 0) {
		pos = lightRow(clusterMap, 0, index, frame.clusterAxis, frame.clusterDepth);
		color = lightRow(clusterMap, 4, index, frame.clusterAxis, frame.clusterDepth);
		cone = lightRow(clusterMap, 8, index, frame.clusterAxis, frame.clusterDepth);
	} else {
		pos = lightTexel(lights, 0, index);
		color = lightTexel(lights, 1, index);
		cone = lightTexel(lights, 2, index);
	}
	var shadow = 1.0;
	if (color.w > 0.5) {
		var first = 31 + color.w;
		var params = lightTexel(lights, 5, first);
		var at = shadowPoint(lit.world, lit.normal, pos.xyz, params);
		var tile = first + tileFace(at, pos.xyz, dot(cone.xyz, cone.xyz) < 0.0001);
		shadow = tileShadow(shadowMap, tileMatrix(lights, tile), lightTexel(lights, 4, tile), params, frame.shadowAtlas, at);
	}
	direct += pbrDirect(lit, localLight(lit.world, lit.normal, pos, color, cone, shadow), p);
		k += 1;
		index = lightIndex(frame.clusters, frame.clusterDepth, object.lights0, object.lights1, clusterMap, cell, k);
	}
	var env = ambientAt(lit, frame, material, occlusionTexture, environmentMap, aoMap);
	return shade(lit, direct, pbrIndirect(lit, env, p), env, pbrEmissive(s, p), frame, material, shadowMap, environmentMap);
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

// the sun (the frame's directional light) at a surface, shadowed by its cascades
function sunLight(s:LitSurface, frame:PbrFrame, material:PbrMaterial, shadowMap:Texture2D):LightSample {
	var l = frame.lightDir.xyz;
	var c = frame.lightColor.xyz * daylight(s, frame, material);
	var lit = shadowed(frame, shadowMap, s.world, s.normal);
	return {
		color: c,
		shadow: lit,
		radiance: c * lit,
		direction: l,
		ndotl: max(dot(s.normal, l), 0)
	};
}

// where a point's local lights are listed: ClusteredLights' cell under it
// (x the column of its first texel in the cluster map, y its row, z its
// lights' count: the cell's at the point's pixel and its depth's slice,
// exponential from the near depth), else the draw's list (z 8)
// (PbrFrame's viewProj, eye, clusters, clusterDepth, clusterAxis: the
// vectors, not the frame, which a function's call copies)
function clusterCell(viewProj:Mat4, eye:Vec4, clusters:Vec4, clusterDepth:Vec4, clusterAxis:Vec4, clusterMap:Texture2D, world:Vec3):Vec3 {
	var cell = vec3(0, 0, 8);
	if (clusters.x > 0) {
		var sc = viewProj * vec4(world, 1);
		var x = clamp(floor((sc.x / sc.w * 0.5 + 0.5) * clusters.x), 0, clusters.x - 1);
		var y = clamp(floor((0.5 - sc.y / sc.w * 0.5) * clusters.y), 0, clusters.y - 1);
		var depth = max(dot(world - eye.xyz, clusterAxis.xyz), clusterDepth.x);
		var z = clamp(floor(log(depth / clusterDepth.x) * clusterDepth.y), 0, clusters.z - 1);
		var column = x * (clusters.w + 1);
		var row = y + z * clusters.y;
		cell = vec3(column, row, mapTexel(clusterMap, column, row, clusterDepth));
	}
	return cell;
}

// the k-th light a point's list names (clusterCell's: the cell's, else the
// draw's, PbrObject's lights0 and lights1: as varyings, rounded), a row of
// the frame's lights; -1: none
function lightIndex(clusters:Vec4, clusterDepth:Vec4, lights0:Vec4, lights1:Vec4, clusterMap:Texture2D, cell:Vec3, k:Float):Float {
	var index = -1.0;
	if (clusters.x > 0) index = mapTexel(clusterMap, cell.x + 1 + k, cell.y, clusterDepth);
	else {
		var four = k < 4 ? lights0 : lights1;
		var j = k < 4 ? k : k - 4;
		index = floor((j < 0.5 ? four.x : j < 1.5 ? four.y : j < 2.5 ? four.z : four.w) + 0.5);
	}
	return index;
}

// texel (x, y) of an R32F map of size.z by size.w texels
function mapTexel(t:Texture2D, x:Float, y:Float, size:Vec4):Float
	return sampleLevel(t, vec2((x + 0.5) / size.z, (y + 0.5) / size.w), 0).x;

// four texels of light k's row of the cluster map (ClusteredLights: after
// its cells' rows, from PbrFrame's clusterAxis.w; clusterDepth's z and w:
// the map's size), from column x
function lightRow(t:Texture2D, x:Float, k:Float, clusterAxis:Vec4, clusterDepth:Vec4):Vec4 {
	var v = (clusterAxis.w + k + 0.5) / clusterDepth.w;
	var w = clusterDepth.z;
	return vec4(sampleLevel(t, vec2((x + 0.5) / w, v), 0).x, sampleLevel(t, vec2((x + 1.5) / w, v), 0).x, sampleLevel(t, vec2((x + 2.5) / w, v), 0).x,
		sampleLevel(t, vec2((x + 3.5) / w, v), 0).x);
}

// the frame's point and spot lights and their shadow tiles: an RGBA32F
// texture of FrameLights.COLUMNS by ROWS texels, 6 by 44 (the renderer's, written
// once a frame), read by row (a texture, not a uniform block: on Metal a
// block of 2.7 KB read at a computed row made little-skies' frame four
// times as long on iOS's simulator, and it was copied at each pipeline's
// bind). Rows 0 to 31 the lights
// (Renderer: up to FrameLights.MAX_LIGHTS, the nearest the view's and the
// brightest), each three texels: position (xyz; w its range, 0: none),
// colour (rgb its colour times intensity; w 1 plus its first tile, 0:
// unshadowed), cone (a spot's axis times 1 / (cos inner - cos outer), w
// -cos outer times that: the cone's smoothstep from one dot; a point
// light's 0, 0, 0, 1). Then the tiles from row 32 (Shadows: a spot
// light's tile, a point light's six, faces +x, -x, +y, -y, +z, -z;
// Shadows.MAX_TILES of them), each six texels: the light's
// view-projection of the tile (its four columns), its place in the atlas
// (xy its corner, z and w its share of the atlas' width and height) and its
// filter (x strength, y the depth bias in metres a metre from the light, z
// the normal offset likewise, w the disc filter's radius in the tile's uv,
// 0: the 3x3 filter).
function lightTexel(t:Texture2D, x:Float, y:Float):Vec4
	return sampleLevel(t, vec2((x + 0.5) / 6, (y + 0.5) / 44), 0);

// a tile's view-projection (lightTexel's row)
function tileMatrix(t:Texture2D, row:Float):Mat4
	return mat4(lightTexel(t, 0, row), lightTexel(t, 1, row), lightTexel(t, 2, row), lightTexel(t, 3, row));

// a local light at a surface (its three vectors: the frame's lights' row or
// ClusteredLights' map's; its lit share, 1 unshadowed: tileShadow's): the
// inverse square falloff windowed to reach 0 at its range (glTF's
// KHR_lights_punctual), a spot's cone (the smoothstep from its outer cone
// to its inner, from one dot: its cone). (The vectors, not the
// blocks nor the surface: a function's call copies what it is passed, and
// Android's emulator's GL, its host SwiftShader, failed to compile a stage
// that copied the lights' and the tiles' arrays, or the lit surface, into
// each.)
function localLight(world:Vec3, normal:Vec3, pos:Vec4, color:Vec4, cone:Vec4, shadow:Float):LightSample {
	var d = pos.xyz - world;
	var dist2 = max(dot(d, d), 0.0001);
	var dist = sqrt(dist2);
	var q = dist / pos.w;
	var window = clamp(1 - q * q * q * q, 0, 1);
	var l = d / dist;
	var t = clamp(dot(-l, cone.xyz) + cone.w, 0, 1);
	var c = color.xyz * (window * window / dist2 * (t * t * (3 - 2 * t)));
	return {
		color: c,
		shadow: shadow,
		radiance: c * shadow,
		direction: l,
		ndotl: max(dot(normal, l), 0)
	};
}

// where a surface's point is looked up in a local light's tiles (lightTexel's
// tiles: a spot light's own, a point light's the face the point is in,
// from its first): moved towards the light (at light) by the bias and off
// its surface by the normal offset, both scaled by its distance (params:
// its first tile's filter)
function shadowPoint(world:Vec3, normal:Vec3, light:Vec3, params:Vec4):Vec3 {
	var d = light - world;
	var dist = max(length(d), 0.0001);
	return world + d * params.y + normal * (params.z * dist);
}

// the face of a point light's tiles (0 to 5: +x, -x, +y, -y, +z, -z) a
// moved point is in (a spot light's: 0)
function tileFace(at:Vec3, light:Vec3, point:Bool):Float {
	var face = 0.0;
	if (point) {
		var d = at - light;
		var a = abs(d);
		face = a.x >= a.y && a.x >= a.z ? (d.x > 0 ? 0.0 : 1.0) : a.y >= a.z ? (d.y > 0 ? 2.0 : 3.0) : (d.z > 0 ? 4.0 : 5.0);
	}
	return face;
}

// a local light's lit share at a moved point (1: lit) from a tile of the
// atlas (viewProj, rect: the tile's; params: the light's filter; inv: a
// texel of the atlas): the 3x3 filter or a disc of taps; 1 outside the tile
function tileShadow(map:Texture2D, viewProj:Mat4, rect:Vec4, params:Vec4, inv:Vec4, at:Vec3):Float {
	var c = viewProj * vec4(at, 1);
	var p = c.xyz / c.w;
	var uv = vec2(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5);
	var result = 1.0;
	if (c.w > 0 && uv.x > 0 && uv.x < 1 && uv.y > 0 && uv.y < 1 && p.z < 1) {
		var t = inv.x / rect.z;
		var lit = 0.0;
		if (params.w > 0) lit = disc(map, uv, rect, inv, p.z, params.w, t);
		else
			lit = grid(map, uv, rect, inv, p.z, t);
		result = 1 - params.x * (1 - lit);
	}
	return result;
}

// the 3x3 filter's lit share, a loop of its nine taps (the same taps, the
// same sum, as cascade's; once in the stage's code, not nine times in the
// light loop's: Android's emulator's SwiftShader failed to compile the
// stage with them unrolled there)
function grid(map:Texture2D, uv:Vec2, rect:Vec4, inv:Vec4, depth:Float, t:Float):Float {
	var sum = 0.0;
	var k = 0.0;
	while (k < 9) {
		var row = floor(k / 3);
		sum += tap(map, uv, rect, inv, depth, (k - row * 3 - 1) * t, (row - 1) * t);
		k += 1;
	}
	return sum / 9;
}

// a tile's uv in the atlas (rect: its corner, its share of the atlas; inv:
// a texel of the atlas), held inside the tile's edge texels (the taps past
// its edge read the edge, as a map of its own clamped)
function atlasUv(uv:Vec2, rect:Vec4, inv:Vec4):Vec2
	return clamp(rect.xy + uv * rect.zw, rect.xy + inv.xy * 0.5, rect.xy + rect.zw - inv.xy * 0.5);

// a disc of 12 taps out to radius (in the tile's uv) on a golden-angle
// spiral, turned at each of the tile's texels as softly's
function disc(map:Texture2D, uv:Vec2, rect:Vec4, inv:Vec4, depth:Float, radius:Float, texel:Float):Float {
	var cell = fract(floor(uv / texel) / 64) * 64;
	var h = fract(52.9829189 * fract(dot(cell, vec2(0.06711056, 0.00583715))));
	var t = 2 * fract(2 * h) - 1;
	var dir = vec2(1 - t * t, 2 * t) * ((h < 0.5 ? 1.0 : -1.0) / (1 + t * t));
	var c = -0.7373688;
	var s = 0.6754903;
	var sum = 0.0;
	var k = 0.0;
	while (k < 12) {
		var off = dir * (sqrt((k + 0.5) / 12) * radius);
		sum += step(depth, sampleLevel(map, atlasUv(uv + off, rect, inv), 0).x);
		dir = vec2(dir.x * c - dir.y * s, dir.x * s + dir.y * c);
		k += 1;
	}
	return sum / 12;
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
		environmentMap:Texture2D):Vec4 {
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
		var lit = shadowed(frame, shadowMap, s.world, n) * day;
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

// the light around a surface with probes (Probes: the draw's, as varyings):
// the light probes' irradiance where it has some (ambient.w), the
// reflection probes' light along the reflection (A's share against B's, or
// the environment's), from their atlas (t; e: its shape, PbrProbes' atlas)
function probeLight(env:IndirectLight, world:Vec3, n:Vec3, v:Vec3, rough:Float, ambient:Vec4, probeA:Vec4, extentA:Vec4, probeB:Vec4, extentB:Vec4,
		t:Texture2D, e:Vec4):IndirectLight {
	var irradiance = env.irradiance;
	if (ambient.w > 0.5) irradiance = ambient.xyz;
	var radiance = env.radiance;
	if (probeA.w > 0.5) {
		var r = reflect(-v, n);
		var b = env.radiance;
		if (probeB.w > 0.5) b = boxReflected(t, world, r, rough, probeB, extentB, e);
		radiance = mix(b, boxReflected(t, world, r, rough, probeA, extentA, e), extentA.w);
	}
	return {irradiance: irradiance, radiance: radiance, occlusion: env.occlusion};
}

// a reflection probe's light along r from a point (its box: probe's centre,
// extent's half size; captured at its centre): the direction from the centre
// to where r leaves the box (parallax-corrected), in its column of the atlas
function boxReflected(t:Texture2D, world:Vec3, r:Vec3, rough:Float, probe:Vec4, extent:Vec4, e:Vec4):Vec3 {
	var rr = r + vec3(0.000001);
	var a = (probe.xyz - extent.xyz - world) / rr;
	var b = (probe.xyz + extent.xyz - world) / rr;
	var far = max(a, b);
	var dist = min(min(far.x, far.y), far.z);
	return probeAtlas(t, world + r * max(dist, 0) - probe.xyz, rough, probe.w - 1, e);
}

// a probe's light along a direction at a roughness: its column of the
// probes' atlas (e: its columns, rows, half a texel across and down a cell),
// two rows by it, blended (sRGB-encoded as an environment's atlas: decoded)
function probeAtlas(t:Texture2D, d:Vec3, rough:Float, column:Float, e:Vec4):Vec3 {
	var rows = e.y;
	var at = rough * (rows - 1);
	var r0 = floor(at);
	var uv = equirect(d);
	var u = (column + clamp(uv.x, e.z, 1 - e.z)) / e.x;
	var v = clamp(uv.y, e.w, 1 - e.w);
	var lo = sampleLevel(t, vec2(u, (r0 + v) / (rows + 1)), 0).xyz;
	var hi = sampleLevel(t, vec2(u, (min(r0 + 1, rows - 1) + v) / (rows + 1)), 0).xyz;
	return pow(mix(lo, hi, at - r0), vec3(2.2));
}

// an area light at a surface (AreaLights: its row, the frame's lights' or the
// cluster map's; ltc: the tables), linearly transformed cosines (Heitz et
// al., three.js's fit): the light's polygon (a rectangle; a disc as an
// octagon of its area) seen from the point, integrated against the cosine
// (diffuse) and against GGX's lobe turned to a cosine by the tables' matrix
// (specular, its Fresnel from the tables' magnitudes); none behind its
// face; windowed to its range
function areaLight(world:Vec3, n:Vec3, v:Vec3, rough:Float, albedo:Vec3, metalness:Float, f0:Vec3, pos:Vec4, color:Vec4, cone:Vec4, ltc:Texture2D):Vec3 {
	var c = pos.xyz;
	// (its normal: the row's packed octahedral place, FrameLights.packNormal)
	var packed = cone.w - 4194304;
	var qu = floor(packed / 2048);
	var qv = packed - qu * 2048;
	var ln = octDirection(vec2(qu, qv) / 2047 * 2 - 1);
	var result = vec3(0);
	if (dot(ln, world - c) > 0) {
		var right = cone.xyz;
		var r = normalize(right);
		var up = cross(ln, r);
		var rect = color.w < -0.75;
		var count = rect ? 4.0 : 8.0;
		var radius = length(right) * 1.0539889;
		var ru = rect ? right * 1.4142136 : r * radius;
		var uu = rect ? up * ((-1 - color.w) * 1.4142136) : up * radius;
		var nv = clamp(dot(n, v), 0, 1);
		var uv = vec2(rough, sqrt(1 - nv)) * 0.984375 + 0.0078125;
		var t1 = sampleLevel(ltc, vec2(uv.x, uv.y * 0.5), 0);
		var t2 = sampleLevel(ltc, vec2(uv.x, uv.y * 0.5 + 0.5), 0);
		var tx = normalize(v - n * dot(v, n) + vec3(0.0001, 0, 0));
		var ty = -cross(n, tx);
		var rel = c - world;
		var spec = ltcPolygon(rel, ru, uu, count, tx, ty, n, vec3(t1.x, 0, t1.y), vec3(t1.z, 0, t1.w));
		var diff = ltcPolygon(rel, ru, uu, count, tx, ty, n, vec3(1, 0, 0), vec3(0, 0, 1));
		var fresnel = f0 * t2.x + (1 - f0) * t2.y;
		var q = length(rel) / pos.w;
		var window = clamp(1 - q * q * q * q, 0, 1);
		result = color.xyz * (albedo * ((1 - metalness) * diff) + fresnel * spec) * (window * window);
	}
	return result;
}

// a polygon's (count vertices round rel, its centre from the point: ru and uu
// its axes to its vertices' circle) form factor through an LTC matrix (its
// columns m0, (0, 1, 0), m2) in the frame tx, ty, n: each edge's vector form
// factor summed, the clipped sphere's (three.js's LTC_ClippedSphereFormFactor)
function ltcPolygon(rel:Vec3, ru:Vec3, uu:Vec3, count:Float, tx:Vec3, ty:Vec3, n:Vec3, m0:Vec3, m2:Vec3):Float {
	var step = 6.2831853 / count;
	var a = ltcVertex(rel, ru, uu, 0.5 * step, tx, ty, n, m0, m2);
	var sum = vec3(0);
	var k = 1.0;
	while (k <= count) {
		var b = ltcVertex(rel, ru, uu, (k + 0.5) * step, tx, ty, n, m0, m2);
		sum += edgeFormFactor(a, b);
		a = b;
		k += 1;
	}
	var l = length(sum);
	return max((l * l + sum.z) / (l + 1), 0);
}

// a polygon's vertex at an angle, into the LTC's space, unit
function ltcVertex(rel:Vec3, ru:Vec3, uu:Vec3, angle:Float, tx:Vec3, ty:Vec3, n:Vec3, m0:Vec3, m2:Vec3):Vec3 {
	var p = rel + ru * cos(angle) + uu * sin(angle);
	var y = vec3(dot(tx, p), dot(ty, p), dot(n, p));
	return normalize(m0 * y.x + vec3(0, y.y, 0) + m2 * y.z);
}

// an edge's vector form factor between two unit vertices (three.js's
// LTC_EdgeVectorFormFactor: a fit of theta over sin theta)
function edgeFormFactor(a:Vec3, b:Vec3):Vec3 {
	var x = dot(a, b);
	var y = abs(x);
	var fa = 0.8543985 + (0.4965155 + 0.0145206 * y) * y;
	var fb = 3.417594 + (4.1616724 + y) * y;
	var v = fa / fb;
	var t = x > 0 ? v : 0.5 * inversesqrt(max(1 - x * x, 0.000001)) - v;
	return cross(a, b) * t;
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

// the sun's share at a point (1: lit) from its cascades' tiles of the
// atlas: the first cascade's where it reaches, else the second's; a 3x3
// percentage-closer filter, or the soft one (Shadows.soft); 1 outside
// them or without shadows (n: the surface's unit normal)
function shadowed(frame:PbrFrame, map:Texture2D, world:Vec3, n:Vec3):Float {
	var strength = frame.shadow.x;
	var result = 1.0;
	if (strength > 0) {
		var nl = max(dot(n, frame.lightDir.xyz), 0);
		var lit = cascade(map, frame.lightViewProj, frame.shadow, frame.shadowRect, frame.shadowAtlas, frame.shadowSoft, frame.shadowSoft.y, world, n, nl);
		if (lit < 0)
			lit = cascade(map, frame.lightViewProjFar, frame.shadowFar, frame.shadowRectFar, frame.shadowAtlas, frame.shadowSoft, frame.shadowSoft.z, world, n, nl);
		if (lit >= 0) result = 1 - strength * (1 - lit);
	}
	return result;
}

// a cascade's lit share (0 to 1) at a point, or -1 where its tile does not
// reach (params: y the bias, z a texel of the map, w the soft filter's
// widest radius in its uv; rect its tile in the atlas, inv a texel of the
// atlas; soft and deep: shadowSoft's, this map's depth a uv)
function cascade(map:Texture2D, viewProj:Mat4, params:Vec4, rect:Vec4, inv:Vec4, soft:Vec4, deep:Float, world:Vec3, n:Vec3, nl:Float):Float {
	var result = -1.0;
	var ls = viewProj * vec4(world, 1);
	var p = ls.xyz / ls.w;
	var uv = vec2(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5);
	if (uv.x > 0 && uv.x < 1 && uv.y > 0 && uv.y < 1 && p.z < 1) {
		// (more bias where the light grazes the surface)
		var depth = p.z - params.y * (1 + 2 * (1 - nl));
		var t = params.z;
		if (soft.x > 0 && params.w > 0) result = softly(map, uv, rect, inv, depth, params.w, t, soft, deep, plane(viewProj, n, deep));
		else
			result = (tap(map, uv, rect, inv, depth, -t, -t) + tap(map, uv, rect, inv, depth, 0, -t) + tap(map, uv, rect, inv, depth, t, -t)
				+ tap(map, uv, rect, inv, depth, -t, 0) + tap(map, uv, rect, inv, depth, 0, 0) + tap(map, uv, rect, inv, depth, t, 0)
				+ tap(map, uv, rect, inv, depth, -t, t) + tap(map, uv, rect, inv, depth, 0, t) + tap(map, uv, rect, inv, depth, t, t)) / 9;
	}
	return result;
}

// 1 where the tile's depth at uv + (dx, dy) is not nearer than depth
function tap(map:Texture2D, uv:Vec2, rect:Vec4, inv:Vec4, depth:Float, dx:Float, dy:Float):Float
	return step(depth, sampleLevel(map, atlasUv(uv + vec2(dx, dy), rect, inv), 0).x);

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
function softly(map:Texture2D, uv:Vec2, rect:Vec4, inv:Vec4, depth:Float, widest:Float, texel:Float, soft:Vec4, deep:Float, g:Vec2):Float {
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
			var d = sampleLevel(map, atlasUv(uv + off, rect, inv), 0).x;
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
			sum += step(margin + dot(g, off), sampleLevel(map, atlasUv(uv + off, rect, inv), 0).x);
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

// --- the glTF extensions' layers (PbrOptions' sheen, specular, clearcoat,
// transmission, iridescence and anisotropy; PhysicalShader's variants) ---

// a map of a layer (PbrMaterial's maps: 1 or 2 its image, layerMap0 or 1;
// 0 none: fallback, the map's neutral texel)
function layerMap(slot:Float, uv:Vec2, fallback:Vec4, t0:Texture2D, t1:Texture2D):Vec4 {
	var c = fallback;
	if (slot > 0.5) c = slot < 1.5 ? sample(t0, uv) : sample(t1, uv);
	return c;
}

// a dielectric's reflectance at normal incidence from its index of
// refraction (KHR_materials_ior: 1.5's, 0.04)
function iorF0(ior:Float):Float {
	var r = (ior - 1) / (ior + 1);
	return r * r;
}

// the metalness, roughness and emissive slots of a variant whose maps have
// their own uvs (uvSets: PhysicalShader's), pbr's at those uvs
function physicalMetalness(s:PbrSurface, p:{material:PbrMaterial, metallicRoughnessTexture:Texture2D}):Float
	return clamp(p.material.params.x * sample(p.metallicRoughnessTexture, s.uvMetallicRoughness).z, 0, 1);

function physicalRoughness(s:PbrSurface, p:{material:PbrMaterial, metallicRoughnessTexture:Texture2D}):Float
	return clamp(mix(p.material.params.y * sample(p.metallicRoughnessTexture, s.uvMetallicRoughness).y, 0.07, p.material.ground.z), 0.04, 1);

function physicalEmissive(s:PbrSurface, p:{material:PbrMaterial, emissiveTexture:Texture2D}):Vec3
	return p.material.emissive.xyz * pow(sample(p.emissiveTexture, s.uvEmissive).xyz, vec3(2.2));

// the physical direct slot (PhysicalShader's): one light's diffuse and
// specular (GGX, height-correlated Smith, Schlick's Fresnel from the
// specular layer's f0 and f90, the thin film's mixed in; anisotropic GGX
// with the anisotropy layer), the diffuse less what transmission lets
// through, a sheen's lobe over it (Charlie's distribution, Neubelt's
// visibility; the base dimmed by its albedo), then a clear coat's over all
// (its own normal and roughness, the base dimmed by its Fresnel)
function physicalDirect(s:LitSurface, l:LightSample, p:{material:PbrMaterial}):Vec3 {
	var n = s.normal;
	var v = s.view;
	var d = l.direction;
	var h = normalize(d + v);
	var nl = max(dot(n, d), 0);
	var nv = max(dot(n, v), 0.0001);
	var nh = max(dot(n, h), 0);
	var vh = max(dot(v, h), 0);
	var f0 = reflectance(s, p.material);
	var f90 = 1.0;
	if (s.specular > 0) {
		f0 = s.specularColor;
		f90 = s.specularWeight;
	}
	var fresnel = f0 + (f90 - f0) * pow(1 - vh, 5);
	if (s.iridescence > 0) fresnel = mix(fresnel, s.iridescenceFresnel, s.iridescence);
	var a = s.roughness * s.roughness;
	var a2 = a * a;
	var dd = nh * nh * (a2 - 1) + 1;
	var lobe = a2 / (3.14159265 * dd * dd) * (0.5 / max(nl * sqrt(nv * nv * (1 - a2) + a2) + nv * sqrt(nl * nl * (1 - a2) + a2), 0.0001));
	if (s.anisotropy > 0) lobe = anisotropic(s, d, h, a, nl, nv, nh);
	var diffuse = (1 - fresnel) * s.albedo * ((1 - s.metalness) / 3.14159265);
	if (s.transmission > 0) diffuse = diffuse * (1 - s.transmission);
	var c = (diffuse + fresnel * lobe) * nl;
	if (s.sheen > 0) c = c * (1 - 0.157 * s.sheen) + s.sheenColor * (charlie(s.sheenRoughness, nh) * neubelt(nv, nl) * nl);
	if (s.coat > 0) {
		var cn = s.coatNormal;
		var cr = s.coatRoughness * s.coatRoughness;
		var fc = (0.04 + 0.96 * pow(1 - max(dot(cn, v), 0), 5)) * s.coat;
		c = c * (1 - fc) + coatLobe(cn, v, d, cr * cr) * s.coat;
	}
	return c * l.radiance;
}

// the physical indirect slot: the irradiance's diffuse share (less what
// transmission lets through: the frame behind refracted through it instead,
// or the environment), the environment's reflection weighted by the split
// sum's fit (Karis') of the specular layer's f0 and f90 (the thin film's
// mixed in; along the anisotropy's bent normal), a sheen's (the irradiance
// times its albedo), then a clear coat's reflection over all
function physicalIndirect(s:LitSurface, env:IndirectLight,
		p:{material:PbrMaterial, frame:PbrFrame, environmentMap:Texture2D, transmissionMap:Texture2D}):Vec3 {
	var n = s.normal;
	var v = s.view;
	var nv = max(dot(n, v), 0.0001);
	var c0 = vec4(-1, -0.0275, -0.572, 0.022);
	var c1 = vec4(1, 0.0425, 1.04, -0.04);
	var rr = c0 * s.roughness + c1;
	var a004 = min(rr.x * rr.x, pow(2, -9.28 * nv)) * rr.x + rr.y;
	var ab = vec2(-1.04, 1.04) * a004 + rr.zw;
	var f0 = reflectance(s, p.material);
	var f90 = 1.0;
	if (s.specular > 0) {
		f0 = s.specularColor;
		f90 = s.specularWeight;
	}
	var specular = f0 * ab.x + vec3(f90 * ab.y);
	if (s.iridescence > 0) {
		// (the film's reflectance seen from the eye as an f0: Schlick's backwards)
		var k = pow(1 - nv, 5);
		var fi = clamp((s.iridescenceFresnel - vec3(k)) / max(1 - k, 0.0001), 0, 1);
		specular = mix(specular, fi * ab.x + vec3(f90 * ab.y), s.iridescence);
	}
	var radiance = env.radiance;
	if (s.anisotropy > 0) {
		// (the reflection about the normal bent towards the highlight's stretch)
		var bent = normalize(cross(cross(s.anisotropyBitangent, v), s.anisotropyBitangent));
		var w = 1 - s.anisotropy * (1 - s.roughness);
		w = w * w;
		bent = normalize(mix(bent, n, w * w));
		radiance = reflected(p.frame, p.environmentMap, reflect(-v, bent), s.roughness);
	}
	var diffuse = env.irradiance * s.albedo * (1 - s.metalness);
	if (s.transmission > 0)
		diffuse = mix(diffuse, transmitted(s, p.material, p.frame, p.environmentMap, p.transmissionMap) * (1 - specular), s.transmission * (1 - s.metalness));
	var c = (diffuse + radiance * specular) * env.occlusion;
	if (s.sheen > 0) c = c * (1 - 0.157 * s.sheen) + env.irradiance * s.sheenColor * (sheenAlbedo(nv, s.sheenRoughness) * env.occlusion);
	if (s.coat > 0) {
		var cn = s.coatNormal;
		var fc = (0.04 + 0.96 * pow(1 - max(dot(cn, v), 0), 5)) * s.coat;
		c = c * (1 - fc) + reflected(p.frame, p.environmentMap, reflect(-v, cn), s.coatRoughness) * (fc * env.occlusion);
	}
	return c;
}

// the light through a transmitting surface (KHR_materials_transmission,
// _volume): the view refracted by its ior through its thickness (0: thin,
// straight through), where it leaves read from the opaque frame behind
// (Transmission's, at the mip level of its roughness widened by the ior),
// else the environment along it; absorbed along the way (Beer's law: the
// attenuation colour at its distance), times the surface's colour
function transmitted(s:LitSurface, layers:PbrMaterial, frame:PbrFrame, environmentMap:Texture2D, transmissionMap:Texture2D):Vec3 {
	var ior = layers.coat.w;
	var i = -s.view;
	var eta = 1 / ior;
	var ni = dot(s.normal, i);
	var k = max(1 - eta * eta * (1 - ni * ni), 0);
	var r = normalize(i * eta - s.normal * (eta * ni + sqrt(k)));
	var exit = s.world + r * s.thickness;
	var rough = s.roughness * clamp(ior * 2 - 2, 0, 1);
	var light = vec3(0);
	if (layers.transmission.w > 0) {
		var c = frame.viewProj * vec4(exit, 1);
		var uv = vec2(c.x / c.w * 0.5 + 0.5, 0.5 - c.y / c.w * 0.5);
		light = sampleLevel(transmissionMap, uv, rough * layers.transmission.w).xyz;
		// (an 8-bit frame's colours encoded: decoded; the frame's exposure undone)
		if (frame.exposure.y < 0.5) light = pow(light, vec3(2.2));
		light = light / max(frame.exposure.x, 0.0001);
	} else
		light = reflected(frame, environmentMap, s.thickness > 0 ? r : i, rough);
	var absorbed = vec3(1);
	if (layers.transmission.z > 0) absorbed = pow(max(layers.attenuation.xyz, vec3(0.0001)), vec3(s.thickness / layers.transmission.z));
	return light * absorbed * s.albedo;
}

// Charlie's sheen distribution (Estevez and Kulla) at a roughness
function charlie(roughness:Float, nh:Float):Float {
	var a = max(roughness * roughness, 0.0049);
	var inv = 1 / a;
	var sin2 = max(1 - nh * nh, 0.0001);
	return (2 + inv) * pow(sin2, inv * 0.5) / 6.2831853;
}

// Neubelt's visibility for the sheen
function neubelt(nv:Float, nl:Float):Float
	return clamp(1 / (4 * (nl + nv - nl * nv)), 0, 1);

// a sheen's directional albedo under an even light (three.js' fit)
function sheenAlbedo(nv:Float, roughness:Float):Float {
	var r2 = roughness * roughness;
	var a = roughness < 0.25 ? -339.2 * r2 + 161.4 * roughness - 25.9 : -8.48 * r2 + 14.3 * roughness - 9.95;
	var b = roughness < 0.25 ? 44 * r2 - 23.7 * roughness + 3.26 : 1.97 * r2 - 3.27 * roughness + 0.72;
	var dg = exp(a * nv + b) + (roughness < 0.25 ? 0 : 0.1 * (roughness - 0.25));
	return clamp(dg / 3.14159265, 0, 1);
}

// the anisotropic GGX lobe, its distribution times visibility
// (KHR_materials_anisotropy: alpha along the stretch mixed to 1 by the
// strength squared, across it the roughness'), towards a unit light along d
function anisotropic(s:LitSurface, d:Vec3, h:Vec3, a:Float, nl:Float, nv:Float, nh:Float):Float {
	var t = s.anisotropyDirection;
	var b = s.anisotropyBitangent;
	var at = mix(a, 1, s.anisotropy * s.anisotropy);
	var ab = max(a, 0.0001);
	var th = dot(t, h);
	var bh = dot(b, h);
	var a2 = at * ab;
	var f = vec3(ab * th, at * bh, a2 * nh);
	var w2 = a2 / max(dot(f, f), 0.0001);
	var dist = a2 * w2 * w2 / 3.14159265;
	var vv = nl * length(vec3(at * dot(t, s.view), ab * dot(b, s.view), nv));
	var vl = nv * length(vec3(at * dot(t, d), ab * dot(b, d), nl));
	return dist * clamp(0.5 / max(vv + vl, 0.0001), 0, 1);
}

// a thin film's reflectance (KHR_materials_iridescence: Belcour and
// Barla's model, as the glTF sample viewer has it) seen at cosine c1 from
// outside (ior 1), the film of an ior and thickness (nm) over a base of
// reflectance f0; out of gamut colours clamped
function iridescent(filmIor:Float, c1:Float, thickness:Float, f0:Vec3):Vec3 {
	var film = mix(1, filmIor, smoothstep(0, 0.03, thickness));
	var sin2 = (1 / (film * film)) * (1 - c1 * c1);
	var cos2sq = 1 - sin2;
	var result = vec3(1);
	if (cos2sq >= 0) {
		var c2 = sqrt(cos2sq);
		var r0 = iorF0(film);
		var r12 = r0 + (1 - r0) * pow(1 - c1, 5);
		var t121 = 1 - r12;
		var phi12 = film < 1 ? 3.14159265 : 0;
		var phi21 = 3.14159265 - phi12;
		var root = sqrt(clamp(f0, vec3(0), vec3(0.9999)));
		var baseIor = (vec3(1) + root) / (1 - root);
		var q = (baseIor - vec3(film)) / (baseIor + vec3(film));
		var r1 = q * q;
		var r23 = r1 + (1 - r1) * pow(1 - c2, 5);
		var phi23 = vec3(baseIor.x < film ? 3.14159265 : 0, baseIor.y < film ? 3.14159265 : 0, baseIor.z < film ? 3.14159265 : 0);
		var opd = 2 * film * thickness * c2;
		var phi = vec3(phi21) + phi23;
		var r123 = clamp(r23 * r12, vec3(0.0001), vec3(0.9999));
		var amp = sqrt(r123);
		var rs = r23 * (t121 * t121) / (1 - r123);
		var cm = (rs - vec3(t121)) * amp;
		var sum = vec3(r12) + rs + cm * (sensitivity(opd, phi) * 2);
		cm = cm * amp;
		sum = sum + cm * (sensitivity(opd * 2, phi * 2) * 2);
		result = max(sum, vec3(0));
	}
	return result;
}

// the film's interference at an optical path (nm) and phase shift, in
// linear sRGB (the sample viewer's fit of the CIE matching functions, in
// micrometres)
function sensitivity(opd:Float, shift:Vec3):Vec3 {
	var phase = 6.2831853 * opd * 0.001;
	var xyz = vec3(0.84659, 1.0002219, 1.0011225) * cos(vec3(1.681, 1.7953, 2.2084) * phase + shift) * exp(vec3(-0.0043278, -0.0093046, -0.0066121) * (phase * phase));
	var x = xyz.x + 0.1538683 * cos(2.2399 * phase + shift.x) * exp(-0.0045282 * phase * phase);
	return vec3(3.2404542 * x - 1.5371385 * xyz.y - 0.4985314 * xyz.z, -0.969266 * x + 1.8760108 * xyz.y + 0.041556 * xyz.z,
		0.0556434 * x - 0.2040259 * xyz.y + 1.0572252 * xyz.z);
}

final pbr = slots({
	options: {
		normalMap: false,
		skinned: false,
		instanced: false,
		prepass: false,
		sheen: false,
		specular: false,
		clearcoat: false,
		transmission: false,
		iridescence: false,
		anisotropy: false,
		uvSets: false,
		// (the sun alone: no local lights' loop, for a frame without them,
		// the renderer's; a smaller stage, faster to compile)
		sunOnly: false,
		// (the local lights unshadowed: no tile read, for a frame none of
		// whose local lights casts, the renderer's; Android's emulator's
		// SwiftShader fails to compile the stage with the tiles' lookup)
		untiled: false,
		// (each a feature's, compiled only where a frame uses it: Probes',
		// AreaLights', Lightmap's)
		probes: false,
		area: false,
		lightmap: false
	},
	vertex: function(v:PbrVertex, p:PbrVertexParams, m:Pbr):PbrVaryings {
		var pos = m.position({pos: v.pos, normal: v.normal, uv: v.uv}, p);
		var nr = v.normal;
		if (m.options.skinned) {
			// (moved by its four joints' matrices, weighted; their count
			// PbrObject's tint.w: no block of the skin's, a slot kept for the
			// physical shaders' maps, sixteen in all)
			var j0 = joint(p.jointMatrices, v.joints.x, p.object.tint.w), j1 = joint(p.jointMatrices, v.joints.y, p.object.tint.w);
			var j2 = joint(p.jointMatrices, v.joints.z, p.object.tint.w), j3 = joint(p.jointMatrices, v.joints.w, p.object.tint.w);
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
			uv1: m.options.uvSets ? v.uv1 : vec2(0),
			tangent: m.options.normalMap ? vec4((model * vec4(v.tangent.xyz, 0)).xyz, v.tangent.w) : vec4(0),
			up: m.options.instanced ? v.m1.xyz : (model * vec4(0, 1, 0, 0)).xyz,
			tint: m.options.instanced ? vec3(1 + v.m0.w, 1 + v.m1.w, 1 + v.m2.w) : p.object.tint.xyz,
			// (the prepass lights nothing: its instanced variants bind no PbrObject)
			lights0: m.options.prepass ? vec4(-1) : p.object.lights0,
			lights1: m.options.prepass ? vec4(-1) : p.object.lights1,
			// (the light probes' irradiance along the vertex's normal, per vertex: their harmonics' polynomial)
			ambient: m.options.probes ? vec4(shIrradiance(p.probes.sh[0], p.probes.sh[1], p.probes.sh[2], p.probes.sh[3], p.probes.sh[4], p.probes.sh[5],
				p.probes.sh[6], normalize(m.options.instanced ? instanceNormal(v.m0.xyz, v.m1.xyz, v.m2.xyz, nr) : (p.object.normalMatrix * vec4(nr, 0)).xyz)),
				p.probes.extentB.w) : vec4(0),
			probeA: m.options.probes ? p.probes.probeA : vec4(0),
			extentA: m.options.probes ? p.probes.extentA : vec4(0),
			probeB: m.options.probes ? p.probes.probeB : vec4(0),
			extentB: m.options.probes ? p.probes.extentB : vec4(0),
			probeAtlas: m.options.probes ? p.probes.atlas : vec4(0),
			// (the lightmap's place at the second uvs)
			lightmapUv: m.options.lightmap ? vec4(v.uv1 * p.lightmap.rect.zw + p.lightmap.rect.xy, p.lightmap.params.x, p.lightmap.params.y) : vec4(0)
		};
	},
	fragment: function(i:PbrVaryings, p:PbrFragmentParams, m:Pbr):Vec4 {
		var ng = normalize(i.normal);
		var uv = uvOf(p.material, i.uv);
		// (uvSets: each core map at its own uvs)
		var uvNormal = uv;
		var uvOcclusion = uv;
		var uvMr = uv;
		var uvEm = uv;
		if (m.options.uvSets) {
			uv = uvSetOf(p.material.uvU, p.material.uvV, i.uv, i.uv1);
			uvNormal = uvSetOf(p.material.uvNormalU, p.material.uvNormalV, i.uv, i.uv1);
			uvOcclusion = uvSetOf(p.material.uvOcclusionU, p.material.uvOcclusionV, i.uv, i.uv1);
			uvMr = uvSetOf(p.material.uvMetallicRoughnessU, p.material.uvMetallicRoughnessV, i.uv, i.uv1);
			uvEm = uvSetOf(p.material.uvEmissiveU, p.material.uvEmissiveV, i.uv, i.uv1);
		}
		var n = ng;
		var t = vec3(0);
		var b = vec3(0);
		if (m.options.normalMap) {
			// (the tangent made at right angles to the interpolated normal;
			// the map's x and y scaled by the material's normal scale, the
			// bitangent n x t times the sign, green up the image: glTF's)
			t = normalize(i.tangent.xyz - ng * dot(ng, i.tangent.xyz));
			b = cross(ng, t) * i.tangent.w;
			var mapped = sample(p.normalTexture, m.options.uvSets ? uvNormal : uv).xyz * 2 - 1;
			var scale = p.material.params.z;
			n = normalize(t * (mapped.x * scale) + b * (mapped.y * scale) + ng * mapped.z);
		}
		var texel = sample(p.baseColorTexture, uv);
		var s:PbrSurface = {
			world: i.world,
			normal: n,
			uv: uv,
			up: normalize(i.up),
			baseColor: vec4(p.material.baseColor.xyz * pow(texel.xyz, vec3(2.2)), p.material.baseColor.w * texel.w),
			uvMetallicRoughness: m.options.uvSets ? uvMr : vec2(0),
			uvEmissive: m.options.uvSets ? uvEm : vec2(0)
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
			// (uvSets: the lit surface's uvs the occlusion map's, ambientAt's)
			var lit = litSurface(m.normal(s, p), s.world, m.options.uvSets ? uvOcclusion : uv, s.up, m.color(s, p) * i.tint, m.alpha(s, p), m.metalness(s, p),
				m.roughness(s, p), p.frame, p.material);
			if (m.options.sheen || m.options.specular || m.options.clearcoat || m.options.transmission || m.options.iridescence || m.options.anisotropy) {
				// (the glTF extensions' layers of the surface, those of the
				// variant's options: the material's and its maps, at its
				// uvs, in the normal map's tangent frame (else one made about
				// the normal); the others copied, read as nothing)
				var x = p.material;
				if (!m.options.normalMap) {
					t = normalize(cross(ng, abs(ng.y) < 0.9 ? vec3(0, 1, 0) : vec3(1, 0, 0)));
					b = cross(ng, t);
				}
				var sheenColor = vec3(0);
				var sheenRoughness = 0.0;
				if (m.options.sheen) {
					sheenColor = x.sheen.xyz * pow(layerMap(x.maps0.x, uv, vec4(1), p.layerMap0, p.layerMap1).xyz, vec3(2.2));
					sheenRoughness = clamp(x.sheen.w * layerMap(x.maps0.y, uv, vec4(1), p.layerMap0, p.layerMap1).w, 0, 1);
				}
				var f0 = vec3(0);
				var f90 = 1.0;
				if (m.options.specular) {
					// (the ior's reflectance tinted, scaled by the factor; a metal's its albedo)
					var weight = x.specular.w * layerMap(x.maps0.z, uv, vec4(1), p.layerMap0, p.layerMap1).w;
					var tint = x.specular.xyz * pow(layerMap(x.maps0.w, uv, vec4(1), p.layerMap0, p.layerMap1).xyz, vec3(2.2));
					f0 = mix(min(vec3(iorF0(x.coat.w)) * tint, vec3(1)) * weight, lit.albedo, lit.metalness);
					f90 = mix(weight, 1, lit.metalness);
				}
				var coat = 0.0;
				var coatRoughness = 0.0;
				var coatNormal = ng;
				if (m.options.clearcoat) {
					// (the coat's normal the geometry's, or its own map's)
					coat = x.coat.x * layerMap(x.maps1.x, uv, vec4(1), p.layerMap0, p.layerMap1).x;
					coatRoughness = clamp(x.coat.y * layerMap(x.maps1.y, uv, vec4(1), p.layerMap0, p.layerMap1).y, 0.04, 1);
					if (x.maps1.z > 0.5) {
						var cm = layerMap(x.maps1.z, uv, vec4(0.5, 0.5, 1, 1), p.layerMap0, p.layerMap1).xyz * 2 - 1;
						coatNormal = normalize(t * (cm.x * x.coat.z) + b * (cm.y * x.coat.z) + ng * cm.z);
					}
					if (p.material.params.w > 0.5 && dot(coatNormal, lit.view) < 0) coatNormal = -coatNormal;
				}
				var transmission = 0.0;
				var thickness = 0.0;
				if (m.options.transmission) {
					// (the thickness in the node's units: its up's length, its scale)
					transmission = x.transmission.x * layerMap(x.maps1.w, uv, vec4(1), p.layerMap0, p.layerMap1).x;
					thickness = x.transmission.y * layerMap(x.maps2.x, uv, vec4(1), p.layerMap0, p.layerMap1).y * length(i.up);
				}
				var iridescence = 0.0;
				var iridescenceFresnel = vec3(0);
				if (m.options.iridescence) {
					// (the film's thickness across its range by its map; none: no film)
					iridescence = x.iridescence.x * layerMap(x.maps2.y, uv, vec4(1), p.layerMap0, p.layerMap1).x;
					var film = mix(x.iridescence.z, x.iridescence.w, layerMap(x.maps2.z, uv, vec4(1), p.layerMap0, p.layerMap1).y);
					if (film <= 0) iridescence = 0;
					var base = m.options.specular ? f0 : reflectance(lit, p.material);
					iridescenceFresnel = iridescent(x.iridescence.y, max(dot(lit.normal, lit.view), 0.0001), film, base);
				}
				var anisotropy = 0.0;
				var direction = vec3(0);
				var across = vec3(0);
				if (m.options.anisotropy) {
					// (its map's direction in the tangent frame, turned by its
					// rotation, its strength times the map's blue)
					var am = layerMap(x.maps2.w, uv, vec4(1, 0.5, 1, 1), p.layerMap0, p.layerMap1);
					var dir = am.xy * 2 - 1;
					var turned = vec2(x.anisotropy.y * dir.x - x.anisotropy.z * dir.y, x.anisotropy.z * dir.x + x.anisotropy.y * dir.y);
					anisotropy = x.anisotropy.x * am.z;
					var ta = t * turned.x + b * turned.y;
					direction = normalize(ta - lit.normal * dot(lit.normal, ta));
					across = cross(lit.normal, direction);
				}
				var layered:LitSurface = {
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
					anisotropyBitangent: m.options.anisotropy ? across : lit.anisotropyBitangent
				};
				lit = layered;
			}
			// (the sun, then each local light the draw's list or the pixel's
			// cell names: the direct slot's, summed)
			var direct = m.direct(lit, sunLight(lit, p.frame, p.material, p.shadowMap), p);
			if (!m.options.sunOnly) {
				var cell = clusterCell(p.frame.viewProj, p.frame.eye, p.frame.clusters, p.frame.clusterDepth, p.frame.clusterAxis, p.clusterMap, s.world);
				// (a list ends at its first -1: a draw lit by none loops not at all)
				var k = 0.0;
				var index = lightIndex(p.frame.clusters, p.frame.clusterDepth, i.lights0, i.lights1, p.clusterMap, cell, k);
				while (k < cell.z && index >= 0) {
					// (the light's row, its shadow: read here, the arrays not passed on)
					var pos = vec4(0);
					var color = vec4(0);
					var cone = vec4(0);
					if (p.frame.clusters.x > 0) {
						pos = lightRow(p.clusterMap, 0, index, p.frame.clusterAxis, p.frame.clusterDepth);
						color = lightRow(p.clusterMap, 4, index, p.frame.clusterAxis, p.frame.clusterDepth);
						cone = lightRow(p.clusterMap, 8, index, p.frame.clusterAxis, p.frame.clusterDepth);
					} else {
						pos = lightTexel(p.lights, 0, index);
						color = lightTexel(p.lights, 1, index);
						cone = lightTexel(p.lights, 2, index);
					}
					var shadow = 1.0;
					// (untiled: no local light casts this frame, no tile read)
					if (!m.options.untiled) {
						if (color.w > 0.5) {
							// (its first tile's row: 32 on, colour's w 1 plus the tile)
							var first = 31 + color.w;
							var params = lightTexel(p.lights, 5, first);
							var at = shadowPoint(lit.world, lit.normal, pos.xyz, params);
							var tile = first + tileFace(at, pos.xyz, dot(cone.xyz, cone.xyz) < 0.0001);
							shadow = tileShadow(p.shadowMap, tileMatrix(p.lights, tile), lightTexel(p.lights, 4, tile), params, p.frame.shadowAtlas, at);
						}
					}
					// (area: a rect or disc light (colour's w below 0) by LTC; else, and
					// in the variants without area lights, a point light)
					if (m.options.area && color.w < -0.25) direct += areaLight(lit.world, lit.normal, lit.view, lit.roughness, lit.albedo, lit.metalness,
						reflectance(lit, p.material), pos, color, cone, p.ltcMap);
					else direct += m.direct(lit, localLight(lit.world, lit.normal, pos, color, cone, shadow), p);
					k += 1;
					index = lightIndex(p.frame.clusters, p.frame.clusterDepth, i.lights0, i.lights1, p.clusterMap, cell, k);
				}
			}
			var env = ambientAt(lit, p.frame, p.material, p.occlusionTexture, p.environmentMap, p.aoMap);
			// (probes: the light probes' irradiance, the reflection probes' light)
			if (m.options.probes) env = probeLight(env, lit.world, lit.normal, lit.view, lit.roughness, i.ambient, i.probeA, i.extentA, i.probeB, i.extentB,
				p.probesMap, i.probeAtlas);
			// (lightmap: its baked light the irradiance; All: the lights' too, none added)
			if (m.options.lightmap) {
				var baked = sample(p.lightMap, i.lightmapUv.xy).xyz;
				if (i.lightmapUv.w > 1.5) baked = pow(baked, vec3(2.2));
				env = {irradiance: baked * i.lightmapUv.z, radiance: env.radiance, occlusion: env.occlusion};
				// (the mode rounded: an interpolated 2 may be just below it)
				var mode = floor(i.lightmapUv.w + 0.5);
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
	position: pbrPosition
});

// the standard material, its plain variant
final PbrShader = pbr.gpuVariant();

// the standard material lit by the sun alone (the renderer's, for a frame
// without local lights: no light loop to compile)
final PbrSunShader = pbr.gpuVariant({sunOnly: true});

// the standard material, its local lights unshadowed (the renderer's, for
// a frame none of whose local lights casts: no tile read)
final PbrUntiledShader = pbr.gpuVariant({untiled: true});
