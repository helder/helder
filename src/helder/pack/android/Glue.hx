package helder.pack.android;

import helder.pack.android.Dex;

// The Java an app needs for views and listeners (classes.dex, written by
// Dex; the APK gets it when the program uses helder.os.android.Glue, and
// org.hxmc.Activity as its activity when it shows Android's views as its
// content: a class marked @:helder.android.views; Classes, a macro, tells
// helder.cli.Android):
//
// - org.hxmc.Activity, the APK's activity: NativeActivity (which loads the
//   program's library and runs it as without classes.dex), whose window
//   then draws views again: onCreate gives back the surface and the input
//   queue NativeActivity took (Window.takeSurface(null),
//   takeInputQueue(null): no ANativeWindow, the views get the input) and
//   the window's default pixel format.
// - org.hxmc.Glue(int id): one listener for every kind of widget, whose
//   methods call its static native event(id, kind, object, a, b), which
//   the program registers (RegisterNatives: helder.os.android.Glue); kinds
//   and arguments: CLICK (View.OnClickListener), TEXT
//   (TextWatcher.afterTextChanged: the Editable), CHECKED
//   (CompoundButton's: the state), PROGRESS (SeekBar's: the progress, from
//   the user), EDITOR (TextView.OnEditorActionListener: the action;
//   handled when event returns non-zero), LAYOUT
//   (View.OnLayoutChangeListener: the width and height), SURFACE_CREATED,
//   SURFACE_CHANGED (width, height), SURFACE_DESTROYED
//   (SurfaceHolder.Callback: the holder), KEY (View.OnKeyListener: the key
//   code and the action; handled when non-zero).
// - org.hxmc.AccessProvider and org.hxmc.AccessDelegate: an
//   AccessibilityNodeProvider and a View.AccessibilityDelegate whose
//   methods are natives (helder.ui.draw.AndroidAccess registers them): a
//   drawn window's accessibility tree as the content view's virtual views.
// - org.hxmc.WebClient(int id), org.hxmc.WebChrome(int id): a
//   WebViewClient and a WebChromeClient whose callbacks call their static
//   native event(id, kind, object, a, b) as Glue's do (the program registers
//   it with Glue's handler: helder.os.android.Glue.adopt): WEB_STARTED,
//   WEB_FINISHED (the URL), WEB_ERROR (the WebResourceError; its code, 1 for
//   the main frame), WEB_NAVIGATED (doUpdateVisitedHistory: the URL),
//   WEB_OVERRIDE (shouldOverrideUrlLoading: the WebResourceRequest; kept
//   when non-zero), WEB_PROGRESS (the progress), WEB_TITLE (the title),
//   WEB_CONSOLE (the ConsoleMessage; handled), WEB_GONE (onRenderProcessGone:
//   handled); and shouldInterceptRequest,
//   on the WebView's own thread, calling the static native intercept(id,
//   request) for its WebResourceResponse (null: the network's).
// - org.hxmc.WebBridge(int id): the object a page reaches as a JavaScript
//   interface, its post(String) @JavascriptInterface calling the static
//   native post(id, message), on the WebView's JavaBridge thread
//   (helder.ui.platform.AndroidWebView).
// - org.hxmc.Editor(Context): a View that is a text editor
//   (onCheckIsTextEditor), never drawn, the input method's for a drawn field
//   (helder.os.android.TextInput): its onCreateInputConnection (the field's
//   EditorInfo, a Connection) and onApplyWindowInsets (the keyboard's
//   insets) natives.
// - org.hxmc.Connection(View, boolean): a BaseInputConnection whose edits
//   and reads are natives (getSurroundingText, getExtractedText, commitText, setComposingText, setComposingRegion,
//   finishComposingText, deleteSurroundingText and InCodePoints,
//   sendKeyEvent, performEditorAction, setSelection, getTextBeforeCursor,
//   getTextAfterCursor, getSelectedText, getCursorCapsMode): the field's
//   text is the program's, mirrored on the main thread.
// The classes keep hxmc's names (org.hxmc.*), which helder.os.android
// looks up. Ported from hxmc (hxmc.android.Glue), MIT.
//
// And the classes of an app service, each in the APK only when the
// program uses it (a class marked @:helder.android.dex("<name>"):
// Classes), with its manifest entry (Apk):
// - Main: NativeActivity whose onNewIntent sets the activity's intent (a
//   deep link while running: helder.os.android.AndroidLinks reads it on
//   resume); the activity of an app with links (org.hxmc.Activity has it
//   too).
// - Request: a transparent activity asking for permissions (the intent's
//   "permissions") or starting an activity for its result (its "intent"),
//   its static native result(id, code, data) called with the
//   permissions' grants (code 0) or the result's code and intent, then
//   finished (helder.os.android.AndroidRequest).
// - Files: a ContentProvider (<package>.hxmc.files) serving the files
//   whose paths are in its static `allowed` (a share's: helder.os.Share; a
//   photo's to take: helder.os.Camera), in the mode asked
//   (ParcelFileDescriptor.parseMode: what the intent granted, the system
//   checks), as content://<authority><path>.
// - Alarm: a BroadcastReceiver posting the notification its intent
//   carries ("id", "title", "body": helder.os.Notifications), in the
//   channel "default", the app's icon (else the system's), a tap opening
//   the app's launch activity with the id as its "hxmc.notification";
//   all Java, for the process may have ended since it was scheduled.
// - Locator(int id): a LocationListener and a Consumer (getCurrentLocation's)
//   whose onLocationChanged and accept call its static native
//   located(id, location) (helder.os.Location).
// - Biometric(int id): a BiometricPrompt.AuthenticationCallback and the
//   prompt's cancel button's DialogInterface.OnClickListener, calling its
//   static native done(id, 1) when the user is verified, done(id, 0) on an
//   error or the cancel (helder.os.Biometrics).
class Glue {
	public static inline var ACTIVITY = "org.hxmc.Activity";
	public static inline var MAIN = "org.hxmc.Main";

	// an app service's classes by name (@:helder.android.dex("<name>"))
	public static final SERVICES = ["Main", "Request", "Files", "Alarm", "Locator", "Biometric"];

