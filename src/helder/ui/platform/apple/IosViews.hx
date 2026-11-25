package helder.ui.platform.apple;

import helder.os.apple.objc.*;
import helder.os.apple.Traits;
import helder.ui.*;
import hxmc.unsafe.*;

// iOS's own views over a window (Ui.platform there): a text field a
// UITextField, a text area a UITextView, borderless and transparent over
// the window's view (above the drawn surface), placed where their nodes'
// content boxes are laid out (points: the layout's pixels), in the node's
// font (by family, else the system's at its weight), colour and alignment,
// the placeholder in the theme's colour; their keyboard the node's
// TextKind (Traits: keyboard and return key types, capitalisation,
// corrections, secure entry, AutoFill's content type). So UIKit's own
// editing is the app's: marked text (Japanese, Chinese, Korean
// compositions, dictation) shown and committed by UIKit, the selection's
// handles, the loupe, the edit menu, autocorrection. One delegate
// (HxmcTextDelegate, made at first use) hears them all: an edit (a field's
// UIControlEventEditingChanged, a text view's textViewDidChange:), the
// selection moved, editing begun and ended (the focus), Return on one
// line (textFieldShouldReturn:: Enter, the program's); each queued, a frame
// asked for, and handed over at the next poll, where the text and
// selection are read; not while marked text is there (the node gets the
// text once committed). The keyboard's focus taken back is let go of at
// the next poll, so that moving it to another field keeps the keyboard up.
// The views are the main thread's (helder.os.OsThread): made, changed and
// read there; what the delegate hears while the program runs on is queued
// at its next call (OsThread.soon).
// No menus of its own: the drawn ones.
@:allow(helder.ui)
@:hxmc.unsafe(gc)
class IosViews implements helder.ui.platform.PlatformViews {
	static var delegate = Ptr.nil();
	static final editors:Array<IosEditor> = [];

	final view:Ptr;
	final ui:Ui;
	final queue:Array<{e:IosEditor, kind:Int}> = [];
	// (an editor whose focus went: it resigns at the next poll unless another took it)
	var resigning:Null<IosEditor> = null;

	public function new(view:Ptr, ui:Ui) {
		this.view = view;
		this.ui = ui;
		if (delegate.isNull()) helder.os.OsThread.run(classes);
	}

	static function classes() {
		// (hxmc dev's host: the class an earlier build made, its methods this build's)
		var d = ObjC.cls("HxmcTextDelegate"), fresh = d.isNull();
		if (fresh) d = Runtime.objc_allocateClassPair(ObjC.cls("NSObject"), Mem.cstr("HxmcTextDelegate"), 0);
		inline function method(sel:String, imp:Ptr, types:String)
			Runtime.class_replaceMethod(d, ObjC.sel(sel), imp, Mem.cstr(types));
		method("hxmcChanged:", Callback.addr(changed), "v@:@");
		method("textFieldDidBeginEditing:", Callback.addr(began), "v@:@");
		method("textFieldDidEndEditing:", Callback.addr(ended), "v@:@");
		method("textFieldDidChangeSelection:", Callback.addr(selected), "v@:@");
		method("textFieldShouldReturn:", Callback.addr(returned), "B@:@");
		method("textViewDidChange:", Callback.addr(changed), "v@:@");
		method("textViewDidBeginEditing:", Callback.addr(began), "v@:@");
		method("textViewDidEndEditing:", Callback.addr(ended), "v@:@");
		method("textViewDidChangeSelection:", Callback.addr(selected), "v@:@");
		if (fresh) Runtime.objc_registerClassPair(d);
		delegate = Msg.id(Msg.id(d, ObjC.sel("alloc")), ObjC.sel("init"));
	}

	public function editor(multiline:Bool):Null<helder.ui.platform.PlatformEditor>
		return helder.os.OsThread.get(() -> editorNow(multiline));

