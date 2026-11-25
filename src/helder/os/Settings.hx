package helder.os;

import helder.view.graph.Graph;
import helder.view.graph.Read;

#if (target.name == "hxmc")
import hxmc.Platform;
#end

typedef SettingsValues = {
	var textScale:Float;
	var reducedMotion:Bool;
	var contrast:Contrast;
	var dark:Bool;
	var orientation:Null<Orientation>;
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
	@:typescript public static var contrast(get, never):Read<Contrast>;
	@:typescript public static var dark(get, never):Read<Bool>;
	@:typescript public static var orientation(get, never):Read<Null<Orientation>>;

	static var state:Null<SettingsState>;

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

	static function get_textScale():Read<Float> return current().textScale;
	static function get_reducedMotion():Read<Bool> return current().reducedMotion;
	static function get_contrast():Read<Contrast> return current().contrast;
	static function get_dark():Read<Bool> return current().dark;
	static function get_orientation():Read<Null<Orientation>> return current().orientation;

	static function refresh() {
		var v = values(), s = state;
		if (s.textScale.peek() != v.textScale) s.textScale(v.textScale);
		if (s.reducedMotion.peek() != v.reducedMotion) s.reducedMotion(v.reducedMotion);
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
		var v:SettingsValues = {textScale: 1, reducedMotion: false, contrast: Normal, dark: false, orientation: null};
		#if (target.name == "hxmc")
		#if helder.headless
		v.dark = App.prefersDark();
		v.reducedMotion = helder.headless.Headless.run.reducedMotion;
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
	public final contrast:helder.view.graph.Signal<Contrast>;
	public final dark:helder.view.graph.Signal<Bool>;
	public final orientation:helder.view.graph.Signal<Null<Orientation>>;

	public function new(v:SettingsValues) {
		textScale = Graph.signal(v.textScale);
		reducedMotion = Graph.signal(v.reducedMotion);
		contrast = Graph.signal(v.contrast);
		dark = Graph.signal(v.dark);
		orientation = Graph.signal(v.orientation);
	}
}