	// the manifest's permissions of one helder.os.Permissions asks for (photos:
	// READ_MEDIA_IMAGES from Android 13, READ_EXTERNAL_STORAGE before it)
	public static function permissions(p:String):Array<String>
		return switch p {
			case "camera": ["CAMERA"];
			case "microphone": ["RECORD_AUDIO"];
			case "photos": ["READ_MEDIA_IMAGES", "READ_EXTERNAL_STORAGE"];
			case "location": ["ACCESS_COARSE_LOCATION", "ACCESS_FINE_LOCATION"];
			case "notifications": ["POST_NOTIFICATIONS"];
			case _: [];
		}

	public static inline var CLICK = 0;
	public static inline var TEXT = 1;
	public static inline var CHECKED = 2;
	public static inline var PROGRESS = 3;
	public static inline var EDITOR = 4;
	public static inline var LAYOUT = 5;
	public static inline var SURFACE_CREATED = 6;
	public static inline var SURFACE_CHANGED = 7;
	public static inline var SURFACE_DESTROYED = 8;
	public static inline var KEY = 9;
	public static inline var WEB_STARTED = 10;
	public static inline var WEB_FINISHED = 11;
	public static inline var WEB_ERROR = 12;
	public static inline var WEB_NAVIGATED = 13;
	public static inline var WEB_OVERRIDE = 14;
	public static inline var WEB_PROGRESS = 15;
	public static inline var WEB_TITLE = 16;
	public static inline var WEB_CONSOLE = 17;
	public static inline var WEB_GONE = 18;

	static inline var GLUE = "Lorg/hxmc/Glue;";
	static inline var OBJECT = "Ljava/lang/Object;";
	static inline var VIEW = "Landroid/view/View;";
	static inline var HOLDER = "Landroid/view/SurfaceHolder;";

	// classes.dex: the views' and listeners' classes (base), and the services named
	public static function dex(base = true, ?services:Array<String>):haxe.io.Bytes {
		var classes = base ? [activity(), glue(), accessProvider(), accessDelegate(), webClient(), webChrome(), webBridge(), editor(), connection()] : [];
		for (s in services ?? [])
			classes.push(switch s {
				case "Main": main();
				case "Request": request();
				case "Files": files();
				case "Alarm": alarm();
				case "Locator": locator();
				case "Biometric": biometric();
				case _: throw 'no service class $s (${SERVICES.join(", ")})';
			});
		return Dex.write(classes);
	}

	static inline var CHARS = "Ljava/lang/CharSequence;";
	static inline var CONNECTION = "Landroid/view/inputmethod/BaseInputConnection;";

	// org.hxmc.Editor: a View, a text editor, its natives the input method's
	static function editor():DexClass {
		var base = "Landroid/view/View;";
		return {
			name: "Lorg/hxmc/Editor;",
			access: Dex.PUBLIC | Dex.FINAL,
			superName: base,
			interfaces: [],
			fields: [],
			methods: [
				{
					name: "<init>",
					ret: "V",
					params: ["Landroid/content/Context;"],
					access: Dex.PUBLIC | Dex.CONSTRUCTOR,
					code: {registers: 2, ins: 2, outs: 2, insns: r -> invoke(INVOKE_DIRECT, r.method(base, "<init>", "V", ["Landroid/content/Context;"]), [0, 1]).concat([RETURN_VOID])}
				},
				// (const/4 v0, 1; return v0)
				{name: "onCheckIsTextEditor", ret: "Z", params: [], access: Dex.PUBLIC, code: {registers: 2, ins: 1, outs: 0, insns: r -> [const4(0, 1), (0 << 8) | 0x0f]}},
				{
					name: "onCreateInputConnection",
					ret: "Landroid/view/inputmethod/InputConnection;",
					params: ["Landroid/view/inputmethod/EditorInfo;"],
					access: Dex.PUBLIC | Dex.NATIVE
				},
				{name: "onApplyWindowInsets", ret: "Landroid/view/WindowInsets;", params: ["Landroid/view/WindowInsets;"], access: Dex.PUBLIC | Dex.NATIVE}
			]
		};
	}

	// org.hxmc.Connection: a BaseInputConnection (not a full editor) whose methods are natives
	static function connection():DexClass {
		inline function native(name:String, ret:String, params:Array<String>):DexMethod
			return {name: name, ret: ret, params: params, access: Dex.PUBLIC | Dex.NATIVE};
		return {
			name: "Lorg/hxmc/Connection;",
			access: Dex.PUBLIC | Dex.FINAL,
			superName: CONNECTION,
			interfaces: [],
			fields: [],
			methods: [
				{
					name: "<init>",
					ret: "V",
					params: [VIEW, "Z"],
					access: Dex.PUBLIC | Dex.CONSTRUCTOR,
					code: {registers: 3, ins: 3, outs: 3, insns: r -> invoke(INVOKE_DIRECT, r.method(CONNECTION, "<init>", "V", [VIEW, "Z"]), [0, 1, 2]).concat([RETURN_VOID])}
				},
				// (true: an editor that takes batches, as an EditText's; an input method composes in one)
				{name: "beginBatchEdit", ret: "Z", params: [], access: Dex.PUBLIC, code: {registers: 2, ins: 1, outs: 0, insns: r -> [const4(0, 1), (0 << 8) | 0x0f]}},
				{name: "endBatchEdit", ret: "Z", params: [], access: Dex.PUBLIC, code: {registers: 2, ins: 1, outs: 0, insns: r -> [const4(0, 1), (0 << 8) | 0x0f]}},
				// (null: no snapshot, rather than one of BaseInputConnection's empty Editable)
				{name: "takeSnapshot", ret: "Landroid/view/inputmethod/TextSnapshot;", params: [], access: Dex.PUBLIC, code: {registers: 2, ins: 1, outs: 0, insns: r -> [const4(0, 0), (0 << 8) | 0x11]}},
				native("getSurroundingText", "Landroid/view/inputmethod/SurroundingText;", ["I", "I", "I"]),
				native("getExtractedText", "Landroid/view/inputmethod/ExtractedText;", ["Landroid/view/inputmethod/ExtractedTextRequest;", "I"]),
				native("commitText", "Z", [CHARS, "I"]),
				native("setComposingText", "Z", [CHARS, "I"]),
				native("setComposingRegion", "Z", ["I", "I"]),
				native("finishComposingText", "Z", []),
				native("deleteSurroundingText", "Z", ["I", "I"]),
				native("deleteSurroundingTextInCodePoints", "Z", ["I", "I"]),
				native("sendKeyEvent", "Z", ["Landroid/view/KeyEvent;"]),
				native("performEditorAction", "Z", ["I"]),
				native("setSelection", "Z", ["I", "I"]),
				native("getTextBeforeCursor", CHARS, ["I", "I"]),
				native("getTextAfterCursor", CHARS, ["I", "I"]),
				native("getSelectedText", CHARS, ["I"]),
				native("getCursorCapsMode", "I", ["I"])
			]
		};
	}

