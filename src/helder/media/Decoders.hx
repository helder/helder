package helder.media;

import hxmc.Platform;

// The system's decoder of a track, where it has one (null: none here):
// Apple's VideoToolbox and AudioToolbox (helder.media.apple), the
// browser's WebCodecs (helder.media.web), Android's MediaCodec
// (helder.media.android), Windows' Media Foundation
// (helder.media.windows), Linux's libavcodec, VAAPI's through it
// (helder.media.linux: a glibc build's; a static one loads no library);
// Vorbis helder's own where the app links it (VorbisDecoder.link(): 38 KB;
// else a Vorbis track is not heard, but a browser's or Linux's).
class Decoders {
	// whether this system has video decoders (an app's file types: the viewer's)
	public static function available():Bool {
		#if (!helder.os || helder.os == "macos" || helder.os == "ios")
		if (Platform.os() == 1) return true;
		#end
		#if ((!helder.os || helder.os == "android") && hxmc.target != "wasm32-wasi")
		if (Platform.target() >= 9) return helder.media.android.MediaNdk.loaded();
		#end
		#if ((!helder.os || helder.os == "windows") && hxmc.target != "wasm32-wasi")
		if (Platform.os() == 2) return helder.media.windows.Mf.loaded();
		#end
		#if ((!helder.os || helder.os == "linux") && hxmc.target != "wasm32-wasi")
		if (Platform.target() == 7 || Platform.target() == 8) return helder.media.linux.Av.loaded();
		#end
		return #if (hxmc.target == "wasm32-wasi") true #else false #end;
	}

	// what this system lacks to decode, said (Linux: libavcodec; null: nothing)
	public static function missing():Null<String> {
		#if ((!helder.os || helder.os == "linux") && hxmc.target != "wasm32-wasi")
		if (Platform.target() == 7 || Platform.target() == 8) return helder.media.linux.Av.missing();
		if (Platform.target() < 2) return "helder.media: a static Linux build loads no decoder (-D hxmc.libc=glibc loads the system's libavcodec)";
		#end
		return null;
	}

	// whether video or audio of t decodes here (the browser's
	// isConfigSupported, awaited; elsewhere true, video and audio telling)
	@:coroutine public static function supported(t:MediaTrack):Bool {
		#if (hxmc.target == "wasm32-wasi")
		if (t.codec != Vorbis || vorbis == null) {
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

	// helder's own Vorbis decoder, once linked (VorbisDecoder.link)
	@:allow(helder.media.VorbisDecoder) static var vorbis:Null<MediaTrack->AudioDecoder>;

	// whether helder's own Vorbis decoder is linked (VorbisDecoder.link):
	// Vorbis plays here whatever the system has
	public static function hasVorbis():Bool
		return vorbis != null;

	public static function video(t:MediaTrack):Null<VideoDecoder> {
		#if (!helder.os || helder.os == "macos" || helder.os == "ios")
		if (Platform.os() == 1 && helder.media.apple.VtDecoder.supports(t.codec)) return new helder.media.apple.VtDecoder(t);
		#end
		#if ((!helder.os || helder.os == "android") && hxmc.target != "wasm32-wasi")
		if (Platform.target() >= 9 && helder.media.android.McVideo.supports(t.codec)) return new helder.media.android.McVideo(t);
		#end
		#if ((!helder.os || helder.os == "windows") && hxmc.target != "wasm32-wasi")
		if (Platform.os() == 2 && helder.media.windows.MfVideo.supports(t.codec)) return new helder.media.windows.MfVideo(t);
		#end
		#if ((!helder.os || helder.os == "linux") && hxmc.target != "wasm32-wasi")
		if ((Platform.target() == 7 || Platform.target() == 8) && helder.media.linux.AvVideo.supports(t.codec)) return new helder.media.linux.AvVideo(t);
		#end
		#if (hxmc.target == "wasm32-wasi")
		if (helder.media.web.WebCodec.name(t) != null) return new helder.media.web.WebVideoDecoder(t);
		#end
		return null;
	}

	public static function audio(t:MediaTrack):Null<AudioDecoder> {
		if (t.codec == Vorbis && vorbis != null) return vorbis(t);
		#if (!helder.os || helder.os == "macos" || helder.os == "ios")
		if (Platform.os() == 1 && helder.media.apple.AtDecoder.supports(t.codec)) return new helder.media.apple.AtDecoder(t);
		#end
		#if ((!helder.os || helder.os == "android") && hxmc.target != "wasm32-wasi")
		if (Platform.target() >= 9 && helder.media.android.McAudio.supports(t.codec)) return new helder.media.android.McAudio(t);
		#end
		#if ((!helder.os || helder.os == "windows") && hxmc.target != "wasm32-wasi")
		if (Platform.os() == 2 && helder.media.windows.MfAudio.supports(t.codec)) return new helder.media.windows.MfAudio(t);
		#end
		#if ((!helder.os || helder.os == "linux") && hxmc.target != "wasm32-wasi")
		if ((Platform.target() == 7 || Platform.target() == 8) && helder.media.linux.AvAudio.supports(t.codec)) return new helder.media.linux.AvAudio(t);
		#end
		#if (hxmc.target == "wasm32-wasi")
		if (helder.media.web.WebCodec.name(t) != null) return new helder.media.web.WebAudioDecoder(t);
		#end
		return null;
	}
}
