import { scenario } from "helder/scenario";
import { sampleForecast } from "./weather";

// main.tsx's App fetches Open-Meteo as it starts: until http fixtures
// (phase 2) these set the result, and the live request still goes out
const time = "2026-11-26T09:00";

export const ghent = scenario({ name: "Weather/Ghent", time, set: { "App.forecast": sampleForecast() } });
export const offline = scenario({ name: "Weather/Offline", time, set: { "App.error": "forecast: 503" } });
