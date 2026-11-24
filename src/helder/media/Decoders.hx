package helder.media;

import hxmc.Platform;

// The system's decoder of a track, where it has one (null: none here):
// Apple's VideoToolbox and AudioToolbox (helder.media.apple), the
// browser's WebCodecs (helder.media.web), helder's own Vorbis everywhere.
// The other systems' come with the roadmap's next parts.
class Decoders {
	// whether this system has video decoders (an app's file types: the viewer's)
	public static function available():Bool {
		#if (!helder.os || helder.os == "macos" || helder.os == "ios")
		if (Platform.os() == 1) return true;
		#end
		return #if (hxmc.target == "wasm32-wasi") true #else false #end;
	}

	// whether video or audio of t decodes here (the browser's
	// isConfigSupported, awaited; elsewhere true, video and audio telling)
	@:coroutine public static function supported(t:MediaTrack):Bool {
		#if (hxmc.target == "wasm32-wasi")
		if (t.codec != Vorbis) {
			var name = helder.media.web.WebCodec.name(t);
			if (name == null) return false;
			var h = asked(t, name);
			var ok = helder.media.web.Glue.Wait.done(h);
			helder.media.web.Glue.free(h);
			return ok;
		}
		#end
		return true;
	}

	#if (hxmc.target == "wasm32-wasi")
	// (isConfigSupported asked: a handle; out of the coroutine, which holds no span)
	static function asked(t:MediaTrack, name:String):Int {
		var d = helder.media.web.WebCodec.description(t) ?? haxe.io.Bytes.alloc(0), audio = t.kind == Audio;
		var kind = audio ? 1 : 0, a = audio ? t.sampleRate : t.width, b = audio ? t.channels : t.height;
		return helder.media.web.Glue.supported(kind, name, a, b, hxmc.Span.ofBytes(d));
	}
	#end

	public static function video(t:MediaTrack):Null<VideoDecoder> {
		#if (!helder.os || helder.os == "macos" || helder.os == "ios")
		if (Platform.os() == 1 && helder.media.apple.VtDecoder.supports(t.codec)) return new helder.media.apple.VtDecoder(t);
		#end
		#if (hxmc.target == "wasm32-wasi")
		if (helder.media.web.WebCodec.name(t) != null) return new helder.media.web.WebVideoDecoder(t);
		#end
		return null;
	}

	public static function audio(t:MediaTrack):Null<AudioDecoder> {
		if (t.codec == Vorbis) return new VorbisDecoder(t);
		#if (!helder.os || helder.os == "macos" || helder.os == "ios")
		if (Platform.os() == 1 && helder.media.apple.AtDecoder.supports(t.codec)) return new helder.media.apple.AtDecoder(t);
		#end
		#if (hxmc.target == "wasm32-wasi")
		if (helder.media.web.WebCodec.name(t) != null) return new helder.media.web.WebAudioDecoder(t);
		#end
		return null;
	}
}
