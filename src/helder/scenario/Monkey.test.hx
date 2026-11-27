package helder.scenario;

import helder.scenario.Scenario;
import helder.test.Gen;
import helder.test.Test;
import helder.ui.*;
import helder.ui.UiWindow.Surface;
import helder.ui.view.UiFlow.Popover;
import helder.view.Flow.*;
import helder.view.View;
import helder.view.graph.Graph;

// (the program's model: its people, the search's text)
final names = Graph.signal(["Ada", "Grace", "Alan"]);
final query = Graph.signal("");
final menu = Graph.signal(false);

final plain = scenario({name: "People/Plain"});
final crowded = scenario({name: "People/Crowded", boot: () -> names([for (i in 0...60) 'Person $i'])});
final broken = scenario({name: "Broken/Plain"});
final reckless = scenario({name: "Reckless/Plain"});

// (a file a reckless program trashes, and a store's file it opens: neither touched)
final KEPT = "bin/test/monkey-reckless/kept.txt";
final STORE = "bin/test/monkey-reckless/store";

// a monkey over a small program booted as its scenarios: one that holds,
// one with a bug of each kind found, shrunk and written as a scenario file
function tests() {
	Hosting.on = true;
	Reckless.main();
	var careless = Hosting.root;
	Broken.main();
	var wrong = Hosting.root;
	People.main();
	// (its own root: another test file's main, built beside it, gives UiWindow.run its own)
	var people = Hosting.root;
	Hosting.on = false;
	var right = test("a program that holds under a monkey", () -> Monkey.check({
		from: Monkey.from(plain, crowded),
		root: people,
		atoms: [Monkey.atom(names), Monkey.atom(query)]
	}, {cases: 30, limit: 30}));
	var outside = test("content outside the window: found, shrunk to the atom's value, written, replayed", () -> {
		var f = Monkey.find({from: Monkey.from(broken), atoms: [Monkey.atom(names)], root: wrong, except: ["popups"], steps: 0}, {cases: 200});
		assert(f != null, "found");
		if (f == null) return;
		equals(f.steps, []);
		assert(f.failure.indexOf("is outside the window") > 0, f.failure);
		assert(f.text.indexOf(".names([") > 0, f.text);
		equals(sys.io.File.getContent(f.file), f.text);
		// (its scenario alone fails as the case did)
		var again = Monkey.find({from: [{scenario: f.scenario, path: "found"}], root: wrong, except: ["popups"], steps: 0}, {cases: 1});
		equals(again?.failure, f.failure);
	});
	var orphan = test("a popup left open as its anchor goes: found, shrunk to a few steps", () -> {
		var f = Monkey.find({from: Monkey.from(broken), root: wrong, except: ["window"], texts: pick(["a", "Hello"])}, {cases: 200});
		assert(f != null, "found");
		if (f == null) return;
		// (a search taking the button away while its popup is open, or one
		// emptied making the button again: the popup's anchor the one made first)
		assert(f.steps.contains('tap("Menu")') && f.steps.length <= 4, f.steps.join(", "));
		assert(f.failure.indexOf("its anchor button gone") > 0, f.failure);
	});
	test("steps as a scenario file writes them", () -> {
		equals([
			Monkey.code(Steps.tap("Add")),
			Monkey.code(Steps.tap({x: 10, y: 20})),
			Monkey.code(Steps.type({role: "textbox", name: "Search"}, 'a "b"\n')),
			Monkey.code(Steps.scroll("People", "end")),
			Monkey.code(Steps.drag("Ada", {dx: -3, dy: 4})),
			Monkey.code(Steps.resize(300, 200)),
			Monkey.code(Steps.wait(0.5))
		], [
			'tap("Add")',
			"tap({x: 10, y: 20})",
			'type({name: "Search", role: "textbox"}, "a \\"b\\"\\n")',
			'scroll("People", "end")',
			'drag("Ada", {dx: -3, dy: 4})',
			"resize(300, 200)",
			"wait(0.5)"
		]);
	});
	var sealed = test("a program that trashes a file, lists the user's places or opens a store's file: refused, the case failed, nothing touched", () -> {
		// (first the seal alone, on nothing there: a broken one trashes nothing)
		var c = new ScreenContext("probe", true);
		c.seal = new helder.os.Seal("a probe");
		var held = c.run(() -> try {
			helder.os.Trash.move("/helder-monkey-test/not-there");
			false;
		} catch (e:helder.os.Seal.SealError) true);
		assert(held, "the seal refuses the trash");
		if (!held) return;
		sys.FileSystem.createDirectory(haxe.io.Path.directory(KEPT));
		sys.io.File.saveContent(KEPT, "kept");
		var f = Monkey.find({from: Monkey.from(reckless), root: careless, except: ["window"]}, {cases: 100});
		assert(f != null && f.failure.indexOf("refused: a monkey's case is sealed off the machine") > 0, f?.failure);
		assert(f != null && f.steps.length == 1, f?.steps.join(", "));
		// (each of its effects, a scenario of that tap)
		for (what in ["Clean up", "Places", "Save"]) {
			var g = Monkey.find({from: [{scenario: scenario({name: what, steps: [Steps.tap(what)]}), path: "reckless"}], root: careless, steps: 0}, {cases: 1});
			assert(g != null && g.failure.indexOf("refused") > 0, '$what: ${g?.failure}');
		}
		equals(sys.FileSystem.exists(KEPT), true);
		equals(sys.FileSystem.exists(STORE), false);
	});
	#if (hxmc.target == "wasm32-wasi")
	// (a robustness property's watchdog and the store's files: natively)
	for (t in [right, outside, orphan, sealed])
		t.skip();
	#end
}

