import helder.ui.*;
import helder.ui.UiWindow;
import helder.ui.widgets.EditableText;
import helder.view.*;
#if (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
import helder.os.android.Jni;
#end

// Text input on a phone (tests/platform/textinput-ios.sh and
// textinput-android.sh read its lines): a scroller of fields, an email's
// (keyboard="email", enterkey="next"), a number's, a name's (done) and one
// at the bottom, below a tall gap. Focused in turn: each one's keyboard
// (iOS: its UITextField's traits; Android: its EditorInfo, which
// `dumpsys input_method` shows too), an email typed, a Japanese
// composition (iOS: setMarkedText then unmarkText on the UITextField;
// Android: the Connection's setComposingText and commitText, as an input
// method calls them), Enter through next and done, then the bottom field
// focused, the keyboard up: it is in view above it and the safe area's
// bottom is the keyboard's. Prints "textinput: N checks, ok" (or FAILED)
// and stays up, its keyboard shown, for a screenshot.
//   helder build tests/platform/TextInputCheck.hx --target ios-sim | android
@:hxmc.unsafe(gc)
class TextInputCheck implements Markup {
	static var failed = 0;
	static var checks = 0;
	static var ui:Ui;
	// (the compositions the email field showed)
	static final composed:Array<String> = [];

	function new() {}

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) failed++;
		Sys.println('textinput: ${ok ? "ok" : "FAIL"}: $what' + (detail == null ? "" : " (" + detail + ")"));
	}

	static function main() {
		Sys.println("textinput: started");
		var w = new UiWindow("TextInput", 400, 700);
		ui = @:privateAccess w.ui;
		Render.render(new TextInputCheck().view(), w.root);
		var steps = script(), at = -1.0, i = 0;
		Clock.add(t -> {
			if (at < 0) at = t + 2;
			if (t < at) return true;
			var wait = steps[i++]();
			at = t + wait;
			return i < steps.length;
		});
		UiWindow.run();
	}

	public function view():View
		return <view width="100%" height="100%" background="#f1f5f9" padding-top="env(safe-area-inset-top)" padding-bottom="env(safe-area-inset-bottom)">
			<scroll tag="scroll" grow={1} padding={16} gap={12}>
				<text font-size={20}>Text input</text>
				<field tag="email" keyboard="email" enterkey="next" onComposition={e -> if (e.text != "") composed.push(e.text)} placeholder="Email" padding={10} background="#fff" radius={8} shrink={0}/>
				<field tag="number" keyboard="number" enterkey="next" placeholder="Number" padding={10} background="#fff" radius={8} shrink={0}/>
				<field tag="name" enterkey="done" autocapitalize="words" placeholder="Name" padding={10} background="#fff" radius={8} shrink={0}/>
				<view height={900} background="#e2e8f0"/>
				<field tag="bottom" enterkey="done" placeholder="At the bottom" padding={10} background="#fff" radius={8} shrink={0}/>
			</scroll>
		</view>;

	static function field(tag:String):EditableText
		return cast ui.root.find(tag);

	static function focused():String
		return ui.focus == null ? "none" : ui.focus.tag;

	static function script():Array<Void->Float>
		return [
			() -> {
				ui.setFocus(field("email"));
				3;
			},
			() -> {
				check("the email field focused", focused() == "email");
				check("the keyboard up", ui.keyboard > 0, 'keyboard ${ui.keyboard}');
				Sys.println('textinput: keyboard ${ui.keyboard}, safe area bottom ${ui.safeArea.bottom}, duration ${ui.keyboardDuration}');
				traits("email", 7, 4);
				typeText("me@example.com");
				1;
			},
			() -> {
				check("the email typed", field("email").text == "me@example.com", field("email").text);
				compose("にほん");
				0.5;
			},
			() -> {
				#if (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
				check("composing: shown in the field, not in its text", composed.indexOf("にほん") >= 0, composed.join(","));
				#else
				check("composing: not in the text yet", field("email").text == "me@example.com", field("email").text + " / " + field("email").composition);
				#end
				commit("日本");
				0.5;
			},
			() -> {
				check("the composition committed", field("email").text == "me@example.com日本", field("email").text);
				enter(5);
				1;
			},
			() -> {
				check("next: the number field", focused() == "number");
				traits("number", 4, 4);
				enter(5);
				1;
			},
			() -> {
				check("next: the name field", focused() == "name");
				traits("name", 0, 9);
				enter(6);
				1.5;
			},
			() -> {
				check("done: no focus", focused() == "none");
				check("done: the keyboard down", ui.keyboard == 0, 'keyboard ${ui.keyboard}');
				ui.setFocus(field("bottom"), false);
				2;
			},
			() -> {
				var b = field("bottom").windowBounds();
				Sys.println('textinput: bottom field at ${b.y}..${b.y + b.height}, window ${ui.height}, keyboard ${ui.keyboard}, safe area bottom ${ui.safeArea.bottom}');
				check("the keyboard up for the bottom field", ui.keyboard > 0);
				check("the safe area's bottom the keyboard's", ui.safeArea.bottom >= ui.keyboard - 1, '${ui.safeArea.bottom} ${ui.keyboard}');
				check("the bottom field above the keyboard", b.y + b.height <= ui.height - ui.keyboard + 0.5 && b.y >= 0, '${b.y + b.height} <= ${ui.height - ui.keyboard}');
				Sys.println('textinput: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
				1;
			}
		];

	// the focused field's keyboard: its UIKeyboardType and UIReturnKeyType (iOS), its EditorInfo (Android)
	static function traits(tag:String, keyboard:Int, ret:Int) {
		var k = field(tag).textKind();
		#if (hxmc.target == "ios-sim-arm64" || hxmc.target == "ios-arm64")
		var v = native(tag);
		check('$tag: its UITextField first responder', onMain(() -> helder.os.apple.objc.Msg.b(v, helder.os.apple.objc.ObjC.sel("isFirstResponder"))));
		var kt = onMain(() -> helder.os.apple.objc.Msg.i(v, helder.os.apple.objc.ObjC.sel("keyboardType")).toInt()), rt = onMain(() -> helder.os.apple.objc.Msg.i(v, helder.os.apple.objc.ObjC.sel("returnKeyType")).toInt());
		check('$tag: UIKeyboardType $keyboard, UIReturnKeyType $ret', kt == keyboard && rt == ret, 'keyboardType $kt, returnKeyType $rt');
		#elseif (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		var t = helder.os.android.TextInput.inputType(k), o = helder.os.android.TextInput.imeOptions(k);
		Sys.println('textinput: $tag: inputType 0x${StringTools.hex(t)} imeOptions 0x${StringTools.hex(o)}');
		#end
	}

	#if (hxmc.target == "ios-sim-arm64" || hxmc.target == "ios-arm64")
	static function native(tag:String):hxmc.unsafe.Ptr
		return @:privateAccess (cast field(tag).editor : helder.ui.platform.apple.IosViews.IosEditor).view;

	static function str(s:String):hxmc.unsafe.Ptr
		return helder.os.apple.objc.ObjC.str(s);

	// (UIKit's, on the main thread, as the keyboard calls it: the program has a thread of its own)
	static function onMain<T>(f:Void->T):T
		return helder.os.OsThread.get(f);
	#end

	// text typed into the focused field (iOS: UITextField's insertText:; Android: the Connection's commitText)
	static function typeText(s:String) {
		#if (hxmc.target == "ios-sim-arm64" || hxmc.target == "ios-arm64")
		var v = native(focused());
		helder.os.OsThread.run(() -> helder.os.apple.objc.Msg.vPtr(v, helder.os.apple.objc.ObjC.sel("insertText:"), str(s)));
		#elseif (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		connection("commitText", s);
		#end
	}

	// (Android: composed then committed as 日本 in one turn of the main thread, as
	// an input method's batch: the keyboard there, Gboard, would otherwise end
	// a composition it did not make)
	static function compose(s:String) {
		#if (hxmc.target == "ios-sim-arm64" || hxmc.target == "ios-arm64")
		var v = native(focused());
		helder.os.OsThread.run(() -> helder.os.apple.objc.Msg.vPtrIntInt(v, helder.os.apple.objc.ObjC.sel("setMarkedText:selectedRange:"), str(s), s.length, 0));
		#elseif (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		helder.os.android.MainThread.post(() -> {
			call("setComposingText", s);
			call("commitText", "日本");
		});
		#end
	}

	// the composition committed as s (iOS: the marked text replaced by s, then unmarked)
	static function commit(s:String) {
		#if (hxmc.target == "ios-sim-arm64" || hxmc.target == "ios-arm64")
		var v = native(focused());
		helder.os.OsThread.run(() -> {
			helder.os.apple.objc.Msg.vPtrIntInt(v, helder.os.apple.objc.ObjC.sel("setMarkedText:selectedRange:"), str(s), s.length, 0);
			helder.os.apple.objc.Msg.v(v, helder.os.apple.objc.ObjC.sel("unmarkText"));
		});
		#end
	}

	// the keyboard's Enter (iOS: the delegate's textFieldShouldReturn:; Android: performEditorAction)
	static function enter(action:Int) {
		#if (hxmc.target == "ios-sim-arm64" || hxmc.target == "ios-arm64")
		var v = native(focused());
		helder.os.OsThread.run(() -> helder.os.apple.objc.Msg.bPtr(helder.os.apple.objc.Msg.id(v, helder.os.apple.objc.ObjC.sel("delegate")), helder.os.apple.objc.ObjC.sel("textFieldShouldReturn:"), v));
		#elseif (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		connection("performEditorAction", null, action);
		#end
	}

	#if (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
	// a method of the input method's Connection called on the main thread, as an input method does
	static function connection(name:String, ?text:String, action = 0)
		helder.os.android.MainThread.post(() -> call(name, text, action));

	static function call(name:String, ?text:String, action = 0) {
			var c = helder.os.android.TextInput.connection;
			if (c.isNull()) {
				Sys.println("textinput: no Connection");
				return;
			}
			var cls = Jni.cls("org.hxmc.Connection");
			if (text == null) Jni.bool(c, Jni.method(cls, name, "(I)Z"), action) else {
				var s = Jni.string(text);
				Jni.bool(c, Jni.method(cls, name, "(Ljava/lang/CharSequence;I)Z"), s.toI64(), 1);
				Jni.deleteLocal(s);
			}
	}
	#end
}
