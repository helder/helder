import helder.scene.World;
import helder.scene.view.SceneRenderer;
import helder.view.*;

// A signal bound to a prop is checked by what it reads.
// expect: PropReads.hx:11: characters
// expect: <pointLight>'s color is a helder.math.Vec3, not a helder.view.graph.Signal<Float> (it reads a Float)
class PropReads implements Markup {
	static function main() {
		var power = helder.view.graph.Graph.signal(1.0);
		Render.render(<pointLight color={power}/>, SceneRenderer.root(new World()));
	}
}
