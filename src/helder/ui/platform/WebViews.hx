package helder.ui.platform;

import helder.gfx.Color;
import helder.os.web.Dom;
import helder.ui.*;
import hxmc.unsafe.*;

// The browser's own views over a window's canvas (Ui.platform there): text
// editors, an input or a textarea of the page placed where their nodes are
// laid out (UiWindow sets it up in the browser; imports of the module
// "hxmc_ui", src/helder/ui/imports.mjs). An editor's events are queued on the
// page and polled before each layout.
@:hxmc.c @:hxmc.lib("hxmc_ui") extern class WebEditors {
	// an editor over that canvas (multiline: a textarea), its handle
	static function editor_create(canvas:Int, multiline:Int):Int;
	static function editor_text(h:Int, text:CString, start:Int, end:Int):Void;
	static function editor_select(h:Int, start:Int, end:Int):Void;
	// what a phone's keyboard shows for it: its keyboard (the input's type
	// and inputmode), enterkeyhint, autocapitalize, autocorrect (and spellcheck)
	static function editor_kind(h:Int, keyboard:CString, enter:CString, capitalize:CString, autocorrect:Int):Void;
	// its place in the canvas's CSS pixels; shown 0: hidden
	static function editor_place(h:Int, x:Float, y:Float, width:Float, height:Float, shown:Int):Void;
	// its CSS (font, colour, alignment, line height), placeholder and colour, whether a password's
	static function editor_style(h:Int, css:CString, placeholder:CString, placeholderColor:CString, secret:Int):Void;
	// the page's focus given (1) or taken back for the canvas (0)
	static function editor_focus(h:Int, on:Int):Void;
	static function editor_dispose(h:Int):Void;
	// the next event into p (five Int32: the handle; kind 1 edited (the
	// selection's start, end, the text's string handle), 2 focused, 3 blurred,
	// 4 a key left to the program (its key, mods)); 0: none
	static function editor_event(p:Ptr<Int32>):Int;
}

@:hxmc.unsafe(gc)
class WebViews implements PlatformViews {
	final canvas:Int;
	final editors = new Map<Int, WebEditor>();

	public function new(canvas:Int)
		this.canvas = canvas;

	public function editor(multiline:Bool):Null<PlatformEditor> {
		var h = WebEditors.editor_create(canvas, multiline ? 1 : 0);
		var e = new WebEditor(this, h);
		editors[h] = e;
		return e;
	}

	// (a page has no menus of its own to show: the drawn one)
	public function menu(items:Array<PlatformMenuItem>, x:Float, y:Float, chosen:Int->Void):Bool
		return false;

	public function menuBar(menus:Array<PlatformMenuItem>, chosen:Int->Void):Bool
		return false;

	@:allow(helder.ui.platform.WebEditor) function forget(h:Int)
		editors.remove(h);

	public function poll()
		Arena.scoped(a -> {
			var p:Ptr<Int32> = a.alloc(20);
			while (WebEditors.editor_event(p) != 0) {
				var e = editors[p[0]], l = e == null ? null : e.listener;
				switch p[1] {
					case 1:
						var t = take(p[4]);
						if (l != null) l.editorEdited(t, p[2], p[3]);
					case 2:
						if (l != null) l.editorFocused(true);
					case 3:
						if (l != null) l.editorFocused(false);
					case 4:
						if (l != null) l.editorKey(p[2], p[3]);
					case _:
				}
			}
		});

	// a string handle's text (the handle freed)
	static function take(h:Int):String {
		var n = Dom.text_length(h);
		var b = haxe.io.Bytes.alloc(n);
		Arena.scoped(a -> {
			var p = a.alloc(n + 1, 1);
			Dom.text_take(h, p);
			BytesPtr.copyIn(b, 0, p, n);
		});
		return b.toString();
	}
}

@:hxmc.unsafe(gc)
class WebEditor implements PlatformEditor {
	// (in a window whose layers are the page's: its element stacked among
	// them, by the number EDITOR | its handle, helder.ui.layers.web.Layers)
	public function slot():Null<helder.ui.LayerSlot> {
		if (hosted == null) hosted = new helder.ui.LayerSlot(Ptr.ofI64(EDITOR | h));
		return hosted;
	}

	public static inline var EDITOR = 1 << 24;

	var hosted:Null<helder.ui.LayerSlot> = null;

	final views:WebViews;
	final h:Int;

	public var listener(default, null):Null<PlatformEditorListener> = null;

	public function new(views:WebViews, h:Int) {
		this.views = views;
		this.h = h;
	}

	public function listen(l:PlatformEditorListener)
		listener = l;

	public function setText(text:String, start:Int, end:Int)
		Arena.scoped(a -> WebEditors.editor_text(h, a.cstring(text), start, end));

	public function select(start:Int, end:Int)
		WebEditors.editor_select(h, start, end);

	public function setKind(k:helder.os.TextKind)
		Arena.scoped(a -> WebEditors.editor_kind(h, a.cstring(k.keyboard), a.cstring(k.enter), a.cstring(k.capitalize), k.autocorrect ? 1 : 0));

	public function place(x:Float, y:Float, width:Float, height:Float, shown:Bool)
		WebEditors.editor_place(h, x, y, width, height, shown ? 1 : 0);

	// (transparent over the drawn box: the background unused)
	public function setStyle(font:Font, color:Color, background:Color, placeholder:String, placeholderColor:Color, align:TextAlign, secret:Bool) {
		var css = 'font: ${font.italic ? "italic " : ""}${font.weight} ${font.size}px "${font.family}"; line-height: ${font.size * font.lineHeight}px; color: ${rgba(color)}; text-align: ${align == Center ? "center" : align == Right ? "right" : align == Justify ? "justify" : "left"};';
		Arena.scoped(a -> WebEditors.editor_style(h, a.cstring(css), a.cstring(placeholder), a.cstring(rgba(placeholderColor)), secret ? 1 : 0));
	}

	static function rgba(c:Color):String
		return 'rgba(${c.r}, ${c.g}, ${c.b}, ${c.a / 255})';

	public function focus(on:Bool)
		WebEditors.editor_focus(h, on ? 1 : 0);

	public function dispose() {
		WebEditors.editor_dispose(h);
		@:privateAccess views.forget(h);
		listener = null;
	}
}
