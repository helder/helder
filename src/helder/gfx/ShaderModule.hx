package helder.gfx;

// a handle (Buffer)
abstract ShaderModule(Int) {
	@:allow(helder.gfx) inline function new(id:Int)
		this = id;

	public inline function id():Int
		return this;
}
