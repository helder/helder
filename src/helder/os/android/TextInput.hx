package helder.os.android;

import helder.os.Event;
import helder.os.TextKind;
import helder.os.android.Jni;
import hxmc.unsafe.*;

// Window.startTextInput on Android: the keyboard and the input method for a
// drawn UI (AndroidWindow), through an org.hxmc.Editor in the activity's
// content (classes.dex: a View that is a text editor, never drawn: the
// program's surface is NativeActivity's), focused at the caret, the soft
// keyboard shown and hidden on it (InputMethodManager), made and driven on
// the main thread (MainThread). Its onCreateInputConnection gives the
// input method the field's EditorInfo (Window.textKind: inputType's class,
// variation and flags, imeOptions' action) and an org.hxmc.Connection,
// whose natives are here: the field's text and selection (Window.textContext)
// mirrored on the main thread, with the input method's composition at the
// caret, so that it reads what is around the caret (getTextBeforeCursor:
// capitalisation, suggestions) and edits it. Its edits become the
// window's events: a composition (setComposingText, setComposingRegion) as
// TextEditing (the region taken out of the text first: TextReplace), a
// commit as TextInput (a newline as Enter), a deletion as TextReplace, a
// selection as TextSelect, keys (sendKeyEvent: Delete, Enter, the arrows)
// as KeyDown and KeyUp, an action (performEditorAction: Next, Done...)
// as Enter. The mirror is changed at once (the input method's next read
// sees its edit) and set again from the program's context once the
// program has seen every event sent (a context older than an edit is
// dropped); one that differs restarts the input (restartInput), a moved
// selection is told (updateSelection). Keys of a hardware keyboard still
// come through the activity's input queue. The window's soft input mode is
// adjustResize, the keyboard's height read from the window's insets
// (Insets: the Editor's onApplyWindowInsets measures them). The events
// wait for the program's thread, which AndroidWindow.pump hands them to.
// Enabled by a program that takes text (enable: helder.ui's UiWindow does).
// (@:helder.android.dex: an APK with this gets classes.dex, Editor and
// Connection in it: helder.pack.android.Classes)
@:hxmc.android @:helder.android.dex
@:hxmc.unsafe(gc)
class TextInput {
	static final lock = new sys.thread.Mutex();
	static var pending:Array<{kind:EventKind, text:String, a:Int, b:Int}> = [];
	// the events sent (the main thread's, under the lock) and those the
	// program's thread took (its own)
	static var sent = 0;
	static var taken = 0;
	// (the main thread's)
	static var view = Ptr.nil();
	static var imm = Ptr.nil();
	static var on = false;
	static var m:Map<String, Ptr>;
	static var kind = TextKind.PLAIN;
	// the field's text and selection as the input method sees it, its
	// composition at start (the selection empty then)
	static var text = "";
	static var start = 0;
	static var end = 0;
	static var composing = "";
	// the input method's Connection last made (a global reference; a test calls it as the input method)
	public static var connection(default, null) = Ptr.nil();

	// Window.startTextInput through this from now on (otherwise a program
	// that never takes text has none of this, nor classes.dex)
	public static function enable() {
		AndroidWindow.textInputHook = set;
		AndroidWindow.textKindHook = k -> MainThread.post(() -> setKind(k));
		AndroidWindow.textContextHook = context;
		AndroidWindow.textEvents = drain;
	}

	// (the program's thread) on at the caret (pixels), or off
	static function set(on:Bool, x:Int, y:Int, width:Int, height:Int)
		MainThread.post(() -> on ? show(x, y) : hide());

	// (the program's thread) the field's text and selection, as of the events it took
	static function context(t:String, s:Int, e:Int) {
		var seen = taken;
		MainThread.post(() -> follow(t, s, e, seen));
	}

	// the Editor (the main thread; null until text input was first on)
	public static function field():Ptr
		return view;

