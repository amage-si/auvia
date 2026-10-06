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
