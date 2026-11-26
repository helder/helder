import { story } from "helder/story";
import { Weather } from "./app";
import { sampleForecast } from "./weather";

export const today = story({ name: "Weather/Ghent", render: () => <Weather forecast={sampleForecast()}/> });
export const loading = story({ name: "Weather/Loading", render: () => <Weather/> });
export const failed = story({ name: "Weather/Offline", render: () => <Weather error="forecast: 503"/> });
