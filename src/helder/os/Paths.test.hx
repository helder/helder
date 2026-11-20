package helder.os;

import helder.test.Test;

// Paths on Linux: the XDG base directories and user-dirs.dirs, the
// specifications' defaults; Device's os-release; the directories here are
// absolute and made
function tests() {
	final env = (vars:Map<String, String>) -> (k:String) -> vars.get(k);
	test("Linux: XDG's directories, else the defaults", () -> {
		var home = env(["HOME" => "/home/ann"]);
		equals(PathsDesktop.linux(14, home, null, "golf"), "/home/ann/.local/share/golf");
		equals(PathsDesktop.linux(13, home, null, "golf"), "/home/ann/.cache/golf");
		equals(PathsDesktop.linux(0, home, null, "golf"), "/tmp");
		equals(PathsDesktop.linux(9, home, null, "golf"), "/home/ann/Documents");
		var set = env(["HOME" => "/home/ann", "XDG_DATA_HOME" => "/data", "XDG_CACHE_HOME" => "relative", "TMPDIR" => "/run/tmp"]);
		equals(PathsDesktop.linux(14, set, null, "golf"), "/data/golf");
		equals(PathsDesktop.linux(13, set, null, "golf"), "/home/ann/.cache/golf");
		equals(PathsDesktop.linux(0, set, null, "golf"), "/run/tmp");
	});
	test("Linux: user-dirs.dirs' documents", () -> {
		var dirs = '# written by xdg-user-dirs-update\nXDG_DESKTOP_DIR="$$HOME/Desktop"\nXDG_DOCUMENTS_DIR="$$HOME/Dokumente"\n';
		equals(PathsDesktop.userDir(dirs, "XDG_DOCUMENTS_DIR", "/home/ann"), "/home/ann/Dokumente");
		equals(PathsDesktop.userDir('XDG_DOCUMENTS_DIR="/srv/docs"', "XDG_DOCUMENTS_DIR", "/home/ann"), "/srv/docs");
		equals(PathsDesktop.userDir('XDG_DOCUMENTS_DIR="docs"', "XDG_DOCUMENTS_DIR", "/home/ann"), null);
		equals(PathsDesktop.linux(9, env(["HOME" => "/home/ann"]), dirs, "golf"), "/home/ann/Dokumente");
	});
	test("os-release: quoted, escaped, comments", () -> {
		var r = DeviceDesktop.release('# a comment\nNAME="Fedora Linux"\nVERSION_ID=41\nPRETTY_NAME=\'Fedora 41\'\nQUOTE="say \\"hi\\""\n');
		equals([r.get("NAME"), r.get("VERSION_ID"), r.get("PRETTY_NAME"), r.get("QUOTE")], ["Fedora Linux", "41", "Fedora 41", 'say "hi"']);
		equals(r.exists("# a comment"), false);
	});
	test("this system's directories: absolute and made, where it has them", () -> {
		for (d in [Paths.data(), Paths.cache(), Paths.temp()])
			if (d != null) {
				assert(haxe.io.Path.isAbsolute(d), d);
				assert(sys.FileSystem.isDirectory(d), d);
			}
		assert(DeviceInfo.get() != null);
	});
}
