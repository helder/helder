package helder.gfx.soft;

// a Vec2 in each of a call's 4 lanes: a Lane a component
@:build(helder.gfx.soft.LaneBuild.vector(2))
@:forward(x, y)
abstract Lane2(Lane2Data) {
	public inline function new(x:Lane, y:Lane)
		this = new Lane2Data(x, y);
}

@:hxmc.struct @:noCompletion final class Lane2Data {
	public final x:Lane;
	public final y:Lane;

	public inline function new(x:Lane, y:Lane) {
		this.x = x;
		this.y = y;
	}
}
