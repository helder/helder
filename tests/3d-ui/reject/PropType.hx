import helder.scene.World;
import helder.scene.view.SceneRenderer;
import helder.view.*;

// A prop's value is checked against its type (SceneProps) when compiling.
// expect: PropType.hx:10: characters
// expect: <pointLight>'s intensity is a Float, not a String
class PropType implements Markup {
	static function main() {
		Render.render(<pointLight intensity="bright"/>, SceneRenderer.root(new World()));
	}
}
