// A dev build's effect that throws a value, not an exception (helder.ui's
// unknown attribute set at run time: a string): hxmc dev runs an effect in
// its compute's scope (helder.view.graph.Node); the error is uncaught,
// printed with where it was thrown, exit code 1, not a crash (exit 139:
// the value read as an exception). The cli lane: tests/lanes/Cli.hx (dev).
class DevThrow {
	static function main() {
		helder.view.graph.Graph.root(_ -> helder.view.graph.Graph.renderEffect(() -> 1, _ -> {
			throw "helder.ui: <view> has no attribute flex-direction";
		}));
	}
}
