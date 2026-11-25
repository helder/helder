package helder.ui;

enum abstract TextAlign(String) {
	var Left = "left";
	var Center = "center";
	var Right = "right";
	// both edges: the room left on each line but the last shared among its spaces
	var Justify = "justify";
}
