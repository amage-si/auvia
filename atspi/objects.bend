import Base
import ../model.bend as M
import ../diff.bend as D
import ../dbus/wire.bend as W

# How Auvia's nodes appear on the AT-SPI bus: object paths, references,
# interfaces, encodings and change signals.
# Interfaces: https://gitlab.gnome.org/GNOME/at-spi2-core/-/tree/main/xml

# bus: our unique name on the accessibility bus. app_id: assigned by the
# registry through Application.Id. origin: the window's top-left corner on
# the screen when known (Base's window API does not report it; see README).
type Ctx is Data:
  Ctx{bus: String, app_id: U32, locale: String, origin_x: F32, origin_y: F32}

def registry() -> String:
  "org.a11y.atspi.Registry"

def root_path() -> String:
  "/org/a11y/atspi/accessible/root"

def null_path() -> String:
  "/org/a11y/atspi/null"

def cache_path() -> String:
  "/org/a11y/atspi/cache"

def prefix() -> String:
  "/org/a11y/atspi/accessible/"

def path(+id: U32) -> String:
  Bool.pick(String, U32.is_eq(id, 0), root_path(), prefix() ++ U32.show(id))

def path_id.read(m: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match m:
    case None{}:
      None{}
    case Some{n}:
      Some{n}

# The node id an object path names, if it is one of ours.
def path_id(+p: String) -> Maybe<&2, U32>:
  Bool.pick(Maybe<&2, U32>, String.eq(p, root_path()), Some{0},
    Bool.pick(Maybe<&2, U32>, String.starts_with(p, prefix()),
      path_id.read(U32.read(String.drop(p, String.length(prefix())))), None{}))

def ref(bus: String, p: String) -> W.Value:
  W.tuple([W.DStr{bus}, W.DPath{p}])

def node_ref(ctx: Ctx, +id: U32) -> W.Value:
  Ctx{bus, a, l, x, y} = ctx
  ref(bus, path(id))

def null_ref(ctx: Ctx) -> W.Value:
  Ctx{bus, a, l, x, y} = ctx
  ref(bus, null_path())

def desktop_ref() -> W.Value:
  ref(registry(), root_path())

# The root's parent is the registry's desktop.
def parent_ref(ctx: Ctx, n: M.Node) -> W.Value:
  M.Node{+id, p, r, nm, d, s, a, rl, at, b, v, c} = n
  Bool.pick(W.Value, U32.is_eq(id, 0), desktop_ref(), node_ref(ctx, p))

def bus_name(ctx: Ctx) -> String:
  Ctx{bus, a, l, x, y} = ctx
  bus

# Interfaces
# ----------

def i_accessible() -> String:
  "org.a11y.atspi.Accessible"

def i_application() -> String:
  "org.a11y.atspi.Application"

def i_component() -> String:
  "org.a11y.atspi.Component"

def i_action() -> String:
  "org.a11y.atspi.Action"

def i_value() -> String:
  "org.a11y.atspi.Value"

def i_cache() -> String:
  "org.a11y.atspi.Cache"

def i_properties() -> String:
  "org.freedesktop.DBus.Properties"

def i_introspectable() -> String:
  "org.freedesktop.DBus.Introspectable"

def i_peer() -> String:
  "org.freedesktop.DBus.Peer"

def has_value(m: Maybe<&2, M.Range>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{r}:
      True{}

def has_actions(xs: List<&2, M.Action>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case _:
      True{}

def when(-A: Data, ok: Bool, x: A) -> List<&2, A>:
  match ok:
    case False{}:
      Nil{}
    case True{}:
      [x]

# The AT-SPI interfaces a node implements: Accessible always; Application
# on the root; Component on every node with geometry (all but the root);
# Action when it has actions; Value when it has a range.
def interfaces(n: M.Node) -> List<&2, String>:
  M.Node{+id, p, r, nm, d, s, a, rl, at, b, v, c} = n
  Con{i_accessible(), List.concat(&2, String, [
    when(String, U32.is_eq(id, 0), i_application()),
    when(String, U32.is_ne(id, 0), i_component()),
    when(String, has_actions(a), i_action()),
    when(String, has_value(v), i_value())])}

def implements(xs: List<&2, String>, +iface: String) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{x, rest}:
      String.eq(x, iface) || implements(rest, iface)

# Encodings
# ---------

def string_values(xs: List<&2, String>) -> List<&2, W.Value>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, rest}:
      Con{W.DStr{x}, string_values(rest)}

def strings(xs: List<&2, String>) -> W.Value:
  W.array("s", string_values(xs))

def words_value(p: U32 & U32) -> W.Value:
  (lo, hi) = p
  W.array("u", [W.DU32{lo}, W.DU32{hi}])

def state_value(ss: List<&2, M.State>) -> W.Value:
  words_value(M.state_words(ss, 0, 0))

def refs(ctx: Ctx, ids: List<&2, U32>) -> List<&2, W.Value>:
  match ids:
    case Nil{}:
      Nil{}
    case Con{+id, rest}:
      +c = ctx
      Con{node_ref(c, id), refs(c, rest)}

def children_value(+ctx: Ctx, ids: List<&2, U32>) -> W.Value:
  W.array("(so)", refs(ctx, ids))

def relation_value(+ctx: Ctx, r: M.Relation) -> W.Value:
  M.Relation{k, ts} = r
  W.tuple([W.DU32{M.relation_code(k)}, W.array("(so)", refs(ctx, ts))])

def relation_values(+ctx: Ctx, rs: List<&2, M.Relation>) -> List<&2, W.Value>:
  match rs:
    case Nil{}:
      Nil{}
    case Con{r, rest}:
      Con{relation_value(ctx, r), relation_values(ctx, rest)}

def relations_value(ctx: Ctx, rs: List<&2, M.Relation>) -> W.Value:
  W.array("(ua(so))", relation_values(ctx, rs))

def attr_entry(a: M.Attr) -> W.Value:
  M.Attr{k, v} = a
  W.DEntry{W.DStr{k}, W.DStr{v}}

def attr_entries(xs: List<&2, M.Attr>) -> List<&2, W.Value>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{a, rest}:
      Con{attr_entry(a), attr_entries(rest)}

def attrs_value(xs: List<&2, M.Attr>) -> W.Value:
  W.array("{ss}", attr_entries(xs))

def action_value(a: M.Action) -> W.Value:
  M.Action{name, desc, key} = a
  W.tuple([W.DStr{name}, W.DStr{desc}, W.DStr{key}])

def action_values(xs: List<&2, M.Action>) -> List<&2, W.Value>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{a, rest}:
      Con{action_value(a), action_values(rest)}

def actions_value(xs: List<&2, M.Action>) -> W.Value:
  W.array("(sss)", action_values(xs))

# Geometry
# --------

# Rounds to the nearest integer as two's-complement i32.
def to_i32(+x: F32) -> U32:
  +m = F32.to_u32(F32.round(Bool.pick(F32, (x < 0.0 : F32), F32.neg(x), x)))
  Bool.pick(U32, (x < 0.0 : F32), (0 - m : U32), m)

def from_i32(+u: U32) -> F32:
  Bool.pick(F32, (u >= 2147483648 : U32), F32.neg(U32.to_f32((0 - u : U32))), U32.to_f32(u))

def parent_box.of(m: Maybe<&2, M.Node>) -> M.Box:
  match m:
    case None{}:
      M.zero_box()
    case Some{p}:
      M.node_bounds(p)

def parent_box(+ns: List<&2, M.Node>, n: M.Node) -> M.Box:
  parent_box.of(M.find(ns, M.node_parent(n)))

# The context with the window's top-left corner at (x, y) on the screen,
# as the platform reports it (Ankra's Moved events).
def at(ctx: Ctx, +x: F32, +y: F32) -> Ctx:
  Ctx{bus, app, l, ox, oy} = ctx
  Ctx{bus, app, l, x, y}

# The offset from window coordinates to coord_type's: 0 screen (the window
# origin, when known), 1 window (none), 2 parent (minus the parent's corner).
type Offset is Data:
  Offset{dx: F32, dy: F32}

def offset(ctx: Ctx, +coord: U32, pb: M.Box) -> Offset:
  Ctx{bus, a, l, ox, oy} = ctx
  M.Box{px, py, pw, ph} = pb
  +parent = U32.is_eq(coord, 2)
  +screen = U32.is_eq(coord, 0)
  Offset{Bool.pick(F32, screen, ox, Bool.pick(F32, parent, F32.neg(px), 0.0)),
    Bool.pick(F32, screen, oy, Bool.pick(F32, parent, F32.neg(py), 0.0))}

def moved(b: M.Box, o: Offset) -> M.Box:
  M.Box{x, y, w, h} = b
  Offset{dx, dy} = o
  M.Box{(x + dx : F32), (y + dy : F32), w, h}

def box_value(b: M.Box) -> W.Value:
  M.Box{x, y, w, h} = b
  W.tuple([W.DI32{to_i32(x)}, W.DI32{to_i32(y)}, W.DI32{to_i32(w)}, W.DI32{to_i32(h)}])

# The node's box in coord_type's coordinates.
def box_in(ctx: Ctx, +ns: List<&2, M.Node>, +n: M.Node, coord: U32) -> M.Box:
  moved(M.node_bounds(n), offset(ctx, coord, parent_box(ns, n)))

def extents(ctx: Ctx, +ns: List<&2, M.Node>, +n: M.Node, coord: U32) -> W.Value:
  box_value(box_in(ctx, ns, n, coord))

def inside(b: M.Box, +px: F32, +py: F32) -> Bool:
  M.Box{+x, +y, w, h} = b
  (px >= x : F32) && (py >= y : F32) && (px < x + w : F32) && (py < y + h : F32)

def one() -> W.Value:
  W.DF64{1072693248, 0}

# Cache
# -----

def node_states_value(n: M.Node) -> W.Value:
  state_value(M.node_states(n))

# One org.a11y.atspi.Cache item: ((so) self, (so) app, (so) parent,
# i index in parent, i child count, as interfaces, s name, u role,
# s description, au states).
def cache_item(+ctx: Ctx, +ns: List<&2, M.Node>, +n: M.Node) -> W.Value:
  M.Node{+id, p, r, nm, d, s, a, rl, at, b, v, c} = n
  W.tuple([node_ref(ctx, id), node_ref(ctx, 0), parent_ref(ctx, n),
    W.DI32{M.index_in_parent(ns, n)}, W.DI32{M.count(c)}, strings(interfaces(n)),
    W.DStr{nm}, W.DU32{M.role_code(r)}, W.DStr{d}, state_value(s)])

def cache_items(+ctx: Ctx, +all: List<&2, M.Node>, ns: List<&2, M.Node>) -> List<&2, W.Value>:
  match ns:
    case Nil{}:
      Nil{}
    case Con{n, rest}:
      Con{cache_item(ctx, all, n), cache_items(ctx, all, rest)}

def item_sig() -> String:
  "((so)(so)(so)iiassusau)"

# Signals
# -------

def no_props() -> W.Value:
  W.DArr{"{sv}", W.DEnd{}}

# Event bodies are (siiva{sv}): detail, detail1, detail2, any data, and
# properties (unused).
def event(+id: U32, iface: String, member: String, detail: String, d1: U32, d2: U32, data: W.Value) -> W.Message:
  W.signal(path(id), iface, member, W.seq([W.DStr{detail}, W.DI32{d1}, W.DI32{d2}, W.DVar{data}, no_props()]))

def object_event(id: U32, member: String, detail: String, d1: U32, d2: U32, data: W.Value) -> W.Message:
  event(id, "org.a11y.atspi.Event.Object", member, detail, d1, d2, data)

def property_event(id: U32, name: String, data: W.Value) -> W.Message:
  object_event(id, "PropertyChange", name, 0, 0, data)

def added_item(+ctx: Ctx, +ns: List<&2, M.Node>, m: Maybe<&2, M.Node>) -> List<&2, W.Message>:
  match m:
    case None{}:
      Nil{}
    case Some{n}:
      [W.signal(cache_path(), i_cache(), "AddAccessible", W.seq([cache_item(ctx, ns, n)]))]

# The bus messages announcing one change. ns is the new tree.
def signals(+ctx: Ctx, +ns: List<&2, M.Node>, c: D.Change) -> List<&2, W.Message>:
  match c:
    case D.StateChanged{id, s, on}:
      [object_event(id, "StateChanged", M.state_name(s), Bool.to_u32(on), 0, W.DI32{0})]
    case D.NameChanged{id, name}:
      [property_event(id, "accessible-name", W.DStr{name})]
    case D.DescriptionChanged{id, text}:
      [property_event(id, "accessible-description", W.DStr{text})]
    case D.RoleChanged{id, role}:
      [property_event(id, "accessible-role", W.DU32{M.role_code(role)})]
    case D.ValueChanged{id, value}:
      [property_event(id, "accessible-value", W.f64(value))]
    case D.BoundsChanged{id, b}:
      [object_event(id, "BoundsChanged", "", 0, 0, box_value(b))]
    case D.ParentChanged{id, p}:
      [property_event(id, "accessible-parent", node_ref(ctx, p))]
    case D.ChildAdded{p, index, child}:
      [object_event(p, "ChildrenChanged", "add", index, 0, node_ref(ctx, child))]
    case D.ChildRemoved{p, index, child}:
      [object_event(p, "ChildrenChanged", "remove", index, 0, node_ref(ctx, child))]
    case D.FocusGained{id}:
      [event(id, "org.a11y.atspi.Event.Focus", "Focus", "", 0, 0, W.DI32{0})]
    case D.Added{id}:
      added_item(ctx, ns, M.find(ns, id))
    case D.Removed{id}:
      [W.signal(cache_path(), i_cache(), "RemoveAccessible", W.seq([node_ref(ctx, id)]))]
    case D.WindowActivated{id}:
      [event(id, "org.a11y.atspi.Event.Window", "Activate", "", 0, 0, W.DStr{""})]
    case D.WindowDeactivated{id}:
      [event(id, "org.a11y.atspi.Event.Window", "Deactivate", "", 0, 0, W.DStr{""})]
    case D.Announced{id, text, level}:
      [object_event(id, "Announcement", "", level, 0, W.DStr{text})]

def announce(+ctx: Ctx, +ns: List<&2, M.Node>, cs: List<&2, D.Change>) -> List<&2, W.Message>:
  match cs:
    case Nil{}:
      Nil{}
    case Con{c, rest}:
      List.append(&2, W.Message, signals(ctx, ns, c), announce(ctx, ns, rest))
