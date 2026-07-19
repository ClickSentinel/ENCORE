# Wine patches

`encore-wine.patch` is the complete patch exported from Wine revision `6eb2e4c32cc9e271856146df11ed3a5c2cf29234`. It includes all locally changed or added paths used by the current build, including the portal, HiDPI/Xwayland, VST3 hosting, DXGI vblank, dynamic menu theming, cpuset-aware CPU topology, stale-thread recovery, host-file drag-and-drop compatibility work, and the windowing/graphics/stability fixes credited below.

The guided installer applies this patch automatically to the pinned Wine checkout. It is the complete source delta required by ENCORE.

## Windowing, graphics, and stability fixes

Nine of the patches here fix real, reproduced bugs affecting Ableton Live under Wine: a fullscreen-mode cursor/click misalignment, a double-titlebar decoration bug at high DPI, a self-resize infinite-spin bug, silent window-class registration failures causing multi-second menu freezes, window-activation requests being dropped by strict window managers, audio device names nesting infinitely on enumeration, JUCE plugin popups rendering as opaque black rectangles, a fatal crash opening certain GL-based plugin editors, and a missing sRGB pixel format advertisement. See [docs/live11-graphics.md](../docs/live11-graphics.md) for the full technical detail on each, plus the separate (non-Wine-patch) GDI-rendering-backend fix for the blank account sign-in dialog.

Originally identified and fixed by **shibco** (shibacomputer, `cade@parare.al`) in [`shibco/ableton-linux`](https://github.com/shibco/ableton-linux), and adapted to ENCORE's pinned Wine revision by **Jae** (jaesharp) in their ENCORE fork ([`jaesharp/ENCORE`](https://github.com/jaesharp/ENCORE)). Brought into ENCORE proper from that fork, with full credit to both for the original diagnosis and fixes.
