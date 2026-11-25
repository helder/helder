package helder.gfx.d3d11;

import helder.gfx.*;
import helder.gfx.d3d11.D3D11;
import helder.gfx.d3d11.DComp;
import helder.os.win32.Com;
import helder.os.win32.Com.IUnknown;
import helder.os.Surface;
import hxmc.unsafe.*;

// The Direct3D 11 back end (Windows): a device and its immediate context,
// rendering to a window's flip-model swap chain (DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL,
// two RGBA8 buffers, resized with the window) or, headless, to an offscreen
// texture. The swap chain queues one frame at most: a window's frame waits
// for its frame latency object before it is drawn (waitFrame: the program's
// before it takes its input, the compositor's before it samples its
// offsets, else at beginFrame), so that its presents keep the display's
// pace, a frame never queued behind another. WARP (the system's software
// rasterizer) when HXMC_GFX_SOFTWARE=1 or when there is no hardware device.
// Shaders are HLSL compiled at run time (D3DCompile, entry point main,
// shader model 5.0, or 4.0 below feature level 11_0), vertex inputs at semantic TEXCOORD<location> (as
// SPIRV-Cross names them); a 32-bit float depth buffer of the target's
// size; a pipeline's state objects (rasterizer, depth, blend) made with it.
// A texture at slot n is a shader resource view at tn and its sampler at
// sn, in both stages. A render target has a render target view (a depth
// texture a depth-stencil view, its texture typeless), bound by a pass into
// it and unbound at its end; a texture of mip levels can GenerateMips.
// readPixels copies the target into a staging texture
// and maps it. With antialias a window's frame is multisampled (4 samples
// a pixel, when the device has them): its passes render into a
// multisampled colour texture and depth buffer of the back buffer's size,
// resolved into the back buffer before Present and readPixels; the frame's
// pipelines (no colorFormat) rasterize with MultisampleEnable. Uniform blocks: with Direct3D 11.1's constant buffer offsets
// (VSSetConstantBuffers1; WARP has them), a dynamic ring buffer written
// without overwriting (discarded at the frame's first block), else a
// dynamic constant buffer per slot, discarded at each setUniforms
// (HXMC_GFX_D3D11_NO_OFFSETS=1 forces that).
// The compute tier (feature level 11_0: cs_5_0): a storage buffer is a raw
// buffer (BUFFER_ALLOW_RAW_VIEWS, its elements loaded and stored by the
// HLSL at their std430 offsets) with a raw UAV (written: u<index>) and SRV
// (read: t<slot>), also bindable as a vertex or index buffer (an indirect
// buffer: DRAWINDIRECT_ARGS); a storage texture has a UAV. A compute pass
// binds them at each dispatch that follows a change and unbinds them at
// endCompute (so that draws may read them: Direct3D 11 orders the rest);
// readBuffer copies a range into a staging buffer and maps it.
// The system's layers (helder.ui.draw.DcLayers): a window asked to be
// composed (compose) has its swap chain made for composition, the content
// of a visual of a DirectComposition target on the window (DcRoot), the
// layers' visuals over it; a frame may be drawn into a surface of theirs
// (frameOnto: BeginDraw's texture, at its offset, never cleared whole: it
// may be an atlas of the system's), and the window's own frames then go
// unpresented (quiet).
@:hxmc.unsafe(gc)
class D3D11Backend {
	public final backend = Backend.D3D11;
	public var width(default, null) = 0;
	public var height(default, null) = 0;

	final surface:Surface;
	final device:Ptr; // ID3D11Device
	final context:Ptr; // ID3D11DeviceContext
	final shaderModel:String;
	var swapChain = Ptr.nil(); // IDXGISwapChain1 (a window)
	var target = Ptr.nil(); // ID3D11Texture2D: the back buffer, or the headless target
	var view = Ptr.nil(); // its ID3D11RenderTargetView
	var depth = Ptr.nil(); // the depth buffer (ID3D11Texture2D) and its ID3D11DepthStencilView
	var depthView = Ptr.nil();
	var samples = 1; // the frame's samples a pixel
	var msaa = Ptr.nil(); // multisampled: the frame's colour texture, view's
	var upload = Ptr.nil(); // writeBuffer's copy of the data, of uploadSize bytes
	var uploadSize = 0;
	var staging = Ptr.nil(); // readPixels' texture, of stagingWidth x stagingHeight
	var stagingWidth = 0;
	var stagingHeight = 0;
	// native memory: out-parameters, the clear colour, the viewport, the
	// vertex buffers bound at the next draw
	final scratch:Ptr<Ptr>;
	final clear:Ptr<Float32>;
	final viewport:Ptr<D3D11_VIEWPORT>;
	final mapped:Ptr<D3D11_MAPPED_SUBRESOURCE>;
	final box:Ptr<D3D11_BOX>;
	final vbufs:Ptr<Ptr>;
	final strides:Ptr<Int32>;
	final offsets:Ptr<Int32>;
	final cbuf:Ptr<Ptr>; // setUniforms' arguments
	final cfirst:Ptr<Int32>;
	final cnum:Ptr<Int32>;

	// tables (handle = index + 1)
	final buffers:Array<Ptr> = []; // ID3D11Buffer
	final bufferViews:Array<Ptr> = []; // a storage buffer's raw ID3D11ShaderResourceView, and its ID3D11UnorderedAccessView
	final bufferUavs:Array<Ptr> = [];
	final computes:Array<D3DCompute> = [];
	final textures:Array<D3DTexture> = [];
	final samplers:Array<Ptr> = []; // ID3D11SamplerState
	final shaders:Array<D3DShader> = [];
	final pipelines:Array<D3DPipeline> = [];

	// draw state
	var pipeline:D3DPipeline = null;
	var dirty = true;
	var offscreen = false; // the pass is into a texture
	var resolveFrom:Null<D3DTexture> = null; // a multisampled pass's colour, and what it resolves into
	var resolveInto:Null<D3DTexture> = null;
	// uniform blocks: the ID3D11DeviceContext1 (nil: no constant buffer
	// offsets), its ring and the next offset into it; else a buffer per slot
	var context1 = Ptr.nil();
	var ring = Ptr.nil();
	var cursor = 0;
	final slotBuffers:Array<Ptr> = [];
	final slotSizes:Array<Int> = [];
	// the compute pass: in one; its pipeline; each slot's storage buffer or
	// texture (handles), bound at the next dispatch; the UAVs and shader
	// resource views bound (unbound at endCompute: nils)
	var computing = false;
	var compute:Null<D3DCompute> = null;
	final storageSlots = [for (_ in 0...16) 0];
	final imageSlots = [for (_ in 0...16) 0];
	var storageDirty = false;
	final uavs:Ptr<Ptr>;
	final nils:Ptr<Ptr>;
	var uavsBound = 0;
	var srvsBound = 0; // (a mask of the compute stage's shader resource slots)
	var readback = Ptr.nil(); // readBuffer's staging buffer, of readbackSize bytes
	var readbackSize = 0;

	// frameInto's texture (0: the surface's); the headless target's size and
	// its view; the depth buffer's size; the shared textures this frame
	// holds the keyed mutex of (sampled, or drawn into: released at endFrame)
	var frameTarget = 0;
	var targetWidth = 0;
	var targetHeight = 0;
	var targetTexture = Ptr.nil();
	var targetView = Ptr.nil();
	var depthWidth = 0;
	var depthHeight = 0;
	final held:Array<D3DTexture> = [];
	// (the swap chain's back buffer, its view and size: a frame onto
	// another target leaves them as they are)
	var chainTarget = Ptr.nil();
	var chainView = Ptr.nil();
	var chainWidth = 0;
	var chainHeight = 0;
	// (frameOnto's: the texture, its view, where in it)
	var onto = Ptr.nil();
	var ontoView = Ptr.nil();
	var ontoX = 0;
	var ontoY = 0;
	var ontoWidth = 0;
	var ontoHeight = 0;

	// the next window's swap chain for DirectComposition, where it has it
	// (helder.ui's windows of system layers; read and cleared by the next
	// back end made); the window's composition (null: a swap chain of its own)
	public static var compose = false;

	public var composition(default, null):Null<DcRoot> = null;
	// the last hardware device made (nil: none, WARP's), where helder.media
	// decodes video (DXVA: a device of D3D11_CREATE_DEVICE_VIDEO_SUPPORT)
	public static var decoding(default, null) = Ptr.nil();
	// the window's own frames left unpresented: the system's layers are drawn from what they render into targets
	public var quiet = false;
	// (the swap chain's frame latency object (nil: none), and whether the next present waited for it)
	var latency = Ptr.nil();
	var waited = false;
	var occluded = false;
	// (the last Present's HRESULT: a test's probes)
	@:noCompletion public var presentResult(default, null) = 0;

	static inline var MAX_SLOTS = 8;

