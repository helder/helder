package helder.dom;

using StringTools;

// The DOM's name validation (1.4) and ASCII case folding.
@:noCompletion class Names {
	static inline function isWsOrNul(c:Int):Bool
		return c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0C || c == 0x0D || c == 0;

	static inline function isAlpha(c:Int):Bool
		return c >= "a".code && c <= "z".code || c >= "A".code && c <= "Z".code;

	public static function validNamespacePrefix(s:String):Bool {
		if (s.length == 0) return false;
		for (i in 0...s.length) {
			var c = s.fastCodeAt(i);
			if (isWsOrNul(c) || c == "/".code || c == ">".code) return false;
		}
		return true;
	}

	public static function validAttributeLocalName(s:String):Bool {
		if (s.length == 0) return false;
		for (i in 0...s.length) {
			var c = s.fastCodeAt(i);
			if (isWsOrNul(c) || c == "/".code || c == "=".code || c == ">".code) return false;
		}
		return true;
	}

	public static function validElementLocalName(s:String):Bool {
		if (s.length == 0) return false;
		var c = s.fastCodeAt(0);
		if (isAlpha(c)) {
			for (i in 1...s.length) {
				var d = s.fastCodeAt(i);
				if (isWsOrNul(d) || d == "/".code || d == ">".code) return false;
			}
			return true;
		}
		if (c != ":".code && c != "_".code && c < 0x80) return false;
		for (i in 1...s.length) {
			var d = s.fastCodeAt(i);
			if (!(isAlpha(d) || d >= "0".code && d <= "9".code || d == "-".code || d == ".".code || d == ":".code || d == "_".code || d >= 0x80))
				return false;
		}
		return true;
	}

	public static function validDoctypeName(s:String):Bool {
		for (i in 0...s.length) {
			var c = s.fastCodeAt(i);
			if (isWsOrNul(c) || c == ">".code) return false;
		}
		return true;
	}

	// XML's Name production (a processing instruction's target)
	public static function isXmlName(s:String):Bool {
		if (s.length == 0) return false;
		var i = 0, first = true;
		while (i < s.length) {
			var c = s.fastCodeAt(i++);
			if (c >= 0xD800 && c <= 0xDBFF && i < s.length) c = 0x10000 + ((c - 0xD800) << 10) + (s.fastCodeAt(i++) - 0xDC00);
			if (!(nameStart(c) || !first && nameChar(c))) return false;
			first = false;
		}
		return true;
	}

	static function nameStart(c:Int):Bool
		return c == ":".code || isAlpha(c) || c == "_".code || c >= 0xC0 && c <= 0xD6 || c >= 0xD8 && c <= 0xF6 || c >= 0xF8 && c <= 0x2FF
			|| c >= 0x370 && c <= 0x37D || c >= 0x37F && c <= 0x1FFF || c >= 0x200C && c <= 0x200D || c >= 0x2070 && c <= 0x218F
			|| c >= 0x2C00 && c <= 0x2FEF || c >= 0x3001 && c <= 0xD7FF || c >= 0xF900 && c <= 0xFDCF || c >= 0xFDF0 && c <= 0xFFFD
			|| c >= 0x10000 && c <= 0xEFFFF;

	static function nameChar(c:Int):Bool
		return c == "-".code || c == ".".code || c >= "0".code && c <= "9".code || c == 0xB7 || c >= 0x300 && c <= 0x36F || c >= 0x203F && c <= 0x2040;

	// validate and extract: [namespace, prefix, localName]
	public static function extract(namespace:Null<String>, qualifiedName:String, element:Bool):Array<Null<String>> {
		if (namespace == "") namespace = null;
		var prefix:Null<String> = null, localName = qualifiedName;
		var colon = qualifiedName.indexOf(":");
		if (colon >= 0) {
			prefix = qualifiedName.substr(0, colon);
			localName = qualifiedName.substr(colon + 1);
			if (!validNamespacePrefix(prefix)) throw new DOMException("invalid prefix", "InvalidCharacterError");
		}
		if (element ? !validElementLocalName(localName) : !validAttributeLocalName(localName))
			throw new DOMException("invalid name", "InvalidCharacterError");
		if (prefix != null && namespace == null) throw new DOMException("a prefix without a namespace", "NamespaceError");
		if (prefix == "xml" && namespace != Namespaces.XML) throw new DOMException("xml is the XML namespace's", "NamespaceError");
		if ((qualifiedName == "xmlns" || prefix == "xmlns") && namespace != Namespaces.XMLNS)
			throw new DOMException("xmlns is the XMLNS namespace's", "NamespaceError");
		if (namespace == Namespaces.XMLNS && qualifiedName != "xmlns" && prefix != "xmlns")
			throw new DOMException("the XMLNS namespace is xmlns's", "NamespaceError");
		return [namespace, prefix, localName];
	}

	public static function lower(s:String):String {
		for (i in 0...s.length) {
			var c = s.fastCodeAt(i);
			if (c >= "A".code && c <= "Z".code) {
				var b = new StringBuf();
				b.addSub(s, 0, i);
				for (j in i...s.length) {
					var d = s.fastCodeAt(j);
					b.addChar(d >= "A".code && d <= "Z".code ? d + 32 : d);
				}
				return b.toString();
			}
		}
		return s;
	}

	public static function upper(s:String):String {
		for (i in 0...s.length) {
			var c = s.fastCodeAt(i);
			if (c >= "a".code && c <= "z".code) {
				var b = new StringBuf();
				b.addSub(s, 0, i);
				for (j in i...s.length) {
					var d = s.fastCodeAt(j);
					b.addChar(d >= "a".code && d <= "z".code ? d - 32 : d);
				}
				return b.toString();
			}
		}
		return s;
	}
}
