package helder.os;

// What a text field takes, for the system's keyboard (Window.textKind, a
// native editor's): its keys (Keyboard), its Enter key's label (EnterKey),
// what is capitalised, whether words are corrected, a password's (secure:
// no suggestions, AutoFill's password; a new one's, newPassword: one
// suggested) and several lines. iOS: UIKeyboardType,
// UIReturnKeyType, UITextAutocapitalizationType, UITextAutocorrectionType,
// secureTextEntry and a textContentType (AutoFill); Android: EditorInfo's
// inputType and imeOptions; the browser: an input's type, inputmode,
// enterkeyhint, autocapitalize, autocorrect and spellcheck; the desktop
// none of it but secure.
class TextKind {
	public static final PLAIN = new TextKind();

	public final keyboard:Keyboard;
	public final enter:EnterKey;
	public final capitalize:Capitalize;
	public final autocorrect:Bool;
	public final secure:Bool;
	public final multiline:Bool;
	public final newPassword:Bool;

	// (capitalize and autocorrect null: sentences and corrected, but for an
	// email's, a URL's and a password)
	public function new(keyboard = Keyboard.Text, enter = EnterKey.Default, ?capitalize:Capitalize, ?autocorrect:Bool, secure = false, multiline = false,
			newPassword = false) {
		var plain = !(secure || keyboard == Keyboard.Email || keyboard == Keyboard.Url);
		this.keyboard = keyboard;
		this.enter = enter;
		this.capitalize = capitalize ?? (plain ? Capitalize.Sentences : Capitalize.None);
		this.autocorrect = autocorrect ?? plain;
		this.secure = secure;
		this.multiline = multiline;
		this.newPassword = newPassword;
	}

	public function equals(k:Null<TextKind>):Bool
		return k != null && k.keyboard == keyboard && k.enter == enter && k.capitalize == capitalize && k.autocorrect == autocorrect && k.secure == secure
			&& k.multiline == multiline && k.newPassword == newPassword;
}

enum abstract Keyboard(String) to String {
	var Text = "text";
	var Email = "email";
	var Number = "number";
	var Decimal = "decimal";
	var Phone = "phone";
	var Url = "url";
	var Search = "search";

	public static function parse(s:String):Keyboard
		return switch s {
			case "text" | "email" | "number" | "decimal" | "phone" | "url" | "search": cast s;
			case _: throw 'helder.os: keyboard="$s" is not text, email, number, decimal, phone, url or search';
		}
}

enum abstract EnterKey(String) to String {
	var Default = "default";
	var Done = "done";
	var Next = "next";
	var Go = "go";
	var Search = "search";
	var Send = "send";

	public static function parse(s:String):EnterKey
		return switch s {
			case "default" | "done" | "next" | "go" | "search" | "send": cast s;
			case _: throw 'helder.os: enterkey="$s" is not default, done, next, go, search or send';
		}
}

enum abstract Capitalize(String) to String {
	var None = "none";
	var Words = "words";
	var Sentences = "sentences";
	var Characters = "characters";

	public static function parse(s:String):Capitalize
		return switch s {
			case "none" | "words" | "sentences" | "characters": cast s;
			case _: throw 'helder.os: autocapitalize="$s" is not none, words, sentences or characters';
		}
}