	public function new(surface:Surface, antialias:Bool) {
		this.surface = surface;
		scratch = LibC.malloc(64);
		clear = LibC.malloc(16);
		viewport = LibC.malloc(24);
		mapped = LibC.malloc(16);
		box = LibC.malloc(24);
		vbufs = LibC.malloc(8 * MAX_SLOTS);
		strides = LibC.malloc(4 * MAX_SLOTS);
		offsets = LibC.malloc(4 * MAX_SLOTS);
		LibC.memset(vbufs, 0, 8 * MAX_SLOTS);
		cbuf = LibC.malloc(8);
		cfirst = LibC.malloc(4);
		cnum = LibC.malloc(4);
		uavs = LibC.malloc(8 * 8);
		nils = LibC.malloc(8 * 16);
		LibC.memset(nils, 0, 8 * 16);
		var level:Ptr<Int32> = scratch.offset(2).raw();
		// (a transparent window's too: its alpha is DirectComposition's to compose)
		var composed = (compose || surface.transparent) && surface.kind == Win32;
		compose = false;
		#if hxmc.dev_host
		// (the host keeps the swap chain, not a composition of this build's)
		if (helder.dev.Hosted.hosted()) composed = false;
		// (hxmc dev's host: the device, its context and the window's swap chain as the last build left them)
		var keptDevice = surface.kind == Win32 && helder.dev.Hosted.hosted() ? helder.dev.Hosted.get(helder.dev.Hosted.D3D_DEVICE) : Ptr.nil();
		if (!keptDevice.isNull()) {
			device = keptDevice;
			context = helder.dev.Hosted.get(helder.dev.Hosted.D3D_CONTEXT);
			swapChain = helder.dev.Hosted.get(helder.dev.Hosted.D3D_SWAP_CHAIN);
			paced();
			shaderModel = ID3D11Device.GetFeatureLevel(device) >= D3D.FEATURE_LEVEL_11_0 ? "_5_0" : "_4_0";
			if (Sys.getEnv("HXMC_GFX_D3D11_NO_OFFSETS") != "1") offsetting();
			width = surface.width;
			height = surface.height;
			samples = sampling(antialias);
			backBuffer();
			return;
		}
		#end
		var flags = composed ? D3D.CREATE_DEVICE_BGRA_SUPPORT : 0;
		// (video support for helder.media's decoders, where the driver has it)
		var hr = Sys.getEnv("HXMC_GFX_SOFTWARE") == "1" ? -1 : createDevice(D3D.DRIVER_TYPE_HARDWARE, level, flags | D3D.CREATE_DEVICE_VIDEO_SUPPORT), video = hr >= 0;
		if (hr < 0 && Sys.getEnv("HXMC_GFX_SOFTWARE") != "1") hr = createDevice(D3D.DRIVER_TYPE_HARDWARE, level, flags);
		if (hr < 0) hr = createDevice(D3D.DRIVER_TYPE_WARP, level, flags);
		check(hr, "D3D11CreateDevice");
		device = scratch.value;
		if (video) decoding = device;
		context = scratch.offset(1).value;
		shaderModel = level.value >= D3D.FEATURE_LEVEL_11_0 ? "_5_0" : "_4_0";
		if (Sys.getEnv("HXMC_GFX_D3D11_NO_OFFSETS") != "1") offsetting();
		width = surface.width;
		height = surface.height;
		samples = sampling(antialias);
		if (surface.kind == Win32) {
			createSwapChain(composed);
			#if hxmc.dev_host
			if (helder.dev.Hosted.hosted()) {
				helder.dev.Hosted.set(helder.dev.Hosted.D3D_DEVICE, device);
				helder.dev.Hosted.set(helder.dev.Hosted.D3D_CONTEXT, context);
				helder.dev.Hosted.set(helder.dev.Hosted.D3D_SWAP_CHAIN, swapChain);
			}
			#end
		} else {
			Arena.scoped(a -> {
				var d = a.make(D3D11_TEXTURE2D_DESC);
				d.value.Width = width;
				d.value.Height = height;
				d.value.MipLevels = 1;
				d.value.ArraySize = 1;
				d.value.Format = D3D.FORMAT_R8G8B8A8_UNORM;
				d.value.SampleCount = 1;
				d.value.Usage = D3D.USAGE_DEFAULT;
				d.value.BindFlags = D3D.BIND_RENDER_TARGET;
				check(ID3D11Device.CreateTexture2D(device, d, Ptr.nil(), scratch), "CreateTexture2D");
			});
			target = scratch.value;
			createView();
			createDepth();
			targetWidth = width;
			targetHeight = height;
			targetTexture = target;
			targetView = view;
		}
	}

	// ---- shared textures: DXGI's shared handles, keyed mutexes (Device.createShared, openShared)

	public function sharing():Null<String>
		return "dxgi";

	// a render target of the frame's format with a keyed mutex (key 0: a
	// mutex both processes take), its legacy shared handle (a value any
	// process opens)
	public function createShared(w:Int, h:Int):Null<{id:Int, handle:String}> {
		var hr = Arena.scopedValue(a -> {
			var d = a.make(D3D11_TEXTURE2D_DESC);
			d.value.Width = w;
			d.value.Height = h;
			d.value.MipLevels = 1;
			d.value.ArraySize = 1;
			d.value.Format = D3D.FORMAT_R8G8B8A8_UNORM;
			d.value.SampleCount = 1;
			d.value.Usage = D3D.USAGE_DEFAULT;
			d.value.BindFlags = D3D.BIND_RENDER_TARGET | D3D.BIND_SHADER_RESOURCE;
			d.value.MiscFlags = D3D.RESOURCE_MISC_SHARED_KEYEDMUTEX;
			ID3D11Device.CreateTexture2D(device, d, Ptr.nil(), scratch);
		});
		if (hr < 0) return null;
		var tex = scratch.value;
		var t = new D3DTexture(tex, TextureInfo.of({width: w, height: h, renderTarget: true}));
		if (IUnknown.QueryInterface(tex, IID.IDXGIResource, scratch) < 0) {
			t.release();
			return null;
		}
		var res = scratch.value;
		hr = IDXGIResource.GetSharedHandle(res, scratch);
		Com.release(res);
		var handle = scratch.value;
		if (hr < 0 || IUnknown.QueryInterface(tex, IID.IDXGIKeyedMutex, scratch) < 0) {
			t.release();
			return null;
		}
		t.mutex = scratch.value;
		check(ID3D11Device.CreateRenderTargetView(device, tex, Ptr.nil(), scratch), "CreateRenderTargetView");
		t.rtv = scratch.value;
		check(ID3D11Device.CreateShaderResourceView(device, tex, Ptr.nil(), scratch), "CreateShaderResourceView");
		t.view = scratch.value;
		textures.push(t);
		return {id: textures.length, handle: "dxgi:" + Std.string(handle.toI64().toInt())};
	}

	public function openShared(handle:String, w:Int, h:Int):Int {
		if (StringTools.startsWith(handle, "mem:") || StringTools.startsWith(handle, "d3d11:")) return openPlane(handle, w, h);
		if (!StringTools.startsWith(handle, "dxgi:")) return 0;
		var n = Std.parseInt(handle.substr(5));
		if (n == null) return 0;
		if (ID3D11Device.OpenSharedResource(device, Ptr.ofI64(n), IID.ID3D11Texture2D, scratch) < 0) return 0;
		var tex = scratch.value;
		var t = new D3DTexture(tex, TextureInfo.of({width: w, height: h}));
		if (ID3D11Device.CreateShaderResourceView(device, tex, Ptr.nil(), scratch) < 0) {
			t.release();
			return 0;
		}
		t.view = scratch.value;
		if (IUnknown.QueryInterface(tex, IID.IDXGIKeyedMutex, scratch) >= 0) t.mutex = scratch.value;
		textures.push(t);
		return textures.length;
	}

	// (a video frame's plane, helder.media's: "mem:ADDRESS:PITCH:FORMAT:N",
	// its rows in memory copied into a texture of w x h (a software
	// decoder's); "d3d11:TEXTURE:SLICE:FORMAT:W:H:N", an NV12 or P010
	// texture on this device, viewed as it is where it is one slice that may
	// be sampled (helder.media's copy of a DXVA frame), else its slice's
	// W x H copied on the GPU first, the plane sampled by the view's format
	// (r8, rg8; r16, rg16): no copy on the CPU)
	function openPlane(handle:String, w:Int, h:Int):Int {
		var at = handle.split(":"), mem = at[0] == "mem";
		var format = switch at[3] {
			case "r8": D3D.FORMAT_R8_UNORM;
			case "rg8": D3D.FORMAT_R8G8_UNORM;
			case "r16": D3D.FORMAT_R16_UNORM;
			case "rg16": D3D.FORMAT_R16G16_UNORM;
			case _: 0;
		}
		if (format == 0 || at[1].length != 16) return 0;
		var p = address(at[1]);
		var hr = Arena.scopedValue(a -> {
			var d = a.make(D3D11_TEXTURE2D_DESC);
			d.value.MipLevels = 1;
			d.value.ArraySize = 1;
			d.value.SampleCount = 1;
			d.value.Usage = D3D.USAGE_DEFAULT;
			d.value.BindFlags = D3D.BIND_SHADER_RESOURCE;
			if (mem) {
				d.value.Width = w;
				d.value.Height = h;
				d.value.Format = format;
				var init = a.make(D3D11_SUBRESOURCE_DATA);
				init.value.pSysMem = p;
				init.value.SysMemPitch = Std.parseInt(at[2]) ?? 0;
				return ID3D11Device.CreateTexture2D(device, d, init, scratch);
			}
			ID3D11Texture2D.GetDesc(p, d);
			// (one slice that may be sampled (helder.media's copy out of the decoder's pool): viewed as it is)
			if (d.value.ArraySize == 1 && d.value.BindFlags & D3D.BIND_SHADER_RESOURCE != 0) {
				IUnknown.AddRef(p);
				scratch.value = p;
				return 0;
			}
			var fw = Std.parseInt(at[4]) ?? 0, fh = Std.parseInt(at[5]) ?? 0;
			d.value.Width = (fw + 1) & ~1;
			d.value.Height = (fh + 1) & ~1;
			d.value.ArraySize = 1;
			d.value.BindFlags = D3D.BIND_SHADER_RESOURCE;
			d.value.MiscFlags = 0;
			d.value.CPUAccessFlags = 0;
			d.value.Usage = D3D.USAGE_DEFAULT;
			var hr = ID3D11Device.CreateTexture2D(device, d, Ptr.nil(), scratch);
			if (hr < 0) return hr;
			var b = box;
			b.value.left = 0;
			b.value.top = 0;
			b.value.front = 0;
			b.value.right = d.value.Width;
			b.value.bottom = d.value.Height;
			b.value.back = 1;
			ID3D11DeviceContext.CopySubresourceRegion(context, scratch.value, 0, 0, 0, 0, p, Std.parseInt(at[2]) ?? 0, b);
			hr;
		});
		if (hr < 0) return 0;
		var tex = scratch.value;
		var t = new D3DTexture(tex, TextureInfo.of({width: w, height: h}));
		hr = Arena.scopedValue(a -> {
			// (D3D11_SHADER_RESOURCE_VIEW_DESC: the format, TEXTURE2D, its one level)
			var v:Ptr<Int32> = a.alloc(24);
			LibC.memset(v, 0, 24);
			v[0] = format;
			v[1] = 4;
			v[3] = 1;
			ID3D11Device.CreateShaderResourceView(device, tex, v, scratch);
		});
		if (hr < 0) {
			t.release();
			return 0;
		}
		t.view = scratch.value;
		textures.push(t);
		return textures.length;
	}

