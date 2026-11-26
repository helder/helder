package helder.dom;

using StringTools;

// The DOM's DOMTokenList: an attribute's value as an ordered set of tokens
// (an element's classList), read from the attribute as it is now.
@:allow(helder.dom)
class DOMTokenList {
	public var length(get, never):Int;
	public var value(get, set):String;

	final element:Element;
	final name:String;
	var read:Null<String> = null;
	var set:Array<String> = [];

	function new(element:Element, name:String) {
		this.element = element;
		this.name = name;
	}

	// the ordered set parser
	static function parse(s:String):Array<String> {
		var out = [], i = 0, n = s.length;
		while (i < n) {
			while (i < n && isWs(s.fastCodeAt(i)))
				i++;
			var start = i;
			while (i < n && !isWs(s.fastCodeAt(i)))
				i++;
			if (i > start) {
				var t = s.substring(start, i);
				if (!out.contains(t)) out.push(t);
			}
		}
		return out;
	}

	static inline function isWs(c:Int):Bool
		return c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0C || c == 0x0D;

	function tokens():Array<String> {
		var a = element.byNamespace(null, name);
		var v = a == null ? null : a.data;
		if (v != read) {
			read = v;
			set = v == null ? [] : parse(v);
		}
		return set;
	}

	function update(tokens:Array<String>) {
		if (element.byNamespace(null, name) == null && tokens.length == 0) return;
		element.setAttrValue(name, tokens.join(" "));
	}

	static function validate(token:String) {
		if (token == "") throw new DOMException("an empty token", "SyntaxError");
		for (i in 0...token.length)
			if (isWs(token.fastCodeAt(i))) throw new DOMException("a token with white space", "InvalidCharacterError");
	}

	function get_length():Int
		return tokens().length;

	public function item(index:Int):Null<String> {
		var t = tokens();
		return index >= 0 && index < t.length ? t[index] : null;
	}

	public function contains(token:String):Bool
		return tokens().contains(token);

	public function add(...tokens:String) {
		for (t in tokens)
			validate(t);
		var set = this.tokens().copy();
		for (t in tokens)
			if (!set.contains(t)) set.push(t);
		update(set);
	}

	public function remove(...tokens:String) {
		for (t in tokens)
			validate(t);
		var set = [for (t in this.tokens()) if (!tokens.toArray().contains(t)) t];
		update(set);
	}

	public function toggle(token:String, ?force:Bool):Bool {
		validate(token);
		var set = tokens().copy();
		if (set.contains(token)) {
			if (force == null || !force) {
				set.remove(token);
				update(set);
				return false;
			}
			return true;
		}
		if (force == null || force) {
			set.push(token);
			update(set);
			return true;
		}
		return false;
	}

	public function replace(token:String, newToken:String):Bool {
		validate(token);
		validate(newToken);
		var set = tokens();
		if (!set.contains(token)) return false;
		// (an ordered set's replace: the first of either becomes newToken, the others go)
		var first = -1;
		for (i in 0...set.length)
			if (set[i] == token || set[i] == newToken) {
				first = i;
				break;
			}
		set = [for (i in 0...set.length) if (i == first) newToken else if (set[i] != token && set[i] != newToken) set[i]];
		update(set);
		return true;
	}

	// (no token list in the DOM or HTML so far defines its supported tokens for class)
	public function supports(token:String):Bool
		throw new DOMException(name + " has no supported tokens", "TypeError");

	function get_value():String
		return element.attrValue(name);

	function set_value(v:String):String {
		element.setAttrValue(name, v);
		return v;
	}

	public function iterator():Iterator<String>
		return tokens().copy().iterator();

	public function toString():String
		return get_value();
}
