package helder.os.web;

import haxe.io.Bytes;
import hxmc.unsafe.*;

// The page's file input (accept image/*, multiple when more than one;
// capture for the camera's photo: a phone's camera, a desktop's file
// picker): the files read, kept by the page until taken into Bytes here.
@:hxmc.unsafe(gc)
class WebPhotos {
	#if (hxmc.target == "wasm32-wasi")
	static final pending = new Map<Int, Int->Void>();
	static var next = 1;

	@:coroutine public static function pick(max:Int):Array<Bytes>
		return taken(helder.os.Await.answer(done -> {
			var id = next++;
			pending.set(id, done);
			Picker.photos_pick(max, Callback.addr(picked), id);
		}));

	@:coroutine public static function take(front:Bool):Null<Bytes> {
		var photo = taken(helder.os.Await.answer(done -> {
			var id = next++;
			pending.set(id, done);
			Picker.camera_take(front ? 1 : 0, Callback.addr(picked), id);
		}));
		return photo.length == 0 ? null : photo[0];
	}

	static function taken(n:Int):Array<Bytes> {
		var out = [for (i in 0...n) {
			var b = Bytes.alloc(Picker.photos_length(i));
			Picker.photos_take(i, hxmc.Span.ofBytes(b));
			b;
		}];
		Picker.photos_clear();
		return out;
	}

	@:hxmc.callback static function picked(id:Int, n:Int):Int {
		var f = pending.get(id);
		pending.remove(id);
		if (f != null) f(n);
		return 0;
	}
	#end
}

#if (hxmc.target == "wasm32-wasi")
@:hxmc.c @:hxmc.lib("hxmc_os") private extern class Picker {
	// the input shown: done(id, how many were read; 0 when cancelled)
	static function photos_pick(max:Int, done:Ptr, id:Int):Void;
	// the same input with capture ("user" for the front camera, else "environment"), one file
	static function camera_take(front:Int, done:Ptr, id:Int):Void;
	static function photos_length(i:Int):Int;
	@:hxmc.fast @:hxmc.safe static function photos_take(i:Int, buf:hxmc.Span<UInt8>):Void;
	static function photos_clear():Void;
}
#end
