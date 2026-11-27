package studio;

import helder.asset.Embed;

// The agent's guide (studio.guide {topic}): a fast start and the APIs a
// topic needs, each short, its TypeScript built by Guides.test.hx so that
// it stays true (apps/studio/guide/*.md, embedded)
class Guides {
	public static final topics:Array<{name:String, about:String, text:String}> = [
		{name: "start", about: "the project's files, screens as scenarios, design frames and groups, the loop, what builds take", text: Embed.bytes("guide/start.md").toString()},
		{name: "ui", about: "views, text, layout (flex, gap), styles, signals, lists, events", text: Embed.bytes("guide/ui.md").toString()},
		{name: "game", about: "a per-frame step, keys and the pointer, shapes that move, timing; a paddle and a ball", text: Embed.bytes("guide/game.md").toString()},
		{name: "design", about: "design files: frames and groups, sketched at once", text: Embed.bytes("guide/design.md").toString()},
		{name: "assets", about: "images, fonts and sound from the project", text: Embed.bytes("guide/assets.md").toString()},
		{name: "3d", about: "3D as markup: a <Scene> of meshes, lights and a camera, posed by stories; markup only", text: Embed.bytes("guide/3d.md").toString()},
	];

	// a topic's text (null: start), the others listed after it; an unknown one a thrown message
	public static function get(topic:Null<String>):String {
		var t = Lambda.find(topics, t -> t.name == (topic ?? "start"));
		if (t == null) throw 'no topic $topic (${[for (t in topics) t.name].join(", ")})';
		return t.text + "\n---\nTopics (studio.guide {topic}): " + [for (o in topics) '${o.name}: ${o.about}'].join("; ") + "\n";
	}
}
