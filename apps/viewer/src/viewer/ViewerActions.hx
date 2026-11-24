package viewer;

import helder.ui.actions.Actions;
import helder.ui.actions.Keymap;
import helder.ui.menu.Menu;

// The viewer's actions (helder.ui.actions: viewer::Next... in a keymap),
// its default keymap, its menus and its context menus. The keys and the
// menus' shortcuts are one: the keymap's (a user's file over it:
// helder-viewer-keymap.json in the Store's folder: ~/.local/share/helder-viewer,
// %APPDATA%\helder-viewer, ~/Library/Application Support/helder-viewer).
enum ViewerAction {
	Open;
	OpenRecent(path:String);
	// the browser
	Back;
	Forward;
	Enclosing;
	Go(path:String);
	OpenSelected;
	ShowGrid;
	ShowList;
	SortBy(key:String);
	Ascending;
	FoldersFirst;
	ShowHidden;
	Search;
	CloseSearch;
	ToggleInspector;
	EditPath;
	Trash;
	UndoTrash;
	// the full-size viewer
	Close;
	Next;
	Previous;
	First;
	Last;
	ZoomIn;
	ZoomOut;
	Fit;
	ActualSize;
	ToggleFullscreen;
	LeaveFullscreen;
	ToggleStatus;
	NextPage;
	PreviousPage;
	FirstPage;
	LastPage;
	GoToPage;
	CloseGoTo;
	CloseAbout;
	CopyPath;
	ShowInFolder;
	OpenWithDefault;
	PlayPause;
	StepForward;
	StepBack;
	ToggleMute;
}

class ViewerActions {
	static var declared = false;

	// the viewer's default bindings, in keymap (once): the root's context is
	// "Viewer", with browser while the browser shows and full while a file
	// is open full size; fullscreen while it is, pdf while a document of
	// several pages is shown, media while a video or an audio file is, goto
	// while its go to page card is open, search in the search field
	public static function defaults(keymap:Keymap) {
		if (declared) return;
		declared = true;
		actions("viewer", ViewerAction);
		keymap.bind("secondary-o", Open, "Viewer");
		// (the browser: its list's arrows, Home, End, Page Up and Down, Enter and type-ahead are the list's own)
		var browser = "Viewer && browser && !about", typing = "Viewer && browser && !search && !about";
		keymap.bind("secondary-[", Back, browser);
		keymap.bind("secondary-]", Forward, browser);
		keymap.bind("alt-left", Back, typing);
		keymap.bind("alt-right", Forward, typing);
		keymap.bind("secondary-up", Enclosing, browser);
		keymap.bind("secondary-down", OpenSelected, browser);
		keymap.bind("enter", OpenSelected, typing);
		keymap.bind("secondary-1", ShowGrid, browser);
		keymap.bind("secondary-2", ShowList, browser);
		keymap.bind("secondary-f", Search, browser);
		keymap.bind("escape", CloseSearch, browser);
		keymap.bind("secondary-i", ToggleInspector, browser);
		keymap.bind("secondary-l", EditPath, browser);
		keymap.bind("secondary-shift-.", ShowHidden, browser);
		keymap.bind("delete", Trash, typing);
		keymap.bind("secondary-backspace", Trash, typing);
		keymap.bind("secondary-z", UndoTrash, typing);
		keymap.bind("secondary-shift-c", CopyPath, browser);
		// (a file full size: today's keys)
		var here = "Viewer && full && !goto && !about";
		keymap.bind("escape", Close, "Viewer && full && !fullscreen && !goto && !about");
		keymap.bind("secondary-up", Close, here);
		keymap.bind("delete", Trash, here);
		keymap.bind("secondary-backspace", Trash, here);
		for (k in ["space", "pagedown", "down", "right"])
			keymap.bind(k, Next, here);
		for (k in ["backspace", "pageup", "up", "left"])
			keymap.bind(k, Previous, here);
		keymap.bind("home", First, here);
		keymap.bind("end", Last, here);
		// (+ and -: whichever key the layout has them on, Mod with them too; the last is what menus show)
		for (k in ["secondary-=", "secondary-shift-=", "secondary-+", "=", "shift-=", "shift-+", "+"])
			keymap.bind(k, ZoomIn, here);
		for (k in ["secondary--", "shift--", "-"])
			keymap.bind(k, ZoomOut, here);
		keymap.bind("secondary-0", Fit, here);
		keymap.bind("0", Fit, here);
		keymap.bind("1", ActualSize, here);
		keymap.bind("enter", ToggleFullscreen, here);
		keymap.bind("ctrl-cmd-f", ToggleFullscreen, here);
		keymap.bind("f11", ToggleFullscreen, here);
		keymap.bind("escape", LeaveFullscreen, "Viewer && full && fullscreen && !goto && !about");
		keymap.bind("i", ToggleStatus, here);
		// (a PDF's pages: Page Down and Up, Space and Backspace page through it, the arrows still the folder's files)
		var pdf = "Viewer && full && pdf && !goto && !about";
		for (k in ["pagedown", "space", "]"])
			keymap.bind(k, NextPage, pdf);
		for (k in ["pageup", "backspace", "shift-space", "["])
			keymap.bind(k, PreviousPage, pdf);
		keymap.bind("secondary-home", FirstPage, pdf);
		keymap.bind("secondary-end", LastPage, pdf);
		keymap.bind("secondary-g", GoToPage, pdf);
		keymap.bind("g", GoToPage, pdf);
		// (a video or audio file: Space plays and pauses, the arrows across and , and . step a frame, M mutes; Up and Down still the folder's)
		var media = "Viewer && full && media && !goto && !about";
		for (k in ["space", "k"])
			keymap.bind(k, PlayPause, media);
		for (k in [".", "right"])
			keymap.bind(k, StepForward, media);
		for (k in [",", "left"])
			keymap.bind(k, StepBack, media);
		keymap.bind("m", ToggleMute, media);
		keymap.bind("escape", CloseGoTo, "Viewer && goto");
		keymap.bind("escape", CloseAbout, "Viewer && about");
		keymap.bind("enter", CloseAbout, "Viewer && about");
		keymap.bind("secondary-shift-c", CopyPath, here);
		// (macOS: Command-Q is the application menu's)
		if (!Keymap.mac) keymap.bind("secondary-q", StandardAction.Quit);
	}

