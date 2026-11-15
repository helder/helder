package helder.scene.render;

// The physical shader for every material (DESIGN-3D.md 1.3): one variant
// set with every glTF material extension (PhysicalShader.ALL: sheen,
// specular and ior, clearcoat with its maps, transmission and volume,
// iridescence, anisotropy; each core map at its own uvs), drawing each material whose fields use one
// (Material.extensions) and that has no shader of its own: a model loaded
// at run time (Model.load, whose extensions are not known when compiling),
// or materials made in code. Opted in, as it is big (one shader with every
// layer, each a branch on the material's values):
//
//   renderer.use(new Physical());   // made before Model.load's models are read
//
// Model.of's models need none: their materials get the variants of the
// extensions they use, made when compiling (PhysicalShader).
class Physical implements RenderFeature implements RenderFeature.PhysicalSource {
	final shader:MaterialShader = PhysicalShader.of({
		sheen: true,
		specular: true,
		clearcoat: true,
		transmission: true,
		iridescence: true,
		anisotropy: true,
		uvSets: true
	});

	// (glTF files read from now on read their extensions: GltfExtensions;
	// made before the models load)
	public function new()
		helder.scene.gltf.GltfExtensions.install();

	public function attach(renderer:Renderer)
		@:privateAccess renderer.physical = this;

	// the shader of a material that uses an extension (Material.extensions)
	public function shaderOf(m:Material):Null<MaterialShader>
		return m.extensions() != 0 ? shader : null;
}
