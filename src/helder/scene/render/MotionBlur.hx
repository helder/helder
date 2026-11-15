package helder.scene.render;

// Motion blur, a PostProcess's (post.motionBlur = new MotionBlur({...})):
// each pixel's light gathered along its motion on the screen since the
// frame before, in linear light before depth of field and bloom: the
// camera's motion from the view buffers' depth and the last frame's
// view-projection (no motion target: what a phone affords), or with objects
// each node's own too (the view buffers' motion, ViewBuffers.velocity: a
// second geometry pass, desktop and web). Its target is RGBA16F, the frame's
// size; nothing is allocated per frame. Its options alone: its pass is
// MotionBlurPass's, linked by a program that sets it on a chain.
//
//   post.motionBlur = new MotionBlur({strength: 0.5});                 // the camera's
//   post.motionBlur = new MotionBlur({strength: 0.5, objects: true});  // and each object's
class MotionBlur {
	// the share of the frame's motion blurred (the shutter: 0.5 a half-open
	// one, 180 degrees; 1 the whole frame's)
	public var strength:Float;
	// the taps along the motion (8 for phones, 12, 16)
	public var samples:Int;
	// the longest blur (a share of the frame's height)
	public var max:Float;
	// each object's motion too (the view buffers' motion), not the camera's alone
	public var objects:Bool;

	public function new(?options:MotionBlurOptions) {
		strength = options?.strength ?? 0.5;
		samples = options?.samples ?? 12;
		max = options?.max ?? 0.05;
		objects = options?.objects ?? false;
	}
}

typedef MotionBlurOptions = {
	?strength:Float,
	?samples:Int,
	?max:Float,
	?objects:Bool
}
