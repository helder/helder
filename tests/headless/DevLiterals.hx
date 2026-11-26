import helder.ui.Node;
import helder.ui.controls.Standard;

// A dev build's live literals (-D hxmc.dev: helder.view.LiveMacro) in two
// markup patterns that once failed to build: a variant written as a literal
// (size="sm", checked against the look) and a ternary's string beside a
// number (width={w > 0 ? w : "auto"}). The cli lane: tests/lanes/Cli.hx (dev).
@:renderer(helder.ui.view.NodeRenderer)
class DevLiterals implements helder.view.Markup {
	static function main() {
		var w = 0, root = new Node();
		helder.view.Render.render(<view width={w > 0 ? w : "auto"}><Standard.Button size="sm">Open</Standard.Button></view>, root);
		helder.view.graph.Graph.flush();
		Sys.println('built: ${root.children.length} view');
	}
}
