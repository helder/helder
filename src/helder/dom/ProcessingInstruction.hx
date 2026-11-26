package helder.dom;

using StringTools;

// The DOM's ProcessingInstruction: <?target data?>. Its attributes are the
// pseudo-attributes its data reads as (name="value" ..., xml-stylesheet's
// rules; none if the data does not), read when first asked for.
@:allow(helder.dom)
class ProcessingInstruction extends CharacterData {
	public var target(default, null):String;

	// name, value, ...: the attribute map (null: not read from the data yet)
	var map:Null<Array<String>> = null;

	function new(doc:Document, target:String, data:String) {
		super(Node.PROCESSING_INSTRUCTION_NODE, doc, data);
		this.target = target;
	}

	override function get_nodeName():String
		return target;

	override function changed()
		map = null;

	function attrs():Array<String>
		return map ?? (map = parse(value));

	public function hasAttributes():Bool
		return attrs().length > 0;

	public function getAttributeNames():Array<String> {
		var m = attrs();
		return [for (i in 0...m.length >> 1) m[i * 2]];
	}

	public function getAttribute(name:String):Null<String> {
		var m = attrs(), i = find(m, name);
		return i < 0 ? null : m[i + 1];
	}

	public function hasAttribute(name:String):Bool
		return find(attrs(), name) >= 0;

	public function setAttribute(name:String, value:String) {
		if (!Names.validAttributeLocalName(name)) throw new DOMException("invalid name", "InvalidCharacterError");
		var m = attrs(), i = find(m, name);
		if (i < 0) {
			m.push(name);
			m.push(value);
		} else m[i + 1] = value;
		update(m);
	}

	public function removeAttribute(name:String) {
		var m = attrs(), i = find(m, name);
		if (i < 0) return;
		m.splice(i, 2);
		update(m);
	}

	public function toggleAttribute(name:String, ?force:Bool):Bool {
		if (!Names.validAttributeLocalName(name)) throw new DOMException("invalid name", "InvalidCharacterError");
		var m = attrs(), i = find(m, name);
		if (i < 0) {
			if (force == null || force) {
				m.push(name);
				m.push("");
				update(m);
				return true;
			}
			return false;
		}
		if (force == null || !force) {
			m.splice(i, 2);
			update(m);
			return false;
		}
		return true;
	}

	static function find(m:Array<String>, name:String):Int {
		var i = 0;
		while (i < m.length) {
			if (m[i] == name) return i;
			i += 2;
		}
		return -1;
	}

	// update data from attributes (the map kept: the data is its serialization)
	function update(m:Array<String>) {
		var buf = new StringBuf();
		var i = 0;
		while (i < m.length) {
			if (i > 0) buf.add(" ");
			buf.add(m[i]);
			buf.add("=\"");
			buf.add(m[i + 1].replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;"));
			buf.add("\"");
			i += 2;
		}
		replaceData(0, value.length, buf.toString());
		map = m;
	}

	// xml-stylesheet's pseudo-attributes: (S? Name S? = S? "value")* S?, a
	// value's & only as &#n;, &#xn; or a predefined entity; any error: none
	static function parse(data:String):Array<String> {
		var out = [], i = 0, n = data.length;
		inline function ws(c:Int)
			return c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;
		while (true) {
			var spaced = i == 0;
			while (i < n && ws(data.fastCodeAt(i))) {
				i++;
				spaced = true;
			}
			if (i >= n) return out;
			if (!spaced) return [];
			var start = i;
			while (i < n && !ws(data.fastCodeAt(i)) && data.fastCodeAt(i) != "=".code)
				i++;
			var name = data.substring(start, i);
			if (!Names.isXmlName(name)) return [];
			while (i < n && ws(data.fastCodeAt(i)))
				i++;
			if (i >= n || data.fastCodeAt(i) != "=".code) return [];
			i++;
			while (i < n && ws(data.fastCodeAt(i)))
				i++;
			if (i >= n) return [];
			var quote = data.fastCodeAt(i++);
			if (quote != "\"".code && quote != "'".code) return [];
			var buf = new StringBuf();
			while (true) {
				if (i >= n) return [];
				var c = data.fastCodeAt(i);
				if (c == quote) break;
				if (c == "<".code) return [];
				if (c == "&".code) {
					var semi = data.indexOf(";", i);
					if (semi < 0) return [];
					var ref = data.substring(i + 1, semi);
					switch ref {
						case "amp": buf.add("&");
						case "lt": buf.add("<");
						case "gt": buf.add(">");
						case "quot": buf.add("\"");
						case "apos": buf.add("'");
						case _:
							var code = ref.startsWith("#x") ? Std.parseInt("0x" + ref.substr(2)) : ref.startsWith("#") ? Std.parseInt(ref.substr(1)) : null;
							if (code == null || code <= 0 || code > 0x10FFFF || ref.length < 2) return [];
							buf.addChar(code);
					}
					i = semi + 1;
					continue;
				}
				buf.addChar(c);
				i++;
			}
			i++;
			var k = find(out, name);
			if (k >= 0) out[k + 1] = buf.toString() else {
				out.push(name);
				out.push(buf.toString());
			}
		}
	}

	override function cloneOne(document:Document):Node
		return new ProcessingInstruction(document, target, value);

	override function equalsOne(other:Node):Bool
		return other.nodeType == nodeType && (cast other : ProcessingInstruction).target == target && (cast other : ProcessingInstruction).value == value;
}
