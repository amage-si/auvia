# Changelog

All notable changes to Auvia are recorded here. Auvia follows
[semantic versioning](https://semver.org) in its 0.x form: while the API is
experimental, a minor version (0.2.0) may change it in breaking ways and a
patch version (0.1.1) only fixes. Auvia is built from source together with its
sibling AMAGE libraries; the set of versions tested together is listed in
[eco-build's releases](https://github.com/amage-si/eco-build/tree/main/releases).

## [0.1.1] - 2026-10-09

### Changed

- Build with Bend 2.0.36: the four native effects register as
  `io_eff(CID(name), run)`, the form 2.0.36 requires (upstream #1281 removed
  the third `need` argument; an effect that waits parks itself).
  `Unix.poll_bytes` already parked itself with `io_wait_on` (socket readable
  or deadline), so waiting is unchanged. Its comments now point to the
  `try_` twins of Base's `tcp_recv`, since 2.0.36 removed `tcp_poll`. No API
  change.
- The frame decoder's internal `Next` constructor `Ready` is now `Whole`:
  2.0.36's Base declares `Poll`'s `Ready`, and a constructor name may be
  declared once.
- The bus link reads `TCP.send_bytes`' 2.0.36 failure, which carries the
  unsent bytes beside the error; a failed send still closes the link with
  the error's text.
- The application's AT-SPI `Version` property reports 0.1.1.

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

[0.1.1]: https://github.com/amage-si/auvia/releases/tag/v0.1.1
[0.1.0]: https://github.com/amage-si/auvia/releases/tag/v0.1.0
