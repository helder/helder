import { Client } from "helder/async";

export type Sky = "clear" | "partly" | "cloudy" | "fog" | "drizzle" | "rain" | "snow" | "storm";

export interface Day {
	date: string; // YYYY-MM-DD: the model is plain data
	sky: Sky;
	high: number;
	low: number;
	rain: number; // chance of rain, %
}

export interface Forecast {
	now: { temp: number; feels: number; sky: Sky; wind: number; humidity: number };
	days: Day[]; // today first, then the next 5
}

export const dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
export const longDayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
export const monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];

export const skyLabel: Record<Sky, string> = {
	clear: "Clear", partly: "Partly cloudy", cloudy: "Cloudy", fog: "Fog",
	drizzle: "Drizzle", rain: "Rain", snow: "Snow", storm: "Thunderstorm",
};

/** WMO weather code to a sky. */
export function skyOf(code: number): Sky {
	if (code === 0) return "clear";
	if (code <= 2) return "partly";
	if (code === 3) return "cloudy";
	if (code === 45 || code === 48) return "fog";
	if (code >= 51 && code <= 57) return "drizzle";
	if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) return "rain";
	if ((code >= 71 && code <= 77) || code === 85 || code === 86) return "snow";
	if (code >= 95) return "storm";
	return "cloudy";
}

const url = "https://api.open-meteo.com/v1/forecast?latitude=51.05&longitude=3.72"
	+ "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code"
	+ "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"
	+ "&timezone=Europe%2FBrussels&forecast_days=6";

export async function fetchForecast(): Promise<Forecast> {
	const res = await Client.request(url);
	if (res.status !== 200) throw new Error(`forecast: ${res.status}`);
	const j = JSON.parse(res.text());
	const d = j.daily;
	const days: Day[] = (d.time as string[]).map((t, i) => {
		return {
			date: t,
			sky: skyOf(d.weather_code[i]),
			high: d.temperature_2m_max[i],
			low: d.temperature_2m_min[i],
			rain: d.precipitation_probability_max[i] ?? 0,
		};
	});
	return {
		now: {
			temp: j.current.temperature_2m,
			feels: j.current.apparent_temperature,
			sky: skyOf(j.current.weather_code),
			wind: j.current.wind_speed_10m,
			humidity: j.current.relative_humidity_2m,
		},
		days,
	};
}

/** A posed forecast for stories: late November in Ghent. */
export function sampleForecast(start = new Date(2026, 10, 26)): Forecast {
	const plan: [Sky, number, number, number][] = [
		["rain", 9, 5, 80], ["cloudy", 8, 4, 30], ["partly", 7, 2, 10],
		["clear", 6, 0, 0], ["drizzle", 8, 4, 55], ["storm", 10, 6, 90],
	];
	return {
		now: { temp: 7.4, feels: 4.1, sky: "rain", wind: 22, humidity: 88 },
		days: plan.map(([sky, high, low, rain], i) => ({
			date: dayKey(new Date(start.getFullYear(), start.getMonth(), start.getDate() + i)),
			sky, high, low, rain,
		})),
	};
}

function pad(n: number) { return n < 10 ? `0${n}` : `${n}`; }

export function dayKey(d: Date): string {
	return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

export function dateOf(key: string): Date {
	const [y, m, d] = key.split("-").map(Number);
	return new Date(y, m - 1, d);
}
