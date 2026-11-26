import { signal } from "helder/view";
import { Format } from "helder/os";

// what a screen's environment shows: its clock and zone, its language, its
// randomness, its timers (a tick a second, set in the screen: on its clock)
export function App() {
	const lucky = Math.random().toFixed(6);
	const ticks = signal(0);
	setInterval(() => ticks(ticks() + 1), 1000);
	return <view flexGrow={1} padding={16} gap={8} background="#ffffff">
		<text fontSize={13} color="#111827">{() => new Date().toString()}</text>
		<text fontSize={13} color="#111827">{() => Format.date(new Date(), { date: "medium", time: "short" })}</text>
		<text fontSize={13} color="#111827">{Format.number(1234567.891, { decimals: 2 })}</text>
		<text fontSize={13} color="#111827">{"lucky " + lucky}</text>
		<text fontSize={13} color="#111827">{() => "ticks " + ticks()}</text>
	</view>;
}
