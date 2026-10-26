# CCT_Player multitasking design

**Status:** recommended architecture plus an experimental CoCoPSG process prototype. Build and module identity are verified; guest playback, scheduling, and timing remain **NOT RUN**.

## Current source findings

The default build of `cct_os9.asm` remains byte-for-byte identical to the tracked `cctplay` baseline. Conditional `EXPERIMENTAL_PSG` code now builds a separate `cctplaymt` module; the prototype details and current evidence are in [PSG-PROTOTYPE.md](PSG-PROTOTYPE.md).

| Area | Source evidence | Effect |
| --- | --- | --- |
| Scheduling | `PLAY_CHIP_OPL`, `PLAY_CHIP_SN76489`, and `PLAY_CHIP_YM2149` set `ORCC #$50` at `cct_os9.asm:1224`, `:1421`, and `:1585`. There is no matching restore on the playback exit path. | Both IRQ and FIRQ stay masked through command playback, so OS-9 cannot run its normal interrupt-driven clock and process scheduling during a track. |
| VGM waits | `VGM_WAIT_SAMPLES` and the SN76489/YM2149 copies at `:1348`, `:1511`, and `:1687` count down one sample at a time. The source comments target about 40.5844 CPU cycles per 44.1 kHz sample in CoCo 3 fast mode and pad paths for 6809/6309 differences. | Timing is tied to a busy loop. Removing the masks alone adds interrupt/scheduler time to that loop and changes event timing. |
| Wait commands | The handlers map `0x61` to its 16-bit sample count, `0x62` to 735 samples, `0x63` to 882 samples, and `0x70–0x7F` to short waits. | The common decoder must turn waits into one monotonically increasing sample timeline and keep both 50 Hz and 60 Hz frame waits. |
| MMU | VGM/CCT loading allocates and temporarily maps 8 KB blocks with `F$AllRAM`, `F$MapBlk`, and `F$ClrBlk`; playback switches the logical `$2000` mapping by writing block IDs to `$FFA9` in `:1262`, `:1458`, `:1627`, and `VGM_GET_RAM_BLOCK` at `:1762`. | `$FFA9` bypasses the process mapping API during playback. That assumption is only stable while the player owns the CPU and must be removed or isolated before scheduling is enabled. Physical 2 MB RAM does not expand a process beyond its 64 KB logical DAT window. |
| Keyboard and signals | The three wait loops write `$FF02` and read `$FF00` to test BREAK/ESC (`:1363–1366`, `:1526–1527`, `:1702–1703`). `F$Icpt` installs `SIGNAL_HANDLER`; it sets `abortFlag`, which is checked during final cleanup (`:1914`, `:1954–1964`). | The player performs its own PIA scan while the OS keyboard service is unavailable. OS-9 signals cannot provide prompt cancellation while the playback masks remain in force. Input must move to SCF/OS-9 signals. |
| Audio hardware | The source saves/restores `$FF7F` (MPI selection) and `$FF23` (sound PIA) on the normal reset path (`:1870–1875`). OPL uses `$FF50–$FF54`; CoCoPSG uses `$FF5D–$FF5F`; GMC uses `$FF41`. | One backend must own chip selection and register writes at a time. The source writes `$FFD9` to force fast mode but does not save and restore its prior value. GIME-X speed-state ownership needs explicit treatment. |
| OS-9 calls | The player uses `F$Icpt`, `F$AllRAM`, `F$MapBlk`, `F$ClrBlk`, `F$DelRAM`, file `I$` calls, and `F$Exit`. `os9.d` defines `F$Sleep`, `F$VIRQ`, and `F$IRQ`, but the player does not call them. | Existing path, allocation, and playlist cleanup provides a starting point, but the current player has no yield or driver-owned event service. Every new open path, allocation, interrupt registration, and hardware claim needs one cleanup owner. |

The `os9.d`, `rbf.d`, and `scf.d` includes are the local Level II symbol and path-descriptor definitions. No include-file edits are proposed in this design.

## Experimental CoCoPSG process prototype

