package studio;

using StringTools;

// The project an empty folder starts as (the studio opened on one, its
// Untitled one): the smallest TypeScript helder program that builds and
// shows on the canvas, so that the agent starts from something that works:
// main.tsx (the app's window), app.tsx (its view, plain: until the agent
// changes the project the canvas holds its places: Watch's queued blocks), app.story.tsx
// (one screen, the canvas' frame), tsconfig.json (helder's modules where they
// are: config). A TypeScript project outside a package with helder in it
// gets that tsconfig.json too, when it has none (an agent's first main.tsx).
class Starter {
	// whether dir was empty and is the starter now
	public static function write(dir:String):Bool {
		#if (hxmc.target == "wasm32-wasi")
		return false;
		#else
		if (!empty(dir)) return false;
		Files.save('$dir/main.tsx', MAIN);
		Files.save('$dir/app.tsx', APP);
		Files.save('$dir/app.story.tsx', STORY);
		Files.save('$dir/.gitignore', "bin/\n");
		config(dir);
		return true;
		#end
	}

	// (nothing in it but dot files)
	public static function empty(dir:String):Bool
		return Files.isDirectory(dir) && !Lambda.exists(Files.list(dir), n -> !n.startsWith("."));

	// a tsconfig.json mapping helder's modules to the helder the studio was
	// built with, when the project has none and no package resolves them
	public static function config(dir:String) {
		#if !(hxmc.target == "wasm32-wasi")
		if (Files.exists('$dir/tsconfig.json') || resolves(dir)) return;
		var src = BuildInfo.helderSrc();
		Files.save('$dir/tsconfig.json', haxe.Json.stringify({
			compilerOptions: {paths: {"helder/*": ['$src/helder/*/index.d.ts', '$src/helder/*/index.ts', '$src/helder/*.ts']}}
		}, "\t") + "\n");
		#end
	}

	// TypeScript's checker for a project outside any package (found from its
	// folder up, then the working directory's, which an Untitled project's are
	// not under): the one beside the helder the studio was built with, unless
	// HELDER_TYPESCRIPT names one
	public static function typescript() {
		#if !(hxmc.target == "wasm32-wasi")
		if ((Sys.getEnv("HELDER_TYPESCRIPT") ?? "") != "") return;
		var d = haxe.io.Path.normalize(BuildInfo.helderSrc());
		while (d != "" && d != "/") {
			if (Files.exists('$d/node_modules/typescript/dist/api/node/protocol.js')) {
				Sys.putEnv("HELDER_TYPESCRIPT", '$d/node_modules/typescript');
				return;
			}
			var up = haxe.io.Path.directory(d);
			if (up == d) return;
			d = up;
		}
		#end
	}

	// (helder found as a bundler finds it: node_modules/helder, or the package helder itself, at or above dir)
	static function resolves(dir:String):Bool {
		var d = haxe.io.Path.normalize(dir);
		while (d != "" && d != "/") {
			if (Files.exists('$d/node_modules/helder')) return true;
			if (Files.exists('$d/package.json') && (try haxe.Json.parse(Files.read('$d/package.json')).name == "helder" catch (_:Dynamic) false)) return true;
			var up = haxe.io.Path.directory(d);
			if (up == d) break;
			d = up;
		}
		return false;
	}

	static inline var MAIN = '// The app in a window (`helder run .`); its screens are the stories (app.story.tsx)
import { UiWindow, Surface } from "helder/ui";
import { App } from "./app";

UiWindow.run(
	<Surface title="App" width={480} height={640}>
		<App/>
	</Surface>
);
';

	static inline var APP = 'export function App() {
	return <view grow={1} align-items="center" justify="center" background="#ffffff">
		<text font-size={14} color="#71717a">App</text>
	</view>;
}
';

	static inline var STORY = '// The canvas\' screens: each story a frame, named Flow/Screen
import { story } from "helder/story";
import { App } from "./app";

export const start = story({ name: "App/Start", width: 480, height: 640, render: () => <App/> });
';
}
