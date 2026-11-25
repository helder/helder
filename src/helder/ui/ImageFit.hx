package helder.ui;

// How an ImageNode's image fills its content box (CSS's object-fit)
enum abstract ImageFit(String) {
	// stretched to the box
	var Fill = "fill";
	// scaled to fit inside it, centred (bars beside or above)
	var Contain = "contain";
	// scaled to cover it, centred (cut at the sides or top and bottom)
	var Cover = "cover";
	// at its own size, centred (cut where larger)
	var None = "none";
}