The first prototype keeps VGM/CCT parsing and file ownership in the existing player process. Its conditional PSG path splits command fetch/decode (`VGM_YM2149_NEXT_COMMAND`, `VGM_YM2149_CMD_CHIP`, and wait-command decoding), delay handling (`VGM_PSG_COARSE_WAIT` plus the sample-count fine loop), and register output (`VGM_PSG_WRITE_REG`). It enables interrupts throughout parsing and waits. Short delays use the CPU-cycle loop; longer delays may sleep in OS-9 ticks and then finish the sub-tick remainder. This is a scheduling experiment, not yet a drift-corrected timestamp scheduler.

For the PSG stream, the prototype maps each allocated file block into the process DAT image with `F$MapBlk`, clears the old mapping with `F$ClrBlk`, and reserves a top guard block so the stream page is mapped below `$E000`. The EOU manual specifies top-down mapping into the highest available process addresses. This removes direct `$FFA9` writes from the reachable experimental PSG stream path; the baseline OPL/GMC paths and original helper remain unchanged in the default build. Guest context-switch behavior has not yet been observed.

The test process uses the existing `F$Icpt` signal intercept and `abortFlag`; the experimental wait path does not scan keyboard PIA registers. The PSG control value, MPI selection, and sound PIA value are saved/restored, and the existing PSG silence sequence uses a short CC save/mask/restore section. The MPI and PIA registers are global hardware state: this prototype has no inter-process device lock, so another program that also changes MPI/audio hardware is outside the first counter-only experiment.

The prototype does not enqueue normalized timestamped events. Every wait is relative to the previous command, so interrupt and scheduler delays can accumulate as music drift. `F$Sleep` saves CPU time on long waits but wake-up scheduling can add lateness; short waits still occupy the player process between clock interrupts. No CPU, jitter, drift, register-write, or audible measurements exist yet. See the evidence matrix and exact guest commands in [PSG-PROTOTYPE.md](PSG-PROTOTYPE.md).

## Approaches considered

### `F$Sleep` as the playback clock

Reject this as the only event timer. The EOU manual defines `F$Sleep` in system ticks; `X=1` yields the remainder of the current time slice and `X=0` sleeps until a signal. At a 60 Hz tick, a tick is about 16.67 ms or 735 VGM samples. It cannot schedule every sub-tick register event. It remains useful for a producer waiting for queue space/data or for coarse waits.

### Interruptible user-process timing

Use this for the first scheduling prototype, not as a pre-approved timing solution. Keep interrupts enabled, decode events against an absolute sample counter, and yield at bounded points. It can establish that another process and the Shell continue to run. Measure event lateness and duration drift under disk I/O and competing processes; enabled interrupts alone do not prove acceptable audio timing.

### OS-9 playback service

Use this if the process prototype misses the agreed timing limits. Keep file parsing and playlist work in a regular user process. Put normalized events into a bounded queue through a normal driver path. A small EOU driver owns the timer and the selected sound hardware, installs IRQ polling through `F$IRQ` from driver/system context, and services only due events. Keep the handler deterministic and bounded: no file I/O, parsing, blocking calls, allocation, printing, or unbounded catch-up loops. `F$VIRQ` is a clock-tick mechanism; use it only for coarse driver wakeups, not for sub-tick deadlines.

