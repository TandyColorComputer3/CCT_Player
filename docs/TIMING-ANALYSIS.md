# CoCoPSG timing measurements

This is the historical `d4f98b1` timing checkpoint. Later matched-control and storage results are in [STABILITY-ANALYSIS.md](STABILITY-ANALYSIS.md).

**Run:** 2026-10-26, isolated MAME 0.289 `coco3h`, HD6309 native mode, 2 MB, NTSC EOU Level II, CoCoPSG in MPI slot 2. All timestamps below come from MAME `manager.machine.time`; they are emulated seconds, not host wall time. A separate pre-existing MAME instance and its mounted disks were left untouched.

The production `cctplaymt` measured here is 8,988 bytes, CRC `$05B97E` Good. The original `cctplay` remains byte-identical to its rebuild (SHA-256 `eabe6b6f3910ebd1af557f64b02c1fb1e1802a3a07a1bf134016b1a4a6792f36`).

The previously failing direct MAME launch was retried with elevated execution in the logged-in Aqua session and started successfully using the same binary and private media. That establishes a working launch context; the precise cause of the earlier `NSApplication` registration abort was not determined. No Ample installation changes were needed.

## Clock and sleep observations

- **PASS:** The original `tpsprobe` ran, but did not display carry. A register capture and the corrected `tpsprobe` showed `TPS!A=00 B=D0`: carry set, `E$UnkSvc`. `F$TPS` is unavailable on this EOU boot; it did not establish the clock rate.
- **PASS:** `sleepprb` wrote register-select markers immediately before and after five calls at each count. Normal returns had X=0. Measured marker-to-marker intervals were: X=1, 1.143 ms; X=2, 13.346–14.980 ms; X=3, about 33.873 ms; X=4, about 50.042 ms; X=10, about 150.170 ms; X=61, about 1,001.303 ms. These include call, marker, wakeup phase and scheduler costs. The X=61 result is consistent with roughly 60 NTSC video ticks near 59.92 Hz; it is not a separate measurement of scheduler latency.
- **PASS:** A separate probe requested X=6000 and received `S$Intrpt` after 30.154 emulated seconds / 1,807 MAME video frames. It returned carry clear with X=`$1061` (4,193) remaining. This one observation establishes an early return with a nonzero remainder, not a complete characterization of every signal or wakeup phase.
- The user process has no verified sub-tick monotonic clock. `F$Time` returns a six-byte date/time packet, while this boot rejects `F$TPS`. An absolute-deadline scheduler therefore remains an evaluation, not an implementation or a basis for claiming scheduling accuracy.

## What caused the measured drift

The old `b6b4291` timing build ran 30-second 735-sample-wait streams about 1.76% early. Consecutive PSG writes were about 114 microseconds apart in a controlled trace; the select-to-data bus pair alone was about 5 microseconds. The larger interval includes command decoding and dispatch, so it is not a direct measurement of either parser CPU time or sound-bus time alone.

A separate fixture used 27,600 VGM short-wait commands (15–16 samples each) over 10 seconds. An intermediate build that accounted for register writes but not individual waits took 14.144654 seconds: an excess of 4.144654 / 27,600 = **150.2 microseconds per wait**, including its decoding, bookkeeping and scheduling effects. The final build took 10.085214 seconds to its end-command marker with the counter active. The 30-second variant contains 82,800 short waits.

Irregular real-track intervals that included coarse sleeps were 3.7–4.4 ms early on average after nominal sample and tick time were subtracted. That residual combines sleep phase, fine delay, command work and scheduler effects; it is not an isolated runtime measurement of `F$Sleep` latency. The sleep probe independently shows that a call begins partway through a tick and can wake early. Total parser CPU time, fine-delay CPU time, sleep time and scheduler wait time were **not** independently sampled; CPU percentage is **NOT RUN**.

## Correction

The experimental PSG path keeps interrupts enabled and applies a bounded relative correction in VGM's 44,100 Hz sample units:

