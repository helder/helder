package helder.ui.menu;

import helder.test.Test;
import helder.ui.*;

function tests() {
	test("a menu taller than the window: inside it, its choices scrolled, the last reached", () -> {
		var ui = new Ui(new helder.story.StoryText(), 400, 200);
		var choices:Array<TouchMenu.Choice> = [for (i in 0...30) {label: 'Choice $i', run: () -> {}}];
		TouchMenu.open(ui, choices, {x: 20, y: 20, width: 40, height: 40}, null, false);
		ui.update();
		var menu = ui.overlay.find("touch-menu"), b = menu.windowBounds();
		assert(b.y >= 0 && b.y + b.height <= 200, 'at ${b.y}, ${b.height} high');
		ui.wheel(b.x + 10, b.y + 10, 0, 1e5);
		ui.update();
		var last = menu.find("menu-Choice 29").windowBounds();
		assert(last.y + last.height <= b.y + b.height + 0.5, 'the last at ${last.y}');
	});
	test("the window resized: dismissed, as the platforms' menus are", () -> {
		var ui = new Ui(new helder.story.StoryText(), 400, 300), closed = 0;
		TouchMenu.open(ui, [{label: "One", run: () -> {}}], {x: 20, y: 20, width: 40, height: 40}, null, false, null, () -> closed++);
		ui.update();
		ui.resize(300, 400);
		ui.update();
		equals([closed, ui.overlay.children.length], [1, 0]);
	});
}