The EOU Technical Reference Manual restricts `F$IRQ` to system state, describes the IRQ handler return convention, and says VIRQ counts clock ticks and must be paired with an IRQ-poll entry for a VIRQ-only device. It also limits VIRQ use to drivers/pseudo-drivers or `/nil` through VRN. The [EOU Technical Reference Manual](https://www.lcurtisboyle.com/nitros9/EOUDOCS/NitrOS-9_EOU_Level_2_Technical_Reference_Manual.pdf) is the authority for those calls; the [CoCo 3 Service Manual](https://colorcomputerarchive.com/coco/Documents/Manuals/Hardware/Color%20Computer%203%20Service%20Manual%20%2826-3334%29%20%28Tandy%29.pdf) describes the shared GIME timer registers. Do not assume the GIME timer is free: establish EOU ownership, clock interactions, and MAME behavior before enabling it.

## Recommended architecture

Use one reusable playback engine with separate format, timing, and chip-output layers:

1. **User process and format readers.** Keep VGM/CCT/M3U file paths, metadata, loops, playlist transitions, signal state, and all RBF operations in the player process. Prefer a small streaming read buffer. If block allocation remains necessary, use the OS-9 mapping calls and never change `$FFA9` directly while the process can be switched out.
2. **Shared decoder.** Decode file commands once into normalized chip events. Maintain a wide absolute VGM sample timeline; waits advance the timeline without emitting writes. Preserve 735/882 frame waits and short waits. Store conversion remainder when mapping samples to timer units so repeated rounded divisions do not accumulate drift.
3. **Bounded producer/consumer queue.** Use fixed-size event records containing deadline, backend, register/command, value, and flags. Keep the queue in driver-owned or otherwise explicitly shared storage; never pass a process-local pointer to an IRQ routine. Back-pressure parks the producer with OS-9 scheduling while the service drains events.
4. **One timing service.** Start with the interruptible user-process prototype. If measurements require lower jitter, replace only the event sink with the EOU driver service; keep the same decoder and event record format. Do not add a kernel patch or install random vectors.
5. **Chip backends.** Implement CoCoPSG first (register select then data write, preserving slot/PIA state), GMC next (SN76489 command-byte writes in slot 1), and OPL3 separately for real MMMPI hardware. Keep each backend's register ordering and settling delays intact, and measure the required spacing on its target. Standard MAME does not emulate the original MMMPI OPL3 target.

VGM timing is expressed as 44,100 samples per second. At the source's fast-mode estimate, one sample spans roughly 40.58 CPU cycles, so an interrupt per sample is not viable on a 1.78 MHz CoCo 3. The queue schedules actual register-write events; the sound chips generate their tones between writes. The exact timer source, timer quantization, maximum event density, IRQ cost, and acceptable jitter remain measurement tasks, not assumptions.

## Ownership and cleanup rules

- The player process owns file/playlist paths, buffers, signal intercept, and any process-local RAM. It closes every path and returns every allocated block on normal stop, signal, EOF, and every error path.
- The sound driver owns one chip selection, its MPI slot, PIA/audio enable state, timer state, and its `F$IRQ`/VIRQ registrations. It restores the prior state on close/unload and silences notes on abort.
- No user-state code installs `F$IRQ`, changes interrupt vectors, writes a shared timer configuration, or keeps interrupts masked while parsing, waiting, yielding, or doing file I/O.
- The IRQ handler saves/restores the state required by the EOU ABI, performs bounded hardware writes, updates counters, and returns with `RTS` as required by the EOU IRQ-poll service. It does not call blocking OS-9 services.
- Keep mutable state in process/driver data (`U`) and constants PC-relative. Use `BSR`/`LBSR` for re-entrant local calls.

## Expected performance and measurement gates

The producer should run ahead far enough to hide RBF latency without holding the full track in a large MMU allocation. The queue should remain small relative to the 64 KB process address space. The service should use CPU only at register-write deadlines, rather than generating a 44.1 kHz software sample stream.

No timing or CPU result has been measured yet. Record at least: register-write deadline error distribution, worst lateness, duration drift versus the original baseline, missed/overrun events, queue high-water mark, player CPU share, and concurrent counter rate. Compare the same track and loop settings with the original player. A 60 Hz-only service has 735-sample granularity and is not acceptable for individual VGM events.

## Incremental implementation and rollback

1. Preserve the current source and build/module hashes in `BASELINE.md`.
2. Extract the shared VGM wait/command decoder without changing output behavior; keep the original executable path available for comparison.
3. Add an interruptible user-process scheduler and a synthetic PSG event stream. Verify scheduling first, then measure timing with the counter and disk workload active.
4. Implement the CoCoPSG backend and first MAME milestone. Add the OS-9 driver only if the process scheduler misses the measured timing limits or cannot provide reliable hardware ownership.
5. Reuse the event queue for GMC, then evaluate OPL3 on real hardware. Run the format/error/resource matrix after each backend change.

Each implementation commit should record the exact build and test commands, PASS/FAIL/NOT RUN evidence, measured limits, and a rollback commit/reference in its review description. Rollback is to revert the small feature commit; the original `cctplay` and source baseline remain available.
