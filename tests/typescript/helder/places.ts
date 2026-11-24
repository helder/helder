import { Places, Trash, type Place, type PlaceKind, type Volume } from "helder/os";

const home: PlaceKind = "Home";
const places: Place[] = Places.user();
const volumes: Volume[] = Places.volumes();
const available = Trash.available();
console.log(available
	? places[0]?.kind === home && volumes[0]?.root && volumes[0].total > 0
	: places.length === 0 && volumes.length === 0);

let unavailable = false;
if (available) unavailable = true;
else {
	try {
		const destination: string | null = Trash.move("file");
		console.log(destination);
	} catch {
		unavailable = true;
	}
}
console.log(unavailable);
