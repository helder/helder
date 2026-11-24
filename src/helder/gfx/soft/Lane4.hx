package helder.gfx.soft;

// a Vec4 in each of a call's 4 lanes: a Lane a component
@:build(helder.gfx.soft.LaneBuild.vector(4))
@:forward(x, y, z, w)
abstract Lane4(Lane4Data) {
	public inline function new(x:Lane, y:Lane, z:Lane, w:Lane)
		this = new Lane4Data(x, y, z, w);
}

@:hxmc.struct @:noCompletion final class Lane4Data {
	public final x:Lane;
	public final y:Lane;
	public final z:Lane;
	public final w:Lane;

	public inline function new(x:Lane, y:Lane, z:Lane, w:Lane) {
		this.x = x;
		this.y = y;
		this.z = z;
		this.w = w;
	}
}