	static inline var NODE_INFO = "Landroid/view/accessibility/AccessibilityNodeInfo;";
	static inline var NODE_PROVIDER = "Landroid/view/accessibility/AccessibilityNodeProvider;";

	// a constructor calling its superclass's, of no arguments
	static function constructor(base:String):DexMethod
		return {
			name: "<init>",
			ret: "V",
			params: [],
			access: Dex.PUBLIC | Dex.CONSTRUCTOR,
			code: {registers: 1, ins: 1, outs: 1, insns: r -> invoke(INVOKE_DIRECT, r.method(base, "<init>", "V", []), [0]).concat([RETURN_VOID])}
		};

	// org.hxmc.AccessProvider: an AccessibilityNodeProvider whose methods are
	// natives (helder.ui.draw.AndroidAccess's): a drawn window's nodes as
	// virtual views
	static function accessProvider():DexClass
		return {
			name: "Lorg/hxmc/AccessProvider;",
			access: Dex.PUBLIC | Dex.FINAL,
			superName: NODE_PROVIDER,
			interfaces: [],
			fields: [],
			methods: [
				constructor(NODE_PROVIDER),
				{name: "createAccessibilityNodeInfo", ret: NODE_INFO, params: ["I"], access: Dex.PUBLIC | Dex.NATIVE},
				{name: "performAction", ret: "Z", params: ["I", "I", "Landroid/os/Bundle;"], access: Dex.PUBLIC | Dex.NATIVE},
				{name: "findFocus", ret: NODE_INFO, params: ["I"], access: Dex.PUBLIC | Dex.NATIVE}
			]
		};

	// org.hxmc.AccessDelegate: a View.AccessibilityDelegate whose provider is a native's (the AccessProvider)
	static function accessDelegate():DexClass {
		var base = "Landroid/view/View$AccessibilityDelegate;";
		return {
			name: "Lorg/hxmc/AccessDelegate;",
			access: Dex.PUBLIC | Dex.FINAL,
			superName: base,
			interfaces: [],
			fields: [],
			methods: [
				constructor(base),
				{name: "getAccessibilityNodeProvider", ret: NODE_PROVIDER, params: [VIEW], access: Dex.PUBLIC | Dex.NATIVE}
			]
		};
	}

	// ---- Dalvik instructions (16-bit units)

	static inline function op(a:Int, b:Int, op:Int):Int
		return (b << 12) | (a << 8) | op;

	// invoke-* {regs}, method (35c: up to five registers of 4 bits)
	static function invoke(opcode:Int, method:Int, regs:Array<Int>):Array<Int> {
		var r = regs.concat([0, 0, 0, 0, 0]);
		return [(regs.length << 12) | (r[4] << 8) | opcode, method, (r[3] << 12) | (r[2] << 8) | (r[1] << 4) | r[0]];
	}

	static inline var INVOKE_VIRTUAL = 0x6e;
	static inline var INVOKE_SUPER = 0x6f;
	static inline var INVOKE_DIRECT = 0x70;
	static inline var INVOKE_STATIC = 0x71;
	static inline var INVOKE_INTERFACE = 0x72;
	static inline var RETURN_VOID = 0x000e;

	// const/4 vA, #b (-8..7)
	static inline function const4(a:Int, b:Int):Int
		return op(a, b & 15, 0x12);

	static inline function moveResult(a:Int):Int
		return (a << 8) | 0x0a;

	// ---- the classes

	static function activity():DexClass {
		var cls = "Lorg/hxmc/Activity;", base = "Landroid/app/NativeActivity;", window = "Landroid/view/Window;";
		return {
			name: cls,
			access: Dex.PUBLIC,
			superName: base,
			interfaces: [],
			fields: [],
			methods: [
				{
					name: "<init>",
					ret: "V",
					params: [],
					access: Dex.PUBLIC | Dex.CONSTRUCTOR,
					code: {registers: 1, ins: 1, outs: 1, insns: r -> invoke(INVOKE_DIRECT, r.method(base, "<init>", "V", []), [0]).concat([RETURN_VOID])}
				},
				{
					// (v0 the window, v1 null and 0, v2 this, v3 the bundle)
					name: "onCreate",
					ret: "V",
					params: ["Landroid/os/Bundle;"],
					access: Dex.PROTECTED,
					code: {
						registers: 4,
						ins: 2,
						outs: 2,
						insns: r -> invoke(INVOKE_SUPER, r.method(base, "onCreate", "V", ["Landroid/os/Bundle;"]), [2, 3])
							.concat(invoke(INVOKE_VIRTUAL, r.method("Landroid/app/Activity;", "getWindow", window, []), [2]))
							.concat([(0 << 8) | 0x0c, const4(1, 0)]) // move-result-object v0
							.concat(invoke(INVOKE_VIRTUAL, r.method(window, "takeSurface", "V", ["Landroid/view/SurfaceHolder$Callback2;"]), [0, 1]))
							.concat(invoke(INVOKE_VIRTUAL, r.method(window, "takeInputQueue", "V", ["Landroid/view/InputQueue$Callback;"]), [0, 1]))
							.concat(invoke(INVOKE_VIRTUAL, r.method(window, "setFormat", "V", ["I"]), [0, 1]))
							.concat([RETURN_VOID])
					}
				},
				newIntent(base)
			]
		};
	}

	// onNewIntent: the activity's intent the new one (v0 this, v1 the intent)
	static function newIntent(base:String):DexMethod
		return {
			name: "onNewIntent",
			ret: "V",
			params: [INTENT],
			access: Dex.PROTECTED,
			code: {
				registers: 2,
				ins: 2,
				outs: 2,
				insns: r -> invoke(INVOKE_SUPER, r.method(base, "onNewIntent", "V", [INTENT]), [0, 1])
					.concat(invoke(INVOKE_VIRTUAL, r.method(ANDROID_ACTIVITY, "setIntent", "V", [INTENT]), [0, 1]))
					.concat([RETURN_VOID])
			}
		};

