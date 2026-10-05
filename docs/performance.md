# Finding stutters

The engine has a built-in frame tracer. It records how long every frame
took while you play and flags the stutters. When asked, it also notes which
of the game's code was running and how long the GPU spent on each piece of
work. Afterwards, `ermod-engine trace report` says what made the slow frames
slow.

It needs no mod. It is part of the engine, off by default, and you switch
it on when you want it.

## Turn it on

**While the game runs**, from a terminal:

```sh
ermod-engine trace start              # frame timing, plus CPU sampling at the "normal" level
ermod-engine trace start --gpu        # frame timing, plus GPU timing
ermod-engine trace start --cpu detailed --gpu
ermod-engine trace stop
```

Start a trace when a stutter shows up, play through it, then stop. Changing
what is traced while a trace is running starts a new trace file.

**From launch**, in `engine.cfg` (see
[Settings](install.md#settings-enginecfg)):

```text
frame_trace_cpu = "normal"   # "off", "light", "normal" or "detailed"
frame_trace_gpu = true
```

Both are off by default. With either one on, a trace starts as the game
does and runs until `trace stop` or until the game exits.

| Option           | What it adds                                                                                                |
| ---------------- | ----------------------------------------------------------------------------------------------------------- |
| every trace      | each frame's time, split into the game's CPU work, waiting on the GPU or display, and the engine's own work |
| `--cpu light`    | which game code and which libraries run during stutters, sampled about 50 times a second                    |
| `--cpu normal`   | the same, about 100 times a second; enough for most stutters                                                |
| `--cpu detailed` | the same, about 250 times a second; for catching a single short stutter                                     |
| `--gpu`          | the GPU time of each batch of work the game submits                                                         |

## Read the report

```sh
ermod-engine trace report               # the newest trace
ermod-engine trace report <file.ftr>    # a specific one
```

Traces are written into the game's prefix, under `drive_c/ermod/trace/`;
`trace start` prints the full folder for your setup. A report starts with
the frames:

```text
trace 2.7.1.0  2764 frames  47.3 s  58.4 fps
interval  p50 16.9 ms  p99 22.5 ms  p99.9 81.3 ms   spikes 7
spikes by side  cpu 6  present/gpu 0  engine 1
worst spikes  (ms: total = cpu + engine + present, mods)
  +47.3 s  95.4 = 94.5 + 0.8 + 0.1   mods 0.3
```

- **p50, p99, p99.9** are the typical frame time, the slowest 1 % and the
  slowest 0.1 %. Smooth play has p99 close to p50.
- **A spike** is a frame that took more than twice the typical frame time,
  or 8 ms longer than it, whichever is larger. The rule adapts to your frame
  rate, so it works at 30, 60 and 144 fps alike.
- **The side** says where a spike's time went:
  - `cpu` is the game working out the frame (loading, streaming, AI,
    physics).
  - `present/gpu` is waiting on the graphics card, the display or the
    driver, including shader compilation stutter.
  - `engine` is ermod itself. `mods` is the part spent in mods' handlers.
    A spike on the engine's side is ours to fix, so please report it.

With `--cpu`, the report adds tables that compare slow frames against
normal ones:

- **By library.** Where the sampled code was running: the game, or a system
  or graphics library such as `ntdll.dll`, `winevulkan.dll` or the driver.
- **Game code.** Which game function was running, or which one called into
  that library. `x8.3` means it shows up 8.3 times as often in slow frames
  as in normal ones. A function that runs in every frame is not your
  stutter; one that turns up "only in spikes" probably is.
- **Call paths.** The same, with up to four callers, read from the game's
  own unwind information. A path marked `(scan)` was found by searching the
  stack, so treat its first entry with some care.

Functions are named by their offset in the game (`game+0x1ed80f0`). They
are the same on every machine with the same game build, so two people's
reports can be compared.

With `--gpu`, the report adds the GPU time per frame and per batch of work.
It first checks that the game submits its work in the same order from frame
to frame. The game does not always do so, and the per-batch rows only use
frames where it did. If too few stutters fall in such frames, the report
says so instead of guessing.

## What it costs

Tracing is designed not to cause the stutters it measures. Nothing it does
while you play waits on a file or a lock; a separate thread writes the
trace four times a second.

- **Off**: one memory read per frame, plus the stutter counter mods can
  read, at about 0.5 µs a frame.
- **Frame timing**: three clock reads per frame and a small record.
- **CPU sampling**: briefly pauses the busiest game threads to note where
  they are, at the rate of the level you chose.
- **GPU timing**: two timestamps around each batch of work the game sends
  to the graphics card.

How much CPU sampling slows frames down has not been measured precisely
yet. If a trace looks worse than the game feels, try `--cpu light`.

## Sharing a trace

A trace with frame timing alone is about 120 KB a minute; with CPU sampling
it is a few MB a minute. It holds timings, code offsets and the names of the
libraries loaded into the game. With CPU sampling, each sample also holds a
raw 1 KB copy of the sampled thread's stack, which can contain fragments of
whatever the game had in memory at that moment. The report's text holds
none of that. Attach the report's text to a bug report first, and the
`.ftr` file only if you are asked for it.

## For mod authors

`sdk.perf.spikes()` counts stutters with the same rule, without a trace
running. See [`perf`](scripting.md#perf) and `examples/perf_monitor.lua`.
