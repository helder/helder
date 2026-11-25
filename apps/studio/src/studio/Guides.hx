package studio;

import helder.asset.Asset;

// The agent's guide (studio.guide {topic}): a fast start and the APIs a
// topic needs, each short, its TypeScript built by Guides.test.hx so that
// it stays true (apps/studio/guide/*.md, embedded)
class Guides {
	public static final topics:Array<{name:String, about:String, text:String}> = [
		{name: "start", about: "the project's files, screens as stories, design frames and groups, the loop, what builds take", text: Asset.embed("guide/start.md").toString()},
		{name: "ui", about: "views, text, layout (flex, gap), styles, signals, lists, events", text: Asset.embed("guide/ui.md").toString()},
		{name: "game", about: "a per-frame step, keys and the pointer, shapes that move, timing; a paddle and a ball", text: Asset.embed("guide/game.md").toString()},
		{name: "design", about: "design files: frames and groups, sketched at once", text: Asset.embed("guide/design.md").toString()},
		{name: "assets", about: "images, fonts and sound from the project", text: Asset.embed("guide/assets.md").toString()},
	];

	// a topic's text (null: start), the others listed after it; an unknown one a thrown message
	public static function get(topic:Null<String>):String {
		var t = Lambda.find(topics, t -> t.name == (topic ?? "start"));
		if (t == null) throw 'no topic $topic (${[for (t in topics) t.name].join(", ")})';
		return t.text + "\n---\nTopics (studio.guide {topic}): " + [for (o in topics) '${o.name}: ${o.about}'].join("; ") + "\n";
	}
}
