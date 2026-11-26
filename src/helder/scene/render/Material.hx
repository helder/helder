package helder.scene.render;

import helder.gfx.Texture;
import helder.math.Vec2;
import helder.math.Vec3;
import helder.math.Vec4;

// A surface of glTF's metallic-roughness model: base colour (linear,
// times the texture's sRGB colour when there is one), metallic and
// roughness from 0 to 1, emitted light (linear); double-sided ones are
// drawn without back-face culling.
//
// Its shading model is its shader's (helder.scene.render.shading), chosen
// by the factory it is made with, three.js's materials by name:
//
//   Material.standard({...})   pbr, the default (MeshStandardMaterial; new Material(...))
//   Material.lambert({...})    a light's diffuse alone (MeshLambertMaterial): the cheap lit one for phones
//   Material.phong({...})      Blinn-Phong (MeshPhongMaterial), shininess as three's
//   Material.toon({...})       light in steps bands, the shade away from it (MeshToonMaterial)
//   Material.unlit({...})      the colour alone, no light (MeshBasicMaterial)
//   Material.matcap({...})     a lit sphere's picture by the normal (MeshMatcapMaterial)
//   Material.normals()         the normal in view space as a colour (MeshNormalMaterial)
//   Material.depth(near, far)  the view's depth as a grey (MeshDepthMaterial)
//
// The lit ones keep pbr's shadows, lights, fog and normal maps (only how a
// light reaches the surface differs); the unlit ones read no light. A
// factory references its model's shader alone, so a program that never
// calls Material.toon links no toon shader.
class Material {
	static var count = 0;

	// the material's index (draws sort by it; an index into a material buffer later)
	public final id:Int = count++;

	public var name:String;
	public var baseColor:Vec4;
	public var metallic:Float;
	public var roughness:Float;
	public var emissive:Vec3;
	public var baseColorTexture:Null<Texture>;
	// glTF's other maps: roughness (green) and metallic (blue), times the
	// factors; emitted colour (sRGB), times emissive; ambient occlusion (red)
	public var metallicRoughnessTexture:Null<Texture>;
	public var emissiveTexture:Null<Texture>;
	public var occlusionTexture:Null<Texture>;
	// a tangent-space normal map (drawn with NormalMaps, on primitives with
	// tangents), its x and y scaled by normalScale
	public var normalTexture:Null<Texture>;
	public var normalScale = 1.0;
	public var doubleSided:Bool;
	// how its textures are read (null: the renderer's: linear, mip-mapped,
	// repeating; glTF's samplers otherwise)
	public var sampler:Null<helder.gfx.Sampler>;
	// see-through (glTF's alphaMode BLEND): blended over what is behind,
	// drawn after the opaque surfaces, farthest first, without writing
	// depth; by the base colour's alpha (Alpha), added to what is behind
	// (Additive: glows, holograms, beams; faded by its alpha), premultiplied
	// or multiplied; None (the default): opaque
	public var blend(default, set):MaterialBlend = None;
	// (blend not None, and its pipelines' blending: the renderer's loops read these)
	@:noCompletion public var blended(default, null) = false;
	@:noCompletion public var blending(default, null):helder.gfx.Blend = Alpha;

