import helder.ui.*;
import helder.ui.UiWindow;
import helder.ui.view.UiFlow.*;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Signal;

// Native text editors in a browser (web-field.mjs: wasm32-wasi in headless
// Chromium): a field and a text area, native by the window's policy, among
// drawn nodes (a button, a select whose list covers the field when open,
// a field drawn by its host).
// After each frame whose state changed it prints the boxes of the nodes the
// test clicks and the state: "field name=... | notes=... | submitted=... |
// focus=<tag> | keyboard=<the soft keyboard's height>". The name field's
// keyboard an email's, its Enter key Go, not capitalised (its input's
// inputmode, enterkeyhint, autocapitalize, autocorrect).
class WebField implements Markup {
	static function main() {
		var w = new UiWindow({title: "Fields", width: 420, height: 320});
		var name = signal(""), notes = signal(""), submitted = signal(""), fruit = signal("Apple"), drawn = signal("");
		Render.render(<view flexGrow={1} padding={20} rowGap={12} alignItems="stretch" fontFamily="Inter" background="#ffffff">
			<view flexDirection="row" columnGap={12}>
				<Select tag="fruit" value={fruit} options={["Apple", "Pear", "Plum", "Fig"]} label="Fruit"/>
				<view host="drawn" flexGrow={1}><field tag="drawn" value={drawn} placeholder="Drawn" aria-label="Drawn" onInput={e -> drawn(e.text)} padding="6 10"
					borderWidth={1}/></view>
			</view>
			<field tag="name" value={name} placeholder="Your name" aria-label="Name" keyboard="email" enterKeyHint="go" autoCapitalize="none" onInput={e -> name(e.text)}
				onKeyDown={e -> if (e.key == Key.ENTER) submitted(name.peek())} padding="6 10" borderWidth={1}/>
			<textarea tag="notes" value={notes} rows={3} placeholder="Notes" aria-label="Notes" onInput={e -> notes(e.text)} padding="6 10" borderWidth={1}/>
			<button tag="reset" alignSelf="start" padding="6 12" borderWidth={1} onPress={_ -> name("Reset")}>Reset</button>
		</view>, w.root);
		var last = "";
		w.onFrame = () -> {
			var parts = [];
			for (tag in ["fruit", "drawn", "name", "notes", "reset"]) {
				var n = w.root.find(tag);
				if (n != null) parts.push('$tag=${n.absX},${n.absY},${n.width},${n.height}');
			}
			var f = w.ui.focus;
			var s = "boxes " + parts.join(" ") + " | name=" + name.peek() + " | notes=" + StringTools.replace(notes.peek(), "\n", "\\n") + " | submitted="
				+ submitted.peek() + " | drawn=" + drawn.peek() + " | focus=" + (f == null ? "" : f.tag) + " | keyboard=" + w.ui.keyboard;
			if (s != last) {
				last = s;
				Sys.println(s);
			}
		};
		UiWindow.run();
	}

	// (a select: its value on a button, its options in a popup under it while open)
	static function Select(props:{value:Signal<String>, options:Array<String>, tag:String, label:String}):View {
		var open = signal(false);
		return <button tag={props.tag} role="combobox" aria-label={props.label} aria-expanded={open} width={160} padding="6 10" borderWidth={1}
			onPress={() -> open(o -> !o)}>
			{props.value}
			<Popover open={open} placement="below" onDismiss={() -> open(false)}>
				<view tag={props.tag + "-list"} role="listbox" width={160} padding={4} borderWidth={1} background="#ffffff">
					<For each={props.options}>{option -> {
						var o = option();
						<button role="option" padding="4 8" onPress={() -> {
							props.value(o);
							open(false);
						}}>{o}</button>;
					}}</For>
				</view>
			</Popover>
		</button>;
	}
}
