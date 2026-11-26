package helder.os;

import helder.os.locale.*;
import helder.view.graph.Graph;
import helder.view.graph.Read;
import helder.view.graph.Signal;

#if (target.name == "hxmc")
import hxmc.Platform;
#end

// The device's preferred languages.
class Locale {
	@:typescript public static var current(get, never):Read<String>;
	static var tag:Null<Signal<String>>;
	static var languages:Array<String>;
	// (the current screen's language over the device's: helder.ui.ScreenContext sets it, a scenario's locale)
	@:noCompletion public static var screen:Null<String> = null;

	static function get_current():Read<String> {
		var s = screen;
		if (s != null) return (new helder.view.graph.Read.Const(s) : helder.view.graph.Read.Reader<String>);
		init();
		return tag;
	}

	// An ordered list of the user's preferred language tags.
	@:typescript public static function preferred():Array<String> {
		var s = screen;
		if (s != null) return [s];
		init();
		return languages.copy();
	}

	static function init() {
		if (tag != null) return;
		languages = preferences();
		// (shared: the device's, the same in every screen's store, its watcher's writes seen by all)
		tag = Graph.signalOf(languages[0], {shared: true});
		#if (target.name == "hxmc")
		#if (!helder.os || helder.os == "web")
		if (Platform.os() == Platform.WASI) {
			helder.os.locale.web.Locale.watch(refresh);
		} else
		#end
		#if !helder.headless
		if (!(Platform.os() == Platform.LINUX && Platform.target() < 2)) {
			@:privateAccess App.watchSettings(refresh);
		}
		#else {} #end
		#elseif js
		js.Syntax.code("globalThis.addEventListener?.('languagechange', {0})", refresh);
		js.Syntax.code("globalThis.document?.addEventListener('visibilitychange', () => { if (!document.hidden) {0}(); })", refresh);
		#end
	}

	static function refresh() {
		languages = preferences();
		if (tag.peek() == languages[0]) return;
		tag(languages[0]);
		Graph.flush();
	}

	static function preferences():Array<String> {
		var tags = [];
		#if (target.name == "hxmc")
		if (Platform.os() == Platform.WASI) {
			#if (!helder.os || helder.os == "web") tags = helder.os.locale.web.Locale.preferred(); #end
		} else if (Platform.os() == Platform.WINDOWS) {
			#if (!helder.os || helder.os == "windows") tags = helder.os.locale.windows.Locale.preferred(); #end
		} else if (Platform.os() == Platform.MACOS) {
			#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
			tags = helder.os.locale.apple.Locale.preferred();
			#end
		} else if (Platform.target() >= 9) {
			#if (!helder.os || helder.os == "android") tags = helder.os.android.AndroidLocale.preferred(); #end
		} else {
			tags = LocaleFallback.preferred(Sys.getEnv);
		}
		#elseif js
		tags = js.Syntax.code("Array.from(globalThis.navigator?.languages ?? [])");
		#elseif sys
		tags = LocaleFallback.preferred(Sys.getEnv);
		#end
		return LocaleTag.preferred(tags);
	}

}