	function editorNow(multiline:Bool):Null<helder.ui.platform.PlatformEditor> {
		var v = Arena.scopedValue(a -> {
			var r = a.make(CGRect);
			r.value.size.width = 10;
			r.value.size.height = 10;
			Msg.idRect(Msg.id(multiline ? ObjC.cls("UITextView") : ObjC.cls("UITextField"), ObjC.sel("alloc")), ObjC.sel("initWithFrame:"), r.value);
		});
		Msg.vPtr(v, ObjC.sel("setBackgroundColor:"), Msg.id(ObjC.cls("UIColor"), ObjC.sel("clearColor")));
		Msg.vBool(v, ObjC.sel("setHidden:"), true);
		Msg.vPtr(v, ObjC.sel("setDelegate:"), delegate);
		if (multiline) {
			Arena.scoped(a -> Msg.vInsets(v, ObjC.sel("setTextContainerInset:"), a.make(UIEdgeInsets).value));
			Msg.vFloat(Msg.id(v, ObjC.sel("textContainer")), ObjC.sel("setLineFragmentPadding:"), 0);
		} else {
			Msg.vInt(v, ObjC.sel("setBorderStyle:"), 0); // UITextBorderStyleNone
			// (UIControlEventEditingChanged)
			Msg.vPtrPtrInt(v, ObjC.sel("addTarget:action:forControlEvents:"), delegate, ObjC.sel("hxmcChanged:"), 1 << 17);
		}
		var e = new IosEditor(this, v, multiline);
		// (in the system's layer tree: in a host, placed with the window's layers)
		if (ui.layered) {
			var h = helder.ui.layers.apple.LayerViews.host();
			Msg.vPtr(h, ObjC.sel("addSubview:"), v);
			Msg.vPtr(view, ObjC.sel("addSubview:"), h);
			e.hosted = new helder.ui.LayerSlot(h, true);
			e.hosted.inner = v;
		} else
			Msg.vPtr(view, ObjC.sel("addSubview:"), v);
		editors.push(e);
		return e;
	}

	public function menu(items:Array<helder.ui.platform.PlatformMenuItem>, x:Float, y:Float, chosen:Int->Void):Bool
		return false;

	public function menuBar(menus:Array<helder.ui.platform.PlatformMenuItem>, chosen:Int->Void):Bool
		return false;

	function push(e:IosEditor, kind:Int)
		helder.os.OsThread.soon(() -> {
			queue.push({e: e, kind: kind});
			ui.requestFrame();
		});

	// (hxmc dev's host, at a hand-over: the editors gone with this build, whose code they call)
	public function dispose()
		helder.os.OsThread.run(() -> {
			for (e in editors.copy())
				if (@:privateAccess e.views == this) e.disposeNow();
			queue.resize(0);
		});

	public function poll()
		helder.os.OsThread.run(pollNow);

	function pollNow() {
		var r = resigning;
		resigning = null;
		if (r != null && Msg.b(r.view, ObjC.sel("isFirstResponder"))) {
			r.focusing = true;
			Msg.b(r.view, ObjC.sel("resignFirstResponder"));
			r.focusing = false;
		}
		while (queue.length > 0) {
			var q = queue.shift(), e = q.e, l = e.listener;
			if (l == null) continue;
			switch q.kind {
				case 1 | 6:
					if (e.composing()) continue;
					var t = e.text(), s = e.selection();
					if (q.kind == 1 || t != e.reported) l.editorEdited(t, s[0], s[1]) else l.editorSelected(s[0], s[1]);
					e.reported = t;
				case 2:
					l.editorFocused(true);
				case 3:
					l.editorFocused(false);
				case 4:
					l.editorKey(Key.ENTER, 0);
				case _:
			}
		}
	}

	static function of(v:Ptr):Null<IosEditor> {
		for (e in editors)
			if (e.view == v) return e;
		return null;
	}

	@:hxmc.callback static function changed(self:Ptr, cmd:Ptr, v:Ptr) {
		var e = of(v);
		if (e != null && !e.focusing) e.views.push(e, 1);
	}

	@:hxmc.callback static function selected(self:Ptr, cmd:Ptr, v:Ptr) {
		var e = of(v);
		if (e != null && !e.focusing && !e.setting) e.views.push(e, 6);
	}

	@:hxmc.callback static function began(self:Ptr, cmd:Ptr, v:Ptr) {
		var e = of(v);
		if (e != null && !e.focusing) e.views.push(e, 2);
	}

	@:hxmc.callback static function ended(self:Ptr, cmd:Ptr, v:Ptr) {
		var e = of(v);
		if (e != null && !e.focusing) e.views.push(e, 3);
	}

	// (Return on one line: the program's Enter, no newline)
	@:hxmc.callback static function returned(self:Ptr, cmd:Ptr, v:Ptr):Int {
		var e = of(v);
		if (e != null) e.views.push(e, 4);
		return 0;
	}

