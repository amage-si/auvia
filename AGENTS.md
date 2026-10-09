# Auvia: instructions for contributors and agents

Auvia is the accessibility layer of the AMAGE UI ecosystem, implemented in
**Bend 2**. It represents the roles, names, states, values, actions and
relations of an interface, keeps that tree in sync with focus and changes,
and connects it to the platform's assistive technologies. Read the README for
current capabilities and limits; a direction listed there is not implemented
merely because it is planned.

## Implementation

- Implement library logic in Bend 2, rather than wrapping an accessibility
  toolkit (ATK, AccessKit, GTK) written in another language. Today that
  includes the D-Bus wire format and the AT-SPI object model.
- The official Bend compiler/runtime, OS APIs, the D-Bus daemon and the AT-SPI
  registry remain external dependencies. Keep the native bridge minimal,
  explicit and separate (`native/`).
- Before writing Bend, run `bend version` and read `bend guide` from the
  installed toolchain. Verify available syntax/effects instead of assuming old
  examples work.
- Keep source, comments, documentation and commit messages in English.

## Writing fast Bend

Correct Bend is not fast Bend by default. Measured rules (Bend 2.0.35):

- Indexed, large or hot data (bytes, pixels, coverage, quads) lives in an
  `Array<U32>` (native flat block, ~1 ns/read), not a `List`. Lists are fine
  when tiny, built once and consumed in order. Arrays are affine and cannot be
  fields of `Data` types: keep them local and convert once at the boundary.
- No `do Result`/`do Maybe` binds or callbacks per byte, pixel or glyph: each
  bind is a closure (45% of a measured profile). Thread state through one
  recursive def that matches on the result.
- `||`, `&&` and `Bool.pick` evaluate both sides; use `match` to stop early.
- Never `Array.clone` or append (`List.append`) in a loop; build with a
  reversed accumulator or a tail parameter.
- A parameter that a def only matches or passes to itself is borrowed (no
  refcount); descend trees with the selector as a parameter.
- Keep non-recursive records small (they are passed flattened; the widest one
  widens every call frame). Box big ones with an `Alias{x: T}` constructor.
- Split independent, balanced work of tens of µs or more with a parallel call
  (`a b = f(l) g(r)`); never parallelize tiny or IO-bound work.
- Measure before and after on the same input; print a result before the next
  `IO.now()`.

Here: incoming D-Bus bytes are loaded once into an `Array<U32>` and decoded
at a position by one recursive def over a job stack (`run` in
`dbus/wire.bend`); `drain` decodes frames in place and `recv` passes the
leftover and new bytes to `drain.more` without appending. Nodes are looked up
through `M.Index`, a keyed tree (`keys.bend`, copied from Voltra) built once
per tree, so diff, check and the AT-SPI answers are O(n log n). Still lists:
the encoder writes a reversed byte `List` (the socket takes a list) and
copies an array's items once per nesting level; `M.find` scans for one-off
lookups. Texts are short (a field holds at most 4096 scalars): each Text
query walks the string or the caret stops once, with the decision carried
as a parameter (no nested match on a computed value), and the diff finds a
text's replacement with one prefix pass and one pass over the reversed
rests. Held text calls are a short list per frame. `examples/bench.bend`
times these paths with output digests.

## Linux first

The goal is excellent behavior on Ian's actual Linux machine: correct
semantics, stable registration, precise events, and real use with assistive
technologies. Inspect the effective environment (bus, registry, clients)
before choosing integrations.

Build compatibility layers as the project progresses, after visible, well-made
Linux results. Do not let speculative Windows or macOS abstractions delay local
quality. Introduce abstractions from concrete needs.

## Working practice

- Preserve existing work and keep the library's boundary clear: Auvia reads
  semantics from Mokko/Kairo and routes requests back through Kairo; it does
  not draw, lay out or own interaction state.
- Favor simple, maintainable code. Pursue fast, polished behavior with evidence.
- Run the native checks after changes, and check with a real AT-SPI client when
  what clients see changes. Close every window you open.
- Report levels separately: compiled, native-tested, verified with an AT-SPI
  client, verified with a screen reader. State partial support explicitly.
- Never change global desktop or accessibility settings to make something
  work; describe the needed setting instead.
- Build sequentially. Do not impose virtual-address limits on the Bend runtime
  or suppress crash reporting. Investigate failures before retrying.
- Keep generated binaries, logs, crash dumps, credentials and machine-specific
  evidence out of Git. Stage explicit paths and preserve concurrent changes.

See [CONTRIBUTING.md](CONTRIBUTING.md) for validation commands.
