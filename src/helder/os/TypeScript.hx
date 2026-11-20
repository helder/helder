package helder.os;

// helder.os for TypeScript programs (helder.typescript): what an app keeps
// between runs (Store), the platform's settings, locale and app services
// (Settings, Locale, Format, Plural, Network, Share, Permissions,
// Notifications, Photos, Location, Biometrics, Paths, DeviceInfo,
// StatusBar), the program's arguments and environment (args(), env(name):
// Sys's). Its windows, events and App are helder/scene's.
@:typescript("helder/os")
@:typescript.types(helder.os.Settings.Contrast, helder.os.Settings.Orientation, helder.os.Format.Style, helder.os.Format.NumberOptions, helder.os.Format.DateOptions, helder.os.Plural.PluralCategory, helder.os.Network.NetworkKind,
	helder.os.Permissions.Permission, helder.os.Permissions.PermissionStatus, helder.os.Location.GeoPosition, helder.os.Biometrics.BiometricKind,
	helder.os.DeviceInfo.DeviceKind, helder.os.DeviceInfo.DeviceDetails, helder.os.StatusBar.BarStyle)
@:typescript.classes(helder.os.Store, helder.os.Settings, helder.os.Locale, helder.os.Format, helder.os.Plural, helder.os.Network,
	helder.os.Share, helder.os.Permissions, helder.os.Notifications, helder.os.Photos, helder.os.Location, helder.os.Biometrics,
	helder.os.Paths, helder.os.DeviceInfo, helder.os.StatusBar)
@:typescript.functions(args = Sys.args, env = Sys.getEnv)
@:build(helder.typescript.api.Manifest.build())
class TypeScript {}