	static function init() {
		var v = Jni.cls("android.view.View"), act = Jni.activity, manager = Jni.cls("android.view.inputmethod.InputMethodManager");
		var editor = Jni.cls("org.hxmc.Editor");
		Jni.registerNatives(editor, [
			{name: "onCreateInputConnection", sig: "(Landroid/view/inputmethod/EditorInfo;)Landroid/view/inputmethod/InputConnection;", fn: Callback.addr(connect)},
			{name: "onApplyWindowInsets", sig: "(Landroid/view/WindowInsets;)Landroid/view/WindowInsets;", fn: Callback.addr(insets)}
		]);
		var connection = Jni.cls("org.hxmc.Connection");
		Jni.registerNatives(connection, [
			{
				name: "getSurroundingText",
				sig: "(III)Landroid/view/inputmethod/SurroundingText;",
				fn: Callback.addr(surrounding)
			},
			{
				name: "getExtractedText",
				sig: "(Landroid/view/inputmethod/ExtractedTextRequest;I)Landroid/view/inputmethod/ExtractedText;",
				fn: Callback.addr(extracted)
			},
			{name: "commitText", sig: "(Ljava/lang/CharSequence;I)Z", fn: Callback.addr(commitText)},
			{name: "setComposingText", sig: "(Ljava/lang/CharSequence;I)Z", fn: Callback.addr(setComposingText)},
			{name: "setComposingRegion", sig: "(II)Z", fn: Callback.addr(setComposingRegion)},
			{name: "finishComposingText", sig: "()Z", fn: Callback.addr(finishComposingText)},
			{name: "deleteSurroundingText", sig: "(II)Z", fn: Callback.addr(deleteSurroundingText)},
			{name: "deleteSurroundingTextInCodePoints", sig: "(II)Z", fn: Callback.addr(deleteInCodePoints)},
			{name: "sendKeyEvent", sig: "(Landroid/view/KeyEvent;)Z", fn: Callback.addr(sendKeyEvent)},
			{name: "performEditorAction", sig: "(I)Z", fn: Callback.addr(performEditorAction)},
			{name: "setSelection", sig: "(II)Z", fn: Callback.addr(setSelection)},
			{name: "getTextBeforeCursor", sig: "(II)Ljava/lang/CharSequence;", fn: Callback.addr(textBefore)},
			{name: "getTextAfterCursor", sig: "(II)Ljava/lang/CharSequence;", fn: Callback.addr(textAfter)},
			{name: "getSelectedText", sig: "(I)Ljava/lang/CharSequence;", fn: Callback.addr(selectedText)},
			{name: "getCursorCapsMode", sig: "(I)I", fn: Callback.addr(capsMode)}
		]);
		var info = Jni.cls("android.view.inputmethod.EditorInfo"), key = Jni.cls("android.view.KeyEvent"), utils = Jni.cls("android.text.TextUtils");
		m = [
			"setTranslationX" => Jni.method(v, "setTranslationX", "(F)V"),
			"setTranslationY" => Jni.method(v, "setTranslationY", "(F)V"),
			"requestFocus" => Jni.method(v, "requestFocus", "()Z"),
			"clearFocus" => Jni.method(v, "clearFocus", "()V"),
			"isAttachedToWindow" => Jni.method(v, "isAttachedToWindow", "()Z"),
			"getWindowToken" => Jni.method(v, "getWindowToken", "()Landroid/os/IBinder;"),
			"showSoftInput" => Jni.method(manager, "showSoftInput", "(Landroid/view/View;I)Z"),
			"hide" => Jni.method(manager, "hideSoftInputFromWindow", "(Landroid/os/IBinder;I)Z"),
			"restartInput" => Jni.method(manager, "restartInput", "(Landroid/view/View;)V"),
			"updateSelection" => Jni.method(manager, "updateSelection", "(Landroid/view/View;IIII)V"),
			"inputType" => Jni.field(info, "inputType", "I"),
			"imeOptions" => Jni.field(info, "imeOptions", "I"),
			"initialSelStart" => Jni.field(info, "initialSelStart", "I"),
			"initialSelEnd" => Jni.field(info, "initialSelEnd", "I"),
			"initialCapsMode" => Jni.field(info, "initialCapsMode", "I"),
			"connection" => Jni.method(connection, "<init>", "(Landroid/view/View;Z)V"),
			"getAction" => Jni.method(key, "getAction", "()I"),
			"getKeyCode" => Jni.method(key, "getKeyCode", "()I"),
			"getMetaState" => Jni.method(key, "getMetaState", "()I"),
			"getUnicodeChar" => Jni.method(key, "getUnicodeChar", "(I)I"),
			"getCapsMode" => Jni.staticMethod(utils, "getCapsMode", "(Ljava/lang/CharSequence;II)I")
		];
		var e = Jni.newObject(editor, Jni.method(editor, "<init>", "(Landroid/content/Context;)V"), act.toI64());
		view = Jni.global(e);
		Jni.call(view, Jni.method(v, "setFocusable", "(Z)V"), 1);
		Jni.call(view, Jni.method(v, "setFocusableInTouchMode", "(Z)V"), 1);
		var params = Jni.cls("android.view.ViewGroup$LayoutParams");
		var lp = Jni.newObject(params, Jni.method(params, "<init>", "(II)V"), 1, 1);
		Jni.call(act, Jni.method(Jni.cls("android.app.Activity"), "addContentView", "(Landroid/view/View;Landroid/view/ViewGroup$LayoutParams;)V"), view.toI64(),
			lp.toI64());
		imm = Jni.global(Jni.service("input_method"));
		// (SOFT_INPUT_ADJUST_RESIZE: the window not panned, the keyboard's
		// height in its insets, Insets'; the surface stays the screen's)
		var win = Jni.obj(act, Jni.method(Jni.cls("android.app.Activity"), "getWindow", "()Landroid/view/Window;"));
		Jni.call(win, Jni.method(Jni.cls("android.view.Window"), "setSoftInputMode", "(I)V"), 0x10);
	}

