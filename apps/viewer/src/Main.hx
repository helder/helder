// helder's image viewer (apps/viewer/README.md): `viewer photo.jpg`, `viewer folder/`
class Main {
	static function main() {
		// (Vorbis in WebM and Matroska heard: helder's own decoder linked)
		helder.media.VorbisDecoder.link();
		viewer.Shell.main(Sys.args());
	}
}
