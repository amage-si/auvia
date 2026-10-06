# Auvia API

Import paths are relative to the calling file. An app next to the `Auvia`
directory uses:

```bend
import Base
import ./Auvia/model.bend as M
import ./Auvia/kairo.bend as AK
import ./Auvia/service.bend as S
```

`model.bend`, `diff.bend`, `dbus/wire.bend` and `atspi/*.bend` depend only on
Base. `kairo.bend` also imports Mokko, Kairo and Tessra. `service.bend` and
`dbus/bus.bend` perform IO through the native bridge.

## Model (`model.bend`)

Everything here is reusable data.

```bend
Node{id: U32, parent: U32, role: Role, name: String, description: String,
  states: List<&2, State>, actions: List<&2, Action>,
  relations: List<&2, Relation>, attributes: List<&2, Attr>, bounds: Box,
  value: Maybe<&2, Range>, children: List<&2, U32>}
Tree{nodes: List<&2, Node>}
Action{name, description, key}         Relation{kind: RelationKind, targets: List<&2, U32>}
Attr{key, value}                       Box{x, y, width, height}    (F32)
Range{current, min, max, step}         (F32)
Request: Activate{id, index} | Focus{id}
```

- **Ids.** `0` is the application root (role `Application`). Every other node
  names its parent, and the parent lists it in `children`, in order. Ids are
  the app's choice and must stay stable: they are the object paths assistive
  technologies hold on to.
- **Geometry.** Logical window coordinates, origin top-left, y down (the
  ecosystem contract); the root has no geometry.
- **Roles** (AT-SPI code): Application 75, Frame 23, Panel 39, Label 29,
  PushButton 43, ToggleButton 62, CheckBox 7, StatusBar 54, Heading 83,
  Picture 27, Slider 51, ProgressBar 42, Unknown 67. `role_name` gives
  libatspi's names (`button`, `label`, ...).
- **States** are AT-SPI's state types by bit (`state_bit`) and event detail
  (`state_name`): active, armed, busy, checked, defunct, editable, enabled,
  focusable, focused, horizontal, modal, multi-line, pressed, resizable,
  selectable, selected, sensitive, showing, single-line, vertical, visible,
  required, is-default, read-only, checkable. `state_words` packs a set into
  the two `u32` words of `GetState`.
- **Relations:** label-for 1, labelled-by 2, controller-for 3,
  controlled-by 4, description-for 17, described-by 18.

`check(tree)` returns `Done{Unit{}}` or the first `Problem`: `NoRoot`,
`DuplicateId`, `BadParent` (a node its parent does not list), `MissingChild`
(a listed child that is absent or names another parent), `BadRelation`.
Publish only trees that pass.

## Diff (`diff.bend`)

`diff(old, now) -> List<&2, Change>`, where `Change` is one of:

```bend
StateChanged{id, state, on}   NameChanged{id, name}   DescriptionChanged{id, text}
RoleChanged{id, role}         ValueChanged{id, value} BoundsChanged{id, bounds}
ParentChanged{id, parent}     ChildAdded{parent, index, child}
ChildRemoved{parent, index, child}  FocusGained{id}   Added{id}   Removed{id}
WindowActivated{id}  WindowDeactivated{id}  Announced{id, text, politeness}
```

A frame gaining or losing `active` is also a window (de)activation. A name
change on a node whose `live` (or `container-live`) attribute is `polite` (1)
or `assertive` (2) is also an announcement: screen readers speak name changes
only for the focused object, announcements for any. Diffing from an empty
tree (what `start` publishes) caches every node and activates active frames.

Order of announcement: children removed (old index, last first), cache
removals, states lost, property changes, cache additions, children added (new
index, first first), states gained. So focus leaves the old node before it
reaches the new one, and a new object is in caches before its parent lists it.
A node whose children keep the same members in a new order is reported as all
children moving out and back in. A newly added node reports only `focused` if it
arrives focused. Identical trees produce nothing. Attribute, action and
relation changes are not announced (AT-SPI has no event for them; clients
re-read on demand).

## Kairo and Mokko (`kairo.bend`)

