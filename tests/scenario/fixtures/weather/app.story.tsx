import { story } from "helder/story";
import { Weather } from "./app";
import { sampleForecast } from "./weather";

export const today = story({ name: "Forecast/Ghent", render: () => <Weather forecast={sampleForecast()}/> });
export const loading = story({ name: "Forecast/Loading", render: () => <Weather/> });
export const failed = story({ name: "Forecast/Offline", render: () => <Weather error="forecast: 503"/> });
