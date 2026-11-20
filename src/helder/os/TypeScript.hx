package helder.os;

// helder.os for TypeScript programs (helder.typescript): what an app keeps
// between runs (Store), the program's arguments and environment (args(),
// env(name): Sys's). Its windows, events and App are helder/scene's.
@:typescript("helder/os")
@:typescript.types(helder.os.Settings.Contrast, helder.os.Settings.Orientation, helder.os.Format.Style, helder.os.Format.NumberOptions, helder.os.Format.DateOptions, helder.os.Plural.PluralCategory)
@:typescript.classes(helder.os.Store, helder.os.Settings, helder.os.Locale, helder.os.Format, helder.os.Plural)
@:typescript.functions(args = Sys.args, env = Sys.getEnv)
@:build(helder.typescript.api.Manifest.build())
class TypeScript {}
