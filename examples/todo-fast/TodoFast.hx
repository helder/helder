// title: Todo on fast nodes
// summary: The todo list's markup on fast nodes: typed styles with state variants instead of a style sheet, no cascade
// tags: ui, view, text input
// demo: canvas 480x560

import helder.ui.Key;
import helder.ui.UiWindow;
import helder.ui.UiWindow.Surface;
import helder.ui.fast.FastTags.*;
import helder.ui.fast.FastTags;
import helder.ui.fast.Style;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Signal;
import helder.view.graph.Read;

// examples/todo's list on fast nodes (helder.ui.fast): the same markup,
// its sheet's slots, variants and states typed Styles with hover, checked,
// focus and placeholder variants, inside a <Fast>. Its nodes are the CSS
// engine's boxes; it links no helder.dom and no cascade.
class TodoFast implements Markup {
	static function main() {
		UiWindow.run(<Surface title="Todo" width={480} height={560}><Fast>{new TodoFast().view()}</Fast></Surface>);
	}

	// (Todo.sheet's rules as styles)
	public static final button = Style.of({
		flexDirection: Row,
		alignItems: Center,
		justifyContent: Center,
		padding: [6, 12],
		borderRadius: 6,
		background: 0xFF18181B,
		color: 0xFFFAFAFA,
		cursor: Pointer,
		hover: {background: 0xFF3F3F46}
	});
	public static final outline = button.with({
		background: 0xFFFFFFFF,
		color: 0xFF18181B,
		borderWidth: 1,
		borderColor: 0xFFE4E4E7,
		hover: {background: 0xFFF4F4F5}
	});
	public static final ghost = button.with({background: 0, color: 0xFF71717A, hover: {background: 0xFFF4F4F5, color: 0xFF18181B}});
	public static final small = Style.of({padding: [4, 8]});
	public static final input = Style.of({
		padding: [8, 12],
		borderRadius: 6,
		borderWidth: 1,
		borderColor: 0xFFE4E4E7,
		background: 0xFFFFFFFF,
		focus: {borderColor: 0xFFA1A1AA},
		placeholder: {color: 0xFFA1A1AA}
	});
	public static final checkbox = Style.of({
		width: 16,
		height: 16,
		borderRadius: 4,
		borderWidth: 1,
		borderColor: 0xFFA1A1AA,
		alignItems: Center,
		justifyContent: Center,
		cursor: Pointer,
		checked: {background: 0xFF18181B, borderColor: 0xFF18181B, color: 0xFFFAFAFA}
	});

	public final todos = signal(new Array<Task>());
	public final draft = signal("");
	public final filter = signal("all");

	public function new() {}

	public function add() {
		var t = StringTools.trim(draft());
		if (t == "") return;
		todos(todos().concat([new Task(t)]));
		draft("");
	}

	public function remove(i:Task)
		todos(todos().filter(x -> x != i));

	function visible():Array<Task>
		return todos().filter(i -> switch filter() {
			case "active": !i.done();
			case "done": i.done();
			case _: true;
		});

	static function look(variant:Null<String>, size:Null<String>):Style {
		var s = variant == "ghost" ? ghost : variant == "outline" ? outline : button;
		return size == "sm" ? s.with(small) : s;
	}

	static function Button(props:{label:String, onPress:Void->Void, ?tag:String, ?variant:Read<Null<String>>, ?size:String}):FastView
		return <button tag={props.tag ?? "button"} style={look(props.variant != null ? props.variant() : null, props.size)}
			onPress={props.onPress}>{props.label}</button>;

	// (the label pressed toggles it too; the box named by it, the text hidden from assistive technology)
	static function Checkbox(props:{checked:Signal<Bool>, label:String}):FastView {
		var toggle = () -> props.checked(c -> !c);
		return <view flexDirection="row" alignItems="center" columnGap={8}>
			<button tag="checkbox" style={checkbox} role="checkbox" aria-label={props.label} aria-checked={props.checked}
				data-state={props.checked() ? "checked" : "unchecked"}
				onPress={toggle}>
				<Show when={props.checked}><icon name="check" width={12} height={12}/></Show>
			</button>
			<text aria-hidden cursor="pointer" color={props.checked() ? "#a1a1aa" : "#18181b"}
				textDecoration={props.checked() ? "line-through" : "none"} onPress={toggle}>{props.label}</text>
		</view>;
	}

	public function view():FastView {
		var left = memo(() -> todos().filter(i -> !i.done()).length);
		// (minHeight 0: the window's height its own, the list scrolling in it; CSS's automatic minimum keeps a
		// flex item's content's height, where helder.ui's top box shrinks to the window)
		return <view flexGrow={1} minHeight={0} padding={24} rowGap={14} background="#fafafa" fontSize={14} color="#18181b">
			<text fontSize={28} fontWeight={700} color="#3b82f6">todos</text>
			<view flexDirection="row" columnGap={8}>
				<field tag="draft" style={input} flexGrow={1} value={draft()} placeholder="What needs to be done?" aria-label="What needs to be done?"
					onInput={e -> draft(e.text)} onKeyDown={e -> if (e.key == Key.ENTER) add()}/>
				<Button tag="add" label="Add" onPress={add}/>
			</view>
			<scroll tag="list" flexGrow={1} minHeight={0} rowGap={6} background="#ffffff" borderRadius={8} borderWidth={1} borderColor="#e4e4e7" padding={8}>
				<For each={visible()}>{(item:Read<Task>) -> {
					var i = item();
					<view flexDirection="row" alignItems="center" columnGap={8} padding="4 6" borderRadius={6}>
						<view flexGrow={1}><Checkbox checked={i.done} label={i.title}/></view>
						<Button label="Remove" variant="ghost" size="sm" onPress={() -> remove(i)}/>
					</view>;
				}}</For>
				<Show when={visible().length == 0}><text color="#a1a1aa" padding={6}>Nothing here.</text></Show>
			</scroll>
			<view flexDirection="row" alignItems="center" justifyContent="space-between">
				<text tag="left">{left() == 1 ? "1 item left" : left() + " items left"}</text>
				<view flexDirection="row" columnGap={6}>{() -> [
					for (f in ["all", "active", "done"])
						<Button tag={"filter-" + f} label={f} variant={filter() == f ? null : "outline"} size="sm" onPress={() -> filter(f)}/>
				]}</view>
			</view>
		</view>;
	}
}

class Task {
	public final title:String;
	public final done = signal(false);

	public function new(title:String)
		this.title = title;
}
