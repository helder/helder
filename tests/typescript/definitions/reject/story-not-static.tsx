// a story's name is static (in Haxe: RejectStoryNotStatic.hx).
// expect: definitions); write each story as a literal story({name, width, height, render}) at the module's top level
import {story} from "helder/story";

export function f() {
	const title = "Card";
	return story({name: title, render: (c) => <view/>});
}
