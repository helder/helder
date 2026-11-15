package helder.gfx;

// A set of occlusion queries (Device.createQueries): each counts whether
// any sample of the draws between its Encoder.beginQuery and endQuery
// passed the depth test, answered a frame or more later
// (Device.queryResult), never waited for. A handle, as Buffer's.
abstract QuerySet(Int) {
	public static inline var NONE:QuerySet = cast 0;

	@:allow(helder.gfx) inline function new(id:Int)
		this = id;

	public inline function id():Int
		return this;
}