	static function show(x:Int, y:Int) {
		if (view.isNull()) init();
		var again = on;
		on = true;
		Jni.call(view, m["setTranslationX"], Jni.f(x));
		Jni.call(view, m["setTranslationY"], Jni.f(y));
		if (again) return;
		// (just added to the content: shown once attached, at its first insets)
		if (!Jni.bool(view, m["isAttachedToWindow"])) {
			waiting = true;
			return;
		}
		focusIn();
	}

	static var waiting = false;

	static function focusIn() {
		waiting = false;
		Jni.bool(view, m["requestFocus"]);
		Jni.call(imm, m["restartInput"], view.toI64());
		Jni.bool(imm, m["showSoftInput"], view.toI64(), 0);
	}

	static function hide() {
		if (view.isNull() || !on) return;
		on = false;
		waiting = false;
		Jni.bool(imm, m["hide"], Jni.obj(view, m["getWindowToken"]).toI64(), 0);
		Jni.call(view, m["clearFocus"]);
		if (composing != "") push(TextEditing, "", 0);
		composing = "";
	}

	// (the main thread) Window.textKind: the input made again while it is on
	static function setKind(k:TextKind) {
		if (k.equals(kind)) return;
		kind = k;
		if (on) Jni.call(imm, m["restartInput"], view.toI64());
	}

	// (the main thread) the program's text and selection, unless it has not
	// seen every edit sent yet: what the input method sees, told when it changed
	static function follow(t:String, s:Int, e:Int, seen:Int) {
		lock.acquire();
		var stale = seen != sent;
		lock.release();
		if (stale || view.isNull()) return;
		if (t == text && s == start && e == end) return;
		var edited = t != text || composing != "";
		if (composing != "") push(TextEditing, "", 0);
		text = t;
		start = s;
		end = e;
		composing = "";
		if (!on) return;
		if (edited) Jni.call(imm, m["restartInput"], view.toI64()) else told();
	}

	// (the main thread) the selection and composition now told to the input
	// method, as an editor does after each change (onUpdateSelection: an
	// input method that hears none commits rather than composes)
	static function told() {
		if (!on || view.isNull()) return;
		var n = composing.length;
		Arena.scoped(a -> {
			// (five arguments: Jni.call's four and one)
			var args = a.alloc(40);
			Mem.setPtr(args, 0, view);
			Mem.setI64(args, 8, start + n);
			Mem.setI64(args, 16, end + n);
			Mem.setI64(args, 24, n > 0 ? start : -1);
			Mem.setI64(args, 32, n > 0 ? start + n : -1);
			JniEnv.CallVoidMethodA(Jni.env, imm, m["updateSelection"], args);
			Jni.check();
		});
	}

	// ---- the Editor's natives