	// (16 hex digits)
	static function address(s:String):Ptr {
		var hi = 0, lo = 0;
		for (i in 0...16) {
			var c = s.charCodeAt(i), d = c <= 57 ? c - 48 : (c | 32) - 87;
			if (i < 8) hi = hi << 4 | d else lo = lo << 4 | d;
		}
		return Ptr.ofI64((cast haxe.Int64.make(hi, lo) : Int64));
	}

	public function frameInto(id:Int)
		frameTarget = id;

	// (a shared texture's keyed mutex taken for this frame: false, not in time)
	function hold(t:D3DTexture, ms:Int):Bool {
		if (t.mutex.isNull() || t.held) return true;
		// (0: taken; WAIT_TIMEOUT 0x102 and WAIT_ABANDONED 0x80 are not failures' HRESULTs)
		if (IDXGIKeyedMutex.AcquireSync(t.mutex, 0, ms) != 0) return false;
		t.held = true;
		held.push(t);
		return true;
	}

	function letGo() {
		for (t in held) {
			IDXGIKeyedMutex.ReleaseSync(t.mutex, 0);
			t.held = false;
		}
		held.resize(0);
	}

	// 4 with antialias in a window, when the device has them for the
	// frame's colour and depth formats; else 1
	function sampling(antialias:Bool):Int {
		if (!antialias || surface.kind != Win32) return 1;
		return Arena.scopedValue(a -> {
			var color:Ptr<Int32> = a.alloc(4), depth:Ptr<Int32> = a.alloc(4);
			var ok = ID3D11Device.CheckMultisampleQualityLevels(device, D3D.FORMAT_R8G8B8A8_UNORM, 4, color) >= 0
				&& ID3D11Device.CheckMultisampleQualityLevels(device, D3D.FORMAT_D32_FLOAT, 4, depth) >= 0;
			ok && color.value > 0 && depth.value > 0 ? 4 : 1;
		});
	}

	// the context's 11.1 interface, if constant buffers take offsets there
	function offsetting() {
		if (IUnknown.QueryInterface(context, IID.ID3D11DeviceContext1, scratch) < 0) return;
		var c1 = scratch.value;
		var ok = Arena.scopedValue(a -> {
			var o:Ptr<Int32> = a.alloc(56);
			LibC.memset(o, 0, 56);
			ID3D11Device.CheckFeatureSupport(device, D3D.FEATURE_D3D11_OPTIONS, o, 56) >= 0 && o[7] != 0 && o[8] != 0;
		});
		if (ok) context1 = c1 else Com.release(c1);
	}

	// the device and its context into scratch[0] and [1]
	function createDevice(driver:Int, level:Ptr<Int32>, flags:Int):Int
		return D3D11.D3D11CreateDevice(Ptr.nil(), driver, Ptr.nil(), flags, Ptr.nil(), 0, D3D.SDK_VERSION, scratch, level, scratch.offset(1));

	function check(hr:Int, what:String)
		if (hr < 0) throw "helder.gfx: " + what + " failed (HRESULT 0x" + StringTools.hex(hr, 8) + ")";

	// the window's swap chain, from the factory of the device's adapter;
	// composed: for a DirectComposition visual on the window, where it can
	function createSwapChain(composed:Bool) {
		check(IUnknown.QueryInterface(device, IID.IDXGIDevice, scratch), "QueryInterface(IDXGIDevice)");
		var dxgi = scratch.value;
		var hr = IDXGIDevice.GetAdapter(dxgi, scratch);
		check(hr, "IDXGIDevice::GetAdapter");
		var adapter = scratch.value;
		hr = IDXGIAdapter.GetParent(adapter, IID.IDXGIFactory2, scratch);
		Com.release(adapter);
		check(hr, "IDXGIAdapter::GetParent(IDXGIFactory2)");
		var factory = scratch.value;
		// (made on the window's thread, the main one where the program has its
		// own: DXGI may send the window messages as it hooks it, which a
		// thread waiting for the program would not serve: helder.os.OsThread)
		hr = helder.os.OsThread.get(() -> Arena.scopedValue(a -> {
			var d = a.make(DXGI_SWAP_CHAIN_DESC1);
			d.value.Width = width;
			d.value.Height = height;
			d.value.Format = D3D.FORMAT_R8G8B8A8_UNORM;
			d.value.SampleCount = 1;
			d.value.BufferUsage = D3D.USAGE_RENDER_TARGET_OUTPUT;
			d.value.BufferCount = 2;
			d.value.Scaling = D3D.SCALING_STRETCH;
			// (sequential: Present1's dirty rectangles are a flip-sequential
			// chain's; on a flip-discard one DWM kept an earlier frame's glyph, #98)
			d.value.SwapEffect = D3D.SWAP_EFFECT_FLIP_SEQUENTIAL;
			d.value.Flags = D3D.SWAP_CHAIN_FLAG_FRAME_LATENCY_WAITABLE_OBJECT;
			var root = composed ? DcRoot.make(dxgi, surface.handle) : null;
			if (root != null) {
				d.value.AlphaMode = surface.transparent ? D3D.ALPHA_MODE_PREMULTIPLIED : D3D.ALPHA_MODE_IGNORE;
				var hr = IDXGIFactory2.CreateSwapChainForComposition(factory, device, d, Ptr.nil(), scratch);
				if (hr >= 0 && IDCompositionVisual.SetContent(root.window, scratch.value) >= 0 && IDCompositionDevice.Commit(root.device) >= 0) {
					composition = root;
					return hr;
				}
				Sys.println("helder.gfx: no swap chain for DirectComposition (HRESULT 0x" + StringTools.hex(hr, 8) + "): the window's own");
				if (hr >= 0) Com.release(scratch.value);
				root.dispose();
				d.value.AlphaMode = 0;
				if (surface.transparent) Sys.println("helder.gfx: the window opaque: no DirectComposition for its alpha");
				surface.see(false);
			}
			var hr = IDXGIFactory2.CreateSwapChainForHwnd(factory, device, surface.handle, d, Ptr.nil(), Ptr.nil(), scratch);
			if (hr >= 0) IDXGIFactory2.MakeWindowAssociation(factory, surface.handle, D3D.MWA_NO_ALT_ENTER);
			hr;
		}));
		Com.release(dxgi);
		Com.release(factory);
		check(hr, "CreateSwapChainForHwnd");
		swapChain = scratch.value;
		paced();
		backBuffer();
	}

	// (one frame queued at most, its latency object kept; none where the
	// swap chain was made without it: a build's under hxmc dev's host)
	function paced() {
		if (IUnknown.QueryInterface(swapChain, IID.IDXGISwapChain2, scratch) < 0) return;
		var c = scratch.value;
		if (IDXGISwapChain2.SetMaximumFrameLatency(c, 1) >= 0) latency = IDXGISwapChain2.GetFrameLatencyWaitableObject(c);
		Com.release(c);
	}

	// until the swap chain takes a frame without queueing it behind another
	// (once a present: a frame that waited goes on; at most 100 ms, a
	// hidden window's)
	public function waitFrame() {
		if (latency.isNull() || waited) return;
		waited = true;
		WaitTimer.WaitForSingleObjectEx(latency, 100, 1);
	}

	// (whether the next frame's wait is the swap chain's: a frame was just
	// presented and shown, its latency object signalled at the next vblank)
	public function paces():Bool
		return !latency.isNull() && !waited && !occluded;

	function backBuffer() {
		check(IDXGISwapChain1.GetBuffer(swapChain, 0, IID.ID3D11Texture2D, scratch), "IDXGISwapChain1::GetBuffer");
		target = scratch.value;
		if (samples > 1) createMsaa();
		createView();
		createDepth();
		chainTarget = target;
		chainView = view;
		chainWidth = width;
		chainHeight = height;
	}

	// (one texel of tex at x, y, 0xAABBGGRR: a system layer of one colour, a test's)
	public function writeTexel(tex:Ptr, x:Int, y:Int, abgr:Int) {
		var b = box;
		b.value.left = x;
		b.value.top = y;
		b.value.front = 0;
		b.value.right = x + 1;
		b.value.bottom = y + 1;
		b.value.back = 1;
		Arena.scoped(a -> {
			var px:Ptr<Int32> = a.alloc(4);
			px[0] = abgr;
			ID3D11DeviceContext.UpdateSubresource(context, tex, 0, b, px, 4, 4);
		});
	}

	// the next frame into tex (a texture of the system's: a DirectComposition
	// surface's), its w x h pixels at x, y in it; nil: the window's again
	public function frameOnto(tex:Ptr, x:Int, y:Int, w:Int, h:Int) {
		onto = tex;
		ontoX = x;
		ontoY = y;
		ontoWidth = w;
		ontoHeight = h;
	}

	function createView() {
		check(ID3D11Device.CreateRenderTargetView(device, samples > 1 ? msaa : target, Ptr.nil(), scratch), "CreateRenderTargetView");
		view = scratch.value;
	}

	// the frame's multisampled colour texture, of the back buffer's size
	function createMsaa() {
		Arena.scoped(a -> {
			var d = a.make(D3D11_TEXTURE2D_DESC);
			d.value.Width = width;
			d.value.Height = height;
			d.value.MipLevels = 1;
			d.value.ArraySize = 1;
			d.value.Format = D3D.FORMAT_R8G8B8A8_UNORM;
			d.value.SampleCount = samples;
			d.value.Usage = D3D.USAGE_DEFAULT;
			d.value.BindFlags = D3D.BIND_RENDER_TARGET;
			check(ID3D11Device.CreateTexture2D(device, d, Ptr.nil(), scratch), "CreateTexture2D (multisampled)");
		});
		msaa = scratch.value;
	}

	// (multisampled: the frame's samples into the back buffer, before it is shown or read)
	function resolve()
		if (samples > 1) ID3D11DeviceContext.ResolveSubresource(context, target, 0, msaa, 0, D3D.FORMAT_R8G8B8A8_UNORM);

