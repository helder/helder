package helder.dom;

using StringTools;

// A start or end tag token, the source offsets of its "<" and after its
// ">": its attributes as spans of src (Attrs' layout), or, when parse errors
// are asked for, as names and values read (their references' errors then
// reported where they are).
@:noCompletion class Tag {
	public var name:String;
	public var id:Int;
	public var end:Bool;
	public var selfClosing = false;
	public var acknowledged = false;
	public var start:Int;
	public var stop:Int;
	public var count = 0;
	public var src = "";
	public var raw:Array<Int> = [];
	public var names:Null<Array<String>> = null;
	public var values:Null<Array<String>> = null;

	public function new(name:String, end:Bool, start:Int) {
		this.name = name;
		this.id = name == "" ? 0 : Tags.id(name);
		this.end = end;
		this.start = start;
		this.stop = start;
	}

	public inline function attrName(i:Int):String
		return names != null ? names[i] : Attrs.name(src, raw, i);

	public inline function attrValue(i:Int):String
		return values != null ? values[i] : Attrs.value(src, raw, i);

	public function attr(name:String):Null<String> {
		for (i in 0...count)
			if (names != null ? names[i] == name : Attrs.nameIs(src, raw, i, name)) return attrValue(i);
		return null;
	}

	public function copy():Tag {
		var t = new Tag(name, end, start);
		t.stop = stop;
		t.count = count;
		t.src = src;
		t.raw = raw.slice(0, count * Attrs.SIZE);
		t.names = names == null ? null : names.copy();
		t.values = values == null ? null : values.copy();
		return t;
	}
}

// What the tokenizer emits to (the tree builder, a test's token list).
@:noCompletion interface TokenSink {
	function doctype(name:Null<String>, publicId:Null<String>, systemId:Null<String>, forceQuirks:Bool, start:Int, end:Int):Void;
	function tag(t:Tag):Void;
	// a run of characters; a U+0000 always alone (the tree builder's to drop or replace)
	function chars(text:String, start:Int, end:Int):Void;
	// a run of the source's own characters, s[start, end) as they are (no string made for it)
	function slice(start:Int, end:Int):Void;
	// a character reference's text in content, s[start, end) the reference
	function reference(text:String, start:Int, end:Int):Void;
	function comment(data:String, start:Int, end:Int):Void;
	function pi(target:String, data:String, start:Int, end:Int):Void;
	function eof(at:Int):Void;
	// the adjusted current node is not an HTML element: <![CDATA[ opens a section
	function foreign():Bool;
}

