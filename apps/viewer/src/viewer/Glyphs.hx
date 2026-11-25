package viewer;

import helder.ui.Svg;

// The browser's icons (lucide's shapes, ISC, on their 24 by 24 grid, drawn
// 1.75 wide in the text's colour) and the folder's picture in its two
// tones, each parsed once.
class Glyphs {
	static final PATHS = [
		"back" => '<path d="m15 18-6-6 6-6"/>',
		"forward" => '<path d="m9 18 6-6-6-6"/>',
		"down" => '<path d="m6 9 6 6 6-6"/>',
		"up" => '<path d="m18 15-6-6-6 6"/>',
		"spin" => '<path d="M21 12a9 9 0 1 1-6.22-8.56"/>',
		"check" => '<path d="M20 6 9 17l-5-5"/>',
		"code" => '<path d="m16 18 6-6-6-6M8 6l-6 6 6 6"/>',
		"search" => '<circle cx="11" cy="11" r="7.5"/><path d="m21 21-4.3-4.3"/>',
		"grid" => '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/>',
		"list" => '<path d="M3 6h.01M3 12h.01M3 18h.01M8 6h13M8 12h13M8 18h13"/>',
		"info" => '<circle cx="12" cy="12" r="9"/><path d="M12 16v-4M12 8h.01"/>',
		"trash" => '<path d="M3 6h18M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2M10 11v6M14 11v6"/>',
		"more" => '<path d="M12 12h.01M19 12h.01M5 12h.01" stroke-width="3"/>',
		"folder" => '<path d="M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.7-.9l-.8-1.2A2 2 0 0 0 7.9 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2z"/>',
		"home" => '<path d="M15 21v-8a1 1 0 0 0-1-1h-4a1 1 0 0 0-1 1v8"/><path d="M3 10a2 2 0 0 1 .7-1.5l7-6a2 2 0 0 1 2.6 0l7 6A2 2 0 0 1 21 10v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>',
		"disk" => '<path d="M22 12H2M5.5 5.1 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.5-6.9A2 2 0 0 0 16.8 4H7.2a2 2 0 0 0-1.7 1.1zM6 16h.01M10 16h.01"/>',
		"card" => '<path d="M6 22a2 2 0 0 1-2-2V7l5-5h9a2 2 0 0 1 2 2v16a2 2 0 0 1-2 2zM10 6v3M14 6v3M18 6v3"/>',
		"server" => '<rect x="2" y="3" width="20" height="8" rx="2"/><rect x="2" y="13" width="20" height="8" rx="2"/><path d="M6 7h.01M6 17h.01"/>',
		"image" => '<rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.1-3.1a2 2 0 0 0-2.8 0L6 21"/>',
		"film" => '<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M7 3v18M17 3v18M3 7.5h4M3 12h18M3 16.5h4M17 7.5h4M17 16.5h4"/>',
		"music" => '<path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/>',
		"document" => '<path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7z"/><path d="M14 2v4a2 2 0 0 0 2 2h4M16 13H8M16 17H8M10 9H8"/>',
		"download" => '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M7 10l5 5 5-5M12 15V3"/>',
		"desktop" => '<rect x="2" y="3" width="20" height="14" rx="2"/><path d="M8 21h8M12 17v4"/>',
		"calendar" => '<rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/>',
		"lock" => '<rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>',
		"x" => '<path d="M18 6 6 18M6 6l12 12"/>',
		"sidebar" => '<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M9 3v18"/>',
		"share" => '<path d="M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8"/><path d="m16 6-4-4-4 4"/><path d="M12 2v13"/>',
		"copy" => '<rect x="8" y="8" width="14" height="14" rx="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/>',
		"plus" => '<path d="M5 12h14M12 5v14"/>',
		"clock" => '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
		"play" => '<path d="M7 4.5v15a1 1 0 0 0 1.5.9l12-7.5a1 1 0 0 0 0-1.8l-12-7.5A1 1 0 0 0 7 4.5z" fill="currentColor" stroke="none"/>'
	];

	static final parsed = new Map<String, Svg>();

	public static function get(name:String):Svg {
		var s = parsed.get(name);
		if (s != null) return s;
		var d = PATHS.get(name);
		if (d == null) throw 'viewer: no glyph "$name"';
		s = Svg.parse('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">$d</svg>');
		parsed.set(name, s);
		return s;
	}

	// a place's icon
	public static function place(kind:helder.os.Places.PlaceKind):String
		return switch kind {
			case Home: "home";
			case Desktop: "desktop";
			case Documents: "document";
			case Downloads: "download";
			case Pictures: "image";
			case Movies: "film";
			case Music: "music";
		}

	public static function volume(v:helder.os.Places.Volume):String
		return v.network ? "server" : v.removable ? "card" : "disk";

	// the folder's picture (back, front, a highlight), dark or light
	public static function folder(dark:Bool):Svg {
		var key = dark ? "folder-dark" : "folder-light";
		var s = parsed.get(key);
		if (s != null) return s;
		var back = dark ? "#3f72c4" : "#6aa0ea", front = dark ? "#5b93e6" : "#8cbaf5";
		s = Svg.parse('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 52">'
			+ '<path d="M3 8a4 4 0 0 1 4-4h15a4 4 0 0 1 3 1.4L28.6 9H57a4 4 0 0 1 4 4v31a4 4 0 0 1-4 4H7a4 4 0 0 1-4-4z" fill="$back"/>'
			+ '<path d="M3 17a4 4 0 0 1 4-4h50a4 4 0 0 1 4 4v27a4 4 0 0 1-4 4H7a4 4 0 0 1-4-4z" fill="$front"/>'
			+ '<path d="M7 13.5h50" stroke="rgba(255,255,255,.35)" stroke-width="1"/></svg>');
		parsed.set(key, s);
		return s;
	}

	// a file's glyph by what it is
	public static function of(g:Kinds.Glyph):String
		return switch g {
			case FolderGlyph: "folder";
			case ImageGlyph: "image";
			case VideoGlyph: "film";
			case AudioGlyph: "music";
			case PdfGlyph | DocumentGlyph: "document";
		}
}