	static function main():DexClass {
		var base = "Landroid/app/NativeActivity;";
		return {
			name: "Lorg/hxmc/Main;",
			access: Dex.PUBLIC,
			superName: base,
			interfaces: [],
			fields: [],
			methods: [constructor(base), newIntent(base)]
		};
	}

	static inline var INTENT = "Landroid/content/Intent;";
	static inline var ANDROID_ACTIVITY = "Landroid/app/Activity;";
	static inline var URI = "Landroid/net/Uri;";
	static inline var SET = "Ljava/util/Set;";

	// const-string vA, s; if-eqz / if-nez vA, +units; check-cast, new-instance vA, t;
	// sget-object, sput-object vA, field; return-object, return, throw vA
	static inline function constString(a:Int, r:Refs, s:String):Array<Int>
		return [(a << 8) | 0x1a, r.string(s)];

	static inline function ifEqz(a:Int, units:Int):Array<Int>
		return [(a << 8) | 0x38, units];

	static inline function ifNez(a:Int, units:Int):Array<Int>
		return [(a << 8) | 0x39, units];

	static inline function typed(op:Int, a:Int, index:Int):Array<Int>
		return [(a << 8) | op, index];

	static inline var CHECK_CAST = 0x1f;
	static inline var NEW_INSTANCE = 0x22;
	static inline var SGET_OBJECT = 0x62;
	static inline var SPUT_OBJECT = 0x69;

	static inline function newArray(a:Int, size:Int, t:Int):Array<Int>
		return [(size << 12) | (a << 8) | 0x23, t];

	// aput-object vA, vArray[vIndex]
	static inline function aputObject(a:Int, array:Int, index:Int):Array<Int>
		return [(a << 8) | 0x4d, (index << 8) | array];

	static inline function moveResultObject(a:Int):Int
		return (a << 8) | 0x0c;

	static inline function returnObject(a:Int):Int
		return (a << 8) | 0x11;

	static inline function returnInt(a:Int):Int
		return (a << 8) | 0x0f;

	// a method returning 0 (or null)
	static function zero(name:String, ret:String, params:Array<String>):DexMethod
		return {
			name: name,
			ret: ret,
			params: params,
			access: Dex.PUBLIC,
			code: {registers: 2 + params.length, ins: 1 + params.length, outs: 0, insns: r -> [const4(0, 0), ret == "I" ? returnInt(0) : returnObject(0)]}
		};

	static function request():DexClass {
		var cls = "Lorg/hxmc/Request;", strings = "[Ljava/lang/String;";
		var result = r -> r.method(cls, "result", "V", ["I", "I", OBJECT]);
		return {
			name: cls,
			access: Dex.PUBLIC | Dex.FINAL,
			superName: ANDROID_ACTIVITY,
			interfaces: [],
			fields: [],
			methods: [
				constructor(ANDROID_ACTIVITY),
				{name: "result", ret: "V", params: ["I", "I", OBJECT], access: Dex.PUBLIC | Dex.STATIC | Dex.NATIVE},
				{
					// (v0 the intent, v1 a key, v2, v3 the id, p0 v4, the bundle v5: made again, the request was made)
					name: "onCreate",
					ret: "V",
					params: ["Landroid/os/Bundle;"],
					access: Dex.PROTECTED,
					code: {
						registers: 6,
						ins: 2,
						outs: 3,
						insns: r -> invoke(INVOKE_SUPER, r.method(ANDROID_ACTIVITY, "onCreate", "V", ["Landroid/os/Bundle;"]), [4, 5])
							.concat(ifNez(5, 36))
							.concat(invoke(INVOKE_VIRTUAL, r.method(ANDROID_ACTIVITY, "getIntent", INTENT, []), [4]))
							.concat([moveResultObject(0)])
							.concat(constString(1, r, "id"))
							.concat([const4(2, 0)])
							.concat(invoke(INVOKE_VIRTUAL, r.method(INTENT, "getIntExtra", "I", [STRING, "I"]), [0, 1, 2]))
							.concat([moveResult(3)])
							.concat(constString(1, r, "permissions"))
							.concat(invoke(INVOKE_VIRTUAL, r.method(INTENT, "getStringArrayExtra", strings, [STRING]), [0, 1]))
							.concat([moveResultObject(2)])
							.concat(ifEqz(2, 6))
							.concat(invoke(INVOKE_VIRTUAL, r.method(ANDROID_ACTIVITY, "requestPermissions", "V", [strings, "I"]), [4, 2, 3]))
							.concat([RETURN_VOID])
							.concat(constString(1, r, "intent"))
							.concat(invoke(INVOKE_VIRTUAL, r.method(INTENT, "getParcelableExtra", "Landroid/os/Parcelable;", [STRING]), [0, 1]))
							.concat([moveResultObject(2)])
							.concat(typed(CHECK_CAST, 2, r.type(INTENT)))
							.concat(invoke(INVOKE_VIRTUAL, r.method(ANDROID_ACTIVITY, "startActivityForResult", "V", [INTENT, "I"]), [4, 2, 3]))
							.concat([RETURN_VOID])
					}
				},
				{
					// (v0 0, p0 v1, the id v2, the permissions v3, the grants v4)
					name: "onRequestPermissionsResult",
					ret: "V",
					params: ["I", strings, "[I"],
					access: Dex.PUBLIC,
					code: {
						registers: 5,
						ins: 4,
						outs: 3,
						insns: r -> [const4(0, 0)].concat(invoke(INVOKE_STATIC, result(r), [2, 0, 4]))
							.concat(invoke(INVOKE_VIRTUAL, r.method(ANDROID_ACTIVITY, "finish", "V", []), [1]))
							.concat([RETURN_VOID])
					}
				},
				{
					// (p0 v0, the id v1, the result's code v2, its intent v3)
					name: "onActivityResult",
					ret: "V",
					params: ["I", "I", INTENT],
					access: Dex.PROTECTED,
					code: {
						registers: 4,
						ins: 4,
						outs: 3,
						insns: r -> invoke(INVOKE_STATIC, result(r), [1, 2, 3])
							.concat(invoke(INVOKE_VIRTUAL, r.method(ANDROID_ACTIVITY, "finish", "V", []), [0]))
							.concat([RETURN_VOID])
					}
				}
			]
		};
	}

