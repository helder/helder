import { signal, Show } from "helder/view";
import { Forecast, Sky, Day, fetchForecast, dateOf, dayNames, longDayNames, monthNames, skyLabel } from "./weather";

const ink = "#f8fafc";
const dim = "rgba(248,250,252,0.62)";
const card = "rgba(255,255,255,0.10)";
const line = "rgba(255,255,255,0.14)";
const sun = "#fbbf24";
const cloud = "#e2e8f0";
const drop = "#60a5fa";

const deg = (t: number) => `${Math.round(t)}°`;

/** A weather glyph drawn from shapes, `size` points square. */
export function Icon(props: { sky: Sky; size: number }) {
	const s = props.size;
	const u = s / 10;
	const hasSun = props.sky === "clear" || props.sky === "partly";
	const hasCloud = props.sky !== "clear";
	const wet = props.sky === "drizzle" || props.sky === "rain" || props.sky === "storm";
	const cloudTop = props.sky === "partly" ? 4 * u : 2.4 * u;
	const cloudColor = props.sky === "storm" ? "#94a3b8" : cloud;
	return <view width={s} height={s}>
		{hasSun && (props.sky === "clear"
			? <view position="absolute" left={2 * u} top={2 * u} width={6 * u} height={6 * u} borderRadius={3 * u} background={sun} boxShadow={`0 0 ${2 * u} rgba(251,191,36,0.6)`}/>
			: <view position="absolute" left={1 * u} top={0.8 * u} width={5 * u} height={5 * u} borderRadius={2.5 * u} background={sun}/>)}
		{hasCloud && <view position="absolute" left={1 * u} top={cloudTop} width={8 * u} height={4 * u}>
			<view position="absolute" left={0} top={1.6 * u} width={8 * u} height={2.4 * u} borderRadius={1.2 * u} background={cloudColor}/>
			<view position="absolute" left={1.2 * u} top={0.6 * u} width={3 * u} height={3 * u} borderRadius={1.5 * u} background={cloudColor}/>
			<view position="absolute" left={3.4 * u} top={0} width={3.6 * u} height={3.6 * u} borderRadius={1.8 * u} background={cloudColor}/>
		</view>}
		{props.sky === "fog" && [0, 1].map(i =>
			<view position="absolute" left={(1.5 + i) * u} top={(7 + i * 1.4) * u} width={6 * u} height={0.7 * u} borderRadius={0.35 * u} background={cloud} opacity={0.7}/>)}
		{props.sky === "snow" && [0, 1, 2].map(i =>
			<view position="absolute" left={(2.4 + i * 2) * u} top={(7.2 + (i % 2) * 1.2) * u} width={1 * u} height={1 * u} borderRadius={0.5 * u} background="#ffffff"/>)}
		{wet && [0, 1, 2].map(i =>
			<view position="absolute" left={(2.6 + i * 2) * u} top={(7 + (i % 2) * 0.8) * u} width={0.7 * u} height={(props.sky === "drizzle" ? 1 : 1.8) * u} borderRadius={0.35 * u} background={drop}/>)}
		{props.sky === "storm" && <view position="absolute" left={4.6 * u} top={6.4 * u} width={0.9 * u} height={3 * u} borderRadius={0.3 * u} background={sun}/>}
	</view>;
}

function Stat(props: { label: string; value: string }) {
	return <view flexGrow={1} alignItems="center" rowGap={2}>
		<text fontSize={12} color={dim}>{props.label}</text>
		<text fontSize={16} fontWeight={600} color={ink}>{props.value}</text>
	</view>;
}