	// the depth buffer, of the target's size
	function createDepth() {
		Com.release(depthView);
		Com.release(depth);
		Arena.scoped(a -> {
			var d = a.make(D3D11_TEXTURE2D_DESC);
			d.value.Width = width;
			d.value.Height = height;
			d.value.MipLevels = 1;
			d.value.ArraySize = 1;
			d.value.Format = D3D.FORMAT_D32_FLOAT;
			d.value.SampleCount = samples;
			d.value.Usage = D3D.USAGE_DEFAULT;
			d.value.BindFlags = D3D.BIND_DEPTH_STENCIL;
			check(ID3D11Device.CreateTexture2D(device, d, Ptr.nil(), scratch), "CreateTexture2D (depth)");
		});
		depth = scratch.value;
		check(ID3D11Device.CreateDepthStencilView(device, depth, Ptr.nil(), scratch), "CreateDepthStencilView");
		depthView = scratch.value;
		depthWidth = width;
		depthHeight = height;
	}

	public function createBuffer(d:BufferDesc):Int {
		var data = d.data, size = d.size;
		if (data != null && data.length < size) throw "helder.gfx: createBuffer: data has fewer than size bytes";
		var storage = d.usage == Storage || d.usage == Indirect;
		if (storage && !has(Compute)) throw "helder.gfx: createBuffer: storage buffers need feature level 11_0";
		var hr = Arena.scopedValue(a -> {
			var desc = a.make(D3D11_BUFFER_DESC);
			// (constant buffers: a multiple of 16 bytes; raw ones of 4)
			desc.value.ByteWidth = d.usage == Uniform ? (size + 15) & ~15 : storage ? (size + 3) & ~3 : size;
			desc.value.Usage = D3D.USAGE_DEFAULT;
			desc.value.BindFlags = switch d.usage {
				case Index: D3D.BIND_INDEX_BUFFER;
				case Uniform: D3D.BIND_CONSTANT_BUFFER;
				case Storage: D3D.BIND_UNORDERED_ACCESS | D3D.BIND_SHADER_RESOURCE | D3D.BIND_VERTEX_BUFFER | D3D.BIND_INDEX_BUFFER;
				case Indirect: D3D.BIND_UNORDERED_ACCESS | D3D.BIND_SHADER_RESOURCE;
				case _: D3D.BIND_VERTEX_BUFFER;
			}
			desc.value.MiscFlags = d.usage == Indirect ? D3D.RESOURCE_MISC_BUFFER_ALLOW_RAW_VIEWS | D3D.RESOURCE_MISC_DRAWINDIRECT_ARGS : storage ? D3D.RESOURCE_MISC_BUFFER_ALLOW_RAW_VIEWS : 0;
			var init:Ptr<D3D11_SUBRESOURCE_DATA> = Ptr.nil();
			if (data != null) {
				init = a.make(D3D11_SUBRESOURCE_DATA);
				init.value.pSysMem = a.copyBytes(data, 0, size);
			}
			ID3D11Device.CreateBuffer(device, desc, init, scratch);
		});
		check(hr, "CreateBuffer (" + size + " bytes)");
		var b = scratch.value;
		buffers.push(b);
		bufferViews.push(Ptr.nil());
		bufferUavs.push(Ptr.nil());
		if (storage) {
			// (raw views of all of it: R32_TYPELESS, a 4-byte element each)
			var n = ((size + 3) & ~3) >> 2;
			hr = Arena.scopedValue(a -> {
				var v:Ptr<Int32> = a.alloc(32);
				LibC.memset(v, 0, 32);
				v[0] = D3D.FORMAT_R32_TYPELESS;
				v[1] = D3D.SRV_DIMENSION_BUFFEREX;
				v[3] = n;
				v[4] = D3D.BUFFEREX_SRV_FLAG_RAW;
				ID3D11Device.CreateShaderResourceView(device, b, v, scratch);
			});
			check(hr, "CreateShaderResourceView (a storage buffer)");
			bufferViews[buffers.length - 1] = scratch.value;
			hr = Arena.scopedValue(a -> {
				var v:Ptr<Int32> = a.alloc(32);
				LibC.memset(v, 0, 32);
				v[0] = D3D.FORMAT_R32_TYPELESS;
				v[1] = D3D.UAV_DIMENSION_BUFFER;
				v[3] = n;
				v[4] = D3D.BUFFER_UAV_FLAG_RAW;
				ID3D11Device.CreateUnorderedAccessView(device, b, v, scratch);
			});
			check(hr, "CreateUnorderedAccessView (a storage buffer)");
			bufferUavs[buffers.length - 1] = scratch.value;
		}
		return buffers.length;
	}

	public function writeBuffer(id:Int, offset:Int, data:haxe.io.Bytes, dataOffset:Int, size:Int) {
		// (a copy first: the Bytes may move during the call)
		if (uploadSize < size) {
			LibC.free(upload);
			upload = LibC.malloc((size : Int64));
			uploadSize = size;
		}
		LibC.memcpy(upload, BytesPtr.of(data, dataOffset, size), (size : Int64));
		box.value.left = offset;
		box.value.right = offset + size;
		box.value.top = 0;
		box.value.bottom = 1;
		box.value.front = 0;
		box.value.back = 1;
		ID3D11DeviceContext.UpdateSubresource(context, buffers[id - 1], 0, box, upload, 0, 0);
	}

	public function createTexture(d:TextureDesc):Int {
		// (a depth texture: typeless, its depth-stencil view and shader resource view typed)
		var info = TextureInfo.of(d), format = info.format, levels = info.levels, target = info.target;
		var depth = format.depth, mips = levels > 1 && format.filterable && !format.compressed, multi = info.samples > 1;
		var hr = Arena.scopedValue(a -> {
			var t = a.make(D3D11_TEXTURE2D_DESC);
			t.value.Width = info.width;
			t.value.Height = info.height;
			t.value.MipLevels = levels;
			t.value.ArraySize = info.layers;
			t.value.Format = dxgiFormat(format);
			t.value.SampleCount = info.samples;
			t.value.Usage = D3D.USAGE_DEFAULT;
			// (GenerateMips draws into the levels; a multisampled texture is only drawn into and resolved)
			t.value.BindFlags = (multi ? 0 : D3D.BIND_SHADER_RESOURCE) | (depth ? D3D.BIND_DEPTH_STENCIL : target || mips ? D3D.BIND_RENDER_TARGET : 0)
				| (info.storage ? D3D.BIND_UNORDERED_ACCESS : 0);
			t.value.MiscFlags = (mips ? D3D.RESOURCE_MISC_GENERATE_MIPS : 0) | (info.cube ? D3D.RESOURCE_MISC_TEXTURECUBE : 0);
			ID3D11Device.CreateTexture2D(device, t, Ptr.nil(), scratch);
		});
		check(hr, "CreateTexture2D (" + info.width + "x" + info.height + ")");
		var tex = scratch.value;
		var t = new D3DTexture(tex, info);
		textures.push(t);
		if (!multi) {
			hr = Arena.scopedValue(a -> {
				var v:Ptr<Int32> = Ptr.nil();
				if (depth) {
					v = a.alloc(32);
					LibC.memset(v, 0, 32);
					v[0] = format == Depth16 ? D3D.FORMAT_R16_UNORM : D3D.FORMAT_R32_FLOAT;
					v[1] = D3D.SRV_DIMENSION_TEXTURE2D;
					v[3] = levels; // (Texture2D.MostDetailedMip, MipLevels)
				} else if (info.cube || info.array) {
					// (a cube's view, or a 2D array's of every layer: TextureCube.MipLevels; Texture2DArray's MipLevels, FirstArraySlice, ArraySize)
					v = a.alloc(32);
					LibC.memset(v, 0, 32);
					v[0] = dxgiFormat(format);
					v[1] = info.cube ? D3D.SRV_DIMENSION_TEXTURECUBE : D3D.SRV_DIMENSION_TEXTURE2DARRAY;
					v[3] = levels;
					v[5] = info.layers;
				}
				ID3D11Device.CreateShaderResourceView(device, tex, v, scratch);
			});
			check(hr, "CreateShaderResourceView");
			t.view = scratch.value;
		}
		if (depth) {
			hr = Arena.scopedValue(a -> {
				var v:Ptr<Int32> = a.alloc(32);
				LibC.memset(v, 0, 32);
				v[0] = format == Depth16 ? D3D.FORMAT_D16_UNORM : D3D.FORMAT_D32_FLOAT;
				v[1] = multi ? D3D.DSV_DIMENSION_TEXTURE2DMS : D3D.DSV_DIMENSION_TEXTURE2D;
				ID3D11Device.CreateDepthStencilView(device, tex, v, scratch);
			});
			check(hr, "CreateDepthStencilView");
			t.dsv = scratch.value;
		} else if (target && (info.cube || info.array)) {
			// (a view a layer: Texture2DArray's MipSlice, FirstArraySlice, ArraySize)
			for (l in 0...info.layers) {
				hr = Arena.scopedValue(a -> {
					var v:Ptr<Int32> = a.alloc(32);
					LibC.memset(v, 0, 32);
					v[0] = dxgiFormat(format);
					v[1] = D3D.RTV_DIMENSION_TEXTURE2DARRAY;
					v[3] = l;
					v[4] = 1;
					ID3D11Device.CreateRenderTargetView(device, tex, v, scratch);
				});
				check(hr, "CreateRenderTargetView");
				t.layers.push(scratch.value);
			}
			t.rtv = t.layers[0];
		} else if (target) {
			check(ID3D11Device.CreateRenderTargetView(device, tex, Ptr.nil(), scratch), "CreateRenderTargetView");
			t.rtv = scratch.value;
		}
		if (info.storage) {
			check(ID3D11Device.CreateUnorderedAccessView(device, tex, Ptr.nil(), scratch), "CreateUnorderedAccessView");
			t.uav = scratch.value;
		}
		if (d.data != null)
			for (l in 0...info.layers)
				writeTexture(textures.length, d.data, 0, 0, -1, -1, l * format.levelBytes(info.width, info.height), 0, l);
		return textures.length;
	}

	static function dxgiFormat(format:TextureFormat):Int
		return switch format {
			case RGBA8: D3D.FORMAT_R8G8B8A8_UNORM;
			case RGBA8Srgb: D3D.FORMAT_R8G8B8A8_UNORM_SRGB;
			case R8: D3D.FORMAT_R8_UNORM;
			case RG8: D3D.FORMAT_R8G8_UNORM;
			case RGBA16F: D3D.FORMAT_R16G16B16A16_FLOAT;
			case R32F: D3D.FORMAT_R32_FLOAT;
			case RGBA32F: D3D.FORMAT_R32G32B32A32_FLOAT;
			case Depth16: D3D.FORMAT_R16_TYPELESS;
			case Depth32F: D3D.FORMAT_R32_TYPELESS;
			case BC1: D3D.FORMAT_BC1_UNORM;
			case BC3: D3D.FORMAT_BC3_UNORM;
			case ASTC4x4: throw "helder.gfx: D3D11 has no ASTC";
		}

