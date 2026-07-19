# Windowing, graphics, and stability fixes

Two independent classes of real, reproduced graphical bugs affect Ableton
Live under Wine. Both are fixed here, through two different mechanisms:

1. **Live's own GPU/GL renderer misrendering** - most visibly, the account
   sign-in dialog stays blank until its window is resized, plus elevated idle
   CPU usage. Fixed with a config-only change: forcing Live's built-in GDI
   rendering backend. No Wine patch needed, works with the default prebuilt
   runtime.
2. **A set of real Wine bugs** in windowing, DPI handling, and general
   stability - most visibly, a fullscreen-mode cursor/click misalignment, and
   a double-titlebar bug at high DPI. Fixed with 9 patches to Wine itself.
   Requires `--build-from-source`; not part of the default prebuilt runtime.

Both were reproduced independently of GPU vendor (confirmed on AMD; the
original report was on NVIDIA) and independently of Ableton Live version
(confirmed on both Live 11 and Live 12).

## 1. The GDI rendering backend fix

Live's own GPU/GL renderer misrenders under Wine: large black or blank
content regions (most visibly the account sign-in dialog, which never paints
until its window is resized) plus a persistent CPU spin on software GL.

Ableton reads `-_ForceGdiBackend` from `Options.txt` in its versioned
Preferences directory (e.g. `Live 11.3.25/Preferences/Options.txt`), which
Live only creates on first run. `scripts/run-ableton.sh` ensures the flag in
every existing Live Preferences directory on each launch - idempotent, and
self-healing across Live version updates. Set `ENCORE_LIVE_GPU=1` to opt out
and use Live's own GPU renderer instead.

Because Live only creates that directory on its first-ever launch, the
launcher's own check can't help on that very first run - there's nothing to
find yet. `install.sh`'s `preseed_gdi_backend_flag()` closes that gap: right
after Ableton is installed or imported, before its first launch, it reads the
installed executable's own PE version resource (via `strings -e l`, already a
common dependency - no new one added) to predict the exact versioned
Preferences directory name ahead of time, and places the flag there
proactively. Verified: the previously-blank account sign-in dialog renders
correctly on the very first launch of a freshly installed prefix, no resize
needed.

