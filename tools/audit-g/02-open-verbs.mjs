// Audit G 2: the open verbs. FileDialog.open, which shows the system's
// dialog to pick a file, is FileDialog.pick; Links.open, which shows a page
// (in the app or the browser), is Links.show. (open stays the verb for
// what a program opens and closes: Player.open, WebSocket.open.)
import { edit, done } from "./lib.mjs";

edit(() => true, (s, f) => {
	s = s.replace(/\bFileDialog\.open\b/g, "FileDialog.pick").replace(/\bLinks\.open\b/g, "Links.show");
	if (f === "src/helder/os/FileDialog.hx")
		s = s.replace("public static function open(window:Window, title:String,", "public static function pick(window:Window, title:String,");
	if (f === "src/helder/os/Links.hx")
		s = s.replace("public static function open(url:String, inApp = true):Bool", "public static function show(url:String, inApp = true):Bool");
	return s;
});
done("02-open-verbs");
