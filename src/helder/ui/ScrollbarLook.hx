package helder.ui;

// How a Ui's scrollbars look (Ui.scrollbarLook): Plain, helder's (a thin
// thumb over the content, no track); MacOverlay and MacLegacy, macOS's
// overlay and always-shown scrollers as Chromium paints them
// (NativeThemeMac: their insets, thicknesses and colours), the first with
// Ui.overlayBars (shown while scrolling)
enum abstract ScrollbarLook(Int) {
	var Plain;
	var MacOverlay;
	var MacLegacy;
}
