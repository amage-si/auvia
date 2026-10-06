# Contributing to Auvia

Use Bend 2.0.35 for the current baseline. Read `bend guide` (and `bend guide
effects` before touching `native/`) and keep project text in English. Library
logic belongs in Bend; the native bridge only moves bytes on a Unix socket.

## Validation

From the repository root, with the sibling AMAGE libraries checked out next to
it:

```sh
export BEND_NO_TELEMETRY=1
mkdir -p build
bend tests.bend -o build/tests
./build/tests --threads 2 --gpu off
bend examples/counter.bend -o build/counter
tools/demo_check.sh
```

`tests.bend` runs without a display or a bus. `tools/demo_check.sh` needs an
X11/XWayland session, a running AT-SPI bus and `python3-gobject` with the
`Atspi` typelib; it opens the counter, drives it, captures it under
`build/evidence/` and always closes it. A change to the protocol or to what a
node exposes is not validated until a real AT-SPI client has read it.

Build one target at a time. Wrap builds that may run next to other AMAGE
builds in a shared lock (`flock /tmp/amage-eco-bend-build.lock bend ...`). The
native runtime reserves a large virtual address space; a virtual-memory limit is
not a resident-memory limit. Keep compilation units small: the compiler can
abort on large import graphs, and a single very long list literal can exceed its
arity limit (split it across defs). Preserve crash evidence and investigate
before repeating a failed build.

## Changes

- New AT-SPI behavior needs a native check in `tests.bend` and, when it is
  visible to clients, a step in `tools/atspi_probe.py`.
- Keep the D-Bus layer generic and the AT-SPI layer pure: IO lives in
  `dbus/bus.bend`, `service.bend` and the examples.
- Keep the native bridge minimal. A new effect needs a C file and a JS twin, a
  comment saying exactly what it does, and a reason Bend cannot do it.
- Do not change the user's desktop or accessibility settings to make a test
  pass, and close every window a test opens.

Use English commit messages that explain the result. Do not commit `build/`,
generated C, logs, crash dumps, credentials or machine-specific evidence. Do not
publish BendHub packages as a side effect of validation.
