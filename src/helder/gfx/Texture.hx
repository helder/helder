package helder.gfx;

// a handle (Buffer); TypeScript's a number of its own kind
@:typescript.type("number & {readonly textureBrand: never}")
abstract Texture(Int) {
	@:allow(helder.gfx) inline function new(id:Int)
		this = id;

	public inline function id():Int
		return this;
}