1. Each PSG register command adds six samples of processing debt. Each wait adds an average of 8 3/8 samples, including the accounting work; a three-bit remainder distributes the fractional sample across eight waits.
2. Before each wait, the player subtracts as much debt as the wait permits and carries the rest forward. Debt is capped at one nominal clock tick. Every register change is still emitted in stream order; short waits can become zero while debt is outstanding.
3. At least two whole ticks must remain before using `F$Sleep`. A normally completed coarse sleep adds 215 fine-delay samples (4.875 ms) on NTSC, an empirical allowance for the observed phase deficit. The PAL allowance is scaled to 258 samples and is **NOT RUN**.
4. The interruptible fine loop gained one HD6309 cycle per sample. This is paired with the measured command and sleep accounting; it is not a deadline clock. `psgCommandDebt` and its fractional remainder are process-local and reset at each song.

The changed experimental routines are `VGM_YM2149_CMD_CHIP`, `VGM_YM2149_WAIT_SAMPLES`, `VGM_PSG_COARSE_WAIT`, and the new `VGM_PSG_APPLY_DEBT`. A diagnostic-only `ccttiming` build writes `$FE` to the PSG select port when `$66` is decoded; it performs no data write for the marker and the production module omits it. The trace marker and the eventual mixer mute are separately timestamped. The original binary and nonexperimental build are unchanged.

The allowance is an average, not a measurement of the current tick phase. Preemption and disk work can still cause large local event errors. A sustained stream whose event rate exceeds available CPU time can fall behind: for example, the measured per-wait work is much greater than the 22.68 microseconds represented by a one-sample wait. Debt saturation bounds the deferred compensation, but consecutive zero-residual waits can still continue until OS-9 preempts the player. Such extreme streams and their CPU share were not measured. No IRQ handler, privileged service or kernel change was introduced.

## Controlled fixtures

All expected durations below are sums of decoded waits, with no loop point. `short` uses 735-sample waits; `tiny` uses 15–16-sample VGM short waits; `long` uses 44,100-sample waits; `mixed` combines short and long waits; `dense` writes four registers per 735 samples. Generated data is original and contains no imported music. The first event is at sample zero. The final build ran with `cctcount` active. `ccttiming`/equivalent diagnostic builds mark the exact `$66` dispatch; mixer mute follows about 33 microseconds later. Port-write capture sequences matched every decoded register change, with no buffer overflow or invalidation.

| Fixture | Expected | Baseline end-to-mute | Final `$66` marker | Final mute | Final error |
| --- | ---: | ---: | ---: | ---: | ---: |
| short10 | 10.000 s | 9.827627 s | 9.931212 s | 9.931245 s | −0.688% |
| tiny10 | 10.000 s | NOT RUN | 10.085214 s | 10.085247 s | +0.852% |
| long10 | 10.000 s | 10.014891 s | 10.008093 s | 10.008126 s | +0.081% |
| mixed10 | 10.000 s | 9.834223 s | 10.011230 s | 10.011263 s | +0.112% |
| dense10 | 10.000 s | 10.078689 s | 9.933771 s | 9.933804 s | −0.662% |
| short30 | 30.000 s | 29.471856 s | 29.786367 s | 29.786400 s | −0.712% |
| tiny30 | 30.000 s | NOT RUN | 30.250200 s | 30.250233 s | +0.834% |
| long30 | 30.000 s | 30.036804 s | 30.040069 s | 30.040102 s | +0.134% |
| mixed30 | 30.000 s | 29.549398 s | 30.031798 s | 30.031831 s | +0.106% |
| dense30 | 30.000 s | 30.120277 s | 29.784414 s | 29.784447 s | −0.719% |

Baseline values are first PSG data write to final mute on the earlier build; final values are first data write to the instrumented end marker and final mute. The diagnostic marker adds a few instructions at `$66`, not during waits. A build of the committed `ccttiming` itself ran the one-second fixture and produced the marker and all seven expected writes.

## Real files and production regression

