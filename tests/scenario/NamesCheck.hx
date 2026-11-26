import helder.ui.ScreenContext;
import helder.view.*;
import helder.view.graph.Graph.*;

// helder dev's names of data signals (helder.view.Named): a component's
// Function.variable, a class's field Class.variable, a second instance
// name#1, an unbound or derived signal none; each screen its own
//   <tool> -cp src -cp tests/scenario -D hxmc.dev --run NamesCheck
class NamesCheck implements Markup {
	static var failures = 0;

	static function check(what:String, got:Dynamic, want:Dynamic) {
		if (Std.string(got) == Std.string(want)) return;
		failures++;
		Sys.println('FAIL $what: $got, not $want');
	}

	static function Card(props:{label:String}):View {
		var clicks = signal(0);
		var double = signal(() -> clicks() * 2);
		return <p>{props.label}: {double}</p>;
	}

	static function main() {
		var a = new ScreenContext("a"), b = new ScreenContext("b");
		a.names.preset = ["NamesCheck.Card.clicks" => 4];
		a.run(() -> {
			var counter = new Counter();
			Render.render(<div><Card label="x"/><Card label="y"/></div>, TestRenderer.createElement("div"));
			check("a's names", a.names.names(), ["Counter.count", "NamesCheck.Card.clicks", "NamesCheck.Card.clicks#1"]);
			check("preset", a.names.get("NamesCheck.Card.clicks")?.peek(), 4);
			check("the second not preset", a.names.get("NamesCheck.Card.clicks#1")?.peek(), 0);
			check("a field", counter.count.peek(), 0);
		});
		b.run(() -> {
			Render.render(<div><Card label="z"/></div>, TestRenderer.createElement("div"));
			check("b's names", b.names.names(), ["NamesCheck.Card.clicks"]);
			check("b's own", b.names.get("NamesCheck.Card.clicks")?.peek(), 0);
		});
		if (failures > 0) Sys.exit(1);
		Sys.println("NamesCheck: ok");
	}
}

class Counter {
	public final count = signal(0);

	public function new() {}
}