	// whether the device samples a format: BC on every D3D11 GPU, no ASTC
	public function supports(f:TextureFormat):Bool
		return f != ASTC4x4;

	public function writeTexture(id:Int, data:haxe.io.Bytes, x:Int, y:Int, w:Int, h:Int, dataOffset:Int, level:Int, layer:Int) {
		var t = textures[id - 1], info = t.info;
		info.checkWrite(data, x, y, w, h, dataOffset, level, layer);
		// (the layer's level: its subresource)
		level += layer * info.levels;
		var n = info.format.texelSize;
		if (info.format.compressed) {
			// (a whole level: rows of blocks, no box)
			var f = info.format;
			Arena.scoped(a -> ID3D11DeviceContext.UpdateSubresource(context, t.texture, level, Ptr.nil(), a.copyBytes(data, dataOffset, f.levelBytes(info.w, info.h)),
				((info.w + 3) >> 2) * f.blockBytes, 0));
			return;
		}
		Arena.scoped(a -> {
			var box = a.make(D3D11_BOX);
			box.value.left = x;
			box.value.top = y;
			box.value.front = 0;
			box.value.right = x + info.w;
			box.value.bottom = y + info.h;
			box.value.back = 1;
			ID3D11DeviceContext.UpdateSubresource(context, t.texture, level, box, a.copyBytes(data, dataOffset, info.w * info.h * n), info.w * n, 0);
		});
	}

	public function generateMips(id:Int) {
		var t = textures[id - 1];
		t.info.checkMips();
		ID3D11DeviceContext.GenerateMips(context, t.view);
	}

	public function destroyBuffer(id:Int) {
		if (buffers[id - 1].isNull()) return;
		Com.release(bufferUavs[id - 1]);
		Com.release(bufferViews[id - 1]);
		Com.release(buffers[id - 1]);
		buffers[id - 1] = bufferViews[id - 1] = bufferUavs[id - 1] = Ptr.nil();
	}

	public function destroyTexture(id:Int) {
		var t = textures[id - 1];
		if (t == null) return;
		if (t.held) {
			IDXGIKeyedMutex.ReleaseSync(t.mutex, 0);
			held.remove(t);
		}
		if (frameTarget == id) frameTarget = 0;
		t.release();
		textures[id - 1] = null;
	}

	public function createSampler(d:SamplerDesc):Int {
		var hr = Arena.scopedValue(a -> {
			var s = a.make(D3D11_SAMPLER_DESC);
			s.value.Filter = (d.filter == Nearest ? D3D.FILTER_MIN_MAG_MIP_POINT : 0x14) | (d.mipFilter == Linear ? 1 : 0);
			var w = switch d.wrap {
				case null | Repeat: D3D.TEXTURE_ADDRESS_WRAP;
				case Clamp: D3D.TEXTURE_ADDRESS_CLAMP;
				case Mirror: D3D.TEXTURE_ADDRESS_MIRROR;
			}
			s.value.AddressU = w;
			s.value.AddressV = w;
			s.value.AddressW = w;
			s.value.MipLODBias = 0;
			s.value.MaxAnisotropy = 1;
			s.value.ComparisonFunc = D3D.COMPARISON_NEVER;
			s.value.BorderColor0 = 0;
			s.value.BorderColor1 = 0;
			s.value.BorderColor2 = 0;
			s.value.BorderColor3 = 0;
			s.value.MinLOD = 0;
			// (no mip filter: the first level only)
			s.value.MaxLOD = d.mipFilter == null ? 0 : 3.402823466e38;
			ID3D11Device.CreateSamplerState(device, s, scratch);
		});
		check(hr, "CreateSamplerState");
		samplers.push(scratch.value);
		return samplers.length;
	}

	public function createShader(d:ShaderDesc):Int {
		if (d.code.hlsl == null) throw "helder.gfx: createShader: no HLSL source for the D3D11 back end";
		if (d.stage == Compute) return createComputeShader(d);
		var vertex = d.stage == Vertex;
		scratch.offset(1).value = Ptr.nil();
		var hr = Arena.scopedValue(a -> {
			var src = a.cstring(d.code.hlsl), target = a.cstring((vertex ? "vs" : "ps") + shaderModel);
			D3DCompiler.D3DCompile(src, LibC.strlen(src), Ptr.nil(), Ptr.nil(), Ptr.nil(), Mem.cstr("main"), target, 0, 0, scratch, scratch.offset(1));
		});
		var errors = scratch.offset(1).value;
		var text:Ptr<UInt8> = errors.isNull() ? Ptr.nil() : ID3DBlob.GetBufferPointer(errors);
		var log = errors.isNull() ? "" : (text : CString).toString();
		Com.release(errors);
		if (hr < 0) throw "helder.gfx: the shader does not compile (HRESULT 0x" + StringTools.hex(hr, 8) + "):\n" + log;
		var blob = scratch.value;
		var code = ID3DBlob.GetBufferPointer(blob), size = ID3DBlob.GetBufferSize(blob);
		hr = vertex ? ID3D11Device.CreateVertexShader(device, code, size, Ptr.nil(), scratch) : ID3D11Device.CreatePixelShader(device, code, size,
			Ptr.nil(), scratch);
		if (hr < 0) Com.release(blob);
		check(hr, vertex ? "CreateVertexShader" : "CreatePixelShader");
		// (a vertex shader's code: its pipelines' input layouts are checked against it)
		if (!vertex) {
			Com.release(blob);
			blob = Ptr.nil();
		}
		shaders.push(new D3DShader(scratch.value, blob));
		return shaders.length;
	}

	// a compute shader (cs_5_0), its bindings kept for its pipelines
	function createComputeShader(d:ShaderDesc):Int {
		if (!has(Compute)) throw "helder.gfx: createShader: compute shaders need feature level 11_0";
		scratch.offset(1).value = Ptr.nil();
		var hr = Arena.scopedValue(a -> {
			var src = a.cstring(d.code.hlsl);
			D3DCompiler.D3DCompile(src, LibC.strlen(src), Ptr.nil(), Ptr.nil(), Ptr.nil(), Mem.cstr("main"), Mem.cstr("cs_5_0"), 0, 0, scratch, scratch.offset(1));
		});
		var errors = scratch.offset(1).value;
		var text:Ptr<UInt8> = errors.isNull() ? Ptr.nil() : ID3DBlob.GetBufferPointer(errors);
		var log = errors.isNull() ? "" : (text : CString).toString();
		Com.release(errors);
		if (hr < 0) throw "helder.gfx: the shader does not compile (HRESULT 0x" + StringTools.hex(hr, 8) + "):\n" + log;
		var blob = scratch.value;
		hr = ID3D11Device.CreateComputeShader(device, ID3DBlob.GetBufferPointer(blob), ID3DBlob.GetBufferSize(blob), Ptr.nil(), scratch);
		Com.release(blob);
		check(hr, "CreateComputeShader");
		var s = new D3DShader(scratch.value, Ptr.nil());
		s.bindings = d.code.bindings == null ? [] : d.code.bindings;
		shaders.push(s);
		return shaders.length;
	}

	// ---- the compute tier

	public function has(f:Feature):Bool
		return shaderModel == "_5_0";

	public function createComputePipeline(shader:Int):Int {
		var s = shaders[shader - 1];
		if (s.bindings == null) throw "helder.gfx: createComputePipeline: not a compute shader";
		computes.push(new D3DCompute(s.shader, s.bindings));
		return computes.length;
	}

	public function beginCompute() {
		if (computing) throw "helder.gfx: beginCompute: in a compute pass already";
		computing = true;
		compute = null;
	}

	public function setComputePipeline(id:Int) {
		var c = computes[id - 1];
		if (c == compute) return;
		compute = c;
		ID3D11DeviceContext.CSSetShader(context, c.shader, Ptr.nil(), 0);
		storageDirty = true;
	}

	public function setStorage(slot:Int, id:Int) {
		storageSlots[slot] = id;
		storageDirty = true;
	}

	public function setStorageTexture(slot:Int, id:Int) {
		imageSlots[slot] = id;
		storageDirty = true;
	}

	// the pipeline's storage at its registers: the written buffers' and
	// textures' UAVs at their indices first (a buffer the last dispatch wrote
	// and this one reads is no UAV any more: Direct3D 11 binds no view of a
	// resource bound as a UAV), then the read buffers' views at their slots
	function bindStorage() {
		if (!storageDirty) return;
		storageDirty = false;
		var c = compute, n = 0;
		for (b in c.bindings)
			switch b.kind {
				case StorageWrite:
					uavs[b.index] = bufferUavs[storageSlots[b.slot] - 1];
					if (b.index + 1 > n) n = b.index + 1;
				case StorageTexture:
					uavs[b.index] = textures[imageSlots[b.slot] - 1].uav;
					if (b.index + 1 > n) n = b.index + 1;
				case _:
			}
		// (the UAVs bound before past this pipeline's: unbound too)
		for (i in n...uavsBound)
			uavs[i] = Ptr.nil();
		if (uavsBound > n) n = uavsBound;
		if (n > 0) ID3D11DeviceContext.CSSetUnorderedAccessViews(context, 0, n, uavs, Ptr.nil());
		uavsBound = n;
		for (b in c.bindings)
			if (b.kind == Storage) {
				cbuf.value = bufferViews[storageSlots[b.slot] - 1];
				ID3D11DeviceContext.CSSetShaderResources(context, b.slot, 1, cbuf);
				srvsBound |= 1 << b.slot;
			}
	}

	public function dispatch(x:Int, y:Int, z:Int) {
		bindStorage();
		ID3D11DeviceContext.Dispatch(context, x, y, z);
	}

	public function dispatchIndirect(id:Int, offset:Int) {
		bindStorage();
		ID3D11DeviceContext.DispatchIndirect(context, buffers[id - 1], offset);
	}

