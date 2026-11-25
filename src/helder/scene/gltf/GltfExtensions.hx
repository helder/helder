package helder.scene.gltf;

import helder.math.Vec2;
import helder.math.Vec3;
import helder.scene.gltf.GltfDoc;
import helder.scene.render.Material;

// The glTF material extensions beyond the core (KHR_materials_sheen,
// _specular, _ior, _volume, _iridescence, _anisotropy, clearcoat's and
// transmission's maps) and each core map's own uvs (TEXCOORD_1, a
// KHR_texture_transform a map), read into GltfMaterial.layers and set on
// GltfScene's materials, once installed: by Physical (a model loaded at
// run time) and by Model.of for a file whose materials use some (its
// PhysicalShader sets). A program whose models use none reads and links
// none of it.
class GltfExtensions implements GltfDoc.LayerReader implements ExtensionApplier {
	function new() {}

	// read from now on (Gltf.parse's, GltfScene's)
	public static function install()
		if (Gltf.extensions == null) {
			var x = new GltfExtensions();
			Gltf.extensions = x;
			GltfScene.extensions = x;
		}

	public function read(m:Dynamic, ext:Dynamic, tex:(Dynamic, String) -> Int):GltfLayers {
		inline function obj(o:Dynamic, f:String):Dynamic
			return @:privateAccess Gltf.obj(o, f);
		inline function num(o:Dynamic, f:String, d:Float):Float
			return @:privateAccess Gltf.num(o, f, d);
		inline function int(o:Dynamic, f:String, d:Int):Int
			return @:privateAccess Gltf.int(o, f, d);
		inline function floats(o:Dynamic, f:String):Null<Array<Float>>
			return @:privateAccess Gltf.floats(o, f);
		var pbr = obj(m, "pbrMetallicRoughness");
		var coat = obj(ext, "KHR_materials_clearcoat"), transmission = obj(ext, "KHR_materials_transmission");
	// (each core map's own: texCoord and transform)
	var maps:Array<Null<GltfMap>> = [
		for (t in [obj(pbr, "baseColorTexture"), obj(pbr, "metallicRoughnessTexture"), obj(m, "normalTexture"), obj(m, "occlusionTexture"), obj(m, "emissiveTexture")]) {
			if (t == null) null else {
				var x = obj(obj(t, "extensions"), "KHR_texture_transform");
				var o = floats(x, "offset"), s = floats(x, "scale");
				({
					texCoord: int(x, "texCoord", int(t, "texCoord", 0)),
					offset: o != null && o.length == 2 ? new Vec2(o[0], o[1]) : new Vec2(0, 0),
					rotation: num(x, "rotation", 0),
					scale: s != null && s.length == 2 ? new Vec2(s[0], s[1]) : new Vec2(1, 1)
				} : GltfMap);
			}
		}
	];
	// (the other extensions: KHR_materials_volume, _ior, _specular, _sheen, _iridescence, _anisotropy)
	var layers:GltfLayers = {};
		layers.maps = maps;
	if (ext != null) layers.used = [for (k in Reflect.fields(ext)) k];
	function color(o:Dynamic, f:String, d:Vec3):Vec3 {
		var c = floats(o, f);
		return c != null && c.length == 3 ? new Vec3(c[0], c[1], c[2]) : d;
	}
	layers.clearcoatTexture = tex(coat, "clearcoatTexture");
	layers.clearcoatRoughnessTexture = tex(coat, "clearcoatRoughnessTexture");
	layers.clearcoatNormalTexture = tex(coat, "clearcoatNormalTexture");
	layers.clearcoatNormalScale = num(obj(coat, "clearcoatNormalTexture"), "scale", 1);
	layers.transmissionTexture = tex(transmission, "transmissionTexture");
	var volume = obj(ext, "KHR_materials_volume");
	layers.thickness = num(volume, "thicknessFactor", 0);
	layers.thicknessTexture = tex(volume, "thicknessTexture");
	layers.attenuationColor = color(volume, "attenuationColor", new Vec3(1, 1, 1));
	layers.attenuationDistance = num(volume, "attenuationDistance", 0);
	layers.ior = num(obj(ext, "KHR_materials_ior"), "ior", 1.5);
	var specular = obj(ext, "KHR_materials_specular");
	layers.specularFactor = num(specular, "specularFactor", 1);
	layers.specularColor = color(specular, "specularColorFactor", new Vec3(1, 1, 1));
	layers.specularTexture = tex(specular, "specularTexture");
	layers.specularColorTexture = tex(specular, "specularColorTexture");
	var sheen = obj(ext, "KHR_materials_sheen");
	layers.sheenColor = color(sheen, "sheenColorFactor", new Vec3(0, 0, 0));
	layers.sheenRoughness = num(sheen, "sheenRoughnessFactor", 0);
	layers.sheenColorTexture = tex(sheen, "sheenColorTexture");
	layers.sheenRoughnessTexture = tex(sheen, "sheenRoughnessTexture");
	var iridescence = obj(ext, "KHR_materials_iridescence");
	layers.iridescence = num(iridescence, "iridescenceFactor", 0);
	layers.iridescenceIor = num(iridescence, "iridescenceIor", 1.3);
	layers.iridescenceThicknessMinimum = num(iridescence, "iridescenceThicknessMinimum", 100);
	layers.iridescenceThicknessMaximum = num(iridescence, "iridescenceThicknessMaximum", 400);
	layers.iridescenceTexture = tex(iridescence, "iridescenceTexture");
	layers.iridescenceThicknessTexture = tex(iridescence, "iridescenceThicknessTexture");
	var anisotropy = obj(ext, "KHR_materials_anisotropy");
	layers.anisotropy = num(anisotropy, "anisotropyStrength", 0);
	layers.anisotropyRotation = num(anisotropy, "anisotropyRotation", 0);
	layers.anisotropyTexture = tex(anisotropy, "anisotropyTexture");
		return layers;
	}