Originally identified and fixed by **shibco** (shibacomputer, `cade@parare.al`)
in [`shibco/ableton-linux`](https://github.com/shibco/ableton-linux), ported
into ENCORE by **Jae** (jaesharp) in their ENCORE fork
([`jaesharp/ENCORE`](https://github.com/jaesharp/ENCORE)), who tracked it down
to this exact `Options.txt` mechanism and verified the CPU-usage improvement.
The first-launch preseed gap and its fix are original to this ENCORE branch.

## 2. The Wine-level windowing/graphics/stability patches

Nine patches, added to `patches/encore-wine.patch`, fix real Wine bugs
unrelated to Ableton specifically:

**Windowing / HiDPI:**

- **Fullscreen-mode cursor/click misalignment** - DXGI and wined3d queried a
  swapchain window's present/resize client rects in the *calling thread's*
  DPI awareness context instead of the *target window's own*. In a mixed-DPI
  process (Live's own per-monitor-aware main window alongside DPI-unaware
  plugin/embedded threads - any `LogPixels > 96` setup qualifies), the rect
  comes back in the wrong coordinate space, mis-sizing and mis-positioning
  everything presented through it. This is very likely the root cause behind
  the fullscreen cursor/click misalignment reproduced independently in
  testing.
- **Double-titlebar bug at high DPI** - Live's main window is custom-NC (it
  draws its own window chrome). `get_mwm_decorations` already treated
  `window == visible` as meaning "undecorated," but that stopped holding once
  the display scales, so a reparenting window manager (e.g. mutter, KWin)
  would paint a second title bar/frame around Live's own. Gated on
  `client == window` instead - the robust signal for an app-drawn-chrome
  top-level.
- **Self-resize infinite spin** - at high display scale, Live's own autosize
  handler re-drives `SetWindowPos` from inside its own `WM_WINDOWPOSCHANGED`
  handler; the nested, size-only repost re-enters the same top-level window
  and spins a core forever (80-99% of a core, the window continuously
  "resizing"). Fixed by tracking `WM_WINDOWPOSCHANGED` send depth and target
  window per-thread and dropping a nested size-only re-entry on the same
  top-level window.

**Stability (general Wine bugs, not Ableton-specific):**

- **Shared-session view coherence** - wineserver's shared session memory was
  mapped read-only `MAP_PRIVATE` by ntdll, which is not coherent for that
  memfd: views went permanently stale, window-class registration silently
  failed, and window creation died with a swallowed exception inside Live's
  own vectored crash handler - felt as multi-second menu freezes and
  intermittent "VST3: plug window creation failed." Fixed by mapping session
  views `MAP_SHARED` instead.
- **Window-activation requests dropped** - winex11 sent `_NET_ACTIVE_WINDOW`
  activation requests with timestamp 0; strict window managers (GNOME ≥ 50
  mutter) silently drop these under focus-stealing prevention, and Wine's own
  pending-request dedup then suppressed every further request - one dropped
  request wedged activation for the whole session (menus open-then-close or
  not at all, keyboard shortcuts inert). Fixed by sending the last real input
  timestamp instead, and re-sending when a newer one exists.
- **Audio device names nesting infinitely** - `MMDevice_Create()` re-wrapped
  an absent endpoint's `FriendlyName` on every enumeration ("Speakers
  (Speakers (...))"), nesting one level deeper per boot until audio-device
  enumeration crashed Live at startup. Fixed by only writing endpoint name
  properties when creating a device from a raw driver-supplied name, not on
  registry reloads.
- **JUCE plugin popups rendering as opaque black rectangles** - layered
  windows with no shape (e.g. JUCE drop-shadow popups using per-pixel alpha
  via `UpdateLayeredWindow`) only had their alpha mask forwarded to the X11
  surface on shape changes; win32u's `x11drv_surface_flush()` otherwise ORs in
  full opacity, turning premultiplied mostly-transparent black into solid
  black. Fixed by syncing layered attributes on every flush, not only shape
  changes (a no-op when unchanged).
- **Fatal crash opening certain GL-based plugin editors** - `set_dc_drawable()`
  didn't report a drawable's real X visual when it differed from the default
  (notably depth-32 ARGB visuals on plugin-editor top-levels), so
  `XRenderCreatePicture` failed with `BadMatch` - a fatal X error that took
  down the whole host - when opening an OpenGL plugin editor. Fixed by
  tracking and reporting the drawable's actual visual.
- **Missing sRGB pixel format advertisement** - Wine didn't advertise
  `framebuffer_srgb_capable` for 8-bit RGB formats even when the EGL display
  supports `EGL_KHR_gl_colorspace`, so `wglChoosePixelFormatARB` returned no
  formats at all for GUIs that require `WGL_FRAMEBUFFER_SRGB_CAPABLE`. Fixed
  by advertising it and creating X11 EGL window surfaces with
  `EGL_GL_COLORSPACE_SRGB_KHR`.

All nine were originally identified and fixed by **shibco** (shibacomputer,
`cade@parare.al`) in
[`shibco/ableton-linux`](https://github.com/shibco/ableton-linux), and adapted
to ENCORE's pinned Wine revision (`6eb2e4c32cc9e271856146df11ed3a5c2cf29234`)
by **Jae** (jaesharp) in their ENCORE fork
([`jaesharp/ENCORE`](https://github.com/jaesharp/ENCORE)). Two further
candidate patches from that fork (drag-and-drop DPI-awareness, dynamic menu
theming) turned out to already be part of ENCORE's own `encore-wine.patch`
under different organization, so only these genuinely new nine were added.

Requires `--build-from-source`; the default prebuilt runtime download does
not yet include these fixes (see [Known limitations](../README.md#known-limitations)).

## Verified

- A completely fresh `--live-installer` run of both Ableton Live 11 Suite and
  Live 12 Suite, built from source with this patch set.
- The account sign-in dialog renders immediately on Live's very first launch
  in a freshly installed prefix (previously blank until resized).
- Fullscreen-mode cursor/click alignment is correct throughout, on both Live
  versions.
- Only one application-menu entry appears after install (unrelated fix,
  bundled in the same branch - see the `--live-installer` PR).
