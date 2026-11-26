package helder.story;

import helder.story.Story;

// A project's stories as the studio's screens (apps/studio): the program
// the studio builds of a project (a dev build, -D hxmc.dev) runs every
// story in one program, the studio's preview host (helder.story.Host: each
// story a root of its own with a context of its own): natively one process
// (helder.story.NativeHost: its frames GPU textures the studio's process
// opens, or shared memory where the GPU shares none), built for the web
// (wasm32-wasi) a worker (helder.story.web.Preview). Over the devtools
// protocol `Studio.screens` answers the screens: {screens: [{name, width,
// height}]}.
//
//   // the studio's generated main (bin/studio/<name>/gen/StudioScreens.hx, screens.tsx)
//   helder.story.Screens.run(helder.story.Stories.of("Todo_story"));
//   import { screens } from "helder/story"; screens([empty, items]);
class Screens {
	// (scenarios: the program's moments, its main run for each: helder.scenario)
	public static function run(stories:Array<Story>, ?scenarios:Array<helder.scenario.Scenario>, ?program:Void->Void) {
		var list = [for (s in stories) if (s != null) s];
		var acts = [for (s in scenarios ?? []) if (s != null) s];
		if (list.length == 0 && acts.length == 0) throw "helder.story.Screens: no stories (a release build has none)";
		#if (hxmc.target == "wasm32-wasi")
		helder.story.web.Preview.run(list, acts, program);
		#else
		helder.story.NativeHost.run(list, acts, program);
		#end
	}

	// one story in a window of its own, at its size, live, its input its own:
	// the studio's Play (`helder dev` on a main of it, rebuilt in place)
	//
	//   import { play } from "helder/story"; import { serve } from "./pong.story"; play(serve);
	public static function play(story:Story) {
		if (story == null) throw "helder.story.Screens.play: no story (a release build has none)";
		var c = new Controls(story.seed);
		helder.ui.UiWindow.run(helder.ui.UiWindow.Surface({
			title: story.name,
			width: story.width ?? Stories.WIDTH,
			height: story.height ?? Stories.HEIGHT,
			children: story.build(c)
		}));
	}
}