	// its EditorInfo: the field's kind and selection; its Connection
	@:hxmc.callback static function connect(env:Ptr, self:Ptr, info:Ptr):Ptr {
		var k = kind;
		JniEnv.SetIntField(env, info, m["inputType"], inputType(k));
		JniEnv.SetIntField(env, info, m["imeOptions"], imeOptions(k));
		JniEnv.SetIntField(env, info, m["initialSelStart"], start + composing.length);
		JniEnv.SetIntField(env, info, m["initialSelEnd"], end + composing.length);
		// (CAP_MODE_CHARACTERS, WORDS, SENTENCES: as the text before the caret has them)
		JniEnv.SetIntField(env, info, m["initialCapsMode"], caps(0x7000));
		var c = Jni.newObject(Jni.cls("org.hxmc.Connection"), m["connection"], self.toI64(), 0);
		if (!connection.isNull()) Jni.deleteGlobal(connection);
		connection = Jni.global(c);
		return c;
	}

	// (the keyboard shown or hidden: the insets measured again)
	@:hxmc.callback static function insets(env:Ptr, self:Ptr, wi:Ptr):Ptr {
		if (waiting && on) focusIn();
		Insets.measure();
		MainThread.wake();
		return wi;
	}

	// EditorInfo.inputType: TYPE_CLASS_TEXT 1 (EMAIL_ADDRESS 0x20, URI 0x10,
	// PASSWORD 0x80; CAP_CHARACTERS 0x1000, CAP_WORDS 0x2000, CAP_SENTENCES
	// 0x4000, AUTO_CORRECT 0x8000, MULTI_LINE 0x20000, NO_SUGGESTIONS 0x80000),
	// TYPE_CLASS_NUMBER 2 (DECIMAL 0x2000, PASSWORD 0x10), TYPE_CLASS_PHONE 3
	public static function inputType(k:TextKind):Int {
		switch k.keyboard {
			case Number:
				return 2 | (k.secure ? 0x10 : 0);
			case Decimal:
				return 2 | 0x2000;
			case Phone:
				return 3;
			case _:
		}
		var t = 1 | (k.keyboard == Keyboard.Email ? 0x20 : k.keyboard == Keyboard.Url ? 0x10 : 0) | (k.secure ? 0x80 : 0);
		t |= switch k.capitalize {
			case Characters: 0x1000;
			case Words: 0x2000;
			case Sentences: 0x4000;
			case None: 0;
		}
		if (k.autocorrect) t |= 0x8000 else if (k.secure || k.keyboard == Keyboard.Email || k.keyboard == Keyboard.Url) {} else t |= 0x80000;
		return k.multiline ? t | 0x20000 : t;
	}

	// EditorInfo.imeOptions: IME_ACTION_GO 2, SEARCH 3, SEND 4, NEXT 5, DONE 6
	// (a search keyboard's default its Search); IME_FLAG_NO_EXTRACT_UI,
	// NO_FULLSCREEN (no full-screen editor in landscape); a text area's
	// Enter a newline (NO_ENTER_ACTION), a password's not learnt
	// (NO_PERSONALIZED_LEARNING)
	public static function imeOptions(k:TextKind):Int {
		var action = switch k.enter {
			case Go: 2;
			case Search: 3;
			case Send: 4;
			case Next: 5;
			case Done: 6;
			case Default: k.keyboard == Keyboard.Search ? 3 : 0;
		}
		var o = action | 0x10000000 | 0x2000000 | (k.secure ? 0x1000000 : 0);
		return k.multiline && k.enter == EnterKey.Default ? o | 0x40000000 : o;
	}

	// ---- the Connection's natives (the main thread)

	@:hxmc.callback static function commitText(env:Ptr, self:Ptr, cs:Ptr, cursor:Int):Int {
		var t = Jni.text(cs);
		if (composing != "") push(TextEditing, "", 0);
		composing = "";
		type(t);
		told();
		return 1;
	}

	@:hxmc.callback static function setComposingText(env:Ptr, self:Ptr, cs:Ptr, cursor:Int):Int {
		var t = Jni.text(cs);
		if (composing == "" && start != end) {
			text = text.substr(0, start) + text.substr(end);
			end = start;
		}
		if (t != composing) push(TextEditing, t, t.length);
		composing = t;
		told();
		return 1;
	}

	// (a word of the text composed again: out of the text, the composition)
	@:hxmc.callback static function setComposingRegion(env:Ptr, self:Ptr, a:Int, b:Int):Int {
		finish();
		var s = clamp(a < b ? a : b), e = clamp(a < b ? b : a);
		if (s == e) {
			told();
			return 1;
		}
		var word = text.substring(s, e);
		push(TextReplace, "", s, e);
		text = text.substr(0, s) + text.substr(e);
		start = end = s;
		push(TextEditing, word, word.length);
		composing = word;
		told();
		return 1;
	}

