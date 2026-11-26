package helder.ui.controls;

import helder.test.Test;
import helder.ui.*;

function tests() {
	test("a one-line field keeps line breaks typed or given on its line, as a paste does", () -> {
		var ui = new Ui(new helder.story.StoryText(), 300, 100), f = new TextField();
		ui.root.append(f);
		ui.update();
		var high = f.height;
		ui.setFocus(f);
		ui.textInput("a\nb\r\nc");
		f.replaceText(f.text.length, f.text.length, "\rd");
		ui.update();
		equals([f.text, Std.string(f.height)], ["a b c d", Std.string(high)]);
		f.setText("e\nf");
		ui.update();
		equals([f.text, Std.string(f.height)], ["e f", Std.string(high)]);
	});
}
