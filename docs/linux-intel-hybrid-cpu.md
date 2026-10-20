# Faster Elden Ring on Linux with an Intel P-core and E-core CPU

<!-- description: Elden Ring frame rate on Linux with Intel 12th to 14th gen CPUs. Check whether the game runs on slow E-cores and pin it to the P-cores with taskset. -->

Intel's 12th, 13th and 14th generation desktop CPUs have two kinds of core:
fast **P-cores** and slower **E-cores**. Elden Ring does most of each
frame's work on one thread, so its frame rate follows the speed of the core
that thread runs on. On some Linux systems the kernel does not know the
E-cores are slower and keeps moving that thread onto them.

On an i7-13700KF with a Radeon RX 9070, standing in the same spot:

| Game allowed to run on | Frame rate in the world |
| ---------------------- | ----------------------- |
| every core             | about 91 fps            |
| P-cores only           | about 122 fps           |

**The engine does this for you.** Once your character is in the world, it
keeps the game on the P-cores by itself (see
[Performance cores](install.md#performance-cores)). You need this guide
only to check whether your system is affected, to pin the game by hand when
`cpu_cores = "all"` is set, or with an engine older than that feature.

This guide shows how to check whether your system is affected and how to
keep the game on the P-cores. Nothing here changes your system's settings.

## Does this apply to you?

You need all three:

- **Linux.** Windows steers busy threads to P-cores by itself, and macOS
  gives programs no way to choose cores.
- **An Intel CPU with both core types.** Check with:

  ```sh
  cat /sys/devices/cpu_core/cpus /sys/devices/cpu_atom/cpus
  ```

  Two lines, such as `0-15` and `16-23`, mean you have both: the first
  line lists the P-cores, the second the E-cores. An error means all your
  cores are the same kind, and this guide does not apply.
- **A kernel that treats every core alike.** Check with:

  ```sh
  cat /proc/sys/kernel/sched_itmt_enabled
  cat /sys/devices/system/cpu/cpu*/cpu_capacity | sort -u
  ```

  If the first file is missing or reads `0`, **and** the second command
  prints a single number, the kernel does not prefer the P-cores. If the
  first reads `1`, or the second prints more than one number, the kernel
  already favours the fast cores and pinning will gain you little.

Keep the game off the E-cores only if you have **six or more P-cores**.
On a laptop with two or four, the game's many threads would crowd onto too
few cores and run slower.

## Pin the game to the P-cores

Start the game as usual and load into the world. Then, in a terminal:

```sh
for p in $(pgrep -f eldenring.exe); do
  taskset -a -c -p "$(cat /sys/devices/cpu_core/cpus)" "$p"
done
```

`-a` applies the change to every thread of the game; `-p` changes a
program that is already running. You need no root: anyone may restrict
their own programs. The change lasts until the game exits, so run it again
each time you play.

**Pin only after the game has started.** Do not start the launcher under
`taskset`: with its cores restricted from the start, the game's sound
system fails to set up and the game exits during start-up.

To undo it while the game runs, pin it to every core instead:

```sh
for p in $(pgrep -f eldenring.exe); do taskset -a -c -p "0-$(($(nproc) - 1))" "$p"; done
```

## Check that it helped

Measure the frame rate in the same spot before and after. Either load
`examples/perf_monitor.lua`, which shows the frame rate in the game, or
trace a few seconds from a terminal:

```sh
ermod-engine trace start
ermod-engine trace stop
ermod-engine trace report
```

The report's first line gives the average frame rate. See
[Finding stutters](performance.md) for the rest of it.

## A lasting fix

Pinning works around the kernel not knowing which cores are fast. Two
changes fix that for every program, but they are changes to your system,
and we have not tested them:

- **Firmware.** The kernel learns which cores are faster from what the
  firmware reports. Some boards report every core the same; a firmware
  update or a setting such as Intel Turbo Boost Max Technology 3.0 may
  change that. Your board's manual names the setting, if it has one.
- **A scheduler that knows the core types.** Recent kernels can run a
  replacement scheduler (sched_ext), and some of those, such as
  `scx_lavd` and `scx_bpfland`, take core types into account. Your
  distribution's documentation covers installing one.

If the checks above then show `sched_itmt_enabled` at `1`, the kernel
favours the P-cores by itself and you no longer need to pin the game.