	static function alarm():DexClass {
		var cls = "Lorg/hxmc/Alarm;", base = "Landroid/content/BroadcastReceiver;", context = "Landroid/content/Context;",
			builder = "Landroid/app/Notification$Builder;", cs = "Ljava/lang/CharSequence;", pending = "Landroid/app/PendingIntent;",
			pm = "Landroid/content/pm/PackageManager;", nm = "Landroid/app/NotificationManager;";
		inline function set(r:Refs, name:String, param:String, reg:Int)
			return invoke(INVOKE_VIRTUAL, r.method(builder, name, builder, [param]), [4, reg]);
		return {
			name: cls,
			access: Dex.PUBLIC | Dex.FINAL,
			superName: base,
			interfaces: [],
			fields: [],
			methods: [
				constructor(base),
				{
					// (v0 scratch, v1 the id, v2 the title, v3 the body, v4 the
					// builder, v5-v7 the tap's; p0 v8, the context v9, the intent v10)
					name: "onReceive",
					ret: "V",
					params: [context, INTENT],
					access: Dex.PUBLIC,
					code: {
						registers: 11,
						ins: 3,
						outs: 4,
						insns: r -> {
							var extra = r.method(INTENT, "getStringExtra", STRING, [STRING]);
							var c = [];
							for (reg => k in ["id", "title", "body"])
								c = c.concat(constString(0, r, k)).concat(invoke(INVOKE_VIRTUAL, extra, [10, 0])).concat([moveResultObject(reg + 1)]);
							c.concat(typed(NEW_INSTANCE, 4, r.type(builder)))
								.concat(constString(0, r, "default"))
								.concat(invoke(INVOKE_DIRECT, r.method(builder, "<init>", "V", [context, STRING]), [4, 9, 0]))
								.concat(set(r, "setContentTitle", cs, 2))
								.concat(set(r, "setContentText", cs, 3))
								.concat([const4(0, 1)])
								.concat(set(r, "setAutoCancel", "Z", 0))
								.concat(invoke(INVOKE_VIRTUAL, r.method(context, "getApplicationInfo", "Landroid/content/pm/ApplicationInfo;", []), [9]))
								.concat([moveResultObject(0)])
								.concat([op(0, 0, 0x52), r.field("Landroid/content/pm/ApplicationInfo;", "icon", "I")]) // iget v0, v0, icon
								.concat(ifNez(0, 5))
								.concat([(0 << 8) | 0x14, ICON & 0xffff, ICON >>> 16]) // const v0, @android:drawable/ic_dialog_info
								.concat(set(r, "setSmallIcon", "I", 0))
								.concat(invoke(INVOKE_VIRTUAL, r.method(context, "getPackageManager", pm, []), [9]))
								.concat([moveResultObject(5)])
								.concat(invoke(INVOKE_VIRTUAL, r.method(context, "getPackageName", STRING, []), [9]))
								.concat([moveResultObject(6)])
								.concat(invoke(INVOKE_VIRTUAL, r.method(pm, "getLaunchIntentForPackage", INTENT, [STRING]), [5, 6]))
								.concat([moveResultObject(5)])
								.concat(constString(0, r, "hxmc.notification"))
								.concat(invoke(INVOKE_VIRTUAL, r.method(INTENT, "putExtra", INTENT, [STRING, STRING]), [5, 0, 1]))
								.concat([(0 << 8) | 0x15, 0x2000]) // const/high16 v0, FLAG_ACTIVITY_SINGLE_TOP
								.concat(invoke(INVOKE_VIRTUAL, r.method(INTENT, "addFlags", INTENT, ["I"]), [5, 0]))
								.concat(invoke(INVOKE_VIRTUAL, r.method(STRING, "hashCode", "I", []), [1]))
								.concat([moveResult(6)])
								.concat([(7 << 8) | 0x15, 0x0c00]) // const/high16 v7, FLAG_UPDATE_CURRENT | FLAG_IMMUTABLE
								.concat(invoke(INVOKE_STATIC, r.method(pending, "getActivity", pending, [context, "I", INTENT, "I"]), [9, 6, 5, 7]))
								.concat([moveResultObject(5)])
								.concat(set(r, "setContentIntent", pending, 5))
								.concat(constString(0, r, "notification"))
								.concat(invoke(INVOKE_VIRTUAL, r.method(context, "getSystemService", OBJECT, [STRING]), [9, 0]))
								.concat([moveResultObject(5)])
								.concat(typed(CHECK_CAST, 5, r.type(nm)))
								.concat(invoke(INVOKE_VIRTUAL, r.method(builder, "build", "Landroid/app/Notification;", []), [4]))
								.concat([moveResultObject(6), const4(0, 0)])
								.concat(invoke(INVOKE_VIRTUAL, r.method(nm, "notify", "V", [STRING, "I", "Landroid/app/Notification;"]), [5, 1, 0, 6]))
								.concat([RETURN_VOID]);
						}
					}
				}
			]
		};
	}

	// @android:drawable/ic_dialog_info: a notification's icon when the app has none
	static inline var ICON = 0x0108009b;