	// the menu bar: File, Edit, View, Go, Help (About: on macOS the application menu's)
	public static function menus(recent:Array<String>, places:Array<{name:String, path:String}>):Array<Menu> {
		var open:Array<MenuItem> = [Item("Open…", Open)];
		if (recent.length > 0) open.push(Submenu("Open Recent", [for (r in recent) Item(haxe.io.Path.withoutDirectory(r), OpenRecent(r))]));
		var go:Array<MenuItem> = [Item("Back", Back), Item("Forward", Forward), Item("Enclosing Folder", Enclosing)];
		if (places.length > 0) go = go.concat([Separator]).concat([for (p in places) Item(p.name, Go(p.path))]);
		return [
			{label: "File", items: open.concat([Item("Open Selected", OpenSelected), Separator, Item(trashLabel(), Trash), Separator, Role(Quit)])},
			{label: "Edit", items: [Item("Undo " + trashLabel(), UndoTrash), Separator, Item("Copy Path", CopyPath), Item("Find", Search)]},
			{
				label: "View",
				items: [
					Item("as Grid", ShowGrid), Item("as List", ShowList), Separator, Submenu("Sort By", sorts()), Item("Ascending", Ascending),
					Item("Folders First", FoldersFirst), Item("Show Hidden Files", ShowHidden), Separator, Item("Inspector", ToggleInspector),
					Item("Edit Path", EditPath), Separator, Item("Fit", Fit), Item("Actual Size", ActualSize), Item("Zoom In", ZoomIn),
					Item("Zoom Out", ZoomOut), Separator, Item("Previous", Previous), Item("Next", Next), Separator, Item("Previous Page", PreviousPage),
					Item("Next Page", NextPage), Item("Go to Page…", GoToPage), Separator, Item("Play or Pause", PlayPause), Item("Next Frame", StepForward),
					Item("Previous Frame", StepBack), Item("Mute", ToggleMute), Separator, Item("Full Screen", ToggleFullscreen), Item("Status Line", ToggleStatus)
				]
			},
			{label: "Go", items: go},
			{label: "Help", items: [Role(About)]}
		];
	}

	public static function sorts():Array<MenuItem>
		return [Item("Name", SortBy("name")), Item("Kind", SortBy("kind")), Item("Date Modified", SortBy("modified")), Item("Size", SortBy("size"))];

	// the toolbar's View button: the layout, the order, hidden files
	public static function view():Array<MenuItem>
		return [Item("Grid", ShowGrid), Item("List", ShowList), Separator].concat(sorts()).concat([
			Separator, Item("Ascending", Ascending), Item("Folders First", FoldersFirst), Item("Show Hidden Files", ShowHidden)
		]);

	// a file's context menu in the browser, and the inspector's More
	public static final entry:Array<MenuItem> = [
		Item("Open", OpenSelected), Item(reveal(), ShowInFolder), Item("Open with Default App", OpenWithDefault), Separator, Item("Copy Path", CopyPath),
		Separator, Item(trashLabel(), Trash)
	];

	public static final more:Array<MenuItem> = [Item("Copy Path", CopyPath), Item("Open with Default App", OpenWithDefault)];

	// the image's context menu
	public static final context:Array<MenuItem> = [
		Item("Copy Path", CopyPath), Item(reveal(), ShowInFolder), Item("Open with Default App", OpenWithDefault), Separator, Item("Fit", Fit),
		Item("Actual Size", ActualSize), Separator, Item(trashLabel(), Trash)
	];

	public static function reveal():String
		return Sys.systemName() == "Mac" ? "Show in Finder" : Sys.systemName() == "Windows" ? "Show in Explorer" : "Show in Folder";

	public static function trashLabel():String
		return Sys.systemName() == "Windows" ? "Delete" : "Move to Trash";
}
