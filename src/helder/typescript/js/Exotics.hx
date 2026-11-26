package helder.typescript.js;

import helder.typescript.js.Values;

// What the runtime asks an object of a kind it does not know itself, a
// proxy (JsObject.PROXY): its internal methods, set when Proxy is
// installed (Proxies.setup), so a program without proxies links none of
// them. Only a proxy has the bit, and only Proxy makes one.
class Exotics {
	// (a proxy was made: the runtime looks for them above an object it writes)
	public static var made = false;

	public static var read:(JsObject, String, Dynamic) -> Dynamic;
	public static var write:(JsObject, String, Dynamic, Dynamic) -> Bool;
	public static var contains:(JsObject, String) -> Bool;
	public static var own:(JsObject, String) -> Dynamic;
	public static var define:(JsObject, String, Dynamic) -> Bool;
	public static var remove:(JsObject, String) -> Bool;
	public static var keys:JsObject->Array<String>;
	public static var protoOf:JsObject->JsObject;
	public static var setProto:(JsObject, Dynamic) -> Bool;
	public static var extensibleOf:JsObject->Bool;
	public static var prevent:JsObject->Bool;
	public static var arrayOf:JsObject->Bool;
	public static var target:JsObject->Null<JsObject>;

	public static inline function is(o:Dynamic):Bool return Std.isOfType(o, JsObject) && (o : JsObject).bits & JsObject.PROXY != 0;

	public static function isExtensible(o:JsObject):Bool return o.bits & JsObject.PROXY != 0 ? extensibleOf(o) : o.extensible;

	public static function preventExtensions(o:JsObject):Bool {
		if (o.bits & JsObject.PROXY != 0) return prevent(o);
		o.extensible = false;
		return true;
	}

	// IsArray: a proxy's is its target's
	public static function isArray(v:Dynamic):Bool return Std.isOfType(v, JsArray) || is(v) && arrayOf(v);

	// (a trap's refusal where the operation throws)
	public static function fail(op:String, k:String):Dynamic
		return Lib.error("TypeError", "'" + op + "' on proxy: trap returned falsish for property '" + (Symbols.isSymbolKey(k) ? Symbols.functionName(k) : k) + "'");
}
