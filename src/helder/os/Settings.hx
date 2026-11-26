package helder.os;

import helder.view.graph.Graph;
import helder.view.graph.Read;

#if (target.name == "hxmc")
import hxmc.Platform;
#end

typedef SettingsValues = {
	var textScale:Float;
	var reducedMotion:Bool;
	var reducedTransparency:Bool;
	var contrast:Contrast;
	var dark:Bool;
	var orientation:Null<Orientation>;
}

// a screen's settings over the system's (a scenario's settings), each given one
typedef SettingsOverride = {
	@:optional var textScale:Float;
	@:optional var reducedMotion:Bool;
	@:optional var reducedTransparency:Bool;
	@:optional var contrast:Contrast;
	@:optional var orientation:Orientation;
}

enum abstract Contrast(String) to String {
	var Normal = "normal";
	var More = "more";
	var Less = "less";
	var Custom = "custom";
}

enum abstract Orientation(String) to String {
	var Portrait = "portrait";
	var Landscape = "landscape";
}

class Settings {
	@:typescript public static var textScale(get, never):Read<Float>;
	@:typescript public static var reducedMotion(get, never):Read<Bool>;
	@:typescript public static var reducedTransparency(get, never):Read<Bool>;
	@:typescript public static var contrast(get, never):Read<Contrast>;
	@:typescript public static var dark(get, never):Read<Bool>;
	@:typescript public static var orientation(get, never):Read<Null<Orientation>>;

	static var state:Null<SettingsState>;
	// (the current screen's over the system's: helder.ui.ScreenContext sets it)
	@:noCompletion public static var screen:Null<SettingsOverride> = null;

	static function current():SettingsState {
		if (state == null) {
			state = new SettingsState(values());
			#if (target.name == "hxmc" && !helder.headless)
			if (!musl()) @:privateAccess App.watchSettings(refresh);
			#elseif js
			for (query in queries) {
				var media = mediaQuery(query);
				if (media != null) media.addEventListener("change", _ -> refresh());
			}
			#end
		}
		return state;
	}

	static function get_textScale():Read<Float> {
		var o = screen?.textScale;
		return o != null ? fixed(o) : current().textScale;
	}

	static function get_reducedMotion():Read<Bool> {
		var o = screen?.reducedMotion;
		return o != null ? fixed(o) : current().reducedMotion;
	}

	static function get_reducedTransparency():Read<Bool> {
		var o = screen?.reducedTransparency;
		return o != null ? fixed(o) : current().reducedTransparency;
	}

	static function get_contrast():Read<Contrast> {
		var o = screen?.contrast;
		return o != null ? fixed(o) : current().contrast;
	}

	static inline function fixed<T>(v:T):Read<T>
		return (new helder.view.graph.Read.Const<T>(v) : helder.view.graph.Read.Reader<T>);

	static function get_dark():Read<Bool> return current().dark;
	static function get_orientation():Read<Null<Orientation>> {
		var o = screen?.orientation;
		return o != null ? fixed((o : Null<Orientation>)) : current().orientation;
	}

	static function refresh() {
		var v = values(), s = state;
		if (s.textScale.peek() != v.textScale) s.textScale(v.textScale);
		if (s.reducedMotion.peek() != v.reducedMotion) s.reducedMotion(v.reducedMotion);
		if (s.reducedTransparency.peek() != v.reducedTransparency) s.reducedTransparency(v.reducedTransparency);
		if (s.contrast.peek() != v.contrast) s.contrast(v.contrast);
		if (s.dark.peek() != v.dark) s.dark(v.dark);
		if (s.orientation.peek() != v.orientation) s.orientation(v.orientation);
		Graph.flush();
	}

	#if js
	static function mediaQuery(query:String):Null<js.html.MediaQueryList>
		return js.Syntax.code("globalThis.matchMedia?.({0})", query);

	static final queries = ["(prefers-reduced-motion: reduce)", "(prefers-contrast: more)", "(prefers-contrast: less)",
		"(prefers-contrast: custom)", "(prefers-color-scheme: dark)", "(orientation: portrait)", "(orientation: landscape)"];
	#end

	static function values():SettingsValues {
		var v:SettingsValues = {textScale: 1, reducedMotion: false, reducedTransparency: false, contrast: Normal, dark: false, orientation: null};
		#if (target.name == "hxmc")
		#if helder.headless
		v.dark = App.prefersDark();
		v.reducedMotion = helder.os.headless.Headless.run.reducedMotion;
		v.orientation = windowOrientation();
		#else
		#if (!helder.os || helder.os == "web")
		if (Platform.os() == Platform.WASI) {
			var m = helder.os.web.Dom.settings();
			web(v, m);
		} else
		#end
		if (!musl()) {
			v.dark = App.prefersDark();
			v.orientation = windowOrientation();
			#if (!helder.os || helder.os == "macos" || helder.os == "ios") if (Platform.os() == Platform.MACOS) { if (Platform.apple() >= 1) helder.os.apple.Settings.ios(v) else helder.os.apple.Settings.mac(v); } else #end
			#if (!helder.os || helder.os == "windows") if (Platform.os() == Platform.WINDOWS) helder.os.windows.Settings.read(v) else #end
			#if (!helder.os || helder.os == "android") if (Platform.target() >= 9) helder.os.android.Settings.read(v) else #end
			#if (!helder.os || helder.os == "linux") helder.os.linux.Settings.read(v); #else {} #end
		}
		#end
		#elseif js
		var bits = 0;
		for (i in 0...queries.length) {
			var media = mediaQuery(queries[i]);
			if (media != null && media.matches) bits |= 1 << i;
		}
		web(v, bits);
		#end
		return v;
	}

	#if (target.name == "hxmc")
	// (a static Linux executable, musl's: no window back end links there, so App stays out)
	static inline function musl():Bool
		return Platform.os() == Platform.LINUX && Platform.target() < 2;

	static function windowOrientation():Null<Orientation> {
		var w = App.windows[0];
		return w == null || w.width <= 0 || w.height <= 0 ? null : w.width > w.height ? Landscape : Portrait;
	}
	#end

	static function web(v:SettingsValues, bits:Int) {
		v.reducedMotion = bits & 1 != 0;
		v.contrast = bits & 8 != 0 ? Custom : bits & 2 != 0 ? More : bits & 4 != 0 ? Less : Normal;
		v.dark = bits & 16 != 0;
		v.orientation = bits & 32 != 0 ? Portrait : bits & 64 != 0 ? Landscape : null;
	}
}

private class SettingsState {
	public final textScale:helder.view.graph.Signal<Float>;
	public final reducedMotion:helder.view.graph.Signal<Bool>;
	public final reducedTransparency:helder.view.graph.Signal<Bool>;
	public final contrast:helder.view.graph.Signal<Contrast>;
	public final dark:helder.view.graph.Signal<Bool>;
	public final orientation:helder.view.graph.Signal<Null<Orientation>>;

	// (shared: the system's, the same in every screen's store, its watcher's writes seen by all)
	public function new(v:SettingsValues) {
		textScale = Graph.signalOf(v.textScale, {shared: true});
		reducedMotion = Graph.signalOf(v.reducedMotion, {shared: true});
		reducedTransparency = Graph.signalOf(v.reducedTransparency, {shared: true});
		contrast = Graph.signalOf(v.contrast, {shared: true});
		dark = Graph.signalOf(v.dark, {shared: true});
		orientation = Graph.signalOf(v.orientation, {shared: true});
	}
}
