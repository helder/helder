package helder.dom;

private enum Value {
	N(node:Node);
	S(text:String);
}

// ParentNode's and ChildNode's (Node or DOMString)... arguments: a string
// becomes a Text node in the caller's document.
abstract NodeOrString(Value) {
	inline function new(v:Value)
		this = v;

	@:from static inline function ofNode(node:Node):NodeOrString
		return new NodeOrString(N(node));

	@:from static inline function ofString(text:String):NodeOrString
		return new NodeOrString(S(text));

	@:allow(helder.dom) function toNode(document:Document):Node
		return switch this {
			case N(node): node;
			case S(text): document.createTextNode(text);
		}

	@:allow(helder.dom) function node():Null<Node>
		return switch this {
			case N(node): node;
			case S(_): null;
		}
}
