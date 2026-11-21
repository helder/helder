package fixture;

import java.util.List;
import kotlin.collections.CollectionsKt;
import kotlin.collections.ArraysKt;
import kotlin.text.StringsKt;
import kotlin.ranges.RangesKt;

// kotlin-stdlib's own bytecode (Kotlin's compiler's) called from Java (build.sh)
class KotlinUse {
	static void run() {
		List<Integer> xs = CollectionsKt.listOf(3, 1, 2);
		Main.say("kotlin: " + CollectionsKt.sorted(xs) + " " + CollectionsKt.joinToString(xs, "-", "[", "]", -1, "...", null));
		Main.say("kotlin: " + StringsKt.reversed("kotlin") + " " + StringsKt.padStart("7", 3, '0') + " " + StringsKt.split("a,b,,c", new String[] {","}, false, 0));
		Main.say("kotlin: " + RangesKt.coerceIn(15, 0, 10) + " " + ArraysKt.toList(new int[] {4, 5}) + " " + StringsKt.toIntOrNull("12x"));
		Main.say("kotlin: " + CollectionsKt.map(xs, x -> x * 10));
	}
}