	static function files():DexClass {
		var cls = "Lorg/hxmc/Files;", base = "Landroid/content/ContentProvider;", file = "Ljava/io/File;", cursor = "Landroid/database/MatrixCursor;",
			values = "Landroid/content/ContentValues;", strings = "[Ljava/lang/String;", fd = "Landroid/os/ParcelFileDescriptor;";
		var allowed = r -> r.field(cls, "allowed", SET);
		// (the uri's path into v0; v1 whether it is allowed)
		var allowedPath = (r:Refs, uri:Int) -> invoke(INVOKE_VIRTUAL, r.method(URI, "getPath", STRING, []), [uri])
			.concat([moveResultObject(0)])
			.concat(typed(SGET_OBJECT, 1, allowed(r)))
			.concat(invoke(INVOKE_INTERFACE, r.method(SET, "contains", "Z", [OBJECT]), [1, 0]))
			.concat([moveResult(1)]);
		return {
			name: cls,
			access: Dex.PUBLIC | Dex.FINAL,
			superName: base,
			interfaces: [],
			fields: [{name: "allowed", type: SET, access: Dex.PUBLIC | Dex.STATIC}],
			methods: [
				{
					name: "<clinit>",
					ret: "V",
					params: [],
					access: Dex.STATIC | Dex.CONSTRUCTOR,
					code: {
						registers: 1,
						ins: 0,
						outs: 1,
						insns: r -> typed(NEW_INSTANCE, 0, r.type("Ljava/util/HashSet;"))
							.concat(invoke(INVOKE_DIRECT, r.method("Ljava/util/HashSet;", "<init>", "V", []), [0]))
							.concat(typed(SPUT_OBJECT, 0, allowed(r)))
							.concat([RETURN_VOID])
					}
				},
				constructor(base),
				{
					name: "onCreate",
					ret: "Z",
					params: [],
					access: Dex.PUBLIC,
					code: {registers: 2, ins: 1, outs: 0, insns: r -> [const4(0, 1), returnInt(0)]}
				},
				{
					name: "getType",
					ret: STRING,
					params: [URI],
					access: Dex.PUBLIC,
					code: {
						registers: 3,
						ins: 2,
						outs: 1,
						insns: r -> invoke(INVOKE_VIRTUAL, r.method(URI, "getPath", STRING, []), [2])
							.concat([moveResultObject(0)])
							.concat(invoke(INVOKE_STATIC, r.method("Ljava/net/URLConnection;", "guessContentTypeFromName", STRING, [STRING]), [0]))
							.concat([moveResultObject(0), returnObject(0)])
					}
				},
				{
					// (v0 the path, v1, v2 the mode; p0 v3, the uri v4, its mode v5)
					name: "openFile",
					ret: fd,
					params: [URI, STRING],
					access: Dex.PUBLIC,
					code: {
						registers: 6,
						ins: 3,
						outs: 2,
						insns: r -> allowedPath(r, 4)
							.concat(ifEqz(1, 16))
							.concat(typed(NEW_INSTANCE, 1, r.type(file)))
							.concat(invoke(INVOKE_DIRECT, r.method(file, "<init>", "V", [STRING]), [1, 0]))
							.concat(invoke(INVOKE_STATIC, r.method(fd, "parseMode", "I", [STRING]), [5]))
							.concat([moveResult(2)])
							.concat(invoke(INVOKE_STATIC, r.method(fd, "open", fd, [file, "I"]), [1, 2]))
							.concat([moveResultObject(1), returnObject(1)])
							.concat(typed(NEW_INSTANCE, 1, r.type("Ljava/io/FileNotFoundException;")))
							.concat(invoke(INVOKE_DIRECT, r.method("Ljava/io/FileNotFoundException;", "<init>", "V", [STRING]), [1, 0]))
							.concat([(1 << 8) | 0x27]) // throw v1
					}
				},
				{
					// (a row of the file's name and size; v0 the path, v1 the file, v2 an
					// index, v3 an array, v4 a value, v5 the cursor, v6-v7 the size; p0 v8, the uri v9)
					name: "query",
					ret: "Landroid/database/Cursor;",
					params: [URI, strings, STRING, strings, STRING],
					access: Dex.PUBLIC,
					code: {
						registers: 14,
						ins: 6,
						outs: 2,
						insns: r -> allowedPath(r, 9)
							.concat(ifNez(1, 4))
							.concat([const4(1, 0), returnObject(1)])
							.concat(typed(NEW_INSTANCE, 1, r.type(file)))
							.concat(invoke(INVOKE_DIRECT, r.method(file, "<init>", "V", [STRING]), [1, 0]))
							.concat([const4(2, 2)])
							.concat(newArray(3, 2, r.type(strings)))
							.concat([const4(2, 0)])
							.concat(constString(4, r, "_display_name"))
							.concat(aputObject(4, 3, 2))
							.concat([const4(2, 1)])
							.concat(constString(4, r, "_size"))
							.concat(aputObject(4, 3, 2))
							.concat(typed(NEW_INSTANCE, 5, r.type(cursor)))
							.concat(invoke(INVOKE_DIRECT, r.method(cursor, "<init>", "V", [strings]), [5, 3]))
							.concat([const4(2, 2)])
							.concat(newArray(3, 2, r.type("[Ljava/lang/Object;")))
							.concat(invoke(INVOKE_VIRTUAL, r.method(file, "getName", STRING, []), [1]))
							.concat([moveResultObject(4), const4(2, 0)])
							.concat(aputObject(4, 3, 2))
							.concat(invoke(INVOKE_VIRTUAL, r.method(file, "length", "J", []), [1]))
							.concat([(6 << 8) | 0x0b]) // move-result-wide v6
							.concat(invoke(INVOKE_STATIC, r.method("Ljava/lang/Long;", "valueOf", "Ljava/lang/Long;", ["J"]), [6, 7]))
							.concat([moveResultObject(4), const4(2, 1)])
							.concat(aputObject(4, 3, 2))
							.concat(invoke(INVOKE_VIRTUAL, r.method(cursor, "addRow", "V", ["[Ljava/lang/Object;"]), [5, 3]))
							.concat([returnObject(5)])
					}
				},
				zero("insert", URI, [URI, values]),
				zero("delete", "I", [URI, STRING, strings]),
				zero("update", "I", [URI, values, STRING, strings])
			]
		};
	}

	// a class of an id (its constructor's int) whose methods each call a
	// static native with the id and an argument: a parameter's register, or
	// a constant (v1; p0 this is v2)
	static function idClass(name:String, base:String, interfaces:Array<String>, native:DexMethod, methods:Array<DexMethod>):DexClass
		return {
			name: name,
			access: Dex.PUBLIC | Dex.FINAL,
			superName: base,
			interfaces: interfaces,
			fields: [{name: "id", type: "I", access: Dex.PRIVATE | Dex.FINAL}],
			methods: ([
				{
					name: "<init>",
					ret: "V",
					params: ["I"],
					access: Dex.PUBLIC | Dex.CONSTRUCTOR,
					code: {
						registers: 2,
						ins: 2,
						outs: 1,
						insns: (r:Refs) -> invoke(INVOKE_DIRECT, r.method(base, "<init>", "V", []), [0]).concat([op(1, 0, 0x59), r.field(name, "id", "I"), RETURN_VOID])
					}
				},
				native
			] : Array<DexMethod>).concat(methods)
		};

