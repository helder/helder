package helder.gfx;

// a handle (Buffer): a compute stage's pipeline (Device.createComputePipeline)
abstract ComputePipeline(Int) {
	@:allow(helder.gfx) inline function new(id:Int)
		this = id;

	public inline function id():Int
		return this;
}
