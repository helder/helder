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

	static function get_current():Read<String> {
		init();
		return tag;
	}

	// An ordered list of the user's preferred language tags.
	@:typescript public static function preferred():Array<String> {
		init();
		return languages.copy();
	}

	static function init() {
		if (tag != null) return;
		languages = preferences();
		tag = Graph.signal(languages[0]);
		#if (target.name == "hxmc")
		#if (!helder.os || helder.os == "web")
		if (Platform.os() == Platform.WASI) {
			LocaleWeb.watch(refresh);
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
			#if (!helder.os || helder.os == "web") tags = LocaleWeb.preferred(); #end
		} else if (Platform.os() == Platform.WINDOWS) {
			#if (!helder.os || helder.os == "windows") tags = WindowsLocale.preferred(); #end
		} else if (Platform.os() == Platform.MACOS) {
			#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
			tags = AppleLocale.preferred();
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