	// (the storage unbound: draws may read it next; the uniform blocks and textures stay)
	public function endCompute() {
		if (uavsBound > 0) ID3D11DeviceContext.CSSetUnorderedAccessViews(context, 0, uavsBound, nils, Ptr.nil());
		for (slot in 0...16)
			if (srvsBound & (1 << slot) != 0) ID3D11DeviceContext.CSSetShaderResources(context, slot, 1, nils);
		uavsBound = srvsBound = 0;
		computing = false;
		storageDirty = true;
	}

	public function drawIndirect(id:Int, offset:Int) {
		vertexBuffers();
		ID3D11DeviceContext.DrawInstancedIndirect(context, buffers[id - 1], offset);
	}

	public function drawIndexedIndirect(id:Int, offset:Int) {
		vertexBuffers();
		ID3D11DeviceContext.DrawIndexedInstancedIndirect(context, buffers[id - 1], offset);
	}

	// a range copied into a staging buffer (as big as the largest read yet), mapped (waits for the GPU)
	public function readBuffer(id:Int, offset:Int, dst:haxe.io.Bytes, dstOffset:Int, size:Int) {
		if (size == 0) return;
		if (readbackSize < size) {
			Com.release(readback);
			var hr = Arena.scopedValue(a -> {
				var desc = a.make(D3D11_BUFFER_DESC);
				desc.value.ByteWidth = size;
				desc.value.Usage = D3D.USAGE_STAGING;
				desc.value.BindFlags = 0;
				desc.value.CPUAccessFlags = D3D.CPU_ACCESS_READ;
				ID3D11Device.CreateBuffer(device, desc, Ptr.nil(), scratch);
			});
			check(hr, "CreateBuffer (staging, " + size + " bytes)");
			readback = scratch.value;
			readbackSize = size;
		}
		box.value.left = offset;
		box.value.right = offset + size;
		box.value.top = 0;
		box.value.bottom = 1;
		box.value.front = 0;
		box.value.back = 1;
		ID3D11DeviceContext.CopySubresourceRegion(context, readback, 0, 0, 0, 0, buffers[id - 1], 0, box);
		check(ID3D11DeviceContext.Map(context, readback, 0, D3D.MAP_READ, 0, mapped), "Map (readBuffer)");
		BytesPtr.copyIn(dst, dstOffset, mapped.value.pData, size);
		ID3D11DeviceContext.Unmap(context, readback, 0);
	}

	public function createPipeline(d:PipelineDesc):Int {
		if (d.layout.length > MAX_SLOTS) throw "helder.gfx: more than " + MAX_SLOTS + " vertex buffers";
		var vs = shaders[d.vertex.id() - 1], ps = shaders[d.fragment.id() - 1];
		var count = 0;
		for (l in d.layout)
			count += l.attributes.length;
		var hr = Arena.scopedValue(a -> {
			var e = a.makeArray(D3D11_INPUT_ELEMENT_DESC, count), i = 0;
			var semantic = Mem.cstr("TEXCOORD");
			for (slot in 0...d.layout.length)
				for (at in d.layout[slot].attributes) {
					var el = e.offset(i++);
					el.value.SemanticName = semantic;
					el.value.SemanticIndex = at.location;
					el.value.Format = switch at.format {
						case Float1: D3D.FORMAT_R32_FLOAT;
						case Float2: D3D.FORMAT_R32G32_FLOAT;
						case Float3: D3D.FORMAT_R32G32B32_FLOAT;
						case Float4: D3D.FORMAT_R32G32B32A32_FLOAT;
						case UByte4Norm: D3D.FORMAT_R8G8B8A8_UNORM;
					}
					el.value.InputSlot = slot;
					el.value.AlignedByteOffset = at.offset;
					// (an instance buffer's elements advance once per instance)
					var instanced = d.layout[slot].step == Instance;
					el.value.InputSlotClass = instanced ? D3D.INPUT_PER_INSTANCE_DATA : D3D.INPUT_PER_VERTEX_DATA;
					el.value.InstanceDataStepRate = instanced ? 1 : 0;
				}
			ID3D11Device.CreateInputLayout(device, e, count, ID3DBlob.GetBufferPointer(vs.code), ID3DBlob.GetBufferSize(vs.code), scratch);
		});
		check(hr, "CreateInputLayout");
		var layout = scratch.value;
		hr = Arena.scopedValue(a -> {
			var r = a.make(D3D11_RASTERIZER_DESC);
			r.value.FillMode = D3D.FILL_SOLID;
			r.value.CullMode = switch d.cull {
				case null | None: D3D.CULL_NONE;
				case Front: D3D.CULL_FRONT;
				case Back: D3D.CULL_BACK;
			}
			// (GL's front faces)
			r.value.FrontCounterClockwise = 1;
			r.value.DepthClipEnable = 1;
			r.value.MultisampleEnable = samples > 1 && d.colorFormat == null ? 1 : 0;
			ID3D11Device.CreateRasterizerState(device, r, scratch);
		});
		if (hr < 0) Com.release(layout);
		check(hr, "CreateRasterizerState");
		var rasterizer = scratch.value;
		hr = Arena.scopedValue(a -> {
			var s = a.make(D3D11_DEPTH_STENCIL_DESC);
			var c:Compare = d.depthCompare == null ? Always : d.depthCompare, write = d.depthWrite == true;
			// (no test: nothing written either)
			s.value.DepthEnable = c == Always && !write ? 0 : 1;
			s.value.DepthWriteMask = write ? 1 : 0;
			s.value.DepthFunc = D3D.COMPARISON_NEVER + (cast c : Int);
			s.value.StencilEnable = 0;
			s.value.StencilReadMask = 0xFF;
			s.value.StencilWriteMask = 0xFF;
			s.value.FrontStencilFailOp = s.value.FrontStencilDepthFailOp = s.value.FrontStencilPassOp = D3D.STENCIL_OP_KEEP;
			s.value.BackStencilFailOp = s.value.BackStencilDepthFailOp = s.value.BackStencilPassOp = D3D.STENCIL_OP_KEEP;
			s.value.FrontStencilFunc = s.value.BackStencilFunc = D3D.COMPARISON_ALWAYS;
			ID3D11Device.CreateDepthStencilState(device, s, scratch);
		});
		check(hr, "CreateDepthStencilState");
		var depthState = scratch.value;
		hr = Arena.scopedValue(a -> {
			var b:Ptr<D3D11_BLEND_DESC> = a.alloc(264);
			LibC.memset(b, 0, 264);
			var blend:Blend = d.blend == null ? Opaque : d.blend;
			b.value.BlendEnable = blend == Opaque ? 0 : 1;
			var multiply = blend == Multiply;
			b.value.SrcBlend = multiply ? D3D.BLEND_DEST_COLOR : blend == Premultiplied || blend == Additive ? D3D.BLEND_ONE : D3D.BLEND_SRC_ALPHA;
			b.value.DestBlend = multiply ? D3D.BLEND_ZERO : blend == Additive ? D3D.BLEND_ONE : D3D.BLEND_INV_SRC_ALPHA;
			b.value.BlendOp = D3D.BLEND_OP_ADD;
			b.value.SrcBlendAlpha = multiply ? D3D.BLEND_ZERO : D3D.BLEND_ONE;
			b.value.DestBlendAlpha = blend == Additive || multiply ? D3D.BLEND_ONE : D3D.BLEND_INV_SRC_ALPHA;
			b.value.BlendOpAlpha = D3D.BLEND_OP_ADD;
			b.value.RenderTargetWriteMask = 0xF;
			ID3D11Device.CreateBlendState(device, b, scratch);
		});
		check(hr, "CreateBlendState");
		pipelines.push(new D3DPipeline(vs.shader, ps.shader, layout, rasterizer, depthState, scratch.value, d));
		return pipelines.length;
	}

	public function beginFrame():Bool {
		cursor = 0;
		if (!onto.isNull()) {
			// (no depth: the texture may be larger than the frame, an atlas)
			if (ID3D11Device.CreateRenderTargetView(device, onto, Ptr.nil(), scratch) < 0) return false;
			ontoView = scratch.value;
			target = onto;
			view = ontoView;
			width = ontoWidth;
			height = ontoHeight;
			return true;
		}
		if (frameTarget != 0) {
			// (into a texture: its view the frame's, the depth buffer of its size; a shared one's mutex held to endFrame)
			var t = textures[frameTarget - 1];
			if (!hold(t, 2000)) return false;
			target = t.texture;
			view = t.rtv;
			width = t.info.width;
			height = t.info.height;
			if (depthWidth != width || depthHeight != height) createDepth();
			return true;
		}
		if (swapChain.isNull()) {
			target = targetTexture;
			view = targetView;
			width = targetWidth;
			height = targetHeight;
			if (depthWidth != width || depthHeight != height) createDepth();
			return true;
		}
		waitFrame();
		target = chainTarget;
		view = chainView;
		width = chainWidth;
		height = chainHeight;
		if (depthWidth != width || depthHeight != height) createDepth();
		if (surface.width == width && surface.height == height) return true;
		// the window was resized: the swap chain's buffers follow
		ID3D11DeviceContext.OMSetRenderTargets(context, 0, Ptr.nil(), Ptr.nil());
		Com.release(view);
		Com.release(msaa);
		Com.release(target);
		var hr = IDXGISwapChain1.ResizeBuffers(swapChain, 0, surface.width, surface.height, D3D.FORMAT_UNKNOWN,
			latency.isNull() ? 0 : D3D.SWAP_CHAIN_FLAG_FRAME_LATENCY_WAITABLE_OBJECT);
		check(hr, "IDXGISwapChain1::ResizeBuffers");
		width = surface.width;
		height = surface.height;
		backBuffer();
		return true;
	}