	// (iget v0, p0, id; then native(v0, v1 the constant, or the parameter p1: v3))
	static function idCall(cls:String, method:String, params:Array<String>, native:DexMethod, ?constant:Int):DexMethod
		return {
			name: method,
			ret: "V",
			params: params,
			access: Dex.PUBLIC,
			code: {
				registers: 3 + params.length,
				ins: 1 + params.length,
				outs: 2,
				insns: r -> [op(0, 2, 0x52), r.field(cls, "id", "I")].concat(constant == null ? [] : [const4(1, constant)])
					.concat(invoke(INVOKE_STATIC, r.method(cls, native.name, "V", native.params), [0, constant == null ? 3 : 1]))
					.concat([RETURN_VOID])
			}
		};

	static function locator():DexClass {
		var cls = "Lorg/hxmc/Locator;";
		var located:DexMethod = {name: "located", ret: "V", params: ["I", OBJECT], access: Dex.PUBLIC | Dex.STATIC | Dex.NATIVE};
		return idClass(cls, OBJECT, ["Landroid/location/LocationListener;", "Ljava/util/function/Consumer;"], located, [
			idCall(cls, "onLocationChanged", ["Landroid/location/Location;"], located),
			idCall(cls, "accept", [OBJECT], located),
			nothing("onProviderEnabled", [STRING]),
			nothing("onProviderDisabled", [STRING]),
			nothing("onStatusChanged", [STRING, "I", "Landroid/os/Bundle;"])
		]);
	}

	static function biometric():DexClass {
		var cls = "Lorg/hxmc/Biometric;", prompt = "Landroid/hardware/biometrics/BiometricPrompt";
		var done:DexMethod = {name: "done", ret: "V", params: ["I", "I"], access: Dex.PUBLIC | Dex.STATIC | Dex.NATIVE};
		return idClass(cls, prompt + "$AuthenticationCallback;", ["Landroid/content/DialogInterface$OnClickListener;"], done, [
			idCall(cls, "onAuthenticationSucceeded", [prompt + "$AuthenticationResult;"], done, 1),
			idCall(cls, "onAuthenticationError", ["I", "Ljava/lang/CharSequence;"], done, 0),
			idCall(cls, "onClick", ["Landroid/content/DialogInterface;", "I"], done, 0)
		]);
	}

	// a listener method calling event(id, kind, p1, a, b): v0 the id, v1 the
	// kind, v2 and v3 for the arguments (0 unless `prepare` sets them), the
	// parameters after them (p0 this: v4); a boolean result is event's != 0
	static function forward(name:String, params:Array<String>, kind:Int, a:Int, b:Int, ?ret:String, ?prepare:Refs->Array<Int>, ?cls:String, obj = 5):DexMethod {
		ret = ret ?? "V";
		cls = cls ?? GLUE;
		var ins = 1 + params.length;
		return {
			name: name,
			ret: ret,
			params: params,
			access: Dex.PUBLIC,
			code: {
				registers: 4 + ins,
				ins: ins,
				outs: 5,
				insns: r -> {
					var c = [op(0, 4, 0x52), r.field(cls, "id", "I"), (1 << 8) | 0x13, kind, const4(2, 0), const4(3, 0)]; // iget v0, p0, id; const/16 v1, kind
					if (prepare != null) c = c.concat(prepare(r));
					c = c.concat(invoke(INVOKE_STATIC, r.method(cls, "event", "I", ["I", "I", OBJECT, "I", "I"]), [0, 1, obj, a, b]));
					c.concat(ret == "Z" ? [moveResult(0), const4(1, 0), 0x0038, 3, const4(1, 1), (1 << 8) | 0x0f] : [RETURN_VOID]); // if-eqz v0, +3; return v1
				}
			}
		};
	}

	static inline function nothing(name:String, params:Array<String>):DexMethod
		return {
			name: name,
			ret: "V",
			params: params,
			access: Dex.PUBLIC,
			code: {registers: 1 + params.length, ins: 1 + params.length, outs: 0, insns: r -> [RETURN_VOID]}
		};

	// a class of an id (its constructor's int) and a static native event, as Glue
	static function withId(name:String, base:String, methods:Array<DexMethod>, ?natives:Array<DexMethod>):DexClass
		return {
			name: name,
			access: Dex.PUBLIC | Dex.FINAL,
			superName: base,
			interfaces: [],
			fields: [{name: "id", type: "I", access: Dex.PRIVATE | Dex.FINAL}],
			methods: [
				{
					name: "<init>",
					ret: "V",
					params: ["I"],
					access: Dex.PUBLIC | Dex.CONSTRUCTOR,
					code: {
						registers: 2,
						ins: 2,
						outs: 1,
						insns: r -> invoke(INVOKE_DIRECT, r.method(base, "<init>", "V", []), [0]).concat([op(1, 0, 0x59), r.field(name, "id", "I"), RETURN_VOID])
					}
				},
				{name: "event", ret: "I", params: ["I", "I", OBJECT, "I", "I"], access: Dex.PUBLIC | Dex.STATIC | Dex.NATIVE}
			].concat(natives ?? []).concat(methods)
		};

	static inline var WEB_VIEW = "Landroid/webkit/WebView;";
	static inline var WEB_REQUEST = "Landroid/webkit/WebResourceRequest;";
	static inline var WEB_RESPONSE = "Landroid/webkit/WebResourceResponse;";
	static inline var STRING = "Ljava/lang/String;";

