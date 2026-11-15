import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.scene.World;
import helder.scene.view.SceneRenderer;
import helder.view.*;

// helder.scene.view's markup linking what it names alone (markup.mjs, the
// 3d lane on Linux): a mesh of a box in the standard material, written as
// markup (Tiny), against every geometry and material tag (-D markup_all:
// All, so that the check checks something) and against the same mesh made
// in code (-D markup_code: what markup adds over it, its budget). Each tag's
// factory is called by its own function (SceneRenderer.element_<tag>), not
// by a switch on every name, so Tiny links one generator and one shading
// model (PBR's), not twelve and eight with their shaders. Built only: no
// device is made, its meshes wait for one.
class MarkupSize implements Markup {
	static function main() {
		var world = new World("size");
		#if markup_code
		var mesh = helder.scene.render.Geometry.box({width: 1, height: 1, depth: 1});
		var material = helder.scene.render.Material.standard({color: new Vec4(0.8, 0.3, 0.2, 1)});
		var node = world.node("box");
		node.position = new Vec3(0, 1, 0);
		if (SceneRenderer.device != null)
			helder.scene.render.MeshRenderer.attach(node, SceneRenderer.meshOf(SceneRenderer.device, mesh, material));
		#else
		Render.render(<node name="box" position={new Vec3(0, 1, 0)}>
			<mesh>
				<boxGeometry width={1} height={1} depth={1}/>
				<standardMaterial color={new Vec4(0.8, 0.3, 0.2, 1)}/>
			</mesh>
		</node>, SceneRenderer.root(world));
		#end
		#if markup_all
		Render.render(<node name="all">
			<mesh><sphereGeometry/><lambertMaterial/></mesh>
			<mesh><cylinderGeometry/><phongMaterial/></mesh>
			<mesh><coneGeometry/><toonMaterial/></mesh>
			<mesh><capsuleGeometry/><unlitMaterial/></mesh>
			<mesh><torusGeometry/><matcapMaterial/></mesh>
			<mesh><torusKnotGeometry/><normalMaterial/></mesh>
			<mesh><ringGeometry/><depthMaterial/></mesh>
			<mesh><circleGeometry/><standardMaterial/></mesh>
			<mesh><planeGeometry/><standardMaterial/></mesh>
			<mesh><latheGeometry/><standardMaterial/></mesh>
			<mesh><tubeGeometry/><standardMaterial/></mesh>
		</node>, SceneRenderer.root(world));
		#end
		Sys.println("markup size: " + Lambda.count({iterator: () -> world.root.children()}));
	}
}
