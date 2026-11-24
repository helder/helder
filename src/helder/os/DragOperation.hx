package helder.os;

// The operations a file drag offers, or the one its target performed.
enum abstract DragOperation(String) {
	var None = "none";
	var Copy = "copy";
	var Move = "move";
	var Link = "link";
}