	public function beginPass(p:PassDesc) {
		passQueries = p.queries == null ? 0 : p.queries.id();
		// (a flip-model swap chain unbinds its buffer at each Present)
		var c = p.colors[0], d = p.depth, rtv = view, dsv = onto.isNull() ? depthView : Ptr.nil(), w = width, h = height;
		offscreen = c.texture != null;
		if (offscreen) {
			var t = textures[c.texture.id() - 1];
			var layer = c.layer == null ? 0 : c.layer;
			t.info.checkPass(d, layer);
			if (t.info.samples > 1 || c.resolve != null)
				t.info.checkSamples(d == null ? null : textures[d.texture.id() - 1].info, c.resolve == null ? null : textures[c.resolve.id() - 1].info);
			resolveFrom = c.resolve == null ? null : t;
			resolveInto = c.resolve == null ? null : textures[c.resolve.id() - 1];
			rtv = t.layers.length > 0 ? t.layers[layer] : t.rtv;
			dsv = d == null ? Ptr.nil() : textures[d.texture.id() - 1].dsv;
			w = t.info.width;
			h = t.info.height;
		}
		scratch.value = rtv;
		ID3D11DeviceContext.OMSetRenderTargets(context, 1, scratch, dsv);
		viewport.value.TopLeftX = offscreen ? 0 : ontoX;
		viewport.value.TopLeftY = offscreen ? 0 : ontoY;
		viewport.value.Width = w;
		viewport.value.Height = h;
		viewport.value.MinDepth = 0;
		viewport.value.MaxDepth = 1;
		ID3D11DeviceContext.RSSetViewports(context, 1, viewport);
		if (c.load != Load && (offscreen || onto.isNull())) {
			var k = c.clear;
			clear[0] = k == null ? 0 : k.r;
			clear[1] = k == null ? 0 : k.g;
			clear[2] = k == null ? 0 : k.b;
			clear[3] = k == null ? 1 : k.a;
			ID3D11DeviceContext.ClearRenderTargetView(context, rtv, clear);
		}
		if (d != null && d.load != Load) ID3D11DeviceContext.ClearDepthStencilView(context, dsv, D3D.CLEAR_DEPTH, d.clear == null ? 1 : d.clear, 0);
		pipeline = null;
		dirty = true;
	}

	public function setPipeline(id:Int) {
		var p = pipelines[id - 1];
		if (p == pipeline) return;
		pipeline = p;
		ID3D11DeviceContext.VSSetShader(context, p.vs, Ptr.nil(), 0);
		ID3D11DeviceContext.PSSetShader(context, p.ps, Ptr.nil(), 0);
		ID3D11DeviceContext.IASetInputLayout(context, p.layout);
		ID3D11DeviceContext.IASetPrimitiveTopology(context, p.topology);
		ID3D11DeviceContext.RSSetState(context, p.rasterizer);
		ID3D11DeviceContext.OMSetDepthStencilState(context, p.depth, 0);
		ID3D11DeviceContext.OMSetBlendState(context, p.blend, Ptr.nil(), -1);
		dirty = true;
	}

	public function setVertexBuffer(slot:Int, id:Int, offset:Int) {
		vbufs[slot] = buffers[id - 1];
		offsets[slot] = offset;
		dirty = true;
	}

	public function setUniforms(slot:Int, data:haxe.io.Bytes, offset:Int, size:Int) {
		if (offset < 0 || size < 0 || offset + size > data.length) throw "helder.gfx: setUniforms: outside the data";
		// (constant buffers: whole 256-byte blocks of 16 constants)
		var n = (size + 255) & ~255;
		if (!context1.isNull()) {
			if (cursor + n > Encoder.UNIFORM_RING) throw "helder.gfx: setUniforms: more than " + Encoder.UNIFORM_RING + " bytes of uniforms in a frame";
			if (ring.isNull()) ring = dynamicBuffer(Encoder.UNIFORM_RING);
			check(ID3D11DeviceContext.Map(context, ring, 0, cursor == 0 ? D3D.MAP_WRITE_DISCARD : D3D.MAP_WRITE_NO_OVERWRITE, 0, mapped), "Map");
			LibC.memcpy((mapped.value.pData : Ptr<UInt8>).add(cursor), BytesPtr.of(data, offset, size), (size : Int64));
			ID3D11DeviceContext.Unmap(context, ring, 0);
			cbuf.value = ring;
			cfirst.value = cursor >> 4;
			cnum.value = n >> 4;
			if (computing) ID3D11DeviceContext1.CSSetConstantBuffers1(context1, slot, 1, cbuf, cfirst, cnum) else {
				ID3D11DeviceContext1.VSSetConstantBuffers1(context1, slot, 1, cbuf, cfirst, cnum);
				ID3D11DeviceContext1.PSSetConstantBuffers1(context1, slot, 1, cbuf, cfirst, cnum);
			}
			cursor += n;
			return;
		}
		while (slotBuffers.length <= slot) {
			slotBuffers.push(Ptr.nil());
			slotSizes.push(0);
		}
		if (slotSizes[slot] < n) {
			Com.release(slotBuffers[slot]);
			slotBuffers[slot] = dynamicBuffer(n);
			slotSizes[slot] = n;
		}
		var b = slotBuffers[slot];
		check(ID3D11DeviceContext.Map(context, b, 0, D3D.MAP_WRITE_DISCARD, 0, mapped), "Map");
		LibC.memcpy(mapped.value.pData, BytesPtr.of(data, offset, size), (size : Int64));
		ID3D11DeviceContext.Unmap(context, b, 0);
		cbuf.value = b;
		if (computing) ID3D11DeviceContext.CSSetConstantBuffers(context, slot, 1, cbuf) else {
			ID3D11DeviceContext.VSSetConstantBuffers(context, slot, 1, cbuf);
			ID3D11DeviceContext.PSSetConstantBuffers(context, slot, 1, cbuf);
		}
	}

	// a constant buffer the CPU writes (Map)
	function dynamicBuffer(size:Int):Ptr {
		var hr = Arena.scopedValue(a -> {
			var desc = a.make(D3D11_BUFFER_DESC);
			desc.value.ByteWidth = size;
			desc.value.Usage = D3D.USAGE_DYNAMIC;
			desc.value.BindFlags = D3D.BIND_CONSTANT_BUFFER;
			desc.value.CPUAccessFlags = D3D.CPU_ACCESS_WRITE;
			ID3D11Device.CreateBuffer(device, desc, Ptr.nil(), scratch);
		});
		check(hr, "CreateBuffer (uniforms, " + size + " bytes)");
		return scratch.value;
	}

	public function draw(vertices:Int, instances:Int, first:Int) {
		vertexBuffers();
		if (instances == 1) ID3D11DeviceContext.Draw(context, vertices, first) else
			ID3D11DeviceContext.DrawInstanced(context, vertices, instances, first, 0);
	}

	public function setTexture(slot:Int, texture:Int, sampler:Int) {
		var t = textures[texture - 1];
		// (another process's texture: its mutex held while this frame samples it; not in time, sampled as it is)
		if (!t.mutex.isNull()) hold(t, 100);
		cbuf.value = t.view;
		if (computing) {
			ID3D11DeviceContext.CSSetShaderResources(context, slot, 1, cbuf);
			cbuf.value = samplers[sampler - 1];
			ID3D11DeviceContext.CSSetSamplers(context, slot, 1, cbuf);
			return;
		}
		ID3D11DeviceContext.VSSetShaderResources(context, slot, 1, cbuf);
		ID3D11DeviceContext.PSSetShaderResources(context, slot, 1, cbuf);
		cbuf.value = samplers[sampler - 1];
		ID3D11DeviceContext.VSSetSamplers(context, slot, 1, cbuf);
		ID3D11DeviceContext.PSSetSamplers(context, slot, 1, cbuf);
	}

	public function setIndexBuffer(id:Int, format:IndexFormat, offset:Int)
		ID3D11DeviceContext.IASetIndexBuffer(context, buffers[id - 1], format == UInt16 ? D3D.FORMAT_R16_UINT : D3D.FORMAT_R32_UINT, offset);

	public function drawIndexed(count:Int, instances:Int, first:Int, baseVertex:Int) {
		vertexBuffers();
		if (instances == 1) ID3D11DeviceContext.DrawIndexed(context, count, first, baseVertex) else
			ID3D11DeviceContext.DrawIndexedInstanced(context, count, instances, first, baseVertex, 0);
	}

	// the vertex buffers, after a pipeline or vertex buffer change
	function vertexBuffers() {
		if (!dirty) return;
		// (the strides are the pipeline's: bound with its buffers at the first draw)
		var p = pipeline;
		for (i in 0...p.strides.length)
			strides[i] = p.strides[i];
		if (p.strides.length > 0) ID3D11DeviceContext.IASetVertexBuffers(context, 0, p.strides.length, vbufs, strides, offsets);
		dirty = false;
	}

	// (a render target: unbound, so that it can be sampled next)
	// ---- occlusion queries (D3D11_QUERY_OCCLUSION: the samples passed,
	// read by GetData without flushing): a set's queries, each one's state
	// (begun, its answer not yet read) and last answer (-1 none)
	final querySets:Array<Null<{queries:Array<Ptr>, pending:Array<Bool>, results:Array<Int>, stale:Array<Bool>}>> = [];
	var queryBytes:Ptr<Int32> = Ptr.nil();
	var passQueries = 0;
	var activeQuery = -1;

	public function createQueries(count:Int):Int {
		if (queryBytes.isNull()) queryBytes = LibC.malloc(16);
		var list = [];
		for (_ in 0...count) {
			queryBytes.value = 1;
			queryBytes.offset(1).value = 0;
			check(ID3D11Device.CreateQuery(device, queryBytes, scratch), "CreateQuery (occlusion)");
			list.push(scratch.value);
		}
		querySets.push({queries: list, pending: [for (_ in 0...count) false], results: [for (_ in 0...count) -1], stale: [for (_ in 0...count) false]});
		return querySets.length;
	}

	public function destroyQueries(id:Int) {
		var q = querySets[id - 1];
		if (q == null) return;
		for (p in q.queries)
			Com.release(p);
		querySets[id - 1] = null;
	}

	public function queryResult(id:Int, k:Int):Int {
		var q = querySets[id - 1];
		if (q == null || k < 0 || k >= q.queries.length) return -1;
		if (q.pending[k] && ID3D11DeviceContext.GetData(context, q.queries[k], queryBytes, 8, 1) == 0) {
			q.results[k] = q.stale[k] ? -1 : queryBytes.value != 0 || queryBytes.offset(1).value != 0 ? 1 : 0;
			q.pending[k] = q.stale[k] = false;
		}
		return q.results[k];
	}

	public function resetQuery(id:Int, k:Int) {
		var q = querySets[id - 1];
		if (q == null || k < 0 || k >= q.queries.length) return;
		q.results[k] = -1;
		if (q.pending[k]) q.stale[k] = true;
	}

