package helder.os;

// The system's material behind a transparent window (Window.backdrop):
// "blur", what is behind blurred (macOS's vibrancy, Windows 11's Acrylic,
// KDE's blur); "mica", the desktop's colours, faint (Windows 11's Mica,
// macOS's under-window vibrancy, KDE's blur); "sidebar", a window's
// sidebar's (macOS's sidebar material, Finder's, dimmed while the window is
// not active; Windows 11's Mica, KDE's blur); "glass", macOS 26's Liquid
// Glass; "none".
enum abstract WindowBackdrop(String) to String {
	var None = "none";
	var Blur = "blur";
	var Mica = "mica";
	var Sidebar = "sidebar";
	var Glass = "glass";
}
