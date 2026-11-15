package helder.gfx;

// built once and reused each frame. A pass into the frame has the device's
// depth buffer (depth: null keeps its contents); a pass into a texture
// (colors[0].texture) has a depth buffer only when depth names a texture.
// queries: the occlusion queries its draws may count into
// (Encoder.beginQuery; WebGPU's pass names its query set when it begins)
typedef PassDesc = {
	colors:Array<ColorTarget>,
	?depth:DepthTarget,
	?queries:QuerySet
}
