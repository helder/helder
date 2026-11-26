package helder.dom;

// The DOM's DOMException: name is the error's kind as the spec names it
// ("HierarchyRequestError", "NotFoundError", "InvalidCharacterError",
// "NamespaceError", "InUseAttributeError", "IndexSizeError",
// "NotSupportedError", "SyntaxError", "NoModificationAllowedError").
class DOMException extends haxe.Exception {
	public final name:String;
	public var code(get, never):Int;

	public function new(message = "", name = "Error") {
		super(message);
		this.name = name;
	}

	// (the legacy codes, for the names that have one)
	function get_code():Int
		return switch name {
			case "IndexSizeError": 1;
			case "HierarchyRequestError": 3;
			case "WrongDocumentError": 4;
			case "InvalidCharacterError": 5;
			case "NoModificationAllowedError": 7;
			case "NotFoundError": 8;
			case "NotSupportedError": 9;
			case "InUseAttributeError": 10;
			case "InvalidStateError": 11;
			case "SyntaxError": 12;
			case "NamespaceError": 14;
			case _: 0;
		}

	override function toString():String
		return '$name: $message';
}