	// a material made of a glTF one (GltfScene's) given its layers
	public function apply(mat:Material, m:GltfMaterial, textureOf:Int->Null<helder.gfx.Texture>) {
		var x = m.layers;
		if (x == null) return;
		mat.clearcoatTexture = textureOf(x.clearcoatTexture);
		mat.clearcoatRoughnessTexture = textureOf(x.clearcoatRoughnessTexture);
		mat.clearcoatNormalTexture = textureOf(x.clearcoatNormalTexture);
		mat.clearcoatNormalScale = x.clearcoatNormalScale;
		mat.transmissionTexture = textureOf(x.transmissionTexture);
		mat.thickness = x.thickness;
		mat.thicknessTexture = textureOf(x.thicknessTexture);
		mat.attenuationColor = x.attenuationColor;
		mat.attenuationDistance = x.attenuationDistance;
		mat.ior = x.ior;
		mat.specularFactor = x.specularFactor;
		mat.specularColor = x.specularColor;
		mat.specularTexture = textureOf(x.specularTexture);
		mat.specularColorTexture = textureOf(x.specularColorTexture);
		mat.sheenColor = x.sheenColor;
		mat.sheenRoughness = x.sheenRoughness;
		mat.sheenColorTexture = textureOf(x.sheenColorTexture);
		mat.sheenRoughnessTexture = textureOf(x.sheenRoughnessTexture);
		mat.iridescence = x.iridescence;
		mat.iridescenceIor = x.iridescenceIor;
		mat.iridescenceThicknessMinimum = x.iridescenceThicknessMinimum;
		mat.iridescenceThicknessMaximum = x.iridescenceThicknessMaximum;
		mat.iridescenceTexture = textureOf(x.iridescenceTexture);
		mat.iridescenceThicknessTexture = textureOf(x.iridescenceThicknessTexture);
		mat.anisotropy = x.anisotropy;
		mat.anisotropyRotation = x.anisotropyRotation;
		mat.anisotropyTexture = textureOf(x.anisotropyTexture);
		// (each core map its own uvs, where they differ: uvSets)
		if (helder.scene.render.PhysicalShader.uvSets([
			for (t in x.maps) t == null ? null : [t.texCoord, t.offset.x, t.offset.y, t.rotation, t.scale.x, t.scale.y]
		]))
			mat.textureTransforms = [
				for (k in 0...5) {
					var t = k < x.maps.length ? x.maps[k] : null;
					t == null ? new UvTransform() : new UvTransform(t.offset, t.rotation, t.scale, t.texCoord);
				}
			];
	}

	// a primitive's second uvs (its material's maps on them: TEXCOORD_1,
	// else the first), two floats a vertex; null: none needed
	public function secondUvs(doc:GltfDoc, p:GltfPrimitive, material:Material, count:Int, first:Null<Array<Float>>):Null<haxe.io.Bytes> {
		if (material.textureTransforms == null) return null;
		var second = p.texcoord1 >= 0 ? doc.floats(p.texcoord1) : first;
		var b = haxe.io.Bytes.alloc(count * 8);
		if (second != null)
			for (k in 0...count * 2)
				b.setFloat(4 * k, second[k]);
		return b;
	}
}

// (GltfScene.extensions: GltfExtensions, through an interface: linked when installed)
interface ExtensionApplier {
	function apply(mat:Material, m:GltfMaterial, textureOf:Int->Null<helder.gfx.Texture>):Void;
	function secondUvs(doc:GltfDoc, p:GltfPrimitive, material:Material, count:Int, first:Null<Array<Float>>):Null<haxe.io.Bytes>;
}
