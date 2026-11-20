package helder.os;

// A trackpad's scroll gesture and its momentum, as a Scroll event's phase and
// momentum (0: none, a wheel's)
class ScrollPhase {
	public static inline var Began = 1;
	public static inline var Changed = 2;
	public static inline var Ended = 3;
	public static inline var Cancelled = 4;
}
