package helder.scene.view;

import helder.math.Vec3;
import helder.scene.World;
import helder.scene.render.Hit;

// how a <Scene>'s pointers find their node (SceneBox.picker): the ray from
// the camera through the pointer, into hit; false when it meets none
interface ScenePicker {
	function pick(world:World, origin:Vec3, dir:Vec3, hit:Hit):Bool;
}

// picking by triangles (<Scene pick="triangles">: Raycaster, each
// primitive's tree made when first picked at), SceneEvent's normal and uv
// the triangle's
class TrianglePicker implements ScenePicker {
	public final options:helder.scene.render.Hit.RaycastOptions;

	public function new(?options:helder.scene.render.Hit.RaycastOptions)
		this.options = options ?? new helder.scene.render.Hit.RaycastOptions();

	public function pick(world:World, origin:Vec3, dir:Vec3, hit:Hit):Bool
		return helder.scene.render.Raycaster.raycast(world, origin, dir, hit, options);
}