// The HTML standard's tokenizer (13.2.5), state by state, on the input's
// code units: UTF-16 natively and on wasm, code points on Eval; either way
// a character outside ASCII is passed on as it is. CR and CRLF are read as
// LF (the input stream's preprocessing) where they are met, so the offsets
// given to the sink are the source's own.
@:noCompletion class Tokenizer {
	public static inline var DATA = 0;
	public static inline var RCDATA = 1;
	public static inline var RAWTEXT = 2;
	public static inline var SCRIPT_DATA = 3;
	public static inline var PLAINTEXT = 4;
	static inline var TAG_OPEN = 5;
	static inline var END_TAG_OPEN = 6;
	static inline var TAG_NAME = 7;
	static inline var RCDATA_LT = 8;
	static inline var RCDATA_END_OPEN = 9;
	static inline var RCDATA_END_NAME = 10;
	static inline var RAWTEXT_LT = 11;
	static inline var RAWTEXT_END_OPEN = 12;
	static inline var RAWTEXT_END_NAME = 13;
	static inline var SCRIPT_LT = 14;
	static inline var SCRIPT_END_OPEN = 15;
	static inline var SCRIPT_END_NAME = 16;
	static inline var SCRIPT_ESC_START = 17;
	static inline var SCRIPT_ESC_START_DASH = 18;
	static inline var SCRIPT_ESC = 19;
	static inline var SCRIPT_ESC_DASH = 20;
	static inline var SCRIPT_ESC_DASH_DASH = 21;
	static inline var SCRIPT_ESC_LT = 22;
	static inline var SCRIPT_ESC_END_OPEN = 23;
	static inline var SCRIPT_ESC_END_NAME = 24;
	static inline var SCRIPT_DESC_START = 25;
	static inline var SCRIPT_DESC = 26;
	static inline var SCRIPT_DESC_DASH = 27;
	static inline var SCRIPT_DESC_DASH_DASH = 28;
	static inline var SCRIPT_DESC_LT = 29;
	static inline var SCRIPT_DESC_END = 30;
	static inline var BEFORE_ATTR_NAME = 31;
	static inline var ATTR_NAME = 32;
	static inline var AFTER_ATTR_NAME = 33;
	static inline var BEFORE_ATTR_VALUE = 34;
	static inline var ATTR_VALUE_DQ = 35;
	static inline var ATTR_VALUE_SQ = 36;
	static inline var ATTR_VALUE_UQ = 37;
	static inline var AFTER_ATTR_VALUE_Q = 38;
	static inline var SELF_CLOSING = 39;
	static inline var BOGUS_COMMENT = 40;
	static inline var MARKUP_DECL = 41;
	static inline var COMMENT_START = 42;
	static inline var COMMENT_START_DASH = 43;
	static inline var COMMENT = 44;
	static inline var COMMENT_LT = 45;
	static inline var COMMENT_LT_BANG = 46;
	static inline var COMMENT_LT_BANG_DASH = 47;
	static inline var COMMENT_LT_BANG_DASH_DASH = 48;
	static inline var COMMENT_END_DASH = 49;
	static inline var COMMENT_END = 50;
	static inline var COMMENT_END_BANG = 51;
	static inline var DOCTYPE = 52;
	static inline var BEFORE_DOCTYPE_NAME = 53;
	static inline var DOCTYPE_NAME = 54;
	static inline var AFTER_DOCTYPE_NAME = 55;
	static inline var AFTER_PUBLIC_KW = 56;
	static inline var BEFORE_PUBLIC_ID = 57;
	static inline var PUBLIC_ID_DQ = 58;
	static inline var PUBLIC_ID_SQ = 59;
	static inline var AFTER_PUBLIC_ID = 60;
	static inline var BETWEEN_IDS = 61;
	static inline var AFTER_SYSTEM_KW = 62;
	static inline var BEFORE_SYSTEM_ID = 63;
	static inline var SYSTEM_ID_DQ = 64;
	static inline var SYSTEM_ID_SQ = 65;
	static inline var AFTER_SYSTEM_ID = 66;
	static inline var BOGUS_DOCTYPE = 67;
	public static inline var CDATA = 68;
	static inline var CDATA_BRACKET = 69;
	static inline var CDATA_END = 70;
	static inline var PI_OPEN = 71;
	static inline var PI_TARGET = 72;
	static inline var AFTER_PI_TARGET = 73;
	static inline var PI_DATA = 74;
	static inline var PI_QUESTION = 75;
	static inline var CHAR_REF = 76;
	static inline var NAMED_REF = 77;
	static inline var AMBIGUOUS_AMP = 78;
	static inline var NUMERIC_REF = 79;
	static inline var HEX_REF_START = 80;
	static inline var HEX_REF = 81;
	static inline var DEC_REF = 82;
	static inline var NUMERIC_REF_END = 83;

	static inline var EOF = -1;

	public var state = DATA;
	// the tag name of the last start tag emitted (null: none)
	public var lastStartTag:Null<String> = null;

	final s:String;
	final len:Int;
	final sink:TokenSink;
	final errors:Null<Array<ParseError>>;
	// (no errors asked for: attributes kept as spans, their references read when they are)
	final lazy:Bool;
	var pos = 0;
	// the current input character and where it started (EOF: len)
	var cur = EOF;
	var at = 0;
	var reconsume = false;
	// (an offset whose input errors are reported already)
	var checked = -1;
	// (after a processing instruction's target: where html5lib-tests place an end of file in it)
	var piTargetEnd = 0;

	var returnState = DATA;
	var tag:Tag;
	var tagName:Run;
	var attrName:Run;
	var attrValue:Run;
	var attrStart = 0;
	var data:Run;
	var temp:Run;
	var tokenStart = 0;
	var charRefCode = 0;
	// DOCTYPE
	var dName:Null<String> = null;
	var dPublic:Null<String> = null;
	var dSystem:Null<String> = null;
	var dQuirks = false;
	var piTarget = "";

	public function new(s:String, sink:TokenSink, ?errors:Array<ParseError>) {
		Attrs.decoder = Attrs.decode;
		this.s = s;
		this.len = s.length;
		this.sink = sink;
		this.errors = errors;
		lazy = errors == null;
		tag = new Tag("", false, 0);
		tagName = new Run(s);
		attrName = new Run(s);
		attrValue = new Run(s);
		data = new Run(s);
		temp = new Run(s);
	}

	inline function error(code:String, ?offset:Int)
		if (errors != null) errors.push({code: code, offset: offset == null ? at : offset});

	// the next input character, consumed (CR and CRLF as LF)
	inline function next():Int {
		if (reconsume) {
			reconsume = false;
			return cur;
		}
		if (pos >= len) {
			at = len;
			return cur = EOF;
		}
		at = pos;
		var c = s.fastCodeAt(pos++);
		if (c == "\r".code) {
			if (pos < len && s.fastCodeAt(pos) == "\n".code) pos++;
			c = "\n".code;
		} else if (errors != null && (c < 0x20 || c >= 0x7F) && at != checked) check(c, at);
		return cur = c;
	}

	// the input stream's errors: controls, noncharacters, surrogates
	function check(c:Int, i:Int) {
		if (c >= 0xD800 && c <= 0xDBFF) {
			var lo = i + 1 < len ? s.fastCodeAt(i + 1) : 0;
			if (lo >= 0xDC00 && lo <= 0xDFFF) {
				var cp = 0x10000 + ((c - 0xD800) << 10) + (lo - 0xDC00);
				if (cp & 0xFFFE == 0xFFFE) error("noncharacter-in-input-stream", i);
			} else error("surrogate-in-input-stream", i);
			return;
		}
		if (c >= 0xDC00 && c <= 0xDFFF) {
			var hi = i > 0 ? s.fastCodeAt(i - 1) : 0;
			if (!(hi >= 0xD800 && hi <= 0xDBFF)) error("surrogate-in-input-stream", i);
			return;
		}
		if (c > 0xFFFF) {
			if (c & 0xFFFE == 0xFFFE) error("noncharacter-in-input-stream", i);
			return;
		}
		if (c >= 0xFDD0 && c <= 0xFDEF || c == 0xFFFE || c == 0xFFFF) error("noncharacter-in-input-stream", i);
		else if (c != 0 && c != 9 && c != 10 && c != 12 && c != 13 && (c < 0x20 || c >= 0x7F && c <= 0x9F)) error("control-character-in-input-stream", i);
	}

	// (a run's input errors, when they are asked for)
	function checkRun(from:Int, to:Int)
		for (k in from...to) {
			var c = s.fastCodeAt(k);
			if (c < 0x20 || c >= 0x7F) check(c, k);
		}

	inline function again()
		reconsume = true;

	static inline function isWs(c:Int)
		return c == 0x20 || c == 0x0A || c == 0x09 || c == 0x0C;

	static inline function isUpper(c:Int)
		return c >= "A".code && c <= "Z".code;

	static inline function isLower(c:Int)
		return c >= "a".code && c <= "z".code;

	static inline function isAlpha(c:Int)
		return isUpper(c) || isLower(c);

	static inline function isDigit(c:Int)
		return c >= "0".code && c <= "9".code;

	static inline function isAlnum(c:Int)
		return isAlpha(c) || isDigit(c);

	static inline function isHex(c:Int)
		return isDigit(c) || c >= "a".code && c <= "f".code || c >= "A".code && c <= "F".code;

	// the input at pos starts with word (ASCII case-insensitive: fold)
	function lookingAt(word:String, fold:Bool, ?from:Int):Bool {
		var p = from == null ? pos : from;
		if (p + word.length > len) return false;
		for (k in 0...word.length) {
			var c = s.fastCodeAt(p + k), w = word.fastCodeAt(k);
			if (fold && isUpper(c)) c += 32;
			if (c != w) return false;
		}
		return true;
	}

	function emitChars(text:String, start:Int, end:Int)
		sink.chars(text, start, end);

	inline function emitChar(c:Int) {
		if (c < 0x80) sink.chars(ASCII[c], at, pos) else sink.chars(String.fromCharCode(c), at, pos);
	}

	function emitString(t:String)
		sink.chars(t, at, pos);

	function emitTag() {
		var t = tag;
		t.stop = pos;
		if (t.end) {
			if (t.count > 0) error("end-tag-with-attributes");
			if (t.selfClosing) error("end-tag-with-trailing-solidus");
		} else lastStartTag = t.name;
		sink.tag(t);
	}

	function emitComment()
		sink.comment(data.take(), tokenStart, pos);

	function emitDoctype()
		sink.doctype(dName, dPublic, dSystem, dQuirks, tokenStart, pos);

	// (one start and one end tag, reused: the tree builder copies one it keeps)
	var startTag = new Tag("", false, 0);
	var endTag = new Tag("", true, 0);

	function newTag(end:Bool) {
		var t = tag = end ? endTag : startTag;
		t.start = t.stop = tokenStart;
		t.selfClosing = t.acknowledged = false;
		t.count = 0;
		t.src = s;
		t.names = t.values = null;
		tagName.reset();
	}

	function endTagName()
		tag.id = Tags.id(tag.name = tagName.name());

	function newAttr() {
		finishAttr();
		if (!lazy) {
			attrName.reset();
			attrValue.reset();
		}
		attrStart = at;
		nameDirty = valueDirty = false;
		valueStart = valueEnd = 0;
		naming = true;
	}

	// (lazy: the attribute's spans and whether they need reading)
	var nameEnd = 0;
	var nameDirty = false;
	var valueStart = 0;
	var valueEnd = 0;
	var valueDirty = false;
	var nameRef = 0;

	// (lazy: the attribute being named has attribute j's name)
	function sameName(j:Int):Bool {
		var raw = tag.raw, k = j * Attrs.SIZE;
		var ref = raw[k] & 0xFFFF;
		if (ref != 0 && nameRef != 0) return ref == nameRef;
		if (!nameDirty && raw[k] & Attrs.NAME_DIRTY == 0) {
			if (ref != 0 || nameRef != 0) return false;
			var from = raw[k + 1], n = raw[k + 2] - from;
			if (n != nameEnd - attrStart) return false;
			for (i in 0...n)
				if (s.fastCodeAt(from + i) != s.fastCodeAt(attrStart + i)) return false;
			return true;
		}
		// (upper case or NUL in either: compared as read)
		push(0, 0);
		var same = Attrs.name(s, raw, tag.count) == Attrs.name(s, raw, j);
		return same;
	}

	// (the attribute being read, at the tag's next slot: compare or keep)
	function push(valueFrom:Int, valueTo:Int) {
		var raw = tag.raw, k = tag.count * Attrs.SIZE;
		while (raw.length < k + Attrs.SIZE)
			raw.push(0);
		raw[k] = nameRef | (nameDirty ? Attrs.NAME_DIRTY : 0) | (valueDirty ? Attrs.VALUE_DIRTY : 0);
		raw[k + 1] = attrStart;
		raw[k + 2] = nameEnd;
		raw[k + 3] = valueFrom;
		raw[k + 4] = valueTo;
	}

	function attrNamed() {
		if (!naming) return;
		naming = false;
		if (lazy) {
			nameEnd = at;
			// (a name's table entry looked up when it is read, not here)
			nameRef = 0;
			for (j in 0...tag.count)
				if (sameName(j)) {
					hasPending = false;
					return;
				}
			hasPending = true;
			return;
		}
		pendingName = attrName.name();
		var names = tag.names;
		if (names != null && names.contains(pendingName)) {
			error("duplicate-attribute");
			pendingName = null;
			return;
		}
		hasPending = true;
	}

	var naming = false;
	var pendingName:Null<String> = null;
	var hasPending = false;

	function finishAttr() {
		if (naming) attrNamed();
		if (!hasPending) return;
		hasPending = false;
		if (lazy) {
			push(valueStart, valueEnd);
			tag.count++;
			return;
		}
		if (pendingName == null) return;
		if (tag.names == null) {
			tag.names = [];
			tag.values = [];
		}
		tag.names.push(pendingName);
		tag.values.push(attrValue.take());
		tag.count++;
		pendingName = null;
	}

	// an end tag's name is the last start tag's
	inline function appropriate():Bool
		return lastStartTag != null && tagName.take() == lastStartTag;

	inline function inAttribute():Bool
		return returnState == ATTR_VALUE_DQ || returnState == ATTR_VALUE_SQ || returnState == ATTR_VALUE_UQ;

	// flush code points consumed as a character reference: the input's own
	// (no reference read: refStart to end) or a reference's value
	function flushSlice(end:Int) {
		if (inAttribute()) attrValue.sub(refStart, end) else sink.slice(refStart, end);
	}

	function flushValue(v:String) {
		// (a reference read to its next character, to reconsume: it ends before it)
		if (inAttribute()) attrValue.add(v) else sink.reference(v, refStart, reconsume ? at : pos);
	}

	var refStart = 0;

	// text up to a stop character, emitted as a slice; then the state's own handling
	function textRun(stop1:Int, stop2:Int):Bool {
		var start = pos;
		var i = Scan.stop(s, pos, len, stop1, stop2);
		if (errors != null) checkRun(start, i);
		if (i == start) return false;
		pos = i;
		sink.slice(start, i);
		return true;
	}

	public function run() {
		while (true) {
			switch state {
				case DATA:
					if (!reconsume && textRun("<".code, "&".code)) continue;
					var c = next();
					if (c == "&".code) {
						returnState = DATA;
						state = CHAR_REF;
					} else if (c == "<".code) {
						tokenStart = at;
						state = TAG_OPEN;
						// (fastTag emits it, and leaves the state the tree builder set)
						if (lazy) fastTag();
					} else if (c == 0) {
						error("unexpected-null-character");
						emitChar(0);
					} else if (c == EOF) {
						sink.eof(len);
						return;
					} else emitChar(c);
				case RCDATA:
					if (!reconsume && textRun("<".code, "&".code)) continue;
					var c = next();
					if (c == "&".code) {
						returnState = RCDATA;
						state = CHAR_REF;
					} else if (c == "<".code) {
						tokenStart = at;
						state = RCDATA_LT;
					} else if (c == 0) {
						error("unexpected-null-character");
						emitString("\u{FFFD}");
					} else if (c == EOF) {
						sink.eof(len);
						return;
					} else emitChar(c);
				case RAWTEXT | SCRIPT_DATA | PLAINTEXT:
					if (!reconsume && textRun(state == PLAINTEXT ? 0 : "<".code, 0)) continue;
					var c = next();
					if (c == "<".code && state != PLAINTEXT) {
						tokenStart = at;
						state = state == RAWTEXT ? RAWTEXT_LT : SCRIPT_LT;
					} else if (c == 0) {
						error("unexpected-null-character");
						emitString("\u{FFFD}");
					} else if (c == EOF) {
						sink.eof(len);
						return;
					} else emitChar(c);
				case TAG_OPEN:
					var c = next();
					if (c == "!".code) state = MARKUP_DECL;
					else if (c == "/".code) state = END_TAG_OPEN;
					else if (isAlpha(c)) {
						newTag(false);
						again();
						state = TAG_NAME;
					} else if (c == "?".code) {
						temp.reset();
						state = PI_OPEN;
					} else if (c == EOF) {
						error("eof-before-tag-name");
						sink.chars("<", tokenStart, len);
						sink.eof(len);
						return;
					} else {
						error("invalid-first-character-of-tag-name");
						sink.chars("<", tokenStart, tokenStart + 1);
						again();
						state = DATA;
					}
				case END_TAG_OPEN:
					var c = next();
					if (isAlpha(c)) {
						newTag(true);
						again();
						state = TAG_NAME;
					} else if (c == ">".code) {
						error("missing-end-tag-name");
						state = DATA;
					} else if (c == EOF) {
						error("eof-before-tag-name");
						sink.chars("</", tokenStart, len);
						sink.eof(len);
						return;
					} else {
						error("invalid-first-character-of-tag-name");
						data.reset();
						again();
						state = BOGUS_COMMENT;
					}
				case TAG_NAME:
					if (!reconsume) {
						var i = pos, start = pos;
						while (i < len) {
							var c = s.fastCodeAt(i);
							if (isWs(c) || c == "/".code || c == ">".code || c == 0 || c == "\r".code || isUpper(c) || c < 0x20 || c >= 0x7F) break;
							i++;
						}
						if (i > start) {
							tagName.sub(start, i);
							pos = i;
						}
					}
					var c = next();
					if (isWs(c)) {
						endTagName();
						state = BEFORE_ATTR_NAME;
					} else if (c == "/".code) {
						endTagName();
						state = SELF_CLOSING;
					} else if (c == ">".code) {
						endTagName();
						state = DATA;
						emitTag();
					} else if (isUpper(c)) tagName.char(c + 32);
					else if (c == 0) {
						error("unexpected-null-character");
						tagName.char(0xFFFD);
					} else if (c == EOF) {
						error("eof-in-tag");
						sink.eof(len);
						return;
					} else tagName.char(c);
				case RCDATA_LT | RAWTEXT_LT:
					var c = next();
					if (c == "/".code) {
						temp.reset();
						state = state == RCDATA_LT ? RCDATA_END_OPEN : RAWTEXT_END_OPEN;
					} else {
						sink.chars("<", tokenStart, tokenStart + 1);
						again();
						state = state == RCDATA_LT ? RCDATA : RAWTEXT;
					}
				case RCDATA_END_OPEN | RAWTEXT_END_OPEN | SCRIPT_END_OPEN | SCRIPT_ESC_END_OPEN:
					var c = next();
					var back = state == RCDATA_END_OPEN ? RCDATA : state == RAWTEXT_END_OPEN ? RAWTEXT : state == SCRIPT_END_OPEN ? SCRIPT_DATA : SCRIPT_ESC;
					if (isAlpha(c)) {
						newTag(true);
						again();
						state = state == RCDATA_END_OPEN ? RCDATA_END_NAME : state == RAWTEXT_END_OPEN ? RAWTEXT_END_NAME : state == SCRIPT_END_OPEN ? SCRIPT_END_NAME : SCRIPT_ESC_END_NAME;
					} else {
						sink.chars("</", tokenStart, tokenStart + 2);
						again();
						state = back;
					}
				case RCDATA_END_NAME | RAWTEXT_END_NAME | SCRIPT_END_NAME | SCRIPT_ESC_END_NAME:
					var c = next();
					var back = state == RCDATA_END_NAME ? RCDATA : state == RAWTEXT_END_NAME ? RAWTEXT : state == SCRIPT_END_NAME ? SCRIPT_DATA : SCRIPT_ESC;
					if (isWs(c) && appropriate()) {
						endTagName();
						state = BEFORE_ATTR_NAME;
					} else if (c == "/".code && appropriate()) {
						endTagName();
						state = SELF_CLOSING;
					} else if (c == ">".code && appropriate()) {
						endTagName();
						state = DATA;
						emitTag();
					} else if (isUpper(c)) {
						tagName.char(c + 32);
						temp.char(c);
					} else if (isLower(c)) {
						tagName.char(c);
						temp.char(c);
					} else {
						sink.chars("</" + temp.take(), tokenStart, at);
						again();
						state = back;
					}
				case SCRIPT_LT:
					var c = next();
					if (c == "/".code) {
						temp.reset();
						state = SCRIPT_END_OPEN;
					} else if (c == "!".code) {
						state = SCRIPT_ESC_START;
						sink.chars("<!", tokenStart, pos);
					} else {
						sink.chars("<", tokenStart, tokenStart + 1);
						again();
						state = SCRIPT_DATA;
					}
				case SCRIPT_ESC_START | SCRIPT_ESC_START_DASH:
					var c = next();
					if (c == "-".code) {
						state = state == SCRIPT_ESC_START ? SCRIPT_ESC_START_DASH : SCRIPT_ESC_DASH_DASH;
						emitChar(c);
					} else {
						again();
						state = SCRIPT_DATA;
					}
				case SCRIPT_ESC | SCRIPT_ESC_DASH | SCRIPT_ESC_DASH_DASH:
					if (state == SCRIPT_ESC && !reconsume && textRun("-".code, "<".code)) continue;
					var c = next();
					if (c == "-".code) {
						state = state == SCRIPT_ESC ? SCRIPT_ESC_DASH : SCRIPT_ESC_DASH_DASH;
						emitChar(c);
					} else if (c == "<".code) {
						tokenStart = at;
						state = SCRIPT_ESC_LT;
					} else if (c == ">".code && state == SCRIPT_ESC_DASH_DASH) {
						state = SCRIPT_DATA;
						emitChar(c);
					} else if (c == 0) {
						error("unexpected-null-character");
						state = SCRIPT_ESC;
						emitString("\u{FFFD}");
					} else if (c == EOF) {
						error("eof-in-script-html-comment-like-text");
						sink.eof(len);
						return;
					} else {
						state = SCRIPT_ESC;
						emitChar(c);
					}
				case SCRIPT_ESC_LT:
					var c = next();
					if (c == "/".code) {
						temp.reset();
						state = SCRIPT_ESC_END_OPEN;
					} else if (isAlpha(c)) {
						temp.reset();
						sink.chars("<", tokenStart, tokenStart + 1);
						again();
						state = SCRIPT_DESC_START;
					} else {
						sink.chars("<", tokenStart, tokenStart + 1);
						again();
						state = SCRIPT_ESC;
					}
				case SCRIPT_DESC_START | SCRIPT_DESC_END:
					var c = next();
					if (isWs(c) || c == "/".code || c == ">".code) {
						var script = temp.take() == "script";
						state = state == SCRIPT_DESC_START ? (script ? SCRIPT_DESC : SCRIPT_ESC) : (script ? SCRIPT_ESC : SCRIPT_DESC);
						emitChar(c);
					} else if (isUpper(c)) {
						temp.char(c + 32);
						emitChar(c);
					} else if (isLower(c)) {
						temp.char(c);
						emitChar(c);
					} else {
						again();
						state = state == SCRIPT_DESC_START ? SCRIPT_ESC : SCRIPT_DESC;
					}
				case SCRIPT_DESC | SCRIPT_DESC_DASH | SCRIPT_DESC_DASH_DASH:
					if (state == SCRIPT_DESC && !reconsume && textRun("-".code, "<".code)) continue;
					var c = next();
					if (c == "-".code) {
						state = state == SCRIPT_DESC ? SCRIPT_DESC_DASH : SCRIPT_DESC_DASH_DASH;
						emitChar(c);
					} else if (c == "<".code) {
						state = SCRIPT_DESC_LT;
						emitChar(c);
					} else if (c == ">".code && state == SCRIPT_DESC_DASH_DASH) {
						state = SCRIPT_DATA;
						emitChar(c);
					} else if (c == 0) {
						error("unexpected-null-character");
						state = SCRIPT_DESC;
						emitString("\u{FFFD}");
					} else if (c == EOF) {
						error("eof-in-script-html-comment-like-text");
						sink.eof(len);
						return;
					} else {
						state = SCRIPT_DESC;
						emitChar(c);
					}
				case SCRIPT_DESC_LT:
					var c = next();
					if (c == "/".code) {
						temp.reset();
						state = SCRIPT_DESC_END;
						emitChar(c);
					} else {
						again();
						state = SCRIPT_DESC;
					}
				case BEFORE_ATTR_NAME:
					var c = next();
					if (isWs(c)) {} else if (c == "/".code || c == ">".code || c == EOF) {
						again();
						state = AFTER_ATTR_NAME;
					} else if (c == "=".code) {
						error("unexpected-equals-sign-before-attribute-name");
						newAttr();
						if (!lazy) attrName.char(c);
						state = ATTR_NAME;
					} else {
						newAttr();
						again();
						state = ATTR_NAME;
					}
				case ATTR_NAME:
					if (!reconsume) {
						var i = pos, start = pos;
						while (i < len) {
							var c = s.fastCodeAt(i);
							if (isWs(c) || c == "/".code || c == ">".code || c == "=".code || c == 0 || c == "\r".code || isUpper(c) || c == "\"".code
								|| c == "'".code || c == "<".code || c < 0x20 || c >= 0x7F) break;
							i++;
						}
						if (i > start) {
							if (!lazy) attrName.sub(start, i);
							pos = i;
						}
					}
					var c = next();
					if (isWs(c) || c == "/".code || c == ">".code || c == EOF) {
						attrNamed();
						again();
						state = AFTER_ATTR_NAME;
					} else if (c == "=".code) {
						attrNamed();
						state = BEFORE_ATTR_VALUE;
					} else if (lazy) {
						if (isUpper(c) || c == 0) nameDirty = true;
					} else if (isUpper(c)) attrName.char(c + 32);
					else if (c == 0) {
						error("unexpected-null-character");
						attrName.char(0xFFFD);
					} else {
						if (c == "\"".code || c == "'".code || c == "<".code) error("unexpected-character-in-attribute-name");
						attrName.char(c);
					}
				case AFTER_ATTR_NAME:
					var c = next();
					if (isWs(c)) {} else if (c == "/".code) state = SELF_CLOSING;
					else if (c == "=".code) state = BEFORE_ATTR_VALUE;
					else if (c == ">".code) {
						finishAttr();
						state = DATA;
						emitTag();
					} else if (c == EOF) {
						error("eof-in-tag");
						sink.eof(len);
						return;
					} else {
						newAttr();
						again();
						state = ATTR_NAME;
					}
				case BEFORE_ATTR_VALUE:
					var c = next();
					if (isWs(c)) {} else if (c == "\"".code || c == "'".code) {
						state = c == "\"".code ? ATTR_VALUE_DQ : ATTR_VALUE_SQ;
						valueStart = pos;
						if (lazy) {
							// (the value's end: its quote; a reference, CR or NUL in it read later)
							while (true) {
								var i = Scan.stop(s, pos, len, c, "&".code);
								if (i >= len) {
									pos = len;
									break;
								}
								if (s.fastCodeAt(i) == c) {
									valueEnd = i;
									pos = i + 1;
									state = AFTER_ATTR_VALUE_Q;
									break;
								}
								valueDirty = true;
								pos = i + 1;
							}
						}
					}
					else if (c == ">".code) {
						error("missing-attribute-value");
						finishAttr();
						state = DATA;
						emitTag();
					} else {
						again();
						valueStart = at;
						state = ATTR_VALUE_UQ;
					}
				case ATTR_VALUE_DQ | ATTR_VALUE_SQ:
					var quote = state == ATTR_VALUE_DQ ? "\"".code : "'".code;
					if (!reconsume) {
						var start = pos, i = Scan.stop(s, pos, len, quote, "&".code);
						if (errors != null) checkRun(start, i);
						if (i > start) {
							attrValue.sub(start, i);
							pos = i;
						}
					}
					var c = next();
					if (c == quote) state = AFTER_ATTR_VALUE_Q;
					else if (c == "&".code) {
						returnState = state;
						state = CHAR_REF;
					} else if (c == 0) {
						error("unexpected-null-character");
						attrValue.char(0xFFFD);
					} else if (c == EOF) {
						error("eof-in-tag");
						sink.eof(len);
						return;
					} else attrValue.char(c);
				case ATTR_VALUE_UQ:
					var c = next();
					if (isWs(c)) {
						valueEnd = at;
						finishAttr();
						state = BEFORE_ATTR_NAME;
					} else if (lazy && (c == "&".code || c == 0)) valueDirty = true;
					else if (lazy && c == ">".code) {
						valueEnd = at;
						finishAttr();
						state = DATA;
						emitTag();
					} else if (lazy && c != EOF) {} else if (c == "&".code) {
						returnState = ATTR_VALUE_UQ;
						state = CHAR_REF;
					} else if (c == ">".code) {
						finishAttr();
						state = DATA;
						emitTag();
					} else if (c == 0) {
						error("unexpected-null-character");
						attrValue.char(0xFFFD);
					} else if (c == EOF) {
						error("eof-in-tag");
						sink.eof(len);
						return;
					} else {
						if (c == "\"".code || c == "'".code || c == "<".code || c == "=".code || c == "`".code)
							error("unexpected-character-in-unquoted-attribute-value");
						attrValue.char(c);
					}
				case AFTER_ATTR_VALUE_Q:
					var c = next();
					if (isWs(c)) {
						finishAttr();
						state = BEFORE_ATTR_NAME;
					} else if (c == "/".code) {
						finishAttr();
						state = SELF_CLOSING;
					} else if (c == ">".code) {
						finishAttr();
						state = DATA;
						emitTag();
					} else if (c == EOF) {
						error("eof-in-tag");
						sink.eof(len);
						return;
					} else {
						error("missing-whitespace-between-attributes");
						finishAttr();
						again();
						state = BEFORE_ATTR_NAME;
					}
				case SELF_CLOSING:
					var c = next();
					if (c == ">".code) {
						finishAttr();
						tag.selfClosing = true;
						state = DATA;
						emitTag();
					} else if (c == EOF) {
						error("eof-in-tag");
						sink.eof(len);
						return;
					} else {
						error("unexpected-solidus-in-tag");
						again();
						state = BEFORE_ATTR_NAME;
					}
				case BOGUS_COMMENT:
					var c = next();
					if (c == ">".code) {
						state = DATA;
						emitComment();
					} else if (c == EOF) {
						emitComment();
						sink.eof(len);
						return;
					} else if (c == 0) {
						error("unexpected-null-character");
						data.char(0xFFFD);
					} else data.char(c);
				case MARKUP_DECL:
					if (lookingAt("--", false)) {
						pos += 2;
						data.reset();
						state = COMMENT_START;
					} else if (lookingAt("doctype", true)) {
						pos += 7;
						state = DOCTYPE;
					} else if (lookingAt("[CDATA[", false)) {
						pos += 7;
						if (sink.foreign()) state = CDATA else {
							error("cdata-in-html-content", pos - 1);
							data.reset();
							data.add("[CDATA[");
							state = BOGUS_COMMENT;
						}
					} else {
						// (the next character's own errors first: the state looked at it)
						if (errors != null && pos < len) {
							var c = s.fastCodeAt(pos);
							if (c < 0x20 || c >= 0x7F) check(c, pos);
							checked = pos;
						}
						error("incorrectly-opened-comment", pos);
						data.reset();
						state = BOGUS_COMMENT;
					}
				case COMMENT_START:
					var c = next();
					if (c == "-".code) state = COMMENT_START_DASH;
					else if (c == ">".code) {
						error("abrupt-closing-of-empty-comment");
						state = DATA;
						emitComment();
					} else {
						again();
						state = COMMENT;
					}
				case COMMENT_START_DASH:
					var c = next();
					if (c == "-".code) state = COMMENT_END;
					else if (c == ">".code) {
						error("abrupt-closing-of-empty-comment");
						state = DATA;
						emitComment();
					} else if (c == EOF) {
						error("eof-in-comment");
						emitComment();
						sink.eof(len);
						return;
					} else {
						data.char("-".code);
						again();
						state = COMMENT;
					}
				case COMMENT:
					if (!reconsume) {
						var start = pos, i = Scan.stop(s, pos, len, "<".code, "-".code);
						if (errors != null) checkRun(start, i);
						if (i > start) {
							data.sub(start, i);
							pos = i;
						}
					}
					var c = next();
					if (c == "<".code) {
						data.char(c);
						state = COMMENT_LT;
					} else if (c == "-".code) state = COMMENT_END_DASH;
					else if (c == 0) {
						error("unexpected-null-character");
						data.char(0xFFFD);
					} else if (c == EOF) {
						error("eof-in-comment");
						emitComment();
						sink.eof(len);
						return;
					} else data.char(c);
				case COMMENT_LT:
					var c = next();
					if (c == "!".code) {
						data.char(c);
						state = COMMENT_LT_BANG;
					} else if (c == "<".code) data.char(c) else {
						again();
						state = COMMENT;
					}
				case COMMENT_LT_BANG:
					var c = next();
					if (c == "-".code) state = COMMENT_LT_BANG_DASH else {
						again();
						state = COMMENT;
					}
				case COMMENT_LT_BANG_DASH:
					var c = next();
					if (c == "-".code) state = COMMENT_LT_BANG_DASH_DASH else {
						again();
						state = COMMENT_END_DASH;
					}
				case COMMENT_LT_BANG_DASH_DASH:
					var c = next();
					if (c != ">".code && c != EOF) error("nested-comment");
					again();
					state = COMMENT_END;
				case COMMENT_END_DASH:
					var c = next();
					if (c == "-".code) state = COMMENT_END;
					else if (c == EOF) {
						error("eof-in-comment");
						emitComment();
						sink.eof(len);
						return;
					} else {
						data.char("-".code);
						again();
						state = COMMENT;
					}
				case COMMENT_END:
					var c = next();
					if (c == ">".code) {
						state = DATA;
						emitComment();
					} else if (c == "!".code) state = COMMENT_END_BANG;
					else if (c == "-".code) data.char(c);
					else if (c == EOF) {
						error("eof-in-comment");
						emitComment();
						sink.eof(len);
						return;
					} else {
						data.add("--");
						again();
						state = COMMENT;
					}
				case COMMENT_END_BANG:
					var c = next();
					if (c == "-".code) {
						data.add("--!");
						state = COMMENT_END_DASH;
					} else if (c == ">".code) {
						error("incorrectly-closed-comment");
						state = DATA;
						emitComment();
					} else if (c == EOF) {
						error("eof-in-comment");
						emitComment();
						sink.eof(len);
						return;
					} else {
						data.add("--!");
						again();
						state = COMMENT;
					}
				case DOCTYPE:
					var c = next();
					dName = dPublic = dSystem = null;
					dQuirks = false;
					if (isWs(c)) state = BEFORE_DOCTYPE_NAME;
					else if (c == ">".code) {
						again();
						state = BEFORE_DOCTYPE_NAME;
					} else if (c == EOF) {
						error("eof-in-doctype");
						dQuirks = true;
						emitDoctype();
						sink.eof(len);
						return;
					} else {
						error("missing-whitespace-before-doctype-name");
						again();
						state = BEFORE_DOCTYPE_NAME;
					}
				case BEFORE_DOCTYPE_NAME:
					var c = next();
					if (isWs(c)) {} else if (c == ">".code) {
						error("missing-doctype-name");
						dQuirks = true;
						state = DATA;
						emitDoctype();
					} else if (c == EOF) {
						error("eof-in-doctype");
						dQuirks = true;
						emitDoctype();
						sink.eof(len);
						return;
					} else {
						data.reset();
						if (isUpper(c)) data.char(c + 32);
						else if (c == 0) {
							error("unexpected-null-character");
							data.char(0xFFFD);
						} else data.char(c);
						state = DOCTYPE_NAME;
					}
				case DOCTYPE_NAME:
					var c = next();
					if (isWs(c)) {
						dName = data.take();
						state = AFTER_DOCTYPE_NAME;
					} else if (c == ">".code) {
						dName = data.take();
						state = DATA;
						emitDoctype();
					} else if (isUpper(c)) data.char(c + 32);
					else if (c == 0) {
						error("unexpected-null-character");
						data.char(0xFFFD);
					} else if (c == EOF) {
						error("eof-in-doctype");
						dName = data.take();
						dQuirks = true;
						emitDoctype();
						sink.eof(len);
						return;
					} else data.char(c);
				case AFTER_DOCTYPE_NAME:
					var c = next();
					if (isWs(c)) {} else if (c == ">".code) {
						state = DATA;
						emitDoctype();
					} else if (c == EOF) {
						error("eof-in-doctype");
						dQuirks = true;
						emitDoctype();
						sink.eof(len);
						return;
					} else {
						if (lookingAt("public", true, at)) {
							pos = at + 6;
							state = AFTER_PUBLIC_KW;
						} else if (lookingAt("system", true, at)) {
							pos = at + 6;
							state = AFTER_SYSTEM_KW;
						} else {
							error("invalid-character-sequence-after-doctype-name");
							dQuirks = true;
							again();
							state = BOGUS_DOCTYPE;
						}
					}
				case AFTER_PUBLIC_KW | AFTER_SYSTEM_KW:
					var c = next();
					var pub = state == AFTER_PUBLIC_KW;
					if (isWs(c)) state = pub ? BEFORE_PUBLIC_ID : BEFORE_SYSTEM_ID;
					else if (c == "\"".code || c == "'".code) {
						error(pub ? "missing-whitespace-after-doctype-public-keyword" : "missing-whitespace-after-doctype-system-keyword");
						data.reset();
						if (pub) dPublic = "" else dSystem = "";
						state = pub ? (c == "\"".code ? PUBLIC_ID_DQ : PUBLIC_ID_SQ) : (c == "\"".code ? SYSTEM_ID_DQ : SYSTEM_ID_SQ);
					} else if (c == ">".code) {
						error(pub ? "missing-doctype-public-identifier" : "missing-doctype-system-identifier");
						dQuirks = true;
						state = DATA;
						emitDoctype();
					} else if (c == EOF) {
						error("eof-in-doctype");
						dQuirks = true;
						emitDoctype();
						sink.eof(len);
						return;
					} else {
						error(pub ? "missing-quote-before-doctype-public-identifier" : "missing-quote-before-doctype-system-identifier");
						dQuirks = true;
						again();
						state = BOGUS_DOCTYPE;
					}
				case BEFORE_PUBLIC_ID | BEFORE_SYSTEM_ID:
					var c = next();
					var pub = state == BEFORE_PUBLIC_ID;
					if (isWs(c)) {} else if (c == "\"".code || c == "'".code) {
						data.reset();
						if (pub) dPublic = "" else dSystem = "";
						state = pub ? (c == "\"".code ? PUBLIC_ID_DQ : PUBLIC_ID_SQ) : (c == "\"".code ? SYSTEM_ID_DQ : SYSTEM_ID_SQ);
					} else if (c == ">".code) {
						error(pub ? "missing-doctype-public-identifier" : "missing-doctype-system-identifier");
						dQuirks = true;
						state = DATA;
						emitDoctype();
					} else if (c == EOF) {
						error("eof-in-doctype");
						dQuirks = true;
						emitDoctype();
						sink.eof(len);
						return;
					} else {
						error(pub ? "missing-quote-before-doctype-public-identifier" : "missing-quote-before-doctype-system-identifier");
						dQuirks = true;
						again();
						state = BOGUS_DOCTYPE;
					}
				case PUBLIC_ID_DQ | PUBLIC_ID_SQ | SYSTEM_ID_DQ | SYSTEM_ID_SQ:
					var c = next();
					var pub = state == PUBLIC_ID_DQ || state == PUBLIC_ID_SQ;
					var quote = state == PUBLIC_ID_DQ || state == SYSTEM_ID_DQ ? "\"".code : "'".code;
					if (c == quote) {
						if (pub) dPublic = data.take() else dSystem = data.take();
						state = pub ? AFTER_PUBLIC_ID : AFTER_SYSTEM_ID;
					} else if (c == 0) {
						error("unexpected-null-character");
						data.char(0xFFFD);
					} else if (c == ">".code) {
						error(pub ? "abrupt-doctype-public-identifier" : "abrupt-doctype-system-identifier");
						if (pub) dPublic = data.take() else dSystem = data.take();
						dQuirks = true;
						state = DATA;
						emitDoctype();
					} else if (c == EOF) {
						error("eof-in-doctype");
						if (pub) dPublic = data.take() else dSystem = data.take();
						dQuirks = true;
						emitDoctype();
						sink.eof(len);
						return;
					} else data.char(c);
				case AFTER_PUBLIC_ID | BETWEEN_IDS:
					var c = next();
					var after = state == AFTER_PUBLIC_ID;
					if (isWs(c)) {
						if (after) state = BETWEEN_IDS;
					} else if (c == ">".code) {
						state = DATA;
						emitDoctype();
					} else if (c == "\"".code || c == "'".code) {
						if (after) error("missing-whitespace-between-doctype-public-and-system-identifiers");
						data.reset();
						dSystem = "";
						state = c == "\"".code ? SYSTEM_ID_DQ : SYSTEM_ID_SQ;
					} else if (c == EOF) {
						error("eof-in-doctype");
						dQuirks = true;
						emitDoctype();
						sink.eof(len);
						return;
					} else {
						error("missing-quote-before-doctype-system-identifier");
						dQuirks = true;
						again();
						state = BOGUS_DOCTYPE;
					}
				case AFTER_SYSTEM_ID:
					var c = next();
					if (isWs(c)) {} else if (c == ">".code) {
						state = DATA;
						emitDoctype();
					} else if (c == EOF) {
						error("eof-in-doctype");
						dQuirks = true;
						emitDoctype();
						sink.eof(len);
						return;
					} else {
						error("unexpected-character-after-doctype-system-identifier");
						again();
						state = BOGUS_DOCTYPE;
					}
				case BOGUS_DOCTYPE:
					var c = next();
					if (c == ">".code) {
						state = DATA;
						emitDoctype();
					} else if (c == 0) error("unexpected-null-character");
					else if (c == EOF) {
						emitDoctype();
						sink.eof(len);
						return;
					}
				case CDATA:
					if (!reconsume && textRun("]".code, 0x110000)) continue;
					var c = next();
					if (c == "]".code) state = CDATA_BRACKET;
					else if (c == EOF) {
						error("eof-in-cdata");
						sink.eof(len);
						return;
					} else emitChar(c);
				case CDATA_BRACKET:
					var c = next();
					if (c == "]".code) state = CDATA_END else {
						sink.chars("]", at - 1, at);
						again();
						state = CDATA;
					}
				case CDATA_END:
					var c = next();
					if (c == "]".code) sink.chars("]", at - 2, at - 1);
					else if (c == ">".code) state = DATA;
					else {
						sink.chars("]]", at - 2, at);
						again();
						state = CDATA;
					}
				case PI_OPEN:
					var c = next();
					if (isAlpha(c) || c == "_".code) {
						again();
						state = PI_TARGET;
					} else if (c == EOF) {
						error("eof-in-processing-instruction");
						sink.eof(len);
						return;
					} else {
						error("invalid-first-character-of-processing-instruction-target");
						data.reset();
						data.char("?".code);
						again();
						state = BOGUS_COMMENT;
					}
				case PI_TARGET:
					var c = next();
					if (isWs(c) || c == "?".code || c == ">".code) {
						var target = temp.take();
						var lower = target.toLowerCase();
						if (lower == "xml" || lower == "xml-stylesheet") {
							error("disallowed-processing-instruction-target");
							data.reset();
							data.char("?".code);
							data.add(target);
							again();
							state = BOGUS_COMMENT;
						} else {
							piTarget = target;
							piTargetEnd = at;
							data.reset();
							again();
							state = AFTER_PI_TARGET;
						}
					} else if (isAlnum(c) || c == "-".code || c == "_".code) temp.char(c);
					else if (c == EOF) {
						error("eof-in-processing-instruction");
						sink.eof(len);
						return;
					} else {
						error("invalid-processing-instruction-target");
						data.reset();
						data.char("?".code);
						data.add(temp.take());
						again();
						state = BOGUS_COMMENT;
					}
				case AFTER_PI_TARGET:
					var c = next();
					if (!isWs(c)) {
						again();
						state = PI_DATA;
					}
				case PI_DATA:
					var c = next();
					if (c == "?".code) state = PI_QUESTION;
					else if (c == ">".code) {
						state = DATA;
						sink.pi(piTarget, data.take(), tokenStart, pos);
					} else if (c == EOF) {
						error("eof-in-processing-instruction", piTargetEnd);
						sink.eof(len);
						return;
					} else data.char(c);
				case PI_QUESTION:
					var c = next();
					if (c == ">".code) {
						state = DATA;
						sink.pi(piTarget, data.take(), tokenStart, pos);
					} else if (c == EOF) {
						error("eof-in-processing-instruction", piTargetEnd);
						sink.eof(len);
						return;
					} else {
						data.char("?".code);
						again();
						state = PI_DATA;
					}
				case CHAR_REF:
					refStart = at;
					var c = next();
					if (isAlnum(c)) {
						again();
						state = NAMED_REF;
					} else if (c == "#".code) state = NUMERIC_REF;
					else {
						flushSlice(refStart + 1);
						again();
						state = returnState;
					}
				case NAMED_REF:
					namedRef();
				case AMBIGUOUS_AMP:
					var c = next();
					if (isAlnum(c)) {
						if (inAttribute()) attrValue.char(c) else emitChar(c);
					} else {
						if (c == ";".code) error("unknown-named-character-reference");
						again();
						state = returnState;
					}
				case NUMERIC_REF:
					charRefCode = 0;
					var c = next();
					if (c == "x".code || c == "X".code) state = HEX_REF_START;
					else if (isDigit(c)) {
						again();
						state = DEC_REF;
					} else {
						error("absence-of-digits-in-numeric-character-reference");
						flushSlice(refStart + 2);
						again();
						state = returnState;
					}
				case HEX_REF_START:
					var c = next();
					if (isHex(c)) {
						again();
						state = HEX_REF;
					} else {
						error("absence-of-digits-in-numeric-character-reference");
						flushSlice(refStart + 3);
						again();
						state = returnState;
					}
				case HEX_REF | DEC_REF:
					var c = next();
					var hex = state == HEX_REF;
					if (isDigit(c)) charRefCode = grow(charRefCode * (hex ? 16 : 10) + c - 0x30);
					else if (hex && c >= "A".code && c <= "F".code) charRefCode = grow(charRefCode * 16 + c - 0x37);
					else if (hex && c >= "a".code && c <= "f".code) charRefCode = grow(charRefCode * 16 + c - 0x57);
					else if (c == ";".code) state = NUMERIC_REF_END;
					else {
						error("missing-semicolon-after-character-reference");
						again();
						state = NUMERIC_REF_END;
					}
				case NUMERIC_REF_END:
					numericRefEnd();
					state = returnState;
				case _:
					throw "Tokenizer: state " + state;
			}
		}
	}

	static inline function isTagWs(c:Int):Bool
		return c == 0x20 || c == 0x0A || c == 0x09 || c == 0x0C || c == 0x0D;

	// an ordinary tag read in one pass, as the states would read it (no
	// errors asked for: none to report): a lower-case name, attributes with
	// names in lower case, their values quoted or plain, white space, "/>".
	// Anything else, and nothing is consumed: false, the states read it.
	function fastTag():Bool {
		var p = pos;
		var c = p < len ? s.fastCodeAt(p) : -1;
		var end = c == "/".code;
		if (end) {
			p++;
			c = p < len ? s.fastCodeAt(p) : -1;
		}
		if (!isLower(c)) return false;
		var nameStart = p;
		while (p < len) {
			c = s.fastCodeAt(p);
			if (isLower(c) || isDigit(c) || c == "-".code) p++ else break;
		}
		if (p >= len) return false;
		var tagEnd = p;
		c = s.fastCodeAt(p);
		if (!(isTagWs(c) || c == "/".code || c == ">".code)) return false;
		var t = end ? endTag : startTag;
		tag = t;
		t.count = 0;
		t.src = s;
		t.names = t.values = null;
		while (true) {
			while (p < len && isTagWs(s.fastCodeAt(p)))
				p++;
			if (p >= len) return false;
			c = s.fastCodeAt(p);
			if (c == ">".code) {
				p++;
				t.selfClosing = false;
				break;
			}
			if (c == "/".code) {
				if (p + 1 < len && s.fastCodeAt(p + 1) == ">".code) {
					p += 2;
					t.selfClosing = true;
					break;
				}
				return false;
			}
			// an attribute's name
			var an = p;
			while (p < len) {
				c = s.fastCodeAt(p);
				if (isTagWs(c) || c == "/".code || c == ">".code || c == "=".code) break;
				if (isUpper(c) || c == 0 || c == "\"".code || c == "'".code || c == "<".code) return false;
				p++;
			}
			if (p >= len || p == an) return false;
			var ae = p, vs = 0, ve = 0, dirty = false;
			while (p < len && isTagWs(s.fastCodeAt(p)))
				p++;
			if (p < len && s.fastCodeAt(p) == "=".code) {
				p++;
				while (p < len && isTagWs(s.fastCodeAt(p)))
					p++;
				if (p >= len) return false;
				c = s.fastCodeAt(p);
				if (c == "\"".code || c == "'".code) {
					vs = p + 1;
					var i = vs;
					while (true) {
						i = Scan.stop(s, i, len, c, "&".code);
						if (i >= len) return false;
						if (s.fastCodeAt(i) == c) break;
						dirty = true;
						i++;
					}
					ve = i;
					p = i + 1;
					// (a quote straight after: the states' error, theirs to read)
					if (p < len) {
						var d = s.fastCodeAt(p);
						if (!(isTagWs(d) || d == "/".code || d == ">".code)) return false;
					}
				} else if (c == ">".code) return false;
				else {
					vs = p;
					while (p < len) {
						c = s.fastCodeAt(p);
						if (isTagWs(c) || c == ">".code) break;
						if (c == "\"".code || c == "'".code || c == "<".code || c == "=".code || c == "`".code) return false;
						if (c == "&".code || c == 0) dirty = true;
						p++;
					}
					if (p >= len) return false;
					ve = p;
				}
			}
			// (kept as the states keep it: a duplicate dropped)
			attrStart = an;
			nameEnd = ae;
			nameDirty = false;
			valueDirty = dirty;
			nameRef = 0;
			var duplicate = false;
			for (j in 0...t.count)
				if (sameName(j)) {
					duplicate = true;
					break;
				}
			if (!duplicate) {
				push(vs, ve);
				t.count++;
			}
		}
		t.start = tokenStart;
		t.acknowledged = false;
		t.end = end;
		var k = Tags.find(s, nameStart, tagEnd);
		t.name = k != 0 ? Tags.name(k) : s.substring(nameStart, tagEnd);
		t.id = k != 0 && k <= Tags.DESC ? k : Tags.OTHER;
		pos = p;
		at = p - 1;
		state = DATA;
		emitTag();
		return true;
	}

	// (a code past U+10FFFF is an error whatever its size: kept from overflowing)
	static inline function grow(n:Int):Int
		return n > 0x10FFFF ? 0x110000 : n;

	function namedRef() {
		// the longest name the table has: the letters and digits ahead, with
		// their ";" when it follows, else the longest legacy one among them
		var start = reconsume ? at : pos;
		reconsume = false;
		pos = start;
		var i = start;
		while (i < len && i - start < Entities.LONGEST && isAlnum(s.fastCodeAt(i)))
			i++;
		var matched = -1, value:Null<String> = null;
		if (i < len && s.fastCodeAt(i) == ";".code) {
			value = Entities.get(s.substring(start, i + 1));
			if (value != null) matched = i + 1;
		}
		if (value == null) {
			var j = i;
			while (j > start) {
				value = Entities.get(s.substring(start, j));
				if (value != null) {
					matched = j;
					break;
				}
				j--;
			}
		}
		if (value == null) {
			flushSlice(refStart + 1);
			state = AMBIGUOUS_AMP;
			return;
		}
		var semicolon = s.fastCodeAt(matched - 1) == ";".code;
		var following = matched < len ? s.fastCodeAt(matched) : EOF;
		if (inAttribute() && !semicolon && (following == "=".code || isAlnum(following))) {
			pos = matched;
			flushSlice(matched);
			state = returnState;
			return;
		}
		pos = matched;
		if (!semicolon) error("missing-semicolon-after-character-reference", matched);
		flushValue(value);
		state = returnState;
	}

	function numericRefEnd() {
		var code = charRefCode;
		// (where the reference ends: html5lib-tests' place for its errors)
		var after = reconsume ? at : pos;
		if (code == 0) {
			error("null-character-reference", after);
			code = 0xFFFD;
		} else if (code > 0x10FFFF) {
			error("character-reference-outside-unicode-range", after);
			code = 0xFFFD;
		} else if (code >= 0xD800 && code <= 0xDFFF) {
			error("surrogate-character-reference", after);
			code = 0xFFFD;
		} else if (code >= 0xFDD0 && code <= 0xFDEF || code & 0xFFFE == 0xFFFE) error("noncharacter-character-reference", after);
		else if (code == 0x0D || (code < 0x20 && code != 9 && code != 10 && code != 12) || code >= 0x7F && code <= 0x9F) {
			error("control-character-reference", after);
			if (code >= 0x80 && code <= 0x9F && C1[code - 0x80] != 0) code = C1[code - 0x80];
		}
		code = referenceCode(code);
		flushValue(code < 0x80 ? ASCII[code] : String.fromCharCode(code));
	}

	// a numeric reference's character (the end state's replacements)
	public static function referenceCode(code:Int):Int {
		if (code == 0 || code > 0x10FFFF || code >= 0xD800 && code <= 0xDFFF) return 0xFFFD;
		if (code >= 0x80 && code <= 0x9F && C1[code - 0x80] != 0) return C1[code - 0x80];
		return code;
	}

	static final ASCII = [for (c in 0...0x80) String.fromCharCode(c)];

	static final C1 = [
		0x20AC, 0, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0, 0x017D, 0, 0, 0x2018, 0x2019, 0x201C, 0x201D,
		0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0, 0x017E, 0x0178
	];
}
