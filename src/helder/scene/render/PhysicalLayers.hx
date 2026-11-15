package helder.scene.render;

import helder.gfx.*;
import helder.gfx.shader.Vec4;
import helder.scene.render.PbrShader;

// A physical shader's material data (PhysicalShader's: MaterialShader.layers):
// the glTF extensions' fields into the material's block (PbrMaterial's),
// their maps in two images (the first two distinct ones: a third's maps
// left out), and the opaque frame behind (Transmission's) bound. Reached
// through the shader, so a program drawing no physical shader links none
// of it.
class PhysicalLayers implements RenderFeature.LayerSource {
	public static final INSTANCE = new PhysicalLayers();

	// (the maps' images: their ids, -1 none)
	final ids = [-1, -1];

	function new() {}

	public function block(m:Material, out:PbrMaterial, behind:Float) {
		// (the clear coat and transmission the layers', not the standard's)
		out.layers = new Vec4(0, out.layers.y, 0, out.layers.w);
		out.sheen = new Vec4(m.sheenColor.x, m.sheenColor.y, m.sheenColor.z, m.sheenRoughness);
		out.specular = new Vec4(m.specularColor.x, m.specularColor.y, m.specularColor.z, m.specularFactor);
		out.coat = new Vec4(m.clearcoat, m.clearcoatRoughness, m.clearcoatNormalScale, m.ior);
		out.transmission = new Vec4(m.transmission, m.thickness, m.attenuationDistance, behind);
		out.attenuation = new Vec4(m.attenuationColor.x, m.attenuationColor.y, m.attenuationColor.z, 0);
		out.iridescence = new Vec4(m.iridescence, m.iridescenceIor, m.iridescenceThicknessMinimum, m.iridescenceThicknessMaximum);
		out.anisotropy = new Vec4(m.anisotropy, Math.cos(m.anisotropyRotation), Math.sin(m.anisotropyRotation), 0);
		ids[0] = ids[1] = -1;
		out.maps0 = new Vec4(slot(m.sheenColorTexture), slot(m.sheenRoughnessTexture), slot(m.specularTexture), slot(m.specularColorTexture));
		out.maps1 = new Vec4(slot(m.clearcoatTexture), slot(m.clearcoatRoughnessTexture), slot(m.clearcoatNormalTexture), slot(m.transmissionTexture));
		out.maps2 = new Vec4(slot(m.thicknessTexture), slot(m.iridescenceTexture), slot(m.iridescenceThicknessTexture), slot(m.anisotropyTexture));
		var t = m.textureTransforms;
		if (t != null) {
			// (each core map its own uvs: uvSets; uvU's w the base colour's texCoord)
			out.uvU = transformU(t[0]);
			var v = transformV(t[0]);
			out.uvV = new Vec4(v.x, v.y, v.z, out.uvV.w);
			out.uvMetallicRoughnessU = transformU(t[1]);
			out.uvMetallicRoughnessV = transformV(t[1]);
			out.uvNormalU = transformU(t[2]);
			out.uvNormalV = transformV(t[2]);
			out.uvOcclusionU = transformU(t[3]);
			out.uvOcclusionV = transformV(t[3]);
			out.uvEmissiveU = transformU(t[4]);
			out.uvEmissiveV = transformV(t[4]);
		}
	}

	// a vertex layout with the second uvs (uvSets' variants: a buffer of
	// their own, last, its attribute after the others)
	public function layout(base:Array<VertexBufferLayout>):Array<VertexBufferLayout> {
		var n = 0;
		for (l in base)
			n += l.attributes.length;
		return base.concat([{stride: 8, attributes: [{location: n, format: Float2, offset: 0}]}]);
	}

	// (a map's transform's rows, uvU and uvV's)
	static function transformU(t:Material.UvTransform):Vec4 {
		var c = Math.cos(t.rotation), s = Math.sin(t.rotation);
		return new Vec4(c * t.scale.x, s * t.scale.y, t.offset.x, t.texCoord);
	}

	static function transformV(t:Material.UvTransform):Vec4 {
		var c = Math.cos(t.rotation), s = Math.sin(t.rotation);
		return new Vec4(-s * t.scale.x, c * t.scale.y, t.offset.y, 0);
	}

	public function bind(enc:Encoder, slots:Array<Int>, sampler:Sampler, white:Texture, behind:Texture, behindSampler:Sampler) {
		for (k in 0...2)
			if (slots[15 + k] >= 0) enc.setTexture(slots[15 + k], ids[k] >= 0 ? (cast ids[k] : Texture) : white, sampler);
		if (slots[17] >= 0) enc.setTexture(slots[17], behind, behindSampler);
	}

	// (a map's image among the two: 1 or 2; 0 none, or a third)
	function slot(t:Null<Texture>):Float {
		if (t == null) return 0;
		var id = t.id();
		for (k in 0...2) {
			if (ids[k] == id) return k + 1;
			if (ids[k] < 0) {
				ids[k] = id;
				return k + 1;
			}
		}
		return 0;
	}
}
