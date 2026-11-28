package helder.ui.fast;

import helder.os.Mods;
import helder.text.Grapheme;
import helder.ui.Event;
import helder.ui.Key;

// A field of one line typed into: its value, a caret and a selection
// (keys, the clipboard), its placeholder while it is empty (styled by the
// placeholder state's variant). Its Tree gives it the keys and the text
// typed while it has the focus.
//
//   final draft = new FieldNode(Style.of({padding: [8, 12], placeholder: {color: 0xFFA1A1AA}}));
//   draft.placeholder = "What needs to be done?";
//   draft.onInput = e -> trace(e.text);
class FieldNode extends TextNode {
	public var value(default, set) = "";
	public var placeholder(default, set) = "";
	// its value changed by its user (Event.text: the value)
	public var onInput:Null<Event->Void> = null;

	// (UTF-16 indices: where typing goes, the selection's other end)
	@:allow(helder.ui.fast) var caret = 0;
	@:allow(helder.ui.fast) var anchor = 0;

	public function new(?style:Style) {
		super("", style);
		focusable = true;
		semantics = {role: TextInput};
		shown();
	}

	override function blank():Node
		return new FieldNode();

	override function copied(c:Node) {
		var f:FieldNode = cast c;
		f.placeholder = placeholder;
		f.value = value;
	}

	function set_value(v:String):String {
		v ??= "";
		if (v == value) return v;
		value = v;
		caret = Std.int(Math.min(caret, v.length));
		anchor = Std.int(Math.min(anchor, v.length));
		shown();
		return v;
	}

	function set_placeholder(v:String):String {
		placeholder = v ?? "";
		shown();
		return placeholder;
	}

	// (its value, else its placeholder in the placeholder state)
	function shown() {
		state(Style.PLACEHOLDER, value == "");
		text = value == "" ? placeholder : value;
	}

	@:allow(helder.ui.fast) inline function from():Int
		return caret < anchor ? caret : anchor;

	@:allow(helder.ui.fast) inline function to():Int
		return caret < anchor ? anchor : caret;

	// s over the selection, typed by its user
	@:allow(helder.ui.fast) function typed(s:String, ui:Null<helder.ui.Ui>, target:helder.ui.Node) {
		var a = from(), b = to();
		value = value.substr(0, a) + s + value.substr(b);
		caret = anchor = a + s.length;
		shown();
		if (onInput != null) {
			var e = Event.of(Input, target, 0, 0);
			e.text = value;
			onInput(e);
		}
	}

	function move(i:Int, extend:Bool) {
		caret = i;
		if (!extend) anchor = i;
	}

	// (a key while it has the focus: true when it was its)
	@:allow(helder.ui.fast) function key(e:Event, ui:Null<helder.ui.Ui>, target:helder.ui.Node):Bool {
		var shift = e.mods & Mods.SHIFT != 0, ctrl = e.mods & (Mods.CONTROL | Mods.META) != 0;
		// (by words: Control, or Alt as macOS's Option; Command+Left and Right: the ends)
		var word = e.mods & (Mods.CONTROL | Mods.ALT) != 0, edge = e.mods & Mods.META != 0;
		var v = value, sel = caret != anchor;
		switch e.key {
			case Key.LEFT if (edge): move(0, shift);
			case Key.RIGHT if (edge): move(v.length, shift);
			case Key.LEFT if (word): move(prevWord(caret), shift);
			case Key.RIGHT if (word): move(nextWord(caret), shift);
			case Key.LEFT: move(sel && !shift ? from() : Grapheme.prev(v, caret), shift);
			case Key.RIGHT: move(sel && !shift ? to() : Grapheme.next(v, caret), shift);
			case Key.HOME: move(0, shift);
			case Key.END: move(v.length, shift);
			case Key.BACKSPACE:
				if (!sel) anchor = word ? prevWord(caret) : Grapheme.prev(v, caret);
				typed("", ui, target);
			case Key.DELETE:
				if (!sel) anchor = word ? nextWord(caret) : Grapheme.next(v, caret);
				typed("", ui, target);
			case "a".code if (ctrl):
				anchor = 0;
				caret = v.length;
			case "c".code if (ctrl):
				if (sel && ui != null) ui.clipboard.write(v.substring(from(), to()));
			case "x".code if (ctrl):
				if (sel && ui != null) {
					ui.clipboard.write(v.substring(from(), to()));
					typed("", ui, target);
				}
			case "v".code if (ctrl):
				if (ui != null) ui.clipboard.read(t -> if (t != null && t != "") typed(StringTools.replace(StringTools.replace(t, "\r", ""), "\n", " "), ui, target));
			case _:
				return false;
		}
		return true;
	}

	function prevWord(i:Int):Int {
		while (i > 0 && !isWord(i - 1)) i--;
		while (i > 0 && isWord(i - 1)) i--;
		return i;
	}

	function nextWord(i:Int):Int {
		while (i < value.length && !isWord(i)) i++;
		while (i < value.length && isWord(i)) i++;
		return i;
	}

	function isWord(i:Int):Bool {
		var c = StringTools.fastCodeAt(value, i);
		return c != " ".code && c != "\t".code && c != ".".code && c != ",".code && c != "-".code;
	}
}