	// org.hxmc.WebClient: a WebViewClient (p_i is v(4 + i))
	static function webClient():DexClass {
		var cls = "Lorg/hxmc/WebClient;", error = "Landroid/webkit/WebResourceError;";
		return withId(cls, "Landroid/webkit/WebViewClient;", [
			{
				// (v0 the id, p0 v1, the view v2, the request v3: intercept(id, request)'s response)
				name: "shouldInterceptRequest",
				ret: WEB_RESPONSE,
				params: [WEB_VIEW, WEB_REQUEST],
				access: Dex.PUBLIC,
				code: {
					registers: 4,
					ins: 3,
					outs: 2,
					insns: r -> [op(0, 1, 0x52), r.field(cls, "id", "I")].concat(invoke(INVOKE_STATIC, r.method(cls, "intercept", WEB_RESPONSE, ["I", WEB_REQUEST]), [0, 3]))
						.concat([(0 << 8) | 0x0c, (0 << 8) | 0x11]) // move-result-object v0; return-object v0
				}
			},
			forward("onPageStarted", [WEB_VIEW, STRING, "Landroid/graphics/Bitmap;"], WEB_STARTED, 2, 3, null, null, cls, 6),
			forward("onPageFinished", [WEB_VIEW, STRING], WEB_FINISHED, 2, 3, null, null, cls, 6),
			forward("doUpdateVisitedHistory", [WEB_VIEW, STRING, "Z"], WEB_NAVIGATED, 2, 3, null, null, cls, 6),
			forward("shouldOverrideUrlLoading", [WEB_VIEW, WEB_REQUEST], WEB_OVERRIDE, 2, 3, "Z", null, cls, 6),
			// (v2: the error's code, v3: 1 for the main frame's request)
			forward("onRenderProcessGone", [WEB_VIEW, "Landroid/webkit/RenderProcessGoneDetail;"], WEB_GONE, 2, 3, "Z", null, cls, 6),
			forward("onReceivedError", [WEB_VIEW, WEB_REQUEST, error], WEB_ERROR, 2, 3, null,
				r -> invoke(INVOKE_INTERFACE, r.method(WEB_REQUEST, "isForMainFrame", "Z", []), [6]).concat([moveResult(3)])
					.concat(invoke(INVOKE_VIRTUAL, r.method(error, "getErrorCode", "I", []), [7])).concat([moveResult(2)]), cls, 7)
		], [{name: "intercept", ret: WEB_RESPONSE, params: ["I", WEB_REQUEST], access: Dex.PUBLIC | Dex.STATIC | Dex.NATIVE}]);
	}

	// org.hxmc.WebChrome: a WebChromeClient
	static function webChrome():DexClass {
		var cls = "Lorg/hxmc/WebChrome;";
		return withId(cls, "Landroid/webkit/WebChromeClient;", [
			forward("onProgressChanged", [WEB_VIEW, "I"], WEB_PROGRESS, 6, 3, null, null, cls, 5),
			forward("onReceivedTitle", [WEB_VIEW, STRING], WEB_TITLE, 2, 3, null, null, cls, 6),
			forward("onConsoleMessage", ["Landroid/webkit/ConsoleMessage;"], WEB_CONSOLE, 2, 3, "Z", null, cls, 5)
		]);
	}

	// org.hxmc.WebBridge: post(String) for the page, its native on the bridge's thread
	static function webBridge():DexClass {
		var cls = "Lorg/hxmc/WebBridge;";
		var c = withId(cls, OBJECT, [
			{
				name: "post",
				ret: "V",
				params: [STRING],
				access: Dex.PUBLIC,
				annotations: ["Landroid/webkit/JavascriptInterface;"],
				code: {
					registers: 3,
					ins: 2,
					outs: 2,
					insns: r -> [op(0, 1, 0x52), r.field(cls, "id", "I")].concat(invoke(INVOKE_STATIC, r.method(cls, "message", "V", ["I", STRING]), [0, 2]))
						.concat([RETURN_VOID])
				}
			}
		], [{name: "message", ret: "V", params: ["I", STRING], access: Dex.PUBLIC | Dex.STATIC | Dex.NATIVE}]);
		return c;
	}

	static function glue():DexClass {
		var cs = "Ljava/lang/CharSequence;", seekBar = "Landroid/widget/SeekBar;";
		// (p_i is v(4 + i))
		inline function p(i:Int)
			return 4 + i;
		return {
			name: GLUE,
			access: Dex.PUBLIC | Dex.FINAL,
			superName: OBJECT,
			interfaces: [
				"Landroid/view/View$OnClickListener;", "Landroid/text/TextWatcher;", "Landroid/widget/CompoundButton$OnCheckedChangeListener;",
				"Landroid/widget/SeekBar$OnSeekBarChangeListener;", "Landroid/widget/TextView$OnEditorActionListener;", "Landroid/view/View$OnLayoutChangeListener;",
				"Landroid/view/SurfaceHolder$Callback;", "Landroid/view/View$OnKeyListener;"
			],
			fields: [{name: "id", type: "I", access: Dex.PRIVATE | Dex.FINAL}],
			methods: [
				{
					name: "<init>",
					ret: "V",
					params: ["I"],
					access: Dex.PUBLIC | Dex.CONSTRUCTOR,
					code: {
						registers: 2,
						ins: 2,
						outs: 1,
						insns: r -> invoke(INVOKE_DIRECT, r.method(OBJECT, "<init>", "V", []), [0]).concat([op(1, 0, 0x59), r.field(GLUE, "id", "I"), RETURN_VOID]) // iput v1, v0, id
					}
				},
				{name: "event", ret: "I", params: ["I", "I", OBJECT, "I", "I"], access: Dex.PRIVATE | Dex.STATIC | Dex.NATIVE},
				forward("onClick", [VIEW], CLICK, 2, 3),
				forward("afterTextChanged", ["Landroid/text/Editable;"], TEXT, 2, 3),
				nothing("beforeTextChanged", [cs, "I", "I", "I"]),
				nothing("onTextChanged", [cs, "I", "I", "I"]),
				forward("onCheckedChanged", ["Landroid/widget/CompoundButton;", "Z"], CHECKED, p(2), 3),
				forward("onProgressChanged", [seekBar, "I", "Z"], PROGRESS, p(2), p(3)),
				nothing("onStartTrackingTouch", [seekBar]),
				nothing("onStopTrackingTouch", [seekBar]),
				forward("onEditorAction", ["Landroid/widget/TextView;", "I", "Landroid/view/KeyEvent;"], EDITOR, p(2), 3, "Z"),
				// (sub-int v2, right, left; sub-int v3, bottom, top)
				forward("onLayoutChange", [VIEW, "I", "I", "I", "I", "I", "I", "I", "I"], LAYOUT, 2, 3, null,
					r -> [(2 << 8) | 0x91, (p(2) << 8) | p(4), (3 << 8) | 0x91, (p(3) << 8) | p(5)]),
				forward("surfaceCreated", [HOLDER], SURFACE_CREATED, 2, 3),
				forward("surfaceChanged", [HOLDER, "I", "I", "I"], SURFACE_CHANGED, p(3), p(4)),
				forward("surfaceDestroyed", [HOLDER], SURFACE_DESTROYED, 2, 3),
				// (v3: the event's getAction())
				forward("onKey", [VIEW, "I", "Landroid/view/KeyEvent;"], KEY, p(2), 3, "Z",
					r -> invoke(INVOKE_VIRTUAL, r.method("Landroid/view/KeyEvent;", "getAction", "I", []), [p(3)]).concat([moveResult(3)]))
			]
		};
	}
}