```bend
Surface{id: U32, title: String, width: F32, height: F32, active: Bool}
Note{id: U32, description: String, relations: List<&2, M.Relation>,
  attributes: List<&2, M.Attr>, key: String}
build(app: String, surface: Surface, semantics: List<&2, Mk.Semantic>, notes: List<&2, Note>) -> M.Tree
route(state: KT.State, request: M.Request) -> Routed{change: KT.Change, accepted: Bool}
```

`build` makes root → frame (`surface.id`, must not collide with control ids) →
one node per Mokko `Semantic`, in Mokko's order (Kairo's Tab order). Buttons
are `PushButton` with `focusable`; text is `Label`. `enabled` adds enabled and
sensitive; Kairo focus adds focused; a held press (`Semantic.pressed`) adds
`armed`, AT-SPI's "pressed but not released" (`pressed` is a toggle's latched
state). Mokko's `Activate` becomes the action `click`. `Note`s add what Mokko
does not carry yet.

`route` performs what a request asks, through Kairo's own types:

| Request | Accepted when | Change |
| --- | --- | --- |
| `Activate{id, 0}` | runtime live, `id` is an enabled, focusable button | `[Activated{id}]`, state unchanged — exactly what a click produces |
| `Focus{id}` | runtime live, same eligibility | focus moves to `id`; a pending keyboard gesture is cancelled, as Tab does; only controls whose look changed are dirty |
| anything else | — | `unchanged`, `accepted = False` |

Feed `change` to the app's normal update path (for Mokko's demo,
`D.changed(change, font, clicks, overflow)`), so counting, relabeling and
invalidation stay Kairo's and Mokko's.

## Service (`service.bend`)

`Service` owns the bus connection (a linear `Type`):

| Function | Contract |
| --- | --- |
| `start(tree, log) -> IO(Service)` | Finds the accessibility bus (`AT_SPI_BUS_ADDRESS`, else `org.a11y.Bus.GetAddress` on the session bus), connects, authenticates, says Hello and sends `Socket.Embed` to the registry. On any failure the service is offline (`status` says why) and every other call is a no-op: the app runs on. |
| `pump(svc) -> IO(Service & List<&2, M.Request>)` | Reads what arrived without waiting, answers every call against the published tree, and returns the requests in arrival order. While calls keep arriving it answers again, waiting at most 3 ms per round for up to 256 rounds. Call once per frame. |
| `publish(svc, tree) -> IO(Service)` | Diffs against the published tree, sends the signals, and publishes `tree`. Call after every change you draw. |
| `status(svc) -> Service & String` | `live as :1.36, app id 3` or `offline: <reason>`. |
| `moved(svc, x, y) -> Service` | Records the window's top-left corner on the screen (from the platform, e.g. Ankra's `Moved` event); `Component` answers in screen coordinates (coord type 0) add it. Until then the origin is (0, 0). |
| `stop(svc) -> IO(Unit)` | Closes the connection. |

With `log = True` the service prints each call it answers and each change it
announces. Requests are answered before they are performed: `DoAction` replies
`true` once validated, and the app applies it in the same frame.

## AT-SPI mapping (`atspi/`)

Objects: `/org/a11y/atspi/accessible/root` (id 0), `/org/a11y/atspi/accessible/<id>`,
and `/org/a11y/atspi/cache`. References are `(bus name, path)`; the root's
parent is the registry's desktop, a missing child is `/org/a11y/atspi/null`.