	@:hxmc.callback static function finishComposingText(env:Ptr, self:Ptr):Int {
		finish();
		told();
		return 1;
	}

	@:hxmc.callback static function deleteSurroundingText(env:Ptr, self:Ptr, before:Int, after:Int):Int {
		delete(before, after);
		told();
		return 1;
	}

	// (code points: the UTF-16 units of that many before the selection and after it)
	@:hxmc.callback static function deleteInCodePoints(env:Ptr, self:Ptr, before:Int, after:Int):Int {
		var b = start, a = end;
		for (_ in 0...before)
			if (b > 0) b -= b > 1 && low(StringTools.fastCodeAt(text, b - 1)) && high(StringTools.fastCodeAt(text, b - 2)) ? 2 : 1;
		for (_ in 0...after)
			if (a < text.length) a += a + 1 < text.length && high(StringTools.fastCodeAt(text, a)) && low(StringTools.fastCodeAt(text, a + 1)) ? 2 : 1;
		delete(start - b, a - end);
		told();
		return 1;
	}

	// a key of the keyboard's (Delete, Enter, the arrows): KeyDown or KeyUp,
	// a character's TextInput; the mirror's Delete and Forward Delete done
	@:hxmc.callback static function sendKeyEvent(env:Ptr, self:Ptr, ev:Ptr):Int {
		var down = Jni.int(ev, m["getAction"]) == 0, code = Jni.int(ev, m["getKeyCode"]), meta = Jni.int(ev, m["getMetaState"]);
		var sym = @:privateAccess AndroidWindow.keySym(code), mods = @:privateAccess AndroidWindow.modsOf(meta);
		if (down) finish();
		if (sym != 0) push(down ? KeyDown : KeyUp, "", sym, mods);
		if (!down) return 1;
		if (code == 67 || code == 112) {
			if (start == end) {
				if (code == 67 && start > 0) start--;
				if (code == 112 && end < text.length) end++;
			}
			text = text.substr(0, start) + text.substr(end);
			end = start;
		} else if (code == 66 || code == 160) {
			if (kind.multiline) edit("\n");
		} else {
			var c = Jni.int(ev, m["getUnicodeChar"], meta);
			if (c > 0 && mods & (Mods.CONTROL | Mods.ALT | Mods.META) == 0) {
				var s = new StringBuf();
				s.addChar(c);
				edit(s.toString());
				push(TextInput, s.toString(), 0);
			}
		}
		told();
		return 1;
	}

	// (Go, Search, Send, Next, Done: the field's Enter)
	@:hxmc.callback static function performEditorAction(env:Ptr, self:Ptr, action:Int):Int {
		finish();
		enter();
		told();
		return 1;
	}

	@:hxmc.callback static function setSelection(env:Ptr, self:Ptr, a:Int, b:Int):Int {
		finish();
		start = clamp(a);
		end = clamp(b);
		push(TextSelect, "", start, end);
		if (start > end) {
			var t = start;
			start = end;
			end = t;
		}
		told();
		return 1;
	}

	// the text around the selection, before and after it (SurroundingText, API 31)
	@:hxmc.callback static function surrounding(env:Ptr, self:Ptr, before:Int, after:Int, flags:Int):Ptr {
		var doc = text.substr(0, start) + composing + text.substr(start), n = composing.length;
		var s = start + n, e = end + n, from = s - before < 0 ? 0 : s - before, to = e + after > doc.length ? doc.length : e + after;
		var c = Jni.cls("android.view.inputmethod.SurroundingText"), js = Jni.string(doc.substring(from, to));
		return Jni.newObject(c, Jni.method(c, "<init>", "(Ljava/lang/CharSequence;III)V"), js.toI64(), s - from, e - from, from);
	}

