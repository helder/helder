package viewer;

import helder.scenario.Scenario.scenario;
import helder.scenario.Steps.tap;
import viewer.Shell.act;
import viewer.Shell.with;

// The viewer at its moments (the studio's canvas: helder.scenario), in the
// Sandbox's files: the program's own Window, booted through its actions.
// The search field focused is reached by a tap (steps); a marquee held
// mid-drag and the PDF between two pages stay Viewer.story.hx's
final gridDark = scenario({name: "App/Grid, dark", size: [1100, 700], dark: true});

final gridLight = scenario({name: "App/Grid, light", size: [1100, 700], dark: false});

final listDark = scenario({name: "App/List, dark", size: [1100, 700], dark: true, boot: () -> act(ShowList)});

final listLight = scenario({name: "App/List, light", size: [1100, 700], dark: false, boot: () -> act(ShowList)});

final several = scenario({
	name: "App/Several selected",
	size: [1100, 700],
	dark: true,
	boot: () -> {
		act(Go(Sandbox.HOME));
		with(x -> {
			x.browser.select("alpha.png");
			x.browser.selection.extend(x.browser.indexOf("lossy.webp"));
			x.browser.selectionChanged();
		});
	}
});

final photo = scenario({name: "App/Photo full size", size: [1100, 700], dark: true, boot: () -> act(OpenRecent(Sandbox.HOME + "/photo 2.jpg"))});

final pdf = scenario({name: "App/PDF", size: [1100, 700], dark: true, boot: () -> act(OpenRecent("tests/fixtures/pdf/pages.pdf"))});

final markdownDark = scenario({name: "App/Markdown, dark", size: [1100, 700], dark: true, boot: () -> act(OpenRecent(Samples.ROOT + "/Welcome.md"))});

final markdownLight = scenario({name: "App/Markdown, light", size: [1100, 700], dark: false, boot: () -> act(OpenRecent(Samples.ROOT + "/Welcome.md"))});

final inspector = scenario({
	name: "App/Inspector, photo",
	size: [1100, 700],
	dark: true,
	boot: () -> {
		act(Go(Sandbox.HOME));
		with(x -> x.browser.select("photo 2.jpg"));
	}
});

final noResults = scenario({
	name: "App/No results",
	size: [1100, 700],
	dark: true,
	boot: () -> {
		act(Go(Sandbox.HOME));
		act(Search);
		with(x -> x.browser.search("puffin"));
	}
});

final searchDark = scenario({name: "App/Search focused, dark", size: [1100, 700], dark: true, steps: [tap("Search")]});

final searchLight = scenario({name: "App/Search focused, light", size: [1100, 700], dark: false, steps: [tap("Search")]});

final empty = scenario({name: "App/Empty folder", size: [1100, 700], dark: true, boot: () -> act(Go(Sandbox.EMPTY))});

final locked = scenario({name: "App/Folder that cannot be read", size: [1100, 700], dark: true, boot: () -> act(Go(Sandbox.LOCKED))});

final phone = scenario({name: "App/Phone, folder", size: [390, 844], boot: () -> act(Go(Samples.ROOT))});

final phonePhoto = scenario({name: "App/Phone, photo", size: [390, 844], boot: () -> act(OpenRecent(Samples.ROOT + "/Starlings.jpg"))});

final tablet = scenario({
	name: "App/Tablet, folder",
	size: [820, 1180],
	boot: () -> {
		act(Go(Samples.ROOT));
		with(x -> x.sidebarOpen(true));
	}
});
