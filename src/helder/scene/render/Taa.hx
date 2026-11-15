package helder.scene.render;

// Temporal antialiasing, a PostProcess's (post.taa = new Taa()): the
// frame's projection jittered by a sub-pixel each frame (Renderer.jitter),
// gathered with its history reprojected by the view buffers' motion (asked
// for whole, with ViewBuffers.velocity), the history kept within each
// pixel's neighbourhood (TaaShader's notes); in linear light, before depth
// of field, motion blur and bloom. Desktop and web (MSAA stays a phone's).
// A cut (a camera's jump): PostProcess.resetHistory. Its options alone: its
// passes are TaaPass's, linked by a program that sets it on a chain.
//
//   post.taa = new Taa({blend: 0.1});
class Taa {
	// the share of each new frame in the history (0.1: about ten frames
	// gathered; more: quicker to follow, less smooth)
	public var blend:Float;

	public function new(?options:TaaOptions)
		blend = options?.blend ?? 0.1;
}

typedef TaaOptions = {
	?blend:Float
}
