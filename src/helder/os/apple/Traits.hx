package helder.os.apple;

import helder.os.TextKind;
import helder.os.apple.objc.*;
import hxmc.unsafe.*;

// A TextKind as UIKit's UITextInputTraits: the keyboard's type, the return
// key's, autocapitalisation, autocorrection and spellchecking, secure entry
// and AutoFill's content type (email, phone, URL, a password, a new one);
// given to a UITextField or UITextView (apply), or answered by a view of
// helder's own (IosWindow's, for a drawn field).
@:hxmc.unsafe(gc)
class Traits {
	// (UIKeyboardType: URL 3, NumberPad 4, PhonePad 5, EmailAddress 7, DecimalPad 8, WebSearch 10)
	public static function keyboardType(k:TextKind):Int
		return switch k.keyboard {
			case Email: 7;
			case Number: 4;
			case Decimal: 8;
			case Phone: 5;
			case Url: 3;
			case Search: 10;
			case Text: 0;
		}

	// (UIReturnKeyType: Go 1, Next 4, Search 6, Send 7, Done 9; a search
	// keyboard's default its Search)
	public static function returnKeyType(k:TextKind):Int
		return switch k.enter {
			case Go: 1;
			case Next: 4;
			case Search: 6;
			case Send: 7;
			case Done: 9;
			case Default: k.keyboard == Keyboard.Search ? 6 : 0;
		}

	// (UITextAutocapitalizationType: None 0, Words 1, Sentences 2, AllCharacters 3)
	public static function capitalization(k:TextKind):Int
		return switch k.capitalize {
			case None: 0;
			case Words: 1;
			case Sentences: 2;
			case Characters: 3;
		}

	// (UITextAutocorrectionType and UITextSpellCheckingType: No 1, Yes 2)
	public static inline function correction(k:TextKind):Int
		return k.autocorrect ? 2 : 1;

	// AutoFill's UITextContentType (an NSString constant of UIKit's; nil: none)
	public static function contentType(k:TextKind):Ptr {
		var name = k.secure ? (k.newPassword ? "UITextContentTypeNewPassword" : "UITextContentTypePassword") : switch k.keyboard {
			case Email: "UITextContentTypeEmailAddress";
			case Phone: "UITextContentTypeTelephoneNumber";
			case Url: "UITextContentTypeURL";
			case _: null;
		}
		return name == null ? Ptr.nil() : constant(name);
	}

	// (an NSString constant of UIKit's or Foundation's, by name; nil: none)
	public static function constant(name:String):Ptr {
		var p = Arena.scopedValue(a -> Posix.dlsym(Ptr.ofI64(-2), a.cstring(name)));
		return p.isNull() ? Ptr.nil() : Mem.getPtr(p, 0);
	}

	// the traits set on a UITextField or UITextView (the keyboard shown again
	// when it is up: reloadInputViews)
	public static function apply(view:Ptr, k:TextKind) {
		Msg.vInt(view, ObjC.sel("setKeyboardType:"), keyboardType(k));
		Msg.vInt(view, ObjC.sel("setReturnKeyType:"), returnKeyType(k));
		Msg.vInt(view, ObjC.sel("setAutocapitalizationType:"), capitalization(k));
		Msg.vInt(view, ObjC.sel("setAutocorrectionType:"), correction(k));
		Msg.vInt(view, ObjC.sel("setSpellCheckingType:"), correction(k));
		Msg.vBool(view, ObjC.sel("setSecureTextEntry:"), k.secure);
		Msg.vPtr(view, ObjC.sel("setTextContentType:"), contentType(k));
		if (Msg.b(view, ObjC.sel("isFirstResponder"))) Msg.v(view, ObjC.sel("reloadInputViews"));
	}
}
