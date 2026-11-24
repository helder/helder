package helder.ui.draw;

// What a node drawn on the GPU (a part's shader, a <Scene>, a sprite box)
// renders its texture with before the frame's pass: the device, the scale,
// the frame's count, beforePass (Renderer's). The Renderer itself; in a
// -D helder.soft build the soft canvas's device on the CPU (soft.SoftGpu),
// so that those nodes draw there too.
#if helder.soft
@:forward(device, scale, frames, beforePass)
abstract GpuHost(helder.ui.draw.soft.SoftGpu) {
	public static inline function of(c:Null<helder.ui.Canvas>):Null<GpuHost>
		return cast helder.ui.draw.soft.SoftGpu.of(c);
}
#else
@:forward(device, scale, frames, beforePass)
abstract GpuHost(Renderer) {
	public static inline function of(c:Null<helder.ui.Canvas>):Null<GpuHost>
		return cast Renderer.of(c);
}
#end
