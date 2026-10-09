# Auvia

**Accessibility for the AMAGE UI ecosystem, in Bend 2.**

Auvia publishes an interface's semantics (roles, names, states, actions,
relations, geometry, focus) to assistive technologies, keeps them in sync with
precise change events, and routes actions back into the app. On Linux it speaks
AT-SPI2 over D-Bus. The whole stack above a Unix socket is Bend: the D-Bus wire
format, SASL authentication, the AT-SPI object model, diffing and action
policy. The native bridge is three small effects (about 100 lines of C).

**Status:** first Linux implementation, tested with **Bend 2.0.35** on Arch
(Hyprland/XWayland, at-spi2-core 2.60, dbus-broker 37). The demo window is
listed in the AT-SPI desktop, readable and operable by a real AT-SPI client.
Orca 50.2 reads it: the window title, the button with its role and
description, and every counter update. A text field (Mokko's) is an
editable entry with AT-SPI `Text` and `EditableText`: clients read its text,
caret, selection and extents, and edit it through the same rules as the
keyboard; Orca speaks its name, role, text and selection. The demo runs in
[Ankra](https://github.com/amage-si/ankra)'s native window, which reports
window focus and position, and presents through
[Voltra](https://github.com/amage-si/voltra).

![The accessible counter after AT-SPI focus and two activations.](docs/preview.png)

## What works today

- An accessible node model: 14 roles (with `entry`), 25 states, actions,
  relations, attributes, values (ranges), texts (content, caret, selection,
  caret stops for geometry), geometry and stable ids, in a validated flat
  tree.
- A tree built from Mokko's semantics and Kairo's state, with a frame for the
  window. A held press is `armed`; focus, enabled and focusable follow Kairo.
- Diffing two trees into exact events: state gained/lost, name, description,
  role, value, bounds and parent changes, children added/removed with indices,
  focus, and for texts one replacement (`text-changed:delete` then `:insert`,
  common prefix and suffix kept), `text-caret-moved` and
  `text-selection-changed`. Focus leaves the old node before reaching the new
  one.
- AT-SPI interfaces: `Accessible`, `Application`, `Component`, `Action`,
  `Value`, `Text`, `EditableText`, `Cache`, plus `Properties`,
  `Introspectable` and `Peer`.
  Registration with the registry (`Socket.Embed`), `Event.Object` and
  `Event.Focus` signals, `window:activate`/`deactivate` for the frame (sent at
  start too, so screen readers learn the window), `object:announcement` for
  name changes of live regions (`live` attribute), cache add/remove signals.
  Calls are answered in several short rounds per frame while a client keeps
  asking, so Orca's few hundred startup calls take milliseconds, not seconds.
- Action routing: an AT-SPI `DoAction` on an enabled button becomes exactly one
  Kairo `Activated` (the same action a click produces); `GrabFocus` moves Kairo's
  focus as Tab would. Anything else is refused and changes nothing.
- Text editing from assistive technologies: `InsertText`, `DeleteText`,
  `SetTextContents`, `CutText`, `CopyText`, `PasteText`, `SetCaretOffset` and
  the selection calls on a Mokko field go through Mokko's `feed` and Kairo's
  editing rules (`field.bend`), so what the layout or Kairo refuses (U+2615,
  a line break, a text over the limit) is refused for the client too: the
  call returns false and the text, caret and selection stay as they were.
  The caller's answer waits for the app's verdict and is sent after the
  change's signals.
- A D-Bus implementation in Bend: marshalling and unmarshalling of every basic
  and container type, both byte orders, framing of partial reads, UTF-8,
  F32 to double.

### How it was verified

| Level | Evidence |
| --- | --- |
| Compiled | Every module, the tests and the four examples build natively with `bend -o`. The checker reports only the expected "relies on foreign code" notice for the native effects. |
| Native checks | `tests.bend`: **120 checks pass** (wire format against GLib-encoded golden bytes, model validation, diff order, AT-SPI answers, screen extents from the window origin, Kairo routing, one end-to-end pure flow; Text and EditableText answers, text events and their bytes against GLib's, and edits of a real Mokko field with Liberation Sans, refusals included). |
| Real AT-SPI client | `tools/atspi_probe.py` (libatspi through python `gi`) against the counter on Ankra's native window: **18 checks pass**, including Tab, Space and click sent to the window, AT-SPI `GrabFocus` and `DoAction`. `tools/demo_check.sh` wraps the probe, captures only the window and adds an independent `gdbus` read. Against `examples/headless` with `--field Nome`: **26 checks pass**, 11 of them on the field (text, caret, word, extents, `GrabFocus`, `InsertText` and `DeleteText` performed and announced, a refused `InsertText` of U+20AC returning false with nothing changed, caret and selection). An AT-SPI edit is answered in about 0.05-0.1 s, the headless loop's 50 ms pump. |
| Window focus and position | With synthetic FocusIn/FocusOut sent to the window, the frame gains and loses `active` and `window:activate`/`deactivate` are emitted; after the window manager moved the window to (300, 200), the frame's screen extents were `[300, 200, 480, 320]` and the button's `[479, 284, 122, 44]`. |
| Screen reader | `tools/orca_check.sh` runs Orca 50.2 with throwaway settings and a silent private speech-dispatcher, and keeps its debug log. Orca said: `'Auvia - contador'` (window title, on start), `'Clique aqui'` `'button.'` `'Soma um ao contador.'` (Tab), `'Cliques: 1'` (Space), `'Cliques: 2'` (Enter). This run predates the move to Ankra's native window and was not repeated. `tools/orca_check.sh field` (the headless example, driven by the probe): on focus Orca said `'Nome'` `'entry'` `'olá.'`, and for the selection `'und'` `'selected'`. Edits made by the probe through AT-SPI were processed (braille updated) but not spoken: Orca speaks inserted text only when it comes from typing or a paste it saw, and these came from no key event. Typing into a field under Orca needs a window with a field, which no Auvia example has yet. |

The live check (window `Auvia - contador`, XWayland, 480×320) sees this tree:

```text
application "auvia-counter"                       Accessible, Application
  frame "Auvia - contador"   active enabled ...   Component  [0, 0, 480, 320]
    label "AMAGE Eco"                             Component  [161, 32, 157, 32]
    button "Clique aqui"     focusable ...        Component, Action(click)  [179, 84, 122, 44]
    label "Cliques: 0"       live=polite          Component  [32, 148, 416, 18]
```

and this event sequence, each announced once: Tab → `focused=1` + `focus:` on
the button; Space → `armed=1`, `armed=0`, name `Cliques: 1`; click outside →
`focused=0`; AT-SPI `GrabFocus` → `focused=1` + `focus:`; AT-SPI `DoAction(0)` →
name `Cliques: 2`. The window closes normally: the accessibility connection
is closed explicitly, then Voltra and the window (exit 0, 0 native objects
left). While idle the counter presents nothing and wakes about 20 times per
second to answer the bus (see Current boundaries).

Under Orca, one gap remains: after a click on empty space Kairo clears focus,
but Orca keeps the button as its point of focus, so the next Tab back to the
same button is silent. That is Orca not re-announcing an unchanged focus; a
toolkit that kept focus on the button (or moved it elsewhere) would avoid it.

## Quick start

Requirements: the [Bend 2 toolchain](https://bend-lang.com), Clang 14 or newer,
X11 headers for the demo, an AT-SPI bus (`at-spi2-core`), and the sibling
AMAGE libraries checked out next to `Auvia` (Mokko, Kairo, Tessra, Chromi,
Ankra, Voltra, Runika, Syllo, Dithra) for the adapter and the demo, keeping
their capitalized directory names. The checks and the headless example
read Liberation Sans (`/usr/share/fonts/liberation/LiberationSans-Regular.ttf`)
for the text field. The demo also needs a Vulkan 1.3 driver and an X11 or
XWayland display.

```sh
export BEND_NO_TELEMETRY=1
mkdir -p build
bend tests.bend -o build/tests
./build/tests --threads 2 --gpu off
```

The accessible counter window:

```sh
bend examples/counter.bend -o build/counter
./build/counter --threads 2 --gpu off
```

It prints its bus name and every call and event it handles. Inspect it with any
AT-SPI client, or run the end-to-end check, which opens the window, drives it,
captures only that window and closes it:

```sh
tools/demo_check.sh        # needs python3-gobject (Atspi typelib), grim, hyprctl
```

`examples/headless.bend` is the same protocol without a window, on the same
stack, with a button, a counter and a text field:

```sh
bend examples/headless.bend -o build/headless
./build/headless --threads 2 --gpu off &
tools/atspi_probe.py --app auvia-headless --button Incrementar \
  --label-prefix Cliques: --field Nome --out build/evidence/headless-probe.json
```

`examples/bus_probe.bend` checks that the session and accessibility buses are
reachable.

## The contract

An app keeps a `Service`, publishes a `Tree` after each change, and routes the
requests it gets back:

```bend
svc : S.Service <- S.start(tree, log)          # join the a11y bus, Embed
got : S.Service & List<&2, M.Request> <- S.pump(svc)   # answer calls, no wait
svc = S.settle(svc, request, performed)        # text requests: the verdict
svc : S.Service <- S.publish(svc, next_tree)   # diff, announce, answer
```

`kairo.bend` connects the AMAGE stack: `build(app, surface, semantics, notes)`
makes the tree from Mokko's `Semantic` list (`build.with` adds each field's
text), and `route(state, request)` returns the Kairo `Change` to apply,
exactly as if it came from the user. `field.bend` does the same for Mokko's
text field: `content(edit_state)` is the field's text for the tree, and
`edit(font, size, bounds, state, id, field, request)` performs a text request
through Mokko's `feed`; its `accepted` goes to `S.settle`. The
[API reference](docs/api.md) has the types, ids, ordering and refusal rules.

Ids are stable `U32`s chosen by the app; `0` is the application root. Node ids
become object paths (`/org/a11y/atspi/accessible/<id>`), so an assistive
technology keeps its place across updates.

## Current boundaries

- **Waiting on two sources.** Ankra's wait watches the X connection only, so
  the counter wakes at least every 50 ms to answer the accessibility bus
  (about 20 wakeups per second while idle, no frames presented). A wait that
  watches both sockets would remove them.
- **Window focus** follows the real window (Ankra's `Focused` events through
  Kairo's `WindowFocus`). Kairo ignores keys and presses while the window is
  inactive, as a desktop does; the probe's keyboard checks therefore run
  after a focus-in.
- **Screen coordinates** use the position Ankra reports (`S.moved`). Under a
  Wayland compositor, that is the XWayland position the compositor gives the
  window.
- **Native window id.** Ankra exposes it; Auvia does not use it yet.
- **Kairo inputs.** Kairo has no `Activate{id}` or `Focus{id}` input, so
  `route` builds the change itself with Kairo's own `dirty.finish` and the public
  `State` fields. Native inputs in Kairo would make that path Kairo's own.
- **Text, partly.** Text is single-line and has no attributes (runs and
  default attributes are empty); sentence and paragraph are the whole line;
  `GetTextBeforeOffset`/`AfterOffset`, `ScrollSubstringTo*`,
  `GetBoundedRanges` and the multi-selection calls are not implemented.
  Labels have no `Text` (their name carries the text). `InsertText`'s
  length argument is ignored: the whole string is inserted or nothing.
  Copy and paste are requests to the app, which owns the clipboard
  (`examples/headless` has none and only logs them).
- **Not implemented:** the `Selection`, `Table`, `Hyperlink` and
  `Collection` interfaces; setting `Value.CurrentValue`; relation-change
  events; device (key) event listeners.
- **Performance.** Messages and trees are lists; fine for small interfaces, not
  measured for large ones. A tree is rebuilt and diffed only when Kairo marks
  the frame dirty, the window gains or loses focus, or a request arrives.

## Repository map

| Path | Purpose |
| --- | --- |
| [model.bend](model.bend) | Roles, states, actions, relations, nodes, the tree and its validation. |
| [diff.bend](diff.bend) | Tree diff into ordered change events. |
| [text.bend](text.bend) | Text queries: slices, clusters, words, extents, hit tests, the edit between two texts. |
| [kairo.bend](kairo.bend) | Tree from Mokko semantics and field contents; requests routed into Kairo. |
| [field.bend](field.bend) | Mokko's text field: its EditState as a node text; text requests through Mokko's `feed`. |
| [service.bend](service.bend) | Registration, publishing and answering on the a11y bus (IO). |
| [atspi/objects.bend](atspi/objects.bend) | Paths, references, interfaces, encodings, signals. |
| [atspi/serve.bend](atspi/serve.bend) | Method calls and properties, introspection. |
| [dbus/wire.bend](dbus/wire.bend) | D-Bus marshalling, unmarshalling and framing. |
| [dbus/bus.bend](dbus/bus.bend) | A D-Bus connection: SASL EXTERNAL, Hello, send, receive, call. |
| [native/](native/) | The native bridge: `Unix.connect`, `Unix.poll_bytes`, `Unix.uid` (C and JS). |
| [tests.bend](tests.bend) | Native checks. |
| [examples/](examples/) | The accessible counter, a headless host with a button and a text field, a bus probe, a bench. |
| [tools/](tools/) | Validation only: libatspi probe, X11 input/close helpers, the end-to-end and Orca scripts. |
| [docs/api.md](docs/api.md) | Types, contracts and protocol details. |

## Direction

A window with a text field (the integrated demo in Chromi), so Orca can be
checked while typing; text for labels, one wait for the window and the bus,
then longer Orca sessions (flat review, where-am-I, more widgets). More widgets and
interfaces follow the components Mokko adds. Other platforms come after the
Linux experience is complete.

See [CONTRIBUTING.md](CONTRIBUTING.md) for development rules. The API is
experimental. Licensed under either of [Apache License 2.0](LICENSE-APACHE) or [MIT](LICENSE-MIT), at your option.

## License

Licensed under either of

- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE))
- MIT license ([LICENSE-MIT](LICENSE-MIT))

at your option. Unless you explicitly state otherwise, any contribution
intentionally submitted for inclusion in this work, as defined in the
Apache-2.0 license, shall be dual licensed as above, without any additional
terms or conditions.
