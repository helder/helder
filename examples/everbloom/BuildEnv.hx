// SHOP_API_URL as it was when the app was built (Android's endpoint: an
// app launches with no environment of the caller's); "" when unset
class BuildEnv {
	public static macro function shopApiUrl() {
		var v = Sys.getEnv("SHOP_API_URL") ?? "";
		return macro $v{v};
	}
}
