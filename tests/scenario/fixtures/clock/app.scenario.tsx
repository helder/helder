import { scenario } from "helder/scenario";

// the same moment in two places, and one with nothing given (UTC, en-US)
export const brussels = scenario({ name: "Clock/Brussels", time: "2026-11-26T09:00", zone: "+01:00", locale: "nl-BE", seed: 3, play: 3 });
export const delhi = scenario({ name: "Clock/Delhi", time: "2026-11-26T09:00", zone: "+05:30", locale: "en-IN", seed: 3, play: 3 });
export const plain = scenario({ name: "Clock/Plain", time: "2026-11-26T09:00", play: 3 });
