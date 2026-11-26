import helder.ui.*;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Signal;

// Plain controls for the tests (import Plain.*): views with a role, a
// name and their state for assistive technology, focusable, pressed by a
// click, Enter or Space (a button's onPress), no look but a line in the
// text's colour where a box needs one. A button, a checkbox (its label
// beside it pressing it too), a slider from 0 to 1 (Left and Down a step
// less, Right and Up more: what assistive technology's Increment and
// Decrement press).
class Plain implements Markup {
	public static function Button(props:{label:String, ?onPress:Void->Void, ?tag:String}):View
		return <button tag={props.tag ?? "button"} padding="2 8" borderWidth={1} borderColor="currentColor"
			onPress={() -> if (props.onPress != null) props.onPress()}>{props.label}</button>;

	public static function Checkbox(props:{checked:Signal<Bool>, ?label:String, ?tag:String}):View {
		var toggle = () -> props.checked(c -> !c);
		var box = <button tag={props.tag ?? "checkbox"} role="checkbox" aria-label={props.label} aria-checked={props.checked} width={14} height={14}
			borderWidth={1} borderColor="currentColor" alignItems="center" justifyContent="center" onPress={() -> toggle()}>
			<Show when={props.checked}><view width={8} height={8} background="currentColor"/></Show>
		</button>;
		return props.label == null ? box : <view flexDirection="row" alignItems="center" columnGap={6}>
			{box}<text aria-hidden onPress={_ -> toggle()}>{props.label}</text>
		</view>;
	}

	public static function Slider(props:{value:Signal<Float>, ?step:Float, ?label:String, ?tag:String, ?width:Float}):View {
		var step = props.step ?? 0.1, width = props.width ?? 100;
		var to = (v:Float) -> props.value(Math.max(0, Math.min(1, Math.fround(v / step) * step)));
		return <view tag={props.tag ?? "slider"} role="slider" aria-label={props.label} aria-valuenow={props.value} aria-valuemin={0} aria-valuemax={1} focusable
			width={width} height={12} borderWidth={1} borderColor="currentColor" onKeyDown={e -> switch e.key {
				case Key.RIGHT | Key.UP:
					to(props.value.peek() + step);
					e.preventDefault();
				case Key.LEFT | Key.DOWN:
					to(props.value.peek() - step);
					e.preventDefault();
				case _:
			}}>
			<view height="100%" width={props.value() * (width - 2)} background="currentColor"/>
		</view>;
	}
}