class People implements helder.view.Markup {
	public static function main()
		UiWindow.run(<Surface title="People" width={320} height={400}><App/></Surface>);

	static function App(_:{}):View {
		var shown = Graph.memo(() -> names().filter(n -> n.toLowerCase().indexOf(query().toLowerCase()) >= 0));
		return <view flexGrow={1} flexShrink={1} minHeight={0} rowGap={4} padding={8}>
			<view flexDirection="row" flexWrap="wrap" columnGap={4} rowGap={4}>
				<field value={query} aria-label="Search" flexGrow={1} flexShrink={1} minWidth={0} onInput={e -> query(e.text)}/>
				<button onPress={() -> names(l -> l.concat(['Person ${l.length}']))}>Add</button>
				<view>
					<button onPress={() -> menu(m -> !m)}>Menu</button>
					<Popover open={menu} placement={Below} onDismiss={() -> menu(false)}>
						<button onPress={() -> menu(false)}>Close</button>
					</Popover>
				</view>
			</view>
			<text lineClamp={1} textOverflow="ellipsis" flexShrink={0}>{() -> 'Hello, ${names()[0] ?? "nobody"}'}</text>
			<scroll role="list" aria-label="People" flexGrow={1} flexShrink={1} minHeight={0}>
				<For each={shown}>{n -> <button flexShrink={0}><text lineClamp={1} textOverflow="ellipsis">{n}</text></button>}</For>
			</scroll>
		</view>;
	}
}

// (two bugs: its greeting is not clipped, a long name past the window; its
// menu's popup anchored to a button a search takes away, left open)
class Broken implements helder.view.Markup {
	public static function main()
		UiWindow.run(<Surface title="Broken" width={320} height={400}><App/></Surface>);

	static function App(_:{}):View {
		var button:Null<Node> = null;
		return <view flexGrow={1} rowGap={4} padding={8}>
			<view flexDirection="row" columnGap={4}>
				<field value={query} aria-label="Search" flexGrow={1} flexShrink={1} minWidth={0} onInput={e -> query(e.text)}/>
				<Show when={() -> query() == ""}>
					<button ref={(n:Node) -> button = n} onPress={() -> menu(m -> !m)}>Menu</button>
				</Show>
			</view>
			<Popover open={menu} anchor={button} placement={Below} onDismiss={() -> menu(false)}>
				<button onPress={() -> menu(false)}>Close</button>
			</Popover>
			<view flexDirection="row"><text flexShrink={0}>{() -> 'Hello, ${names()[0] ?? "nobody"}'}</text></view>
		</view>;
	}
}

// (what a program must not do in a scenario's screen, each caught and ignored: refused all the same)
class Reckless implements helder.view.Markup {
	public static function main()
		UiWindow.run(<Surface title="Reckless" width={320} height={200}><App/></Surface>);

	static function App(_:{}):View
		return <view flexGrow={1} rowGap={4} padding={8}>
			<button onPress={() -> try helder.os.Trash.move(KEPT) catch (_:Dynamic) {}}>Clean up</button>
			<button onPress={() -> try helder.os.Places.user() catch (_:Dynamic) {}}>Places</button>
			<button onPress={() -> try helder.os.Store.open("reckless", STORE).set("a", "1") catch (_:Dynamic) {}}>Save</button>
		</view>;
}