	public function beginQuery(k:Int) {
		activeQuery = -1;
		var q = passQueries == 0 ? null : querySets[passQueries - 1];
		if (q == null || k < 0 || k >= q.queries.length) return;
		// (its last answer still to come: not begun again, so that one comes)
		if (q.pending[k]) {
			queryResult(passQueries, k);
			if (q.pending[k]) return;
		}
		ID3D11DeviceContext.Begin(context, q.queries[k]);
		activeQuery = k;
	}

	public function endQuery() {
		if (activeQuery < 0) return;
		var q = querySets[passQueries - 1];
		ID3D11DeviceContext.End(context, q.queries[activeQuery]);
		q.pending[activeQuery] = true;
		activeQuery = -1;
	}

	public function endPass() {
		passQueries = 0;
		if (offscreen) ID3D11DeviceContext.OMSetRenderTargets(context, 0, Ptr.nil(), Ptr.nil());
		// (a multisampled pass's colour into its resolve target)
		if (resolveFrom != null) {
			ID3D11DeviceContext.ResolveSubresource(context, resolveInto.texture, 0, resolveFrom.texture, 0, dxgiFormat(resolveFrom.info.format));
			resolveFrom = resolveInto = null;
		}
	}

	// (the next Present's changed rectangles: Device.damaged)
	var damage:Null<Array<Int>> = null;

	public function damaged(rects:Null<Array<Int>>)
		damage = rects;

	public function endFrame() {
		if (!onto.isNull()) {
			letGo();
			ID3D11DeviceContext.OMSetRenderTargets(context, 0, Ptr.nil(), Ptr.nil());
			Com.release(ontoView);
			ontoView = onto = Ptr.nil();
			ontoX = ontoY = 0;
			return;
		}
		if (swapChain.isNull() || frameTarget != 0) {
			// (the shared textures let go: ReleaseSync flushes)
			letGo();
			ID3D11DeviceContext.Flush(context);
			return;
		}
		letGo();
		if (quiet) {
			damage = null;
			return;
		}
		resolve();
		// (vsync; a lost device is not recovered yet; what changed told DXGI: Device.damaged)
		var r = damage, n = r == null ? 0 : Std.int(r.length / 4);
		damage = null;
		var hr = n == 0 ? IDXGISwapChain1.Present(swapChain, 1, 0) : Arena.scopedValue(a -> {
			// (DXGI_PRESENT_PARAMETERS: the count, its padding, then the rectangles', a scroll's pointers)
			var rects:Ptr<Int32> = a.alloc(16 * n), params:Ptr<Ptr> = a.alloc(32);
			for (i in 0...4 * n)
				rects[i] = r[i];
			params[1] = rects;
			params[2] = Ptr.nil();
			params[3] = Ptr.nil();
			params[0] = Ptr.ofI64(n);
			IDXGISwapChain1.Present1(swapChain, 1, 0, params);
		});
		waited = false;
		occluded = hr == D3D.DXGI_STATUS_OCCLUDED;
		presentResult = hr;
		if (hr == D3D.DXGI_ERROR_DEVICE_REMOVED || hr == D3D.DXGI_ERROR_DEVICE_RESET)
			check(ID3D11Device.GetDeviceRemovedReason(device), "Present: the device was removed");
	}

	public function readPixels(dst:haxe.io.Bytes) {
		var row = width * 4;
		if (dst.length < row * height) throw "helder.gfx: readPixels: " + row * height + " bytes needed";
		if (stagingWidth != width || stagingHeight != height) {
			Com.release(staging);
			Arena.scoped(a -> {
				var d = a.make(D3D11_TEXTURE2D_DESC);
				d.value.Width = width;
				d.value.Height = height;
				d.value.MipLevels = 1;
				d.value.ArraySize = 1;
				d.value.Format = D3D.FORMAT_R8G8B8A8_UNORM;
				d.value.SampleCount = 1;
				d.value.Usage = D3D.USAGE_STAGING;
				d.value.CPUAccessFlags = D3D.CPU_ACCESS_READ;
				check(ID3D11Device.CreateTexture2D(device, d, Ptr.nil(), scratch), "CreateTexture2D (staging)");
			});
			staging = scratch.value;
			stagingWidth = width;
			stagingHeight = height;
		}
		resolve();
		ID3D11DeviceContext.CopyResource(context, staging, target);
		// (waits for the GPU)
		check(ID3D11DeviceContext.Map(context, staging, 0, D3D.MAP_READ, 0, mapped), "Map");
		var src:Ptr<UInt8> = mapped.value.pData, pitch:Int = mapped.value.RowPitch;
		for (y in 0...height)
			BytesPtr.copyIn(dst, y * row, src.add(y * pitch), row);
		ID3D11DeviceContext.Unmap(context, staging, 0);
	}

	public function dispose() {
		// (no decoder opened later on a device let go)
		if (decoding == device) decoding = Ptr.nil();
		ID3D11DeviceContext.ClearState(context);
		ID3D11DeviceContext.Flush(context);
		for (p in pipelines) {
			Com.release(p.layout);
			Com.release(p.rasterizer);
			Com.release(p.depth);
			Com.release(p.blend);
		}
		for (s in shaders) {
			Com.release(s.shader);
			Com.release(s.code);
		}
		for (b in buffers)
			Com.release(b);
		for (v in bufferViews.concat(bufferUavs))
			Com.release(v);
		Com.release(readback);
		for (b in slotBuffers)
			Com.release(b);
		letGo();
		for (t in textures)
			if (t != null) t.release();
		for (s in samplers)
			Com.release(s);
		Com.release(ring);
		Com.release(context1);
		Com.release(staging);
		Com.release(depthView);
		Com.release(depth);
		// (headless: its own target, not a frameInto texture's; a window: its back buffer's)
		if (swapChain.isNull()) {
			view = targetView;
			target = targetTexture;
		} else {
			view = chainView;
			target = chainTarget;
		}
		Com.release(view);
		Com.release(msaa);
		Com.release(target);
		#if hxmc.dev_host
		// (handing over: the swap chain, the context and the device left to the next build)
		var keep = helder.dev.Hosted.handingOver && helder.dev.Hosted.get(helder.dev.Hosted.D3D_DEVICE) == device;
		if (!latency.isNull()) hxmc.unsafe.Win32.CloseHandle(latency);
		if (!keep) {
			if (composition != null) composition.dispose();
			Com.release(swapChain);
			Com.release(context);
			Com.release(device);
		}
		#else
		if (composition != null) composition.dispose();
		Com.release(swapChain);
		if (!latency.isNull()) hxmc.unsafe.Win32.CloseHandle(latency);
		Com.release(context);
		Com.release(device);
		#end
		LibC.free(scratch);
		LibC.free(clear);
		LibC.free(viewport);
		LibC.free(mapped);
		LibC.free(box);
		LibC.free(upload);
		LibC.free(vbufs);
		LibC.free(strides);
		LibC.free(offsets);
		LibC.free(cbuf);
		LibC.free(cfirst);
		LibC.free(cnum);
		LibC.free(uavs);
		LibC.free(nils);
	}
}

// a compiled shader (ID3D11VertexShader or ID3D11PixelShader) and, for a
// vertex shader, its code (an ID3DBlob)
@:hxmc.unsafe(gc)
private class D3DShader {
	public final shader:Ptr;
	public final code:Ptr;
	// (a compute shader's: its resources)
	public var bindings:Null<Array<ShaderBinding>> = null;

	public function new(shader:Ptr, code:Ptr) {
		this.shader = shader;
		this.code = code;
	}
}

// a texture, its shader resource view and, a render target, its render
// target view or depth-stencil view
@:hxmc.unsafe(gc)
private class D3DTexture {
	public final texture:Ptr;
	public final info:TextureInfo;
	// a shared texture's keyed mutex (IDXGIKeyedMutex), whether this frame holds it
	public var mutex = Ptr.nil();
	public var held = false;
	public var view = Ptr.nil();
	public var rtv = Ptr.nil();
	// (a cube's or a 2D array's render target views, one a layer: rtv the first)
	public final layers:Array<Ptr> = [];
	public var dsv = Ptr.nil();
	public var uav = Ptr.nil(); // a storage texture's

	public function new(texture:Ptr, info:TextureInfo) {
		this.texture = texture;
		this.info = info;
	}

	public function release() {
		Com.release(uav);
		Com.release(mutex);
		Com.release(dsv);
		if (layers.length > 0) {
			for (l in layers)
				Com.release(l);
		} else
			Com.release(rtv);
		Com.release(view);
		Com.release(texture);
	}
}

// a compute pipeline: its shader (ID3D11ComputeShader; its own: released
// with the shader's table) and its resources
@:hxmc.unsafe(gc)
private class D3DCompute {
	public final shader:Ptr;
	public final bindings:Array<ShaderBinding>;

	public function new(shader:Ptr, bindings:Array<ShaderBinding>) {
		this.shader = shader;
		this.bindings = bindings;
	}
}

// the state objects a pipeline sets, and its vertex buffers' strides
@:hxmc.unsafe(gc)
private class D3DPipeline {
	public final vs:Ptr;
	public final ps:Ptr;
	public final layout:Ptr; // ID3D11InputLayout
	public final rasterizer:Ptr; // ID3D11RasterizerState
	public final depth:Ptr; // ID3D11DepthStencilState
	public final blend:Ptr; // ID3D11BlendState
	public final topology:Int;
	public final strides:Array<Int> = [];

	public function new(vs:Ptr, ps:Ptr, layout:Ptr, rasterizer:Ptr, depth:Ptr, blend:Ptr, d:PipelineDesc) {
		this.vs = vs;
		this.ps = ps;
		this.layout = layout;
		this.rasterizer = rasterizer;
		this.depth = depth;
		this.blend = blend;
		topology = switch d.topology {
			case null | Triangles: D3D.TOPOLOGY_TRIANGLELIST;
			case TriangleStrip: D3D.TOPOLOGY_TRIANGLESTRIP;
			case Lines: D3D.TOPOLOGY_LINELIST;
			case Points: D3D.TOPOLOGY_POINTLIST;
		}
		for (l in d.layout)
			strides.push(l.stride);
	}
}
