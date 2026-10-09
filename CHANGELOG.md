# Changelog

All notable changes to Auvia are recorded here. Auvia follows
[semantic versioning](https://semver.org) in its 0.x form: while the API is
experimental, a minor version (0.2.0) may change it in breaking ways and a
patch version (0.1.1) only fixes. Auvia is built from source together with its
sibling AMAGE libraries; the set of versions tested together is listed in
[eco-build's releases](https://github.com/amage-si/eco-build/tree/main/releases).

## [0.1.0] - 2026-10-09

First tagged release, tested with Bend 2.0.35 on Linux (X11/XWayland) as part
of AMAGE Eco 0.1.0.

### Included

- AT-SPI2 over D-Bus written in Bend: wire format, SASL, object model,
  diffing and action policy, over a four-effect native socket bridge.
- Accessible tree from Mokko semantics and Kairo state, with exact change
  events and focus.
- `Accessible`, `Application`, `Component`, `Action`, `Value`, `Text`,
  `EditableText` and `Cache` interfaces; edits from assistive tools go
  through the same rules as typing.
- D-Bus decoding from one byte array and keyed node lookups (decoding 1000
  messages: 673 to 42 ms; diffing 2000 nodes: 703 to 11.5 ms).
- Integrated in the eco demo; the bus wait shares Ankra's `watch`.
- 121 native checks; the libatspi probe passes against the demo and the
  headless example.

[0.1.0]: https://github.com/amage-si/auvia/releases/tag/v0.1.0
