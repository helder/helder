package helder.scenario;

import helder.async.Errors;
import helder.ui.*;
import helder.view.Render;
import helder.view.RootView;
import helder.view.graph.Atoms;
import helder.view.graph.Graph;

// A scenario played in a screen (helder.story.Host's), its context and
// store current: its boot run, then the root main gave UiWindow.run
// rendered, its <Surface>'s children into the screen's root (Hosting), its
// wall clock its time
class Act {
	// mounted: what lets it go
	public static function mount(sc:Scenario, root:RootView, context:ScreenContext, ui:Ui):Void->Void {
		context.epoch = sc.time == null ? null : sc.time - context.now * 1000;
		// (run's own: the wall clock read from here on is the scenario's)
		helder.os.Now.get = sc.time == null ? null : () -> (context.epoch ?? 0) + context.now * 1000;
		var boot = sc.boot;
		if (boot != null) {
			boot();
			// (what it wrote committed: the root reads it as it renders)
			Graph.flush();
		}
		return opened(root, props -> Render.insert(props.children, ui.root, null));
	}

	// the size the root's <Surface> gives (its window's), rendered once with nothing in it
	public static function size(root:RootView):{width:Null<Int>, height:Null<Int>} {
		var out:{width:Null<Int>, height:Null<Int>} = {width: null, height: null};
		var store = new Atoms("helder.scenario"), c = new ScreenContext("helder.scenario", true, null, store);
		c.run(() -> helder.dev.Hot.scope("helder.scenario", () -> opened(root, props -> {
			out.width = Render.read(props.width);
			out.height = Render.read(props.height);
		})))();
		store.dispose();
		return out;
	}

	static function opened(root:RootView, surface:UiWindow.SurfaceProps->Void):Void->Void {
		var was = Hosting.surface;
		Hosting.surface = surface;
		var d = try {
			var d = Render.open(root);
			Graph.flush();
			d;
		} catch (e:haxe.Exception) {
			Hosting.surface = was;
			throw Errors.kept(e);
		}
		Hosting.surface = was;
		return d;
	}
}
