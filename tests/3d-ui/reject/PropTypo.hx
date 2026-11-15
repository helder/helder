import helder.scene.World;
import helder.scene.view.SceneRenderer;
import helder.view.*;

// SceneRenderer's tags take their factories' options by name (@:props:
// SceneProps): a prop an element does not take must not compile.
// expect: PropTypo.hx:11: characters
// expect: <toonMaterial> has no prop stepz
class PropTypo implements Markup {
	static function main() {
		Render.render(<mesh><boxGeometry width={2}/><toonMaterial stepz={3}/></mesh>, SceneRenderer.root(new World()));
	}
}
