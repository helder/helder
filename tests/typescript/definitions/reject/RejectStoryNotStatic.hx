// a story's name is static (in TypeScript: story-not-static.tsx).
// expect: definitions); write each story as a literal story({name, width, height, render}) at the module's top level
import helder.story.Story;

class RejectStoryNotStatic {
	static function main() {
		var title = "Card";
		trace(story({name: title, render: c -> helder.view.View.view(<view/>)}));
	}
}
