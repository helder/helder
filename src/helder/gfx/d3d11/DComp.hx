package helder.gfx.d3d11;

import helder.os.windows.Com;
import hxmc.unsafe.*;

// DirectComposition (dcomp.dll, Windows 8 on): the device, a window's
// target and visuals, surfaces drawn by Direct3D 11. dcomp.h is C++ only,
// its overloads (a value or an animation) in the vtable in the reverse of
// their declaration (MSVC's), as mingw-w64's header has them for GCC: an
// animation's first, the value's after it.
@:hxmc.c @:hxmc.lib("dcomp") extern class DCompLib {
	static function DCompositionCreateDevice(dxgiDevice:Ptr, iid:Ptr, out:Ptr<Ptr>):Int;
}

// (DWM's: until its next composition is presented)
@:hxmc.c @:hxmc.lib("dwmapi") extern class Dwm {
	static function DwmFlush():Int;
}

// (a wait to a fraction of a millisecond: Sleep's is the system's tick, 15.6 ms
// by default; a high-resolution waitable timer, Windows 10 1803 on)
@:hxmc.c @:hxmc.lib("kernel32") extern class WaitTimer {
	static function CreateWaitableTimerExW(attributes:Ptr, name:Ptr, flags:Int, access:Int):Ptr;
	static function SetWaitableTimer(timer:Ptr, due:Ptr<Int32>, period:Int, routine:Ptr, arg:Ptr, resume:Int):Int;
	// (the Ex one: hxmc.unsafe.Win32 has WaitForSingleObject as a fast call, this wait blocks)
	static function WaitForSingleObjectEx(handle:Ptr, ms:Int, alertable:Int):Int;
}

@:build(helder.os.windows.Com.build())
@:hxmc.unsafe(gc)
class IDCompositionDevice {
	@:slot(3) static function Commit(self:Ptr):Int;
	// (DCOMPOSITION_FRAME_STATISTICS: lastFrameTime, the rate (two UINTs), currentTime, timeFrequency, nextEstimatedFrameTime)
	@:slot(5) static function GetFrameStatistics(self:Ptr, stats:Ptr):Int;
	@:slot(6) static function CreateTargetForHwnd(self:Ptr, hwnd:Ptr, topmost:Int, out:Ptr<Ptr>):Int;
	@:slot(7) static function CreateVisual(self:Ptr, out:Ptr<Ptr>):Int;
	@:slot(8) static function CreateSurface(self:Ptr, width:Int, height:Int, format:Int, alpha:Int, out:Ptr<Ptr>):Int;
	@:slot(23) static function CreateEffectGroup(self:Ptr, out:Ptr<Ptr>):Int;
	@:slot(24) static function CreateRectangleClip(self:Ptr, out:Ptr<Ptr>):Int;
	@:slot(26) static function CheckDeviceState(self:Ptr, valid:Ptr<Int32>):Int;
}

@:build(helder.os.windows.Com.build())
@:hxmc.unsafe(gc)
class IDCompositionTarget {
	@:slot(3) static function SetRoot(self:Ptr, visual:Ptr):Int;
}

@:build(helder.os.windows.Com.build())
@:hxmc.unsafe(gc)
class IDCompositionVisual {
	@:slot(4) static function SetOffsetX(self:Ptr, x:Float32):Int;
	@:slot(6) static function SetOffsetY(self:Ptr, y:Float32):Int;
	// (a D2D_MATRIX_3X2_F: _11, _12, _21, _22, _31, _32)
	@:slot(8) static function SetTransform(self:Ptr, matrix:Ptr<Float32>):Int;
	@:slot(10) static function SetEffect(self:Ptr, effect:Ptr):Int;
	@:slot(11) static function SetBitmapInterpolationMode(self:Ptr, mode:Int):Int;
	@:slot(12) static function SetBorderMode(self:Ptr, mode:Int):Int;
	@:slot(13) static function SetClipObject(self:Ptr, clip:Ptr):Int;
	// (a D2D_RECT_F: left, top, right, bottom)
	@:slot(14) static function SetClip(self:Ptr, rect:Ptr<Float32>):Int;
	@:slot(15) static function SetContent(self:Ptr, content:Ptr):Int;
	@:slot(16) static function AddVisual(self:Ptr, visual:Ptr, above:Int, reference:Ptr):Int;
	@:slot(17) static function RemoveVisual(self:Ptr, visual:Ptr):Int;
	@:slot(18) static function RemoveAllVisuals(self:Ptr):Int;
}

