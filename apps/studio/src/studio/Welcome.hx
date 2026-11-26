package studio;

import helder.ui.*;
import helder.view.*;
import helder.view.Flow.*;
import studio.Theme.c;
#if (hxmc.target == "wasm32-wasi")
import studio.web.StudioWeb;
import studio.web.StudioWeb.WebText;
#end

// The studio in the browser without a project: a new project (a design
// file), a folder to open (the File System Access API: copied into the
// origin's private file system, OPFS, where projects live), the examples
// bundled with the page, and the projects already in OPFS. Choosing one opens it (the page loads it and
// starts the studio again with it).
@:renderer(helder.ui.view.NodeRenderer)
class Welcome implements Markup {
	public static function view(studio:Studio):View {
		var examples:Array<Dynamic> = [], projects:Array<Dynamic> = [];
		#if (hxmc.target == "wasm32-wasi")
		examples = haxe.Json.parse(WebText.take(StudioWeb.examples()));
		projects = haxe.Json.parse(WebText.take(StudioWeb.projects()));
		#end
		return <scroll tag="welcome" flexGrow={1} background={c("bg")} color={c("fg")} fontFamily={Theme.UI} fontSize={Theme.BODY}
			ref={(n:Node) -> n.theme = Theme.sheet} alignItems="center" padding="56 20">
			<view width="100%" maxWidth={420} rowGap={6}>
				<text fontWeight={Theme.MEDIUM} padding="0 8 14">helder studio</text>
				<button tag="new-project" slot="nav-item" aria-label="New project" onPress={() -> newProject()}>
					<text>New project</text>
				</button>
				<button tag="open-folder" slot="nav-item" aria-label="Open a folder…" onPress={() -> openFolder()}>
					<text>Open a folder…</text>
				</button>
				{list("Examples", "example-", examples, name -> openExample(name))}
				{list("Projects", "project-", projects, name -> openProject(name))}
			</view>
		</scroll>;
	}

	static function list(title:String, prefix:String, items:Array<Dynamic>, open:String->Void):View
		return <Show when={items.length > 0}>
			<text padding="18 8 4" color={c("fg3")} fontSize={Theme.SMALL}>{title}</text>
			<For each={items}>{(r:helder.view.graph.Read<Dynamic>) -> {
				var it:Dynamic = r();
				<button tag={prefix + it.name} slot="nav-item" columnGap={12} aria-label={it.label ?? it.name} onPress={() -> open(it.name)}>
					<text flexGrow={1}>{it.label ?? it.name}</text>
					<text fontFamily={Theme.CODE} fontSize={Theme.SMALL} color={c("fg3")}>{it.screens == null ? "" : it.screens + " screens"}</text>
				</button>;
			}}</For>
		</Show>;

	static function newProject() {
		#if (hxmc.target == "wasm32-wasi")
		StudioWeb.new_project();
		#end
	}

	static function openFolder() {
		#if (hxmc.target == "wasm32-wasi")
		StudioWeb.open_folder();
		#end
	}

	static function openExample(name:String) {
		#if (hxmc.target == "wasm32-wasi")
		hxmc.unsafe.Arena.scoped(a -> StudioWeb.open_example(a.cstring(name)));
		#end
	}

	static function openProject(name:String) {
		#if (hxmc.target == "wasm32-wasi")
		hxmc.unsafe.Arena.scoped(a -> StudioWeb.open_project(a.cstring(name)));
		#end
	}
}
