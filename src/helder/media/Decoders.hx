package helder.media;

import hxmc.Platform;

// The system's decoder of a track, where it has one (null: none here):
// Apple's VideoToolbox and AudioToolbox (helder.media.apple), helder's own
// Vorbis everywhere. The other systems' come with the roadmap's next parts.
class Decoders {
	// whether this system has video decoders (an app's file types: the viewer's)
	public static function available():Bool {
		#if (!helder.os || helder.os == "macos" || helder.os == "ios")
		if (Platform.os() == 1) return true;
		#end
		return false;
	}

	public static function video(t:MediaTrack):Null<VideoDecoder> {
		#if (!helder.os || helder.os == "macos" || helder.os == "ios")
		if (Platform.os() == 1 && helder.media.apple.VtDecoder.supports(t.codec)) return new helder.media.apple.VtDecoder(t);
		#end
		return null;
	}

	public static function audio(t:MediaTrack):Null<AudioDecoder> {
		if (t.codec == Vorbis) return new VorbisDecoder(t);
		#if (!helder.os || helder.os == "macos" || helder.os == "ios")
		if (Platform.os() == 1 && helder.media.apple.AtDecoder.supports(t.codec)) return new helder.media.apple.AtDecoder(t);
		#end
		return null;
	}
}
