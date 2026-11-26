package studio;

using StringTools;

// The project an empty folder starts as (the studio opened on one, its
// Untitled one): the smallest TypeScript helder program that builds and
// shows on the canvas, so that the agent starts from something that works:
// main.tsx (the app's window), app.tsx (its model, a top-level signal, and
// its view, plain: until the agent changes the project the canvas holds its
// places: Watch's queued blocks), app.scenario.tsx (one screen, the app at
// its start: the canvas' frame), tsconfig.json (helder's modules where they
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
		Files.save('$dir/app.scenario.tsx', SCENARIO);
		Files.save('$dir/.gitignore', "bin/\n");
		config(dir);
		return true;
		#end
	}

	// whether a screen is the starter's own: its scenario, its files as written
	// (an agent that makes it its own, editing them, has it shown)
	public static function own(dir:String, docs:Docs, name:String):Bool {
		if (name != "App/Start") return false;
		docs.version();
		function is(f:String, text:String):Bool
			return docs.has('$dir/$f') && docs.get('$dir/$f').text == text;
		return is("app.scenario.tsx", SCENARIO) && is("app.tsx", APP) && is("main.tsx", MAIN);
	}

	// the starter's files the agent's own project no longer needs: each
	// (app.scenario.tsx, then app.tsx) as the starter wrote it, once a screen
	// of the agent's is there, and no other file imports it; its scenario
	// while App/Start is the starter's still (its app.tsx edited: the agent's)
	public static function unused(dir:String, docs:Docs, sources:Array<String>, ownStory:Bool, starterStory:Bool):Array<String> {
		if (!ownStory) return [];
		var out = [];
		for (f in [{name: "app.scenario.tsx", text: SCENARIO, module: "app\\.scenario"}, {name: "app.tsx", text: APP, module: "app"}]) {
			var path = '$dir/${f.name}';
			if (f.name == "app.scenario.tsx" && !starterStory) continue;
			if (!docs.has(path) || docs.get(path).text != f.text) continue;
			var imports = new EReg('[\'"]\\./${f.module}(\\.tsx?)?[\'"]', "");
			if (!Lambda.exists(sources, s -> s != path && !out.contains(s) && docs.has(s) && imports.match(docs.get(s).text))) out.push(path);
		}
		return out;
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

	static inline var MAIN = '// The app in a window (`helder run .`); its moments on the canvas are scenarios (app.scenario.tsx)
import { UiWindow, Surface } from "helder/ui";
import { App } from "./app";

UiWindow.run(
	<Surface title="App" width={480} height={640}>
		<App/>
	</Surface>
);
';

	static inline var APP = 'import { signal } from "helder/view";

// the app\'s model: exported top-level signals, which a scenario\'s boot sets
export const title = signal("App");

export function App() {
	return <view flexGrow={1} alignItems="center" justifyContent="center" background="#ffffff">
		<text fontSize={14} color="#71717a">{title()}</text>
	</view>;
}
';

	static inline var SCENARIO = '// The canvas\' screens: each scenario the app (main.tsx) at a moment, named Flow/Screen
import { scenario } from "helder/scenario";

export const start = scenario({ name: "App/Start" });
';
}