| Test | Expected from decoded waits | Final observed result | Integrity |
| --- | ---: | ---: | --- |
| Arkanoid PSG VGM | 195,372 samples / 4.430204 s | estimated stream start to `$66`: 4.457476 s, +0.616%; mute 4.457509 s | 266 register writes matched |
| Flicky CCT | 885,968 samples / 20.089977 s | first write to `$66`: 19.964100 s, −0.627%; mute 19.964133 s | 820 register writes matched |
| Production synthetic30 | 1,323,000 samples / 30.000 s | first write to mute: 29.958991 s, −0.137% | 210 writes plus mute matched |
| Production two-entry M3U | Ark1 CCT, then Flicky CCT | Ark1 estimated 4.440280 s (+0.227%); Flicky 19.965083 s (−0.622%) | both streams matched; 2,176 port writes including two mute pairs |

Arkanoid's first PSG write is after **276 samples**, so its reported stream-start duration adds the nominal 276/44,100 seconds to the measured first-write interval; actual startup delay was not directly timestamped. The PSG VGM is a private VGM 1.51 wrapper around the real Arkanoid CCT command stream. Neither music nor disk images are committed. No loop-bearing real VGM and no dense real-world PSG VGM were available.

**PASS with limits:** During production synthetic playback, [v6-synthetic-shell.png](../emulator/images/timing-run/snapshots/v6-synthetic-shell.png) shows the counter advancing and `echo V6OK` executing at the returned Shell prompt. All captures above had `invalid=false` and `dropped=0`. The synthetic trace nevertheless includes an event about 176 ms late relative to the first event's sample timeline, although the final duration recovered. A human audio-quality comparison and worst-case latency under other loads remain **NOT RUN**.

**PASS with a prerequisite:** With `cctstop` preloaded, sending `cctstop 14` to the final production player stopped the 30-second fixture after about 11.39 emulated seconds. The last two port writes selected register 7 and wrote `$3F`; the counter continued, and `echo STOPPED` succeeded. A later [process listing](../emulator/images/timing-run/snapshots/v6-final-procs.png) shows the counter and Shell but no player. In the recorded WAV, channel 2 had mean-removed RMS 8,153 while playing versus 0.44 after stopping (16-bit PCM); the remaining post-stop level was DC. A three-second Flicky playback window had mean-removed RMS 13,761. Earlier attempts that loaded `cctstop` on demand coincided with isolated guest reboots on the prior timing build and on an intermediate corrected build. The cause is **unresolved**; preloading correlates with the successful runs but is not proven to be the cause. Do not treat the on-demand stop path as verified.

## Reproduction and evidence

```sh
bash scripts/build.sh
python3 scripts/make-timing-fixtures.py
CCT_TEST_DISK="$PWD/emulator/images/timing-run/media/repro.dsk" \
  bash scripts/stage-test-disk.sh build/timing-fixtures/*.vgm
python3 scripts/analyze-psg-timing.py build/timing-fixtures/tiny30.vgm \
  --capture emulator/images/timing-run/logs/tiny30-v6.json --trace-end-marker
```

Stage only an unmounted private disk. In the isolated guest, preload `cctstop`, run `sleepprb`, `sigprb`, or `ccttiming -psg 2 /d1/<fixture> &` as appropriate, and capture writes to `$FF5E/$FF5F` using the CoCo3 Lua bridge. `sigprb` uses `$F0`/`$F1` select writes to delimit an interruptible X=6000 sleep; see its source for the returned CC/B/X byte layout. Do not run these PSG probes concurrently with music.

Evidence is under ignored `emulator/images/timing-run/`. Example SHA-256 values: `synthetic30-v6.json` `7a89e177967836e48d6f04463d9f660a9c1bbf84da353623b2e47db0c04ee2a0`; `tiny30-v6.json` `8efe532941481e61ae95866488b365eab05da3e687f5c4587bac5a44aa68872c`; `playlist-v6.json` `9cd912c1052887ca43aeb1f05d83352ddcd6fe246c7fb3f0dc30f85b3a4fa414`; `stop-v6.json` `aa5eac06724cf4748f12629df6107aeafa5f87a202c7a9569ac083541a2f7a4d`.
