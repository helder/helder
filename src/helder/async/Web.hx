package helder.async;

#if (hxmc.target == "wasm32-wasi")
import hxmc.unsafe.*;

// The page's side of the loop (WebAssembly): imports of the module
// "helder_async", which src/helder/async/imports.mjs provides (browser.mjs's
// option imports), by their own names (hxmc keys a wasm import by its
// module and name: hxmc_os's start is another function).
@:hxmc.c @:hxmc.lib("helder_async") extern class Web {
	// the loop's turns from now on: turn (a @:hxmc.callback ():Float, the
	// seconds until it wants the next, -1 for none) run by the page's event loop
	@:hxmc.safe static function start(turn:Void->Float):Void;
	// a turn wanted in that many seconds at the latest
	static function wake(seconds:Float):Void;
	// a fetch of url (relative to the page) started: its handle; its state (0
	// loading, 1 done, -1 failed; a turn comes when it changes), its body's
	// length, the body into p (the handle freed); fetch_free aborts it
	@:hxmc.safe static function fetch_start(url:String):Int;
	static function fetch_state(h:Int):Int;
	static function fetch_length(h:Int):Int;
	// the bytes it has received so far, and how many it will (0: not known)
	static function fetch_loaded(h:Int):Int;
	static function fetch_total(h:Int):Int;
	// (fast: a copy, no callback, so that buf may be a Bytes's, Fetch.bytes;
	// safe: no more than buf's length, imports.mjs)
	@:hxmc.fast @:hxmc.safe static function fetch_take(h:Int, buf:hxmc.Span<UInt8>):Void;
	static function fetch_free(h:Int):Void;
	// a request by the page's fetch (Client.request): url, its method, its
	// headers ("name: value" lines), its body; its handle (fetch_state,
	// fetch_length, fetch_take, fetch_free as a fetch's; failed: the network's
	// error, an HTTP error status is a reply), its status, its headers'
	// text's length and the text into buf
	@:hxmc.fast @:hxmc.safe static function http_start(url:String, method:String, headers:String, body:hxmc.Span<UInt8>):Int;
	static function http_status(h:Int):Int;
	static function http_headers_length(h:Int):Int;
	@:hxmc.fast @:hxmc.safe static function http_headers(h:Int, buf:hxmc.Span<UInt8>):Void;
	// the page's WebSocket (WebSocket.open): its handle; its state (0 opening,
	// 1 open, 2 closed, -1 failed to open; a turn comes when it changes or a
	// message comes), the next message's length in UTF-8 (-1: none yet), it
	// taken into buf; a text sent; closed with a code
	@:hxmc.safe static function ws_open(url:String):Int;
	static function ws_state(h:Int):Int;
	static function ws_next(h:Int):Int;
	@:hxmc.fast @:hxmc.safe static function ws_take(h:Int, buf:hxmc.Span<UInt8>):Void;
	@:hxmc.safe static function ws_send(h:Int, text:String):Void;
	static function ws_close(h:Int, code:Int):Void;
}
#end