	// a UIFont for a ui Font: its family's, else the system's at its weight; italic
	static function uiFont(f:Font):Ptr {
		var name = ObjC.str(f.family), cls = ObjC.cls("UIFont");
		var font = Msg.idPtrFloat(cls, ObjC.sel("fontWithName:size:"), name, f.size);
		ObjC.release(name);
		var traits = f.italic ? 1 : 0; // UIFontDescriptorTraitItalic
		if (font.isNull()) font = Msg.idFloatFloat(cls, ObjC.sel("systemFontOfSize:weight:"), f.size, weight(f.weight)) else if (f.weight >= 600) traits |= 2; // ...Bold
		if (traits == 0) return font;
		var d = Msg.idInt(Msg.id(font, ObjC.sel("fontDescriptor")), ObjC.sel("fontDescriptorWithSymbolicTraits:"), traits);
		return d.isNull() ? font : Msg.idPtrFloat(cls, ObjC.sel("fontWithDescriptor:size:"), d, f.size);
	}

	// (UIFontWeight: ultra light -0.8 ... regular 0, medium 0.23, semibold 0.3, bold 0.4, heavy 0.56, black 0.62)
	static function weight(w:Int):Float
		return w <= 100 ? -0.8 : w <= 200 ? -0.6 : w <= 300 ? -0.4 : w <= 400 ? 0 : w <= 500 ? 0.23 : w <= 600 ? 0.3 : w <= 700 ? 0.4 : w <= 800 ? 0.56 : 0.62;

	static function uiColor(c:Color):Ptr
		return Msg.idFloat4(ObjC.cls("UIColor"), ObjC.sel("colorWithRed:green:blue:alpha:"), c.r / 255, c.g / 255, c.b / 255, c.a / 255);
}

@:allow(helder.ui)
@:hxmc.unsafe(gc)
class IosEditor implements helder.ui.platform.PlatformEditor {
	final views:IosViews;
	final view:Ptr;
	final multiline:Bool;
	// (the program's own focus change or text: not the user's)
	var focusing = false;
	var setting = false;
	// (the text last handed to the listener)
	var reported = "";

	public var listener(default, null):Null<helder.ui.platform.PlatformEditorListener> = null;
	var hosted:Null<helder.ui.LayerSlot> = null;

	public function slot():Null<helder.ui.LayerSlot>
		return hosted;

	public function new(views:IosViews, view:Ptr, multiline:Bool) {
		this.views = views;
		this.view = view;
		this.multiline = multiline;
	}

	public function listen(l:helder.ui.platform.PlatformEditorListener)
		listener = l;

	// (marked text there: a composition UIKit has not committed)
	function composing():Bool
		return !Msg.id(view, ObjC.sel("markedTextRange")).isNull();

	function text():String {
		var s = ObjC.string(Msg.id(view, ObjC.sel("text")));
		return s == null ? "" : s;
	}

	// the selection's UTF-16 offsets (UITextInput's positions)
	function selection():Array<Int> {
		var r = Msg.id(view, ObjC.sel("selectedTextRange")), b = Msg.id(view, ObjC.sel("beginningOfDocument"));
		if (r.isNull()) return [0, 0];
		var sel = ObjC.sel("offsetFromPosition:toPosition:");
		var s = Msg.iPtrPtr(view, sel, b, Msg.id(r, ObjC.sel("start"))).toInt(), e = Msg.iPtrPtr(view, sel, b, Msg.id(r, ObjC.sel("end"))).toInt();
		return [s, e];
	}

	public function setText(text:String, start:Int, end:Int)
		helder.os.OsThread.run(() -> setTextNow(text, start, end));

	function setTextNow(text:String, start:Int, end:Int) {
		var s = ObjC.str(text);
		setting = true;
		Msg.vPtr(view, ObjC.sel("setText:"), s);
		setting = false;
		ObjC.release(s);
		reported = text;
		selectNow(start, end);
	}

	public function select(start:Int, end:Int)
		helder.os.OsThread.run(() -> selectNow(start, end));

	function selectNow(start:Int, end:Int) {
		if (gone || composing()) return;
		var b = Msg.id(view, ObjC.sel("beginningOfDocument")), sel = ObjC.sel("positionFromPosition:offset:");
		var from = Msg.idPtrInt(view, sel, b, start), to = Msg.idPtrInt(view, sel, b, end);
		if (from.isNull() || to.isNull()) return;
		setting = true;
		Msg.vPtr(view, ObjC.sel("setSelectedTextRange:"), Msg.idPtrPtr(view, ObjC.sel("textRangeFromPosition:toPosition:"), from, to));
		setting = false;
	}