	function set_blend(b:MaterialBlend):MaterialBlend {
		blended = b != None;
		blending = switch b {
			case Additive: Additive;
			case Premultiplied: Premultiplied;
			case Multiply: Multiply;
			case _: Alpha;
		}
		return blend = b;
	}
	// whether it casts a shadow (Shadows: its primitives drawn into the map,
	// their meshes inside the map's bounds); off for glows and glass
	public var castShadows = true;
	// whether the renderer's fog (Renderer.fog) covers it (off: a glow or
	// a sign that cuts through it)
	public var fog = true;
	// how much of its light it emits only on its night side (0: all of it
	// everywhere, 1: none where the sun shines; city lights on a planet),
	// faded across the terminator
	public var emissiveNight = 0.0;
	// how much it stands on a sphere whose outward normal is its node's up
	// (local +y: a building on a planet, a tree on a globe): 1 and the sun
	// sets on it as on that ground, its direct light and rim faded across
	// the sphere's terminator, so it darkens with its planet's night side
	// (0: lit by its own faces alone)
	public var ground = 0.0;
	// the air between it and the eye (aerial perspective), with ground's
	// up: rgb its colour (linear), w how much at most, reached towards the
	// sphere's limb (where its up turns from the eye), lit by the sun over
	// that ground (0: none)
	public var air = new Vec4(0, 0, 0, 0);
	// how much it is a crystal (0 to 1): polished (roughness 0.07) and a
	// gem's reflectance, the environment's reflection and the rim light
	// strong at grazing angles (Fresnel), lit from inside by its emissive
	// colour lifted towards white, most where it faces the eye (a fake
	// subsurface), the sun through it from behind; its edges opaque, its
	// middle as see-through as its base colour's alpha with blend on
	// (Additive's an additive glass). Faceted by its normals: give its
	// facets flat ones (vertices not shared across their edges)
	public var crystal = 0.0;
	// glTF's KHR_texture_transform: the uvs its textures are read at turned
	// by uvRotation (radians), scaled by uvScale, then moved by uvOffset
	// (one transform for all of a material's textures)
	public var uvOffset = new Vec2(0, 0);
	public var uvRotation = 0.0;
	public var uvScale = new Vec2(1, 1);
	// each core map's own uvs (glTF: a texture's texCoord, TEXCOORD_0 or
	// _1, and its own KHR_texture_transform), in order base colour,
	// metallic-roughness, normal, occlusion, emissive (the extensions' maps
	// read the base colour's); null: the transform above for all, on the
	// first uvs. Drawn by a physical shader (PhysicalShader's uvSets), its
	// primitives' second uvs their own buffer (Mesh.Primitive.uv1)
	public var textureTransforms:Null<Array<UvTransform>> = null;
	// glTF's alphaMode MASK: fragments whose alpha is below it are dropped,
	// the rest opaque (0: none)
	public var alphaCutoff = 0.0;
	// a shader of its own (MaterialShader.material: pbr with slots
	// replaced), null: the standard one; the blocks of its own, by their
	// parameters' names (its slots' parameters the standard ones are not)
	public var shader:Null<MaterialShader> = null;
	public var uniforms:Null<Map<String, haxe.io.Bytes>> = null;
	// a clear coat over the surface (KHR_materials_clearcoat): how much (0
	// to 1) and its roughness; a polished dielectric layer (f0 0.04) whose
	// reflection, from the sun and the environment, is added over the base
	// and dims it by its Fresnel. With a physical shader (PhysicalShader:
	// Model.of's, or Physical's for any material) each light's, and its maps:
	// clearcoatTexture's red times clearcoat, clearcoatRoughnessTexture's
	// green times its roughness, clearcoatNormalTexture its own normal map
	// (its x and y scaled by clearcoatNormalScale; else the geometry's normal)
	public var clearcoat = 0.0;
	public var clearcoatRoughness = 0.0;
	public var clearcoatTexture:Null<Texture>;
	public var clearcoatRoughnessTexture:Null<Texture>;
	public var clearcoatNormalTexture:Null<Texture>;
	public var clearcoatNormalScale = 1.0;
	// how much of the light goes through it (KHR_materials_transmission, 0
	// to 1; transmissionTexture's red times it): its diffuse light replaced
	// by what is behind it (drawn see-through, Premultiplied, after the
	// opaque surfaces), its reflections kept. The standard shader's: a thin
	// surface, what is behind tinted by its colour; a physical shader's:
	// what is behind refracted through it (the opaque frame with
	// Transmission, else the environment), blurred by its roughness
	public var transmission = 0.0;
	public var transmissionTexture:Null<Texture>;
	// its volume (KHR_materials_volume, a physical shader's): how thick it
	// is (in its node's units, 0: thin; thicknessTexture's green times it),
	// and the light it absorbs on the way through: attenuationColor reached
	// at attenuationDistance (0: none, glTF's infinity), Beer's law
	public var thickness = 0.0;
	public var thicknessTexture:Null<Texture>;
	public var attenuationColor = new Vec3(1, 1, 1);
	public var attenuationDistance = 0.0;
	// its index of refraction (KHR_materials_ior: 1.5, a dielectric's 0.04
	// reflectance at normal incidence), and that reflectance's strength and
	// colour (KHR_materials_specular: specularTexture's alpha times
	// specularFactor, specularColorTexture's colour, sRGB, times
	// specularColor; a metal's is its albedo); a physical shader's
	public var ior = 1.5;
	public var specularFactor = 1.0;
	public var specularColor = new Vec3(1, 1, 1);
	public var specularTexture:Null<Texture>;
	public var specularColorTexture:Null<Texture>;
	// a sheen over it (KHR_materials_sheen, cloth's and velvet's: black for
	// none), its colour (linear; sheenColorTexture's, sRGB, times it) and
	// roughness (sheenRoughnessTexture's alpha times it); a physical shader's
	public var sheenColor = new Vec3(0, 0, 0);
	public var sheenRoughness = 0.0;
	public var sheenColorTexture:Null<Texture>;
	public var sheenRoughnessTexture:Null<Texture>;
	// a thin film over it (KHR_materials_iridescence: soap bubbles, oil):
	// how much (iridescenceTexture's red times it), the film's index of
	// refraction and thickness in nanometres (iridescenceThicknessTexture's
	// green from the minimum to the maximum); a physical shader's
	public var iridescence = 0.0;
	public var iridescenceIor = 1.3;
	public var iridescenceThicknessMinimum = 100.0;
	public var iridescenceThicknessMaximum = 400.0;
	public var iridescenceTexture:Null<Texture>;
	public var iridescenceThicknessTexture:Null<Texture>;
	// its highlight stretched (KHR_materials_anisotropy: brushed metal):
	// how much (0 to 1), along the tangent turned by anisotropyRotation
	// (radians), or anisotropyTexture's direction (red and green) and
	// strength (blue, times anisotropy); drawn with its primitive's
	// tangents (NormalMaps); a physical shader's
	public var anisotropy = 0.0;
	public var anisotropyRotation = 0.0;
	public var anisotropyTexture:Null<Texture>;
	// the toon model's (Material.toon): bands of each light's n.l (1 or
	// more), and the shaded side's share of the albedo (linear)
	public var steps = 3;
	public var shade = new Vec3(0.4, 0.4, 0.5);
	// tone mapped as the target takes it (three's toneMapped); false: its
	// colour shown as it is, only encoded for an 8-bit target (the debug
	// views: Material.normals, Material.depth)
	public var toneMapped = true;
	// Material.depth's range along the camera's view: white at depthNear,
	// black at depthFar (scene units)
	public var depthNear = 0.1;
	public var depthFar = 100.0;