| Interface | On | Members |
| --- | --- | --- |
| Accessible | every node | `GetChildAtIndex`, `GetChildren`, `GetIndexInParent`, `GetRelationSet`, `GetRole`, `GetRoleName`, `GetLocalizedRoleName`, `GetState`, `GetAttributes`, `GetApplication`, `GetInterfaces`; properties `Name`, `Description`, `Parent`, `ChildCount`, `Locale`, `AccessibleId` (`auvia-<id>`), `HelpText` |
| Application | root | `GetLocale`, `GetApplicationBusAddress` (empty: use the bus); properties `ToolkitName` (`Auvia`), `Version`, `AtspiVersion` (`2.1`), `Id` (set by the registry) |
| Component | non-root nodes | `Contains`, `GetAccessibleAtPoint` (direct child, ATK's semantics), `GetExtents`, `GetPosition`, `GetSize`, `GetLayer` (window 7 for frames, widget 3), `GetMDIZOrder` (0), `GrabFocus`, `GetAlpha` (1.0) |
| Action | nodes with actions | `GetActions`, `GetName`, `GetLocalizedName`, `GetDescription`, `GetKeyBinding`, `DoAction`; property `NActions` |
| Value | nodes with a range | properties `MinimumValue`, `MaximumValue`, `MinimumIncrement`, `CurrentValue`, `Text` (read-only) |
| Cache | `/org/a11y/atspi/cache` | `GetItems` (`a((so)(so)(so)iiassusau)`); signals `AddAccessible`, `RemoveAccessible` |
| Properties, Introspectable | every node | `Get`, `GetAll`, `Set` (only `Application.Id`), `Introspect` |
| Peer | every path | `Ping` |

Coordinate types: window (1) is the node's box; parent (2) subtracts the
parent's corner; screen (0) adds `Ctx.origin_x/y`, which stays (0, 0) until the
platform reports the window position. Integers are rounded.

A call whose interface does not own the member, or whose object does not
implement the interface, gets `org.freedesktop.DBus.Error.UnknownMethod`; an
unknown path gets `UnknownObject` (except `Ping`/`Introspect`). Calls flagged
`NO_REPLY_EXPECTED` are performed without a reply.

Signals use the body `(siiva{sv})`: `Event.Object.StateChanged` (detail = state
name, detail1 = 1/0), `PropertyChange` (`accessible-name`, `-description`,
`-role`, `-value`, `-parent`), `BoundsChanged` (`(iiii)`), `ChildrenChanged`
(`add`/`remove`, detail1 = index, data = child reference), and
`Event.Focus.Focus` after a node gains focus, `Event.Window.Activate` /
`Deactivate` on frames, and `Event.Object.Announcement` (detail1 =
politeness, data = text).

## D-Bus (`dbus/`)

`wire.bend`: `Value` (`DByte`, `DBool`, `DI16`, `DI32`, `DU32`, `DF64{hi, lo}`,
`DStr`, `DPath`, `DSig`, `DVar`, `DArr{sig, items}`, `DStruct`, `DEntry`, with
`DSeq`/`DEnd` chains for sequences), `Message{kind, flags, serial, reply,
path, iface, member, error, dest, sender, body}`, `encode`, `decode`, `drain`
(split a byte stream into complete messages, keeping the rest), `marshal`,
`sig`, `f64` (exact F32 → double), and constructors `call`, `signal`,
`method_return`, `error_reply`. Output is little-endian; input may be either
byte order. Signed integers are carried as their two's-complement `U32`.
Eight-byte integers decode to their bits as `DF64`.

`bus.bend`: `Link` (`Live{sock, buf, serial, name}` or `Dead{reason}`),
`open(address)` (unix `path=` or `abstract=`; SASL EXTERNAL with the uid as hex
ASCII; Hello), `send`, `recv(link, ms)`, `call` (blocking up to five seconds,
for setup only), `close`.

## Native bridge (`native/`)

| Effect | C | Behavior |
| --- | --- | --- |
| `Unix.connect(path) -> IO(Result<.., Socket>)` | `unix_connect.c` | `socket(AF_UNIX, SOCK_STREAM \| SOCK_CLOEXEC)`, `connect`, non-blocking. A leading `@` selects the abstract namespace. |
| `Unix.poll_bytes(sock, max, ms) -> IO(Socket & Result<.., Maybe<List<U32>>>)` | `unix_poll_bytes.c` | `recv` with a deadline, raw bytes. `None` on timeout, `Some{[]}` when the peer closed. |
| `Unix.uid() -> IO(U32)` | `unix_uid.c` | `getuid()`. |

Sending uses Base's `TCP.send_bytes`, which is `send(2)` on any socket. Each
effect has a JS twin for `bend file.bend` runs (Linux, through `bun:ffi`). The
checker reports defs that rely on these effects as "foreign code"; that is
expected and does not affect native builds. The C side tracks the compiler's
runtime internals and must be rebuilt with every Bend update.