	// the whole text, its selection and composition (ExtractedText)
	@:hxmc.callback static function extracted(env:Ptr, self:Ptr, request:Ptr, flags:Int):Ptr {
		var c = Jni.cls("android.view.inputmethod.ExtractedText"), n = composing.length;
		var x = Jni.newObject(c, Jni.method(c, "<init>", "()V"));
		var s = Jni.string(text.substr(0, start) + composing + text.substr(start));
		JniEnv.SetObjectField(env, x, Jni.field(c, "text", "Ljava/lang/CharSequence;"), s);
		JniEnv.SetIntField(env, x, Jni.field(c, "startOffset", "I"), 0);
		JniEnv.SetIntField(env, x, Jni.field(c, "partialStartOffset", "I"), -1);
		JniEnv.SetIntField(env, x, Jni.field(c, "partialEndOffset", "I"), -1);
		JniEnv.SetIntField(env, x, Jni.field(c, "selectionStart", "I"), start + n);
		JniEnv.SetIntField(env, x, Jni.field(c, "selectionEnd", "I"), end + n);
		return x;
	}

	@:hxmc.callback static function textBefore(env:Ptr, self:Ptr, n:Int, flags:Int):Ptr {
		var s = text.substr(0, start) + composing;
		return Jni.string(s.length > n ? s.substr(s.length - n) : s);
	}

	@:hxmc.callback static function textAfter(env:Ptr, self:Ptr, n:Int, flags:Int):Ptr
		return Jni.string(text.substr(end, n));

	@:hxmc.callback static function selectedText(env:Ptr, self:Ptr, flags:Int):Ptr
		return start == end ? Ptr.nil() : Jni.string(text.substring(start, end));

	// (TextUtils.getCapsMode of what is before the caret: the field's capitalisation)
	@:hxmc.callback static function capsMode(env:Ptr, self:Ptr, modes:Int):Int
		return caps(modes);

	// (the field's own capitalisation only: none, a number's, a password's: 0)
	static function caps(modes:Int):Int {
		var t = inputType(kind);
		if (t & 15 != 1) return 0;
		modes &= t & 0x7000;
		if (modes == 0) return 0;
		var s = text.substr(0, start) + composing;
		var js = Jni.string(s);
		var r = Jni.staticInt(Jni.cls("android.text.TextUtils"), m["getCapsMode"], js.toI64(), s.length, modes);
		Jni.deleteLocal(js);
		return r;
	}

	// ---- the mirror

	// the composition committed: typed at the caret
	static function finish() {
		if (composing == "") return;
		var t = composing;
		composing = "";
		push(TextEditing, "", 0);
		type(t);
	}

	// t typed over the selection (newlines: Enter, the field's own)
	static function type(t:String) {
		var parts = t.split("\n");
		for (i in 0...parts.length) {
			if (i > 0) enter();
			var p = StringTools.replace(parts[i], "\r", "");
			if (p == "") continue;
			edit(p);
			push(TextInput, p, 0);
		}
	}

	static function enter() {
		push(KeyDown, "", 0xFF0D, 0);
		push(KeyUp, "", 0xFF0D, 0);
		if (kind.multiline) edit("\n");
	}

	static function edit(s:String) {
		text = text.substr(0, start) + s + text.substr(end);
		start = end = start + s.length;
	}

	// before units before the selection and after it after (around a
	// composition, which stays), as TextReplace (the later range first: the
	// earlier's indices stay), the selection put back
	static function delete(before:Int, after:Int) {
		var b = clamp(start - (before < 0 ? 0 : before)), a = clamp(end + (after < 0 ? 0 : after));
		if (a > end) push(TextReplace, "", end, a);
		if (b < start) push(TextReplace, "", b, start);
		if (b == start && a == end) return;
		var s = start - b, e = end - b;
		text = text.substr(0, b) + text.substring(start, end) + text.substr(a);
		start = b;
		end = b + (e - s);
		if (end > start) push(TextSelect, "", start, end);
	}

	static inline function clamp(i:Int):Int
		return i < 0 ? 0 : i > text.length ? text.length : i;

	static inline function high(c:Int):Bool
		return c >= 0xD800 && c < 0xDC00;

	static inline function low(c:Int):Bool
		return c >= 0xDC00 && c < 0xE000;

	static function push(kind:EventKind, text:String, a:Int, b = 0) {
		lock.acquire();
		pending.push({kind: kind, text: text, a: a, b: b});
		sent++;
		lock.release();
		MainThread.wake();
	}

	// (the program's thread) the events waiting
	static function drain(dispatch:(kind:EventKind, text:String, a:Int, b:Int) -> Void) {
		lock.acquire();
		var list = pending;
		pending = [];
		taken = sent;
		lock.release();
		for (e in list)
			dispatch(e.kind, e.text, e.a, e.b);
	}
}
