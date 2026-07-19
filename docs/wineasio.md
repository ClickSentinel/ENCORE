# WineASIO: low-latency audio (WineASIO → JACK/PipeWire)

ENCORE bundles **WineASIO**, an ASIO driver that bridges Windows ASIO to the
host's JACK server (PipeWire's JACK compatibility layer on a modern desktop).
Live can then use a low-latency **WineASIO** device instead of routing through
the higher-latency default PulseAudio path. It ships by default on both
install paths — bundled in the prebuilt runtime archive, and built alongside
Wine on a source install — and registers into every new prefix automatically;
opt out entirely with `--no-wineasio`. Ableton itself still won't use it until
you select it as the active driver: see [First use](#first-use-in-live).

> WineASIO is a separate project (GPL-2.0+), pinned and fetched like Wine.

## Components

| Piece | What it is | Where |
| --- | --- | --- |
| WineASIO driver | `wineasio.dll` (+ Unix `.so`), built against ENCORE's Wine | Bundled in the prebuilt runtime archive under `wineasio/`, or built to `runtime/wineasio/` on a source install (either way, resolved via `WINEASIO_ROOT`) |
| Sample-rate patch | Keeps the backend rate instead of the fatal `ASE_NoClock` | [`patches/wineasio/0001-clamp-sample-rate.patch`](../patches/wineasio/0001-clamp-sample-rate.patch) |
| `jacklinkd` | Restores JACK links after an audio device replug | `tools/jacklinkd.c` → `runtime/wineasio/jacklinkd` |
| Build step | Fetch + patch + build + install | [`scripts/build-wineasio.sh`](../scripts/build-wineasio.sh) |
| Registration | `regsvr32` into the prefix + host `libjack` check | [`scripts/configure-prefix.sh`](../scripts/configure-prefix.sh) |
| Launcher wiring | `WINEASIO_*` env, `WINEDLLPATH`, the PipeWire `LD_LIBRARY_PATH` fix, starts `jacklinkd` | [`scripts/run-ableton.sh`](../scripts/run-ableton.sh) |

## The sample-rate patch (why Live doesn't crash on first launch)

WineASIO can't change the backend graph rate, and many machines run one fixed
rate (PipeWire commonly runs its graph at 48 kHz regardless of what an
individual client requests). Stock WineASIO returns `ASE_NoClock` on a
mismatch — but **Live treats that refusal as fatal**: it throws out of its
`OnSetSampleRate` handler, the exception is uncaught, and Live dies during
startup, *before* the Preferences dialog exists, so the user can never reach
the control that would fix the rate. A fresh install lands in a permanent
crash loop (Live defaults new projects to 44.1 kHz, PipeWire to 48 kHz).

The patch keeps the backend rate and reports success instead; Live reads the
effective rate back with `GetSampleRate` and runs the engine at the graph's
real rate. Confirmed in testing: with the patch applied, Live logs

```
[wineasio] host asked for 44100 Hz; the backend runs at 48000 Hz -- keeping the backend rate (wineasio-clamp-sample-rate)
```

and continues normally instead of crashing.

## The JACK library conflict (why the device may fail to open even with the patch)

Even with the sample-rate patch applied, WineASIO can still fail to open the
device entirely — with no crash, just:

```
Cannot connect to server socket err = No such file or directory
Cannot connect to server request channel
jack server is not running or cannot be started
[wineasio] Unable to open a JACK client as: <app name>
```

This happens when the system's `libjack.so.0` at the standard library path
resolves to a **real, standalone JACK library** (`libjack-jackd2-0`, which
`libjack-jackd2-dev` pulls in as a runtime dependency when installed for
building) rather than **PipeWire's own JACK-compatible replacement**, which
installs to a separate directory (`/usr/lib/<triplet>/pipewire-0.3/jack/`)
specifically so it does not overwrite the real library. PipeWire's own
`pw-jack` wrapper script works around exactly this by prepending that
directory to `LD_LIBRARY_PATH` before running a JACK client. `run-ableton.sh`
does the same, using the dynamic linker's `${LIB}` token (left unexpanded on
purpose — it is resolved by `ld.so`, not the shell) so it also works on distros
where the multiarch triplet differs (Fedora's `lib64`, Arch's plain `lib`,
Debian's `lib/x86_64-linux-gnu`). A nonexistent path in `LD_LIBRARY_PATH` is
silently ignored, so this is harmless on a system without PipeWire's JACK shim
installed.

This fix was identified during ENCORE's own testing and is not part of the
upstream patch series below.

## Device recovery: `jacklinkd`

Live's ASIO "device" is the JACK graph, which survives a hardware unplug — but
the JACK *links* between WineASIO's ports and the hardware ports are destroyed
with the device, and PipeWire/WirePlumber never restore JACK links on replug.
`jacklinkd` is a port-less JACK client the launcher starts: it remembers the
links a port held when it disappeared and re-creates them when a same-named
port returns, leaving deliberate disconnects alone. It restores only links it
has seen (it can't invent routing for a never-connected device).

## Building it

WineASIO is set up by default on **either** install path:

```sh
./install.sh                 # --prebuilt (default): downloads Wine + bundled WineASIO
./install.sh --build-from-source  # builds Wine, then WineASIO + jacklinkd from source
./install.sh --no-wineasio   # either path, but skip WineASIO entirely
./scripts/build-wineasio.sh  # (re)build it on its own against an already-built Wine
```

For the **prebuilt** path, `download-wine-runtime.sh` verifies and extracts
the bundled driver alongside the rest of the runtime — nothing is built
locally. For a **source** build, `build-wineasio.sh` clones WineASIO at the
pinned revision (`WINEASIO_REVISION` in `common.sh` — 1.3.0), applies
`patches/wineasio/*.patch`, stages a private install of the built Wine for the
ABI, builds the 64-bit driver, and compiles `jacklinkd` — this needs the
**JACK development headers** (`libjack-jackd2-dev` /
`pipewire-jack-audio-connection-kit-devel`), already added to
`install-dependencies.sh`'s build profile.

Either way, the host's **`libjack.so.0`** is needed at runtime (`pipewire-jack`,
already in the runtime dependency profile for both paths) — this is what
`run-ableton.sh`'s `LD_LIBRARY_PATH` fix (below) actually resolves against.

`WINEASIO_ROOT` (in `common.sh`) resolves automatically to wherever the driver
actually landed: nested inside the prebuilt runtime for `--prebuilt`, or the
independent `runtime/wineasio/` directory for a source build — the same
signal `run-ableton.sh` already uses to pick which Wine binary to launch.

## First use (in Live)

1. Preferences → Audio → **Driver Type: ASIO** → **Device: WineASIO**.
2. Untick **Auto-Scale Plugin Window** if a plugin window resize-loops.
3. If WineASIO isn't listed, or fails to open with no crash: install
   `pipewire-jack` and restart Live; confirm the prefix was configured
   (`configure-prefix.sh`).

## Runtime knobs

Set in the environment before launch: `WINEASIO_NUMBER_INPUTS`/`_OUTPUTS`
(default 2), `WINEASIO_FIXED_BUFFERSIZE` (default `on`),
`WINEASIO_PREFERRED_BUFFERSIZE` (default 256 — raise to 512 if you hear
crackles), `WINEASIO_CONNECT_TO_HARDWARE` (default `on`).

## Verified

- The build: the patched driver compiles and links against ENCORE's Wine, and
  `jacklinkd` compiles and links against the host JACK headers.
- The full runtime path, on a real system: `regsvr32` registration, WineASIO
  listing as an available ASIO device, the sample-rate patch preventing the
  startup crash, and the device successfully opening through PipeWire's JACK
  layer — confirmed on both Ableton Live 11 and Live 12.

## Credit

The WineASIO integration — the sample-rate patch, the `jacklinkd` recovery
helper, and the original build/register/launcher wiring — was identified and
built by **shibco** (shibacomputer, cade@parare.al) in
[`shibco/ableton-linux`](https://github.com/shibco/ableton-linux), and adapted
to ENCORE by **Jae** (jaesharp) in their ENCORE fork
([`jaesharp/ENCORE`](https://github.com/jaesharp/ENCORE)). The `LD_LIBRARY_PATH`
fix for the JACK library conflict was found during ENCORE's own testing of
that integration.
