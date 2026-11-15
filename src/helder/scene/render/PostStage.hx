package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.Shader;

// A pass of a program's own in a PostProcess (post.add(shader, bytes,
// point)): its shader drawn over the whole target, a triangle of vertices
// {pos:Vec2} in clip space (the chain's), its first texture the image the
// chain has made so far, its first uniform block bytes. At a point:
//
//   AfterComposite   (the default) after the curve and the grade: the
//                    image so far tone mapped (8 bits); the last such stage
//                    draws into the chain's output (the frame, or run's
//                    target: any size, its fragments' positions in that
//                    target's pixels), the others into RGBA8 targets of the
//                    run's size
//   BeforeComposite  in linear light, before depth of field, bloom and the
//                    curve: the image so far the scene's light (RGBA16F,
//                    its alpha the coverage), drawn into RGBA16F targets
//                    of the run's size, the last one's what the composite
//                    reads (a blur of the program's own belongs here)
//
// Its pipelines are made by the chain, for what it draws into. What it
// needs beyond the image so far is the chain's context while it runs
// (PostProcess.source: the scene's light as given, width, height), read in
// prepare or bind.
class PostStage {
	// its block's std140 bytes (the shader's first uniform block; null: none)
	public var bytes:Null<Bytes>;
	// how the image so far is read: Linear, or Nearest (big pixels)
	public var filter:Filter = Linear;
	// off: passed over
	public var enabled = true;
	// what else it binds before it draws (another block or texture)
	public var bind:Null<Encoder->Void> = null;
	// what it records before the chain's passes, outside any pass (passes
	// of its own: a blur at half size from the chain's source), each run,
	// enabled or not (it may enable itself); the chain's context (source,
	// width, height) is the run's then
	public var prepare:Null<Encoder->Void> = null;
	// where in the chain it draws
	public final point:PostPoint;

	@:allow(helder.scene.render.PostProcess) final desc:PipelineDesc;
	@:allow(helder.scene.render.PostProcess) final block:Int;
	@:allow(helder.scene.render.PostProcess) final source:Int;
	// (into the targets between, RGBA8 (RGBA16F before the composite); into
	// the output: made when first drawn)
	@:allow(helder.scene.render.PostProcess) var middle:Null<Pipeline> = null;
	@:allow(helder.scene.render.PostProcess) var last:Null<Pipeline> = null;

	@:allow(helder.scene.render.PostProcess)
	function new<V, P>(shader:Shader<V, P>, bytes:Null<Bytes>, point:PostPoint) {
		if (shader.textures.length == 0) throw "helder.scene: a post stage's shader reads the image so far (a Texture2D parameter)";
		if (shader.layout.length != 1 || shader.layout[0].stride != 8) throw "helder.scene: a post stage's vertex is {pos:Vec2}";
		desc = shader.pipeline();
		block = shader.uniforms.length > 0 ? shader.uniforms[0].binding : -1;
		source = shader.textures[0].binding;
		this.bytes = bytes;
		this.point = point;
	}
}

// where a PostStage draws in its chain
enum abstract PostPoint(Int) {
	var AfterComposite;
	var BeforeComposite;
}