function DayRow(props: { day: Day; min: number; max: number; first: boolean }) {
	const d = props.day;
	const span = Math.max(1, props.max - props.min);
	const left = (d.low - props.min) / span;
	const width = Math.max(0.06, (d.high - d.low) / span);
	return <view>
		{!props.first && <view height={1} background={line}/>}
		<view flexDirection="row" alignItems="center" columnGap={12} padding="12 0">
		<text width={44} fontSize={16} fontWeight={500} color={ink}>{dayNames[dateOf(d.date).getDay()]}</text>
		<Icon sky={d.sky} size={30}/>
		<text width={40} fontSize={13} color={d.rain >= 30 ? drop : dim}>{d.rain >= 10 ? `${d.rain}%` : ""}</text>
		<text width={32} fontSize={16} color={dim} textAlign="right">{deg(d.low)}</text>
		<view flexGrow={1} height={6} borderRadius={3} background="rgba(255,255,255,0.12)">
			<view position="absolute" left={`${left * 100}%`} width={`${width * 100}%`} top={0} bottom={0} borderRadius={3}
				background={d.high >= 9 ? "#fb923c" : d.high >= 5 ? "#facc15" : "#7dd3fc"}/>
		</view>
		<text width={32} fontSize={16} fontWeight={600} color={ink}>{deg(d.high)}</text>
		</view>
	</view>;
}

/** The screen, posed by a forecast (or none yet, or an error). */
export function Weather(props: { forecast?: Forecast; error?: string }) {
	const f = props.forecast;
	if (!f) {
		return <view flexGrow={1} alignItems="center" justifyContent="center" rowGap={8} background="#1e3a5f" padding={24}>
			<text fontSize={28} fontWeight={600} color={ink}>Ghent</text>
			<text fontSize={14} color={dim}>{props.error ? "Couldn't load the forecast" : "Loading the forecast…"}</text>
			{props.error && <text fontSize={12} color={dim} opacity={0.7}>{props.error}</text>}
		</view>;
	}
	const today = f.days[0];
	const next = f.days.slice(1, 6);
	const min = Math.min(...next.map(d => d.low));
	const max = Math.max(...next.map(d => d.high));
	const date = dateOf(today.date);
	return <view flexGrow={1} background="#1e3a5f" padding="56 20 24" rowGap={20}>
		<view alignItems="center" rowGap={4}>
			<text fontSize={30} fontWeight={600} color={ink}>Ghent</text>
			<text fontSize={14} color={dim}>{`${longDayNames[date.getDay()]} ${date.getDate()} ${monthNames[date.getMonth()]}`}</text>
		</view>
		<view flexDirection="row" alignItems="center" justifyContent="center" columnGap={16}>
			<Icon sky={f.now.sky} size={96}/>
			<view rowGap={0}>
				<text fontSize={80} fontWeight={200} color={ink}>{deg(f.now.temp)}</text>
			</view>
		</view>
		<view alignItems="center" rowGap={4}>
			<text fontSize={20} fontWeight={500} color={ink}>{skyLabel[f.now.sky]}</text>
			<text fontSize={15} color={dim}>{`H ${deg(today.high)}   L ${deg(today.low)}`}</text>
		</view>
		<view flexDirection="row" padding="14 8" borderRadius={16} background={card}>
			<Stat label="Feels like" value={deg(f.now.feels)}/>
			<Stat label="Wind" value={`${Math.round(f.now.wind)} km/h`}/>
			<Stat label="Humidity" value={`${Math.round(f.now.humidity)}%`}/>
			<Stat label="Rain" value={`${today.rain}%`}/>
		</view>
		<view padding="8 16" borderRadius={16} background={card}>
			<text fontSize={12} fontWeight={600} color={dim} padding="6 0 4">NEXT 5 DAYS</text>
			{next.map((d, i) => <DayRow day={d} min={min} max={max} first={i === 0}/>)}
		</view>
	</view>;
}

// the app's model: the forecast, or why there is none (a scenario's boot writes them)
export const forecast = signal<Forecast | undefined>(undefined);
export const error = signal<string | undefined>(undefined);

/** The app: fetches Ghent's forecast from Open-Meteo. */
export function App() {
	fetchForecast().then(f => forecast(f), e => error(String(e?.message ?? e)));
	return <view flexGrow={1}>
		<Show when={() => forecast() !== undefined}>
			{() => <Weather forecast={forecast()}/>}
		</Show>
		<Show when={() => forecast() === undefined}>
			{() => <Weather error={error()}/>}
		</Show>
	</view>;
}