@:build(helder.os.windows.Com.build())
@:hxmc.unsafe(gc)
class IDCompositionSurface {
	// (update: a RECT or nil (all of it); the texture's interface; where the rectangle's corner is in it)
	@:slot(3) static function BeginDraw(self:Ptr, update:Ptr<Int32>, iid:Ptr, out:Ptr<Ptr>, offset:Ptr<Int32>):Int;
	@:slot(4) static function EndDraw(self:Ptr):Int;
}

@:build(helder.os.windows.Com.build())
@:hxmc.unsafe(gc)
class IDCompositionEffectGroup {
	@:slot(4) static function SetOpacity(self:Ptr, opacity:Float32):Int;
}

@:build(helder.os.windows.Com.build())
@:hxmc.unsafe(gc)
class IDCompositionRectangleClip {
	@:slot(4) static function SetLeft(self:Ptr, v:Float32):Int;
	@:slot(6) static function SetTop(self:Ptr, v:Float32):Int;
	@:slot(8) static function SetRight(self:Ptr, v:Float32):Int;
	@:slot(10) static function SetBottom(self:Ptr, v:Float32):Int;
	@:slot(12) static function SetTopLeftRadiusX(self:Ptr, v:Float32):Int;
	@:slot(14) static function SetTopLeftRadiusY(self:Ptr, v:Float32):Int;
	@:slot(16) static function SetTopRightRadiusX(self:Ptr, v:Float32):Int;
	@:slot(18) static function SetTopRightRadiusY(self:Ptr, v:Float32):Int;
	@:slot(20) static function SetBottomLeftRadiusX(self:Ptr, v:Float32):Int;
	@:slot(22) static function SetBottomLeftRadiusY(self:Ptr, v:Float32):Int;
	@:slot(24) static function SetBottomRightRadiusX(self:Ptr, v:Float32):Int;
	@:slot(26) static function SetBottomRightRadiusY(self:Ptr, v:Float32):Int;
}

// A window composed by DirectComposition (D3D11Backend, for the system's
// layers: helder.ui.layers.windows.Layers): its target (under the window's child
// windows: a native field stays over what is drawn, as before), a root
// visual, under it the window's own visual (its swap chain's frames) and
// what goes over that (the layers' stack)
@:hxmc.unsafe(gc)
class DcRoot {
	public final device:Ptr; // IDCompositionDevice
	public final target:Ptr;
	public final root:Ptr;
	public final window:Ptr;

	function new(device:Ptr, target:Ptr, root:Ptr, window:Ptr) {
		this.device = device;
		this.target = target;
		this.root = root;
		this.window = window;
	}

	static final IID_DEVICE = Com.guid(0xc37ea93a, 0xe7aa, 0x450d, [0xb1, 0x6f, 0x97, 0x46, 0xcb, 0x04, 0x07, 0xf3]);

	// (on the window's thread; null where there is no DirectComposition or a call fails)
	public static function make(dxgi:Ptr, hwnd:Ptr):Null<DcRoot> {
		var out:Ptr<Ptr> = LibC.malloc(8);
		inline function made(hr:Int):Ptr
			return hr < 0 ? Ptr.nil() : out.value;
		var d = made(DCompLib.DCompositionCreateDevice(dxgi, IID_DEVICE, out));
		if (d.isNull()) {
			LibC.free(out);
			Sys.println("helder.gfx: no DirectComposition device");
			return null;
		}
		var t = made(IDCompositionDevice.CreateTargetForHwnd(d, hwnd, 0, out));
		var r = t.isNull() ? Ptr.nil() : made(IDCompositionDevice.CreateVisual(d, out));
		var w = r.isNull() ? Ptr.nil() : made(IDCompositionDevice.CreateVisual(d, out));
		LibC.free(out);
		if (w.isNull() || IDCompositionVisual.AddVisual(r, w, 1, Ptr.nil()) < 0 || IDCompositionTarget.SetRoot(t, r) < 0) {
			for (o in [w, r, t, d])
				Com.release(o);
			Sys.println("helder.gfx: no DirectComposition target for the window");
			return null;
		}
		return new DcRoot(d, t, r, w);
	}

	public function dispose() {
		IDCompositionTarget.SetRoot(target, Ptr.nil());
		IDCompositionDevice.Commit(device);
		for (o in [window, root, target, device])
			Com.release(o);
	}
}
