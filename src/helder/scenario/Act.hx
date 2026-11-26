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
// wall clock its time, its zone, language and settings its own
class Act {
	// mounted: what lets it go
	public static function mount(sc:Scenario, root:RootView, context:ScreenContext, ui:Ui, ?missed:(method:String, url:String) -> Void):Void->Void {
		// (its requests its fixtures' to answer, strictly: none goes out, one unanswered its screen's failure)
		if (context.atoms != null) context.atoms.http = new helder.async.http.Fixtures(sc.http ?? {}, #if sys Sys.getCwd() #else "" #end, missed ?? (_, _) -> {});
		context.epoch = sc.time == null ? null : sc.time - context.now * 1000;
		context.zone = sc.zone;
		context.locale = sc.locale;
		// (its orientation its size's, unless given)
		var o = sc.settings.orientation ?? (ui.width > ui.height ? helder.os.Settings.Orientation.Landscape : helder.os.Settings.Orientation.Portrait);
		context.settings = {
			textScale: sc.settings.textScale,
			reducedMotion: sc.settings.reducedMotion,
			reducedTransparency: sc.settings.reducedTransparency,
			contrast: sc.settings.contrast,
			orientation: o
		};
		context.reducedMotion = sc.settings.reducedMotion;
		// (run's own: what helder.os reads from here on is the scenario's)
		@:privateAccess ScreenContext.environ(context);
		var boot = sc.boot;
		if (boot != null) {
			boot();
			// (what it wrote committed: the root reads it as it renders)
			Graph.flush();
		}
		var d = opened(root, props -> Render.insert(props.children, ui.root, null));
		if (sc.steps.length == 0) return d;
		// (its steps after boot, before the still; one going wrong lets the root go and fails the screen)
		var p = sc.pos, at = p == null ? null : new helder.view.Source(p.fileName, 0, 0, p.lineNumber, 1, p.lineNumber, 1);
		try Steps.run(sc.steps, ui, context, at) catch (e:haxe.Exception) {
			d();
			throw Errors.kept(e);
		}
		return d;
	}

	// the size and title the root's <Surface> gives (its window's), rendered once with nothing in it
	public static function size(root:RootView):{width:Null<Int>, height:Null<Int>, title:Null<String>} {
		var out:{width:Null<Int>, height:Null<Int>, title:Null<String>} = {width: null, height: null, title: null};
		var store = new Atoms("helder.scenario"), c = new ScreenContext("helder.scenario", true, null, store);
		c.run(() -> helder.dev.Hot.scope("helder.scenario", () -> opened(root, props -> {
			out.width = Render.read(props.width);
			out.height = Render.read(props.height);
			out.title = Render.read(props.title);
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
