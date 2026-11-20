package helder.asset;

import helder.os.Format;
import helder.os.Plural;

enum StringPart {
	Text(value:String);
	Value(name:String);
	Count;
	Choice(name:String, forms:Map<String, Array<StringPart>>);
}

class StringMessage {
	public final params = new Map<String, Bool>();
	var parts:Array<StringPart> = [];
	final source:String;
	var at = 0;

	public function new(source:String) {
		this.source = source;
		parts = read(false);
	}

	public function format(locale:String, values:Dynamic):String {
		var out = new StringBuf();
		write(parts, locale, values, out, 0);
		return out.toString();
	}

	static function write(parts:Array<StringPart>, locale:String, values:Dynamic, out:StringBuf, count:Float) {
		for (part in parts) switch part {
			case Text(text): out.add(text);
			case Value(name): out.add(argument(values, name, false));
			case Count: out.add(Format.number(count, {locale: locale}));
			case Choice(name, forms):
				var n:Float = argument(values, name, true);
				var exact = Math.isFinite(n) && n == Math.ffloor(n) ? forms.get("=" + helder.os.locale.Decimal.plain(n == 0 ? 0 : n)) : null;
				write(exact ?? forms.get(Plural.category(locale, n)) ?? forms.get("other") ?? throw "Plural needs an other case", locale, values, out, n);
		}
	}

	static function argument(values:Dynamic, name:String, number:Bool):Dynamic {
		var value:Dynamic = values == null ? null : Reflect.field(values, name);
		if (!(number ? Std.isOfType(value, Float) : Std.isOfType(value, String)))
			throw 'Message argument "$name" needs a ${number ? "number" : "string"}';
		return value;
	}

	function read(inPlural:Bool):Array<StringPart> {
		var result = [], start = at;
		while (at < source.length) {
			switch source.charAt(at) {
				case "}" | "{" | "#" if (source.charAt(at) != "#" || inPlural):
					if (at > start) result.push(Text(source.substring(start, at)));
					switch source.charAt(at++) {
						case "}":
							if (!inPlural) fail('unexpected "}"');
							return result;
						case "{": result.push(placeholder(inPlural));
						case _: result.push(Count);
					}
					start = at;
				case _: at++;
			}
		}
		if (inPlural) fail('expected "}"');
		if (at > start) result.push(Text(source.substring(start, at)));
		return result;
	}

	function placeholder(inPlural:Bool):StringPart {
		var name = token();
		if (!~/^[a-zA-Z_][a-zA-Z_0-9]*$/.match(name)) fail('invalid placeholder "$name"');
		if (take("}")) {
			param(name, false);
			return Value(name);
		}
		if (inPlural || !take(",") || token() != "plural" || !take(",")) fail("expected a placeholder or plural");
		param(name, true);
		var forms = new Map<String, Array<StringPart>>();
		while (!take("}")) {
			var key = token();
			if (!~/^(zero|one|two|few|many|other|=-?(0|[1-9][0-9]*))$/.match(key)) fail('invalid plural case "$key"');
			if (forms.exists(key)) fail('duplicate plural case "$key"');
			if (!take("{")) fail('expected "{" after "$key"');
			forms.set(key, read(true));
		}
		if (!forms.exists("other")) fail('plural needs an "other" case');
		return Choice(name, forms);
	}

	function param(name:String, number:Bool) {
		if (params.exists(name) && params.get(name) != number) fail('conflicting types for "$name"');
		params.set(name, number);
	}

	function token():String {
		spaces();
		var start = at;
		while (at < source.length && " \t\r\n,{}".indexOf(source.charAt(at)) < 0) at++;
		return source.substring(start, at);
	}

	function take(char:String):Bool {
		spaces();
		if (source.charAt(at) != char) return false;
		at++;
		return true;
	}

	function spaces() {
		while (at < source.length && " \t\r\n".indexOf(source.charAt(at)) >= 0) at++;
	}

	function fail(message:String):Dynamic
		throw 'at character ${at + 1}: $message';

	public static function catalogue(json:String):Map<String, StringMessage> {
		var data:Dynamic = haxe.Json.parse(json);
		if (Type.typeof(data) != TObject) throw "expected an object of messages";
		var entries = new Map<String, StringMessage>();
		for (key in Reflect.fields(data)) {
			var text:Dynamic = Reflect.field(data, key);
			if (!Std.isOfType(text, String)) throw 'message "$key" needs a string';
			try entries.set(key, new StringMessage(text)) catch (e:Dynamic) throw 'message "$key": $e';
		}
		return entries;
	}
}