	public function new(?name:String, ?baseColor:Vec4, metallic = 0.0, roughness = 0.5, ?emissive:Vec3, doubleSided = false) {
		this.name = name != null ? name : "";
		this.baseColor = baseColor != null ? baseColor : new Vec4(1, 1, 1, 1);
		this.metallic = metallic;
		this.roughness = roughness;
		this.emissive = emissive != null ? emissive : new Vec3(0, 0, 0);
		this.doubleSided = doubleSided;
	}

	// the standard material (pbr: three's MeshStandardMaterial), made from options
	public static function standard(?options:MaterialOptions):Material
		return made(options);

	// Lambert's (three's MeshLambertMaterial): each light's diffuse alone,
	// the ambient's diffuse alone; no highlight, no reflection
	public static function lambert(?options:MaterialOptions):Material {
		var m = made(options);
		m.shader = helder.scene.render.shading.Lambert.LambertShader;
		return m;
	}

	// Blinn-Phong (three's MeshPhongMaterial): a highlight of shininess
	// (three's: 30 by default), kept as the roughness that lobe matches
	// (shading's Phong), the reflections pbr's
	public static function phong(?options:PhongOptions):Material {
		var m = made(options);
		var shininess = options != null && options.shininess != null ? options.shininess : 30.0;
		m.roughness = Math.pow(2 / (Math.max(shininess, 0) + 2), 0.25);
		m.shader = helder.scene.render.shading.Phong.PhongShader;
		return m;
	}

	// toon shading (three's MeshToonMaterial): each light in steps bands
	// (3 by default), its shadow banded with it, the side away from every
	// light the albedo times shade (linear)
	public static function toon(?options:ToonOptions):Material {
		var m = made(options);
		if (options != null) {
			if (options.steps != null) m.steps = options.steps;
			if (options.shade != null) m.shade = options.shade;
		}
		m.shader = helder.scene.render.shading.Toon.ToonShader;
		return m;
	}

	// no light (three's MeshBasicMaterial): the colour times its texture,
	// tinted and fogged
	public static function unlit(?options:MaterialOptions):Material {
		var m = made(options);
		m.castShadows = options != null && options.castShadows != null ? options.castShadows : false;
		m.shader = helder.scene.render.shading.Unlit.UnlitShader;
		return m;
	}

	// a matcap (three's MeshMatcapMaterial): the picture of a lit sphere
	// (an sRGB image: matcap, kept as the emissiveTexture) read by the
	// normal as the eye sees it, times the colour
	public static function matcap(options:MatcapOptions):Material {
		var m = made(options);
		m.emissiveTexture = options.matcap;
		m.shader = helder.scene.render.shading.Matcap.MatcapShader;
		return m;
	}

