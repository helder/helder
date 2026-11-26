import { scenario } from "helder/scenario";
import { forecast, error } from "./app";
import { sampleForecast } from "./weather";

// App fetches Open-Meteo as it mounts: until http fixtures (phase 2) boot
// writes the answer, and the live request still goes out and may land
const time = "2026-11-26T09:00";

export const ghent = scenario({ name: "Weather/Ghent", time, boot() { forecast(sampleForecast()); } });
export const offline = scenario({ name: "Weather/Offline", time, boot() { error("forecast: 503"); } });
