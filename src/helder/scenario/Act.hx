package helder.scenario;

import helder.async.Errors;
import helder.ui.*;
import helder.view.Render;
import helder.view.graph.Graph;

// A scenario played in a screen (helder.story.Host's): the program's main
// run in its context with no window (Hosting), its <Surface>'s children
// into the screen's root, its named signals preset (helder.view.Named), its
// wall clock its time
class Act {
	// mounted: what lets it go
	public static function mount(sc:Scenario, main:Void->Void, context:ScreenContext, ui:Ui):Void->Void {
		var names = context.names;
		names.preset = sc.set;
		names.used.resize(0);
		context.epoch = sc.time == null ? null : sc.time - context.now * 1000;
		// (run's own: the wall clock read from here on is the scenario's)
		helder.os.Now.get = sc.time == null ? null : () -> (context.epoch ?? 0) + context.now * 1000;
		var opened:Array<Void->Void> = [];
		var gone = () -> for (d in opened)
			d();
		hosted(new Hosting(content -> opened.push(Render.open(content)), props -> Render.insert(props.children, ui.root, null)), main, gone);
		var unknown = names.unknown();
		if (unknown.length > 0) {
			gone();
			throw 'scenario "${sc.name}": no signal named ' + unknown.join(", ") + ' (named: ${names.names().join(", ")})';
		}
		return gone;
	}

	// the size main's <Surface> gives (its window's), main run once with nothing rendered
	public static function size(main:Void->Void):{width:Null<Int>, height:Null<Int>} {
		var out:{width:Null<Int>, height:Null<Int>} = {width: null, height: null};
		var opened:Array<Void->Void> = [];
		var gone = () -> for (d in opened)
			d();
		new ScreenContext("helder.scenario").run(() -> helder.dev.Hot.scope("helder.scenario", () -> {
			hosted(new Hosting(content -> opened.push(Render.open(content)), props -> {
				out.width = Render.read(props.width);
				out.height = Render.read(props.height);
			}), main, gone);
			gone();
			true;
		}));
		return out;
	}

	static function hosted(h:Hosting, main:Void->Void, gone:Void->Void) {
		var was = Hosting.current;
		Hosting.current = h;
		try {
			main();
			Graph.flush();
		} catch (e:haxe.Exception) {
			Hosting.current = was;
			gone();
			throw Errors.kept(e);
		}
		Hosting.current = was;
	}
}
