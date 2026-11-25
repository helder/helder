package helder.test;

import helder.ui.Ui;
import helder.ui.actions.Keymap;
import helder.ui.actions.Keystroke;

@:noCompletion
class UiScript {
	// on macOS secondary is Command (Keymap.mac, known at start)
	public static function setMac(mac:Bool):Void
		Keymap.mac = mac;

	// a Ui of no window (tests), its text helder's own (helder.story's, the same on every system)
	public static function headless(width:Float, height:Float):Ui {
		helder.text.Shaping.engine = helder.text.Shaping.HELDER;
		return new Ui(new helder.story.StoryText(), width, height);
	}

	// content rendered into its root and laid out (dispose removes it)
	public static function mount(ui:Ui, content:helder.view.View):Void->Void {
		var dispose = helder.view.Render.render(content, ui.root);
		ui.update();
		return dispose;
	}

	public static function layout(ui:Ui):Void
		ui.update();

	// each keystroke of keys typed ("ctrl-k ctrl-s"), through the keymap
	public static function type(ui:Ui, keys:String):Void
		for (k in Keystroke.sequence(keys))
			ui.keyDown(k.key, k.held());
}