	public function setKind(kind:helder.os.TextKind)
		helder.os.OsThread.run(() -> if (!gone) Traits.apply(view, kind));

	public function place(x:Float, y:Float, width:Float, height:Float, shown:Bool)
		helder.os.OsThread.run(() -> placeNow(x, y, width, height, shown));

	// (a move the compositor posted may come after dispose: nothing then)
	function placeNow(x:Float, y:Float, width:Float, height:Float, shown:Bool) {
		// (a layout gone wrong: UIKit throws at a NaN frame)
		if (gone || !(Math.isFinite(x) && Math.isFinite(y) && Math.isFinite(width) && Math.isFinite(height))) return;
		Arena.scoped(a -> {
			var r = a.make(CGRect);
			r.value.origin.x = x;
			r.value.origin.y = y;
			r.value.size.width = width;
			r.value.size.height = height;
			Msg.vRect(view, ObjC.sel("setFrame:"), r.value);
		});
		Msg.vBool(view, ObjC.sel("setHidden:"), !shown);
	}

	// (secret: the kind's secure entry, setKind)
	public function setStyle(font:Font, color:Color, background:Color, placeholder:String, placeholderColor:Color, align:TextAlign, secret:Bool)
		helder.os.OsThread.run(() -> if (!gone) styleNow(font, color, placeholder, placeholderColor, align));

	function styleNow(font:Font, color:Color, placeholder:String, placeholderColor:Color, align:TextAlign) {
		Msg.vPtr(view, ObjC.sel("setFont:"), IosViews.uiFont(font));
		Msg.vPtr(view, ObjC.sel("setTextColor:"), IosViews.uiColor(color));
		// (NSTextAlignment on iOS: left 0, center 1, right 2, justified 3)
		Msg.vInt(view, ObjC.sel("setTextAlignment:"), align == Center ? 1 : align == Right ? 2 : align == Justify ? 3 : 0);
		if (multiline) return;
		var p = ObjC.str(placeholder), key = Traits.constant("NSForegroundColorAttributeName");
		var attrs = Msg.idPtrPtr(ObjC.cls("NSDictionary"), ObjC.sel("dictionaryWithObject:forKey:"), IosViews.uiColor(placeholderColor), key);
		var s = Msg.idPtrPtr(Msg.id(ObjC.cls("NSAttributedString"), ObjC.sel("alloc")), ObjC.sel("initWithString:attributes:"), p, attrs);
		Msg.vPtr(view, ObjC.sel("setAttributedPlaceholder:"), s);
		ObjC.release(s);
		ObjC.release(p);
	}

	public function focus(on:Bool)
		helder.os.OsThread.run(() -> if (!gone) focusNow(on));

	function focusNow(on:Bool) {
		if (on) {
			if (hosted != null) {
				Msg.vBool(hosted.handle, ObjC.sel("setHidden:"), false);
				Msg.vBool(view, ObjC.sel("setHidden:"), false);
			}
			if (views.resigning == this) views.resigning = null;
			focusing = true;
			if (!Msg.b(view, ObjC.sel("isFirstResponder"))) Msg.b(view, ObjC.sel("becomeFirstResponder"));
			focusing = false;
			// (another field's let go of: the keyboard stays up)
			views.resigning = null;
		} else if (Msg.b(view, ObjC.sel("isFirstResponder"))) {
			views.resigning = this;
			views.ui.requestFrame();
		}
	}

	public function dispose()
		helder.os.OsThread.run(disposeNow);

	var gone = false;

	function disposeNow() {
		if (gone) return;
		gone = true;
		IosViews.editors.remove(this);
		if (views.resigning == this) views.resigning = null;
		focusing = true;
		if (Msg.b(view, ObjC.sel("isFirstResponder"))) Msg.b(view, ObjC.sel("resignFirstResponder"));
		Msg.vPtr(view, ObjC.sel("setDelegate:"), Ptr.nil());
		Msg.v(view, ObjC.sel("removeFromSuperview"));
		ObjC.release(view);
		if (hosted != null) {
			Msg.v(hosted.handle, ObjC.sel("removeFromSuperview"));
			ObjC.release(hosted.handle);
		}
		listener = null;
	}
}
