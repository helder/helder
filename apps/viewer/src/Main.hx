// helder's image viewer (apps/viewer/README.md): `viewer photo.jpg`, `viewer folder/`; viewer.helder.run
class Main {
	static function main() {
		// (Vorbis in WebM and Matroska heard: helder's own decoder linked)
		helder.media.VorbisDecoder.link();
		#if (hxmc.target == "wasm32-wasi")
		viewer.WebShell.main();
		#else
		viewer.Shell.main(Sys.args());
		#end
	}
}
