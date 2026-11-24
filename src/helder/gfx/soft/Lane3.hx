package helder.gfx.soft;

// a Vec3 in each of a call's 4 lanes: a Lane a component
@:build(helder.gfx.soft.LaneBuild.vector(3))
@:forward(x, y, z)
abstract Lane3(Lane3Data) {
	public inline function new(x:Lane, y:Lane, z:Lane)
		this = new Lane3Data(x, y, z);
}

@:hxmc.struct @:noCompletion final class Lane3Data {
	public final x:Lane;
	public final y:Lane;
	public final z:Lane;

	public inline function new(x:Lane, y:Lane, z:Lane) {
		this.x = x;
		this.y = y;
		this.z = z;
	}
}
