import { scenario } from "helder/scenario";

// the real app, its request answered by a fixture (none goes out)
const time = "2026-11-26T09:00";

export const ghent = scenario({ name: "Weather/Ghent", time, http: { "api.open-meteo.com/v1/forecast*": "fixtures/forecast.json" } });
export const offline = scenario({ name: "Weather/Offline", time, http: { "api.open-meteo.com/*": 503 } });