	// the normal in view space as a colour (three's MeshNormalMaterial),
	// not tone mapped
	public static function normals(?options:MaterialOptions):Material {
		var m = made(options);
		m.toneMapped = options != null && options.toneMapped != null ? options.toneMapped : false;
		m.shader = helder.scene.render.shading.Normals.NormalsShader;
		return m;
	}

	// the depth along the view as a grey, white at near and black at far
	// (three's MeshDepthMaterial, linear), not tone mapped
	public static function depth(near = 0.1, far = 100.0, ?options:MaterialOptions):Material {
		var m = made(options);
		m.depthNear = near;
		m.depthFar = far;
		m.toneMapped = options != null && options.toneMapped != null ? options.toneMapped : false;
		m.shader = helder.scene.render.shading.Depth.DepthShader;
		return m;
	}

	// the glTF extensions its fields use (PhysicalShader's options, as
	// flags: SHEEN, SPECULAR, CLEARCOAT, TRANSMISSION, IRIDESCENCE,
	// ANISOTROPY; 0: none, the standard shader's surface); what Physical
	// draws it with
	public function extensions():Int
		return PhysicalShader.flags(sheenColor.x, sheenColor.y, sheenColor.z, ior, specularFactor, specularColor.x, specularColor.y, specularColor.z,
			specularTexture != null || specularColorTexture != null, clearcoat, transmission, iridescence, anisotropy, textureTransforms != null);

	// whether it is drawn with its primitives' tangents (a normal map, the
	// clear coat's own, an anisotropy: NormalMaps)
	public function tangents():Bool
		return normalTexture != null || (clearcoat > 0 && clearcoatNormalTexture != null) || anisotropy > 0;

	public static inline var SHEEN = 1;
	public static inline var SPECULAR = 2;
	public static inline var CLEARCOAT = 4;
	public static inline var TRANSMISSION = 8;
	public static inline var IRIDESCENCE = 16;
	public static inline var ANISOTROPY = 32;
	public static inline var UV_SETS = 64;

	// (a material of the options given, the others the defaults)
	static function made(o:Null<MaterialOptions>):Material {
		var m = new Material();
		if (o == null) return m;
		if (o.name != null) m.name = o.name;
		if (o.color != null) m.baseColor = o.color;
		if (o.texture != null) m.baseColorTexture = o.texture;
		if (o.metallic != null) m.metallic = o.metallic;
		if (o.roughness != null) m.roughness = o.roughness;
		if (o.emissive != null) m.emissive = o.emissive;
		if (o.doubleSided != null) m.doubleSided = o.doubleSided;
		if (o.blend != null) m.blend = o.blend;
		if (o.alphaCutoff != null) m.alphaCutoff = o.alphaCutoff;
		if (o.fog != null) m.fog = o.fog;
		if (o.castShadows != null) m.castShadows = o.castShadows;
		if (o.toneMapped != null) m.toneMapped = o.toneMapped;
		return m;
	}
}

// a map's uvs (Material.textureTransforms): TEXCOORD_0 or _1 (texCoord),
// turned by rotation (radians), scaled, then moved (KHR_texture_transform)
class UvTransform {
	public var offset:Vec2;
	public var rotation:Float;
	public var scale:Vec2;
	public var texCoord:Int;

	public function new(?offset:Vec2, rotation = 0.0, ?scale:Vec2, texCoord = 0) {
		this.offset = offset != null ? offset : new Vec2(0, 0);
		this.rotation = rotation;
		this.scale = scale != null ? scale : new Vec2(1, 1);
		this.texCoord = texCoord;
	}
}

// what a material is made from (Material's factories): each field the
// material's of the same meaning, its default where not given (color the
// base colour, linear; texture the base colour's, sRGB)
typedef MaterialOptions = {
	?name:String,
	?color:Vec4,
	?texture:Texture,
	?metallic:Float,
	?roughness:Float,
	?emissive:Vec3,
	?doubleSided:Bool,
	?blend:MaterialBlend,
	?alphaCutoff:Float,
	?fog:Bool,
	?castShadows:Bool,
	?toneMapped:Bool
}

// Material.toon's: also its bands and its shade
typedef ToonOptions = {
	> MaterialOptions,
	?steps:Int,
	?shade:Vec3
}

// Material.phong's: also three's shininess (30 by default)
typedef PhongOptions = {
	> MaterialOptions,
	?shininess:Float
}

// Material.matcap's: also the matcap, a lit sphere's picture (sRGB)
typedef MatcapOptions = {
	> MaterialOptions,
	matcap:Texture
}
