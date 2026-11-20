package helder.os.web;

import hxmc.unsafe.*;

// The browser's side of helder.os (WebAssembly): imports of the module
// "hxmc_os", which src/helder/os/imports.mjs provides (loaded by
// src/helder/os/browser.mjs). Canvases are handles into the loader's table of
// JavaScript objects (0: none); sizes are in pixels of the drawing buffer.
@:hxmc.c @:hxmc.lib("hxmc_os") extern class Dom {
	// a canvas for a new window (the loader's `canvas` option, else a new
	// element at the end of the page), its buffer width x height CSS pixels
	static function window_open(title:CString, width:Int, height:Int):Int;
	static function window_close(canvas:Int):Void;
	// the canvas element of that id (0: none)
	static function canvas(id:CString):Int;
	static function width(canvas:Int):Int;
	static function height(canvas:Int):Int;
	// device pixels per CSS pixel
	static function scale():Float;
	// the page's prefers-color-scheme: dark (1) or not (0)
	static function prefers_dark():Int;
	static function settings():Int;
	static function locale_languages():Int;
	static function locale_number(value:Float, locale:Ptr, decimals:Int, percent:Int, currency:Ptr):Int;
	static function locale_date(value:Float, locale:Ptr, date:Int, time:Int):Int;
	static function locale_watch(changed:Ptr):Void;
	// the network: 0 offline, else 1 + wifi, cellular, ethernet's index (navigator.onLine, navigator.connection.type)
	static function network():Int;
	// the page on an Apple system (1: macOS, iOS; navigator's platform), else 0
	static function apple():Int;
	// the next pending event into ev (twelve Int32: canvas, EventKind, key (a
	// TextInput's code point, a TextEditing's string handle, a pointer's
	// pointerId, 0 for none), x, y, button, mods; a pointer's: x and y in
	// 1/256 pixels, then its PointerType | buttons << 4 | 4096 if primary,
	// pressure in 1/65536ths, the time in 1/16 ms, tiltX, tiltY; kind 101: a
	// sample of the pointer's next event); 0: none
	static function next_event(ev:Ptr<Int32>):Int;
	// the clipboard: write; read (its text comes back as an event of kind 100,
	// key: a string handle, 0 for none)
	static function clipboard_write(text:CString):Void;
	static function clipboard_read():Void;
	// a file given to the user: n bytes at p downloaded as name (the page's
	// own download: a Blob's URL on a link clicked); nothing without a document
	@:hxmc.fast @:hxmc.len(data, n) static function download(name:CString, data:hxmc.ReadOnlySpan<UInt8>, n:Int, type:CString):Void;
	// a vibration of ms (helder.os.Haptics: navigator.vibrate, nothing where there is none)
	static function vibrate(ms:Int):Void;
	// a page opened in a new tab (helder.os.Links)
	static function open_url(url:CString):Void;
	// a line in the console (helder.os.SystemLog)
	static function console_log(line:CString):Void;
	// a string handle's UTF-8 length; its bytes into p (the handle freed)
	static function text_length(h:Int):Int;
	static function text_take(h:Int, p:Ptr):Void;
	// text input on (its input element focused, at that area in buffer
	// pixels) or off (the canvas focused again)
	static function text_input(canvas:Int, on:Int, x:Int, y:Int, width:Int, height:Int):Void;
	// the canvas's CSS cursor, by Cursor
	static function set_cursor(canvas:Int, cursor:Int):Void;
	// the page's title; the canvas's CSS size (min: its minimum)
	static function set_title(title:Ptr):Void;
	static function set_size(canvas:Int, width:Int, height:Int, min:Int):Void;
	// a touch drag's question (Window.scrollsAt): the page calls query (a
	// @:hxmc.callback (canvas, x, y, dx, dy):Int, buffer pixels; 1 yes, 0
	// no, -1 not asked) when it would pan the page otherwise
	static function scrolls_at(query:Ptr):Void;
	// the page hidden or shown again (visibilitychange): the page calls
	// changed (a @:hxmc.callback (hidden):Int, 1 hidden, 0 shown)
	static function visibility(changed:Ptr):Void;
	// the history entry of the page's own while deep (1; 0: gone, by
	// history.back()): its popstate, the back button's, calls back (a
	// @:hxmc.callback ():Int, 1 taken, 0 not: then the page's back)
	static function back_depth(deep:Int, back:Ptr):Void;
	// the page's history an app's own (helder.os.History; nil: no longer):
	// its back and forward call popped (a @:hxmc.callback (steps):Int, how
	// many entries back), back_depth's entry kept no more meanwhile; an
	// entry pushed (push 1) or the current one replaced (0), url its path;
	// n entries back (history.go), its popstate not the app's
	static function history_own(popped:Ptr):Void;
	static function history_push(url:CString, push:Int):Void;
	static function history_go(n:Int):Void;
	// the page's path and query (a string handle)
	static function location():Int;
	// requestAnimationFrame calls frame (a @:hxmc.callback ():Int) until it returns 0
	static function start(frame:Ptr):Void;
	// gamepad i's buttons (17 Float32: their values, 0 to 1) then axes (4
	// Float32) into p, the standard mapping's; 1 when it is there, else 0
	static function gamepad_state(i:Int, p:Ptr):Int;
	// helder.os.Store's: 1 when the page has localStorage (0: none, as under
	// node's WASI); the text under key (a string handle, 0: none); written,
	// removed (value null: 0)
	static function store_available():Int;
	static function store_get(key:CString):Int;
	static function store_set(key:CString, value:CString):Void;
}
