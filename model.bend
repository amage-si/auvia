import Base
import ./keys.bend as K

# Auvia's accessible model: a flat tree of nodes with stable ids.
#
# Id 0 is the application root (AT-SPI's ".../accessible/root"). Every other
# node names its parent; parents list their children in order. Geometry is
# in logical window coordinates (origin top-left, y down), as Tessra/Kairo.
# The numeric codes are AT-SPI's (at-spi2-core 2.60, atspi-constants.h).

type Role is Data:
  Application{}
  Frame{}
  Panel{}
  Label{}
  PushButton{}
  ToggleButton{}
  CheckBox{}
  StatusBar{}
  Heading{}
  Picture{}
  Slider{}
  ProgressBar{}
  Unknown{}

def role_code(r: Role) -> U32:
  match r:
    case Application{}:
      75
    case Frame{}:
      23
    case Panel{}:
      39
    case Label{}:
      29
    case PushButton{}:
      43
    case ToggleButton{}:
      62
    case CheckBox{}:
      7
    case StatusBar{}:
      54
    case Heading{}:
      83
    case Picture{}:
      27
    case Slider{}:
      51
    case ProgressBar{}:
      42
    case Unknown{}:
      67

# The names libatspi 2.60 reports (atspi_role_get_name).
def role_name(r: Role) -> String:
  match r:
    case Application{}:
      "application"
    case Frame{}:
      "frame"
    case Panel{}:
      "panel"
    case Label{}:
      "label"
    case PushButton{}:
      "button"
    case ToggleButton{}:
      "toggle button"
    case CheckBox{}:
      "check box"
    case StatusBar{}:
      "status bar"
    case Heading{}:
      "heading"
    case Picture{}:
      "image"
    case Slider{}:
      "slider"
    case ProgressBar{}:
      "progress bar"
    case Unknown{}:
      "unknown"

def same_role(a: Role, b: Role) -> Bool:
  U32.is_eq(role_code(a), role_code(b))

type State is Data:
  Active{}
  Armed{}
  Busy{}
  Checked{}
  Defunct{}
  Editable{}
  Enabled{}
  Focusable{}
  Focused{}
  Horizontal{}
  Modal{}
  MultiLine{}
  Pressed{}
  Resizable{}
  Selectable{}
  Selected{}
  Sensitive{}
  Showing{}
  SingleLine{}
  Vertical{}
  Visible{}
  Required{}
  IsDefault{}
  ReadOnly{}
  Checkable{}

def state_bit(s: State) -> U32:
  match s:
    case Active{}:
      1
    case Armed{}:
      2
    case Busy{}:
      3
    case Checked{}:
      4
    case Defunct{}:
      6
    case Editable{}:
      7
    case Enabled{}:
      8
    case Focusable{}:
      11
    case Focused{}:
      12
    case Horizontal{}:
      14
    case Modal{}:
      16
    case MultiLine{}:
      17
    case Pressed{}:
      20
    case Resizable{}:
      21
    case Selectable{}:
      22
    case Selected{}:
      23
    case Sensitive{}:
      24
    case Showing{}:
      25
    case SingleLine{}:
      26
    case Vertical{}:
      29
    case Visible{}:
      30
    case Required{}:
      33
    case IsDefault{}:
      39
    case ReadOnly{}:
      43
    case Checkable{}:
      41

# The detail of an object:state-changed event.
def state_name(s: State) -> String:
  match s:
    case Active{}:
      "active"
    case Armed{}:
      "armed"
    case Busy{}:
      "busy"
    case Checked{}:
      "checked"
    case Defunct{}:
      "defunct"
    case Editable{}:
      "editable"
    case Enabled{}:
      "enabled"
    case Focusable{}:
      "focusable"
    case Focused{}:
      "focused"
    case Horizontal{}:
      "horizontal"
    case Modal{}:
      "modal"
    case MultiLine{}:
      "multi-line"
    case Pressed{}:
      "pressed"
    case Resizable{}:
      "resizable"
    case Selectable{}:
      "selectable"
    case Selected{}:
      "selected"
    case Sensitive{}:
      "sensitive"
    case Showing{}:
      "showing"
    case SingleLine{}:
      "single-line"
    case Vertical{}:
      "vertical"
    case Visible{}:
      "visible"
    case Required{}:
      "required"
    case IsDefault{}:
      "is-default"
    case ReadOnly{}:
      "read-only"
    case Checkable{}:
      "checkable"

def same_state(a: State, b: State) -> Bool:
  U32.is_eq(state_bit(a), state_bit(b))

def has_state(ss: List<&2, State>, +s: State) -> Bool:
  match ss:
    case Nil{}:
      False{}
    case Con{h, rest}:
      same_state(h, s) || has_state(rest, s)

# AT-SPI's state set: two 32-bit words, bit n of the pair for state n.
def state_words(ss: List<&2, State>, +lo: U32, +hi: U32) -> U32 & U32:
  match ss:
    case Nil{}:
      (lo, hi)
    case Con{s, rest}:
      +b = state_bit(s)
      state_words(rest,
        Bool.pick(U32, (b < 32 : U32), U32.or(lo, U32.shln(1, U32.to_nat(b))), lo),
        Bool.pick(U32, (b >= 32 : U32), U32.or(hi, U32.shln(1, U32.to_nat((b - 32 : U32)))), hi))

type RelationKind is Data:
  LabelFor{}
  LabelledBy{}
  ControllerFor{}
  ControlledBy{}
  DescriptionFor{}
  DescribedBy{}

def relation_code(k: RelationKind) -> U32:
  match k:
    case LabelFor{}:
      1
    case LabelledBy{}:
      2
    case ControllerFor{}:
      3
    case ControlledBy{}:
      4
    case DescriptionFor{}:
      17
    case DescribedBy{}:
      18

type Relation is Data:
  Relation{kind: RelationKind, targets: List<&2, U32>}

# An action an assistive technology can invoke, by index.
type Action is Data:
  Action{name: String, description: String, key: String}

type Attr is Data:
  Attr{key: String, value: String}

type Box is Data:
  Box{x: F32, y: F32, width: F32, height: F32}

type Range is Data:
  Range{current: F32, min: F32, max: F32, step: F32}

type Node is Data:
  Node{id: U32, parent: U32, role: Role, name: String, description: String,
    states: List<&2, State>, actions: List<&2, Action>,
    relations: List<&2, Relation>, attributes: List<&2, Attr>, bounds: Box,
    value: Maybe<&2, Range>, children: List<&2, U32>}

type Tree is Data:
  Tree{nodes: List<&2, Node>}

# What an assistive technology asked the app to do. The AT-SPI layer only
# validates and forwards; the app performs it (see kairo.bend).
type Request is Data:
  Activate{id: U32, index: U32}
  Focus{id: U32}

# Builders
# --------

def zero_box() -> Box:
  Box{0.0, 0.0, 0.0, 0.0}

# A node with no states, actions, relations, attributes or value.
def plain(id: U32, parent: U32, role: Role, name: String, bounds: Box, children: List<&2, U32>) -> Node:
  Node{id, parent, role, name, "", Nil{}, Nil{}, Nil{}, Nil{}, bounds, None{}, children}

def application(name: String, children: List<&2, U32>) -> Node:
  plain(0, 0, Application{}, name, zero_box(), children)

# Access
# ------

def node_id(n: Node) -> U32:
  Node{id, p, r, nm, d, s, a, rl, at, b, v, c} = n
  id

def node_parent(n: Node) -> U32:
  Node{id, p, r, nm, d, s, a, rl, at, b, v, c} = n
  p

def node_role(n: Node) -> Role:
  Node{id, p, r, nm, d, s, a, rl, at, b, v, c} = n
  r

def node_name(n: Node) -> String:
  Node{id, p, r, nm, d, s, a, rl, at, b, v, c} = n
  nm

def node_states(n: Node) -> List<&2, State>:
  Node{id, p, r, nm, d, s, a, rl, at, b, v, c} = n
  s

def node_actions(n: Node) -> List<&2, Action>:
  Node{id, p, r, nm, d, s, a, rl, at, b, v, c} = n
  a

def node_bounds(n: Node) -> Box:
  Node{id, p, r, nm, d, s, a, rl, at, b, v, c} = n
  b

def node_children(n: Node) -> List<&2, U32>:
  Node{id, p, r, nm, d, s, a, rl, at, b, v, c} = n
  c

def nodes(t: Tree) -> List<&2, Node>:
  Tree{ns} = t
  ns

def find(ns: List<&2, Node>, +id: U32) -> Maybe<&2, Node>:
  match ns:
    case Nil{}:
      None{}
    case Con{+n, rest}:
      Bool.pick(Maybe<&2, Node>, U32.is_eq(node_id(n), id), Some{n}, find(rest, id))

def has(ns: List<&2, Node>, +id: U32) -> Bool:
  match ns:
    case Nil{}:
      False{}
    case Con{n, rest}:
      U32.is_eq(node_id(n), id) || has(rest, id)

def lookup(t: Tree, id: U32) -> Maybe<&2, Node>:
  find(nodes(t), id)

def contains_id(xs: List<&2, U32>, +x: U32) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{h, rest}:
      U32.is_eq(h, x) || contains_id(rest, x)

# The position of x in xs, or the length of xs when absent.
def index_of(xs: List<&2, U32>, +x: U32) -> U32:
  match xs:
    case Nil{}:
      0
    case Con{h, rest}:
      Bool.pick(U32, U32.is_eq(h, x), 0, (1 + index_of(rest, x) : U32))

def count(xs: List<&2, U32>) -> U32:
  U32.from_nat(List.length(&2, U32, xs))

def kids_of(m: Maybe<&2, Node>) -> List<&2, U32>:
  match m:
    case None{}:
      Nil{}
    case Some{n}:
      node_children(n)

def children_of(ns: List<&2, Node>, id: U32) -> List<&2, U32>:
  kids_of(find(ns, id))

def index_in_parent(+ns: List<&2, Node>, n: Node) -> U32:
  Node{+id, p, r, nm, d, s, a, rl, at, b, v, c} = n
  Bool.pick(U32, U32.is_eq(id, 0), 0, index_of(children_of(ns, p), id))

# Indexed trees
# -------------
#
# Lookups by id in the node list cost O(n) each; a tree indexed once
# (O(n log n)) answers them in O(log n) from keyed trees.

# Where a node is listed: the parent's id and the index there.
type Place is Data:
  Place{parent: U32, index: U32}

# The nodes, keyed by id (the first node with an id wins, as with `find`),
# and the place of each listed child.
type Index is Data:
  Index{nodes: List<&2, Node>, ids: K.Keys<Node>, places: K.Keys<Place>}

def put_new.pick(-V: Data, had: Bool, m: K.Keys<V>, +k: U32, v: V) -> K.Keys<V>:
  match had:
    case True{}:
      m
    case False{}:
      K.put(V, m, k, v)

# m with k bound to v, unless k is already there.
def put_new(-V: Data, +m: K.Keys<V>, +k: U32, v: V) -> K.Keys<V>:
  put_new.pick(V, K.has(V, m, k), m, k, v)

def ids.go(ns: List<&2, Node>, m: K.Keys<Node>) -> K.Keys<Node>:
  match ns:
    case Nil{}:
      m
    case Con{+n, rest}:
      ids.go(rest, put_new(Node, m, node_id(n), n))

def places.kids(+parent: U32, kids: List<&2, U32>, +i: U32, m: K.Keys<Place>) -> K.Keys<Place>:
  match kids:
    case Nil{}:
      m
    case Con{+c, rest}:
      places.kids(parent, rest, (i + 1 : U32), put_new(Place, m, c, Place{parent, i}))

def places.go(ns: List<&2, Node>, m: K.Keys<Place>) -> K.Keys<Place>:
  match ns:
    case Nil{}:
      m
    case Con{+n, rest}:
      places.go(rest, places.kids(node_id(n), node_children(n), 0, m))

def index.of(+ns: List<&2, Node>, +ids: K.Keys<Node>) -> Index:
  Index{ns, ids, places.go(K.values(Node, ids), K.new(Place))}

def index(+ns: List<&2, Node>) -> Index:
  index.of(ns, ids.go(ns, K.new(Node)))

def indexed(t: Tree) -> Index:
  Tree{ns} = t
  index(ns)

def listed(ix: Index) -> List<&2, Node>:
  match ix:
    case Index{ns, ids, ps}:
      ns

def get(ix: Index, +id: U32) -> Maybe<&2, Node>:
  match ix:
    case Index{ns, ids, ps}:
      K.get(Node, ids, id)

def known(ix: Index, +id: U32) -> Bool:
  match ix:
    case Index{ns, ids, ps}:
      K.has(Node, ids, id)

def place_of(ix: Index, +id: U32) -> Maybe<&2, Place>:
  match ix:
    case Index{ns, ids, ps}:
      K.get(Place, ps, id)

def children_in(ix: Index, +id: U32) -> List<&2, U32>:
  kids_of(get(ix, id))

def position.pick(same: Bool, +i: U32, +ix: Index, +p: U32, +id: U32) -> U32:
  match same:
    case True{}:
      i
    case False{}:
      index_of(children_in(ix, p), id)

def position.of(m: Maybe<&2, Place>, +ix: Index, +p: U32, +id: U32) -> U32:
  match m:
    case None{}:
      index_of(children_in(ix, p), id)
    case Some{Place{+q, +i}}:
      position.pick(U32.is_eq(q, p), i, ix, p, id)

# index_in_parent over an index: the place a child was listed at, read
# from the list only when another parent listed it first.
def position(+ix: Index, n: Node) -> U32:
  Node{+id, +p, r, nm, d, s, a, rl, at, b, v, c} = n
  Bool.pick(U32, U32.is_eq(id, 0), 0, position.of(place_of(ix, id), ix, p, id))

def in_parent.pick(same: Bool, +ix: Index, +p: U32, +id: U32) -> Bool:
  match same:
    case True{}:
      True{}
    case False{}:
      contains_id(children_in(ix, p), id)

def in_parent.of(m: Maybe<&2, Place>, +ix: Index, +p: U32, +id: U32) -> Bool:
  match m:
    case None{}:
      contains_id(children_in(ix, p), id)
    case Some{Place{+q, i}}:
      in_parent.pick(U32.is_eq(q, p), ix, p, id)

# Whether the node p lists id among its children.
def in_parent(+ix: Index, +p: U32, +id: U32) -> Bool:
  in_parent.of(place_of(ix, id), ix, p, id)

def is_enabled(n: Node) -> Bool:
  has_state(node_states(n), Enabled{})

# Validation
# ----------

type Problem is Data:
  NoRoot{}
  DuplicateId{id: U32}
  BadParent{id: U32}
  MissingChild{parent: U32, child: U32}
  BadRelation{id: U32}

def problem_text(p: Problem) -> String:
  match p:
    case NoRoot{}:
      "auvia: node 0 must exist and be the application"
    case DuplicateId{id}:
      "auvia: duplicate node id " ++ U32.show(id)
    case BadParent{id}:
      "auvia: node " ++ U32.show(id) ++ " is not listed by its parent"
    case MissingChild{parent, child}:
      "auvia: node " ++ U32.show(parent) ++ " lists missing or foreign child " ++ U32.show(child)
    case BadRelation{id}:
      "auvia: node " ++ U32.show(id) ++ " relates to a missing node"

def root_ok(m: Maybe<&2, Node>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{n}:
      same_role(node_role(n), Application{})

def first_problem(ps: List<&2, Problem>) -> Result<&2, &2, Problem, Unit>:
  match ps:
    case Nil{}:
      Done{Unit{}}
    case Con{p, rest}:
      Fail{p}

def lasts(ns: List<&2, Node>, +i: U32, m: K.Keys<U32>) -> K.Keys<U32>:
  match ns:
    case Nil{}:
      m
    case Con{n, rest}:
      lasts(rest, (i + 1 : U32), K.put(U32, m, node_id(n), i))

def is_last(m: Maybe<&2, U32>, +i: U32) -> Bool:
  match m:
    case None{}:
      True{}
    case Some{j}:
      U32.is_eq(j, i)

# A node is a duplicate when its id comes again later in the list; last
# maps each id to the position of its last node.
def duplicates.go(ns: List<&2, Node>, +i: U32, +last: K.Keys<U32>) -> List<&2, Problem>:
  match ns:
    case Nil{}:
      Nil{}
    case Con{n, rest}:
      +id = node_id(n)
      +tail = duplicates.go(rest, (i + 1 : U32), last)
      Bool.pick(List<&2, Problem>, is_last(K.get(U32, last, id), i), tail, Con{DuplicateId{id}, tail})

def duplicates(+ns: List<&2, Node>) -> List<&2, Problem>:
  duplicates.go(ns, 0, lasts(ns, 0, K.new(U32)))

def child_named(m: Maybe<&2, Node>, +parent: U32) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{n}:
      U32.is_eq(node_parent(n), parent)

# Every non-root node is listed by its parent, and every listed child exists
# and names that parent back.
def child_ok(+ix: Index, +parent: U32, kids: List<&2, U32>) -> List<&2, Problem>:
  match kids:
    case Nil{}:
      Nil{}
    case Con{+c, rest}:
      +tail = child_ok(ix, parent, rest)
      +ok = U32.is_ne(c, 0) && child_named(get(ix, c), parent)
      Bool.pick(List<&2, Problem>, ok, tail, Con{MissingChild{parent, c}, tail})

def targets_ok(+ix: Index, ts: List<&2, U32>) -> Bool:
  match ts:
    case Nil{}:
      True{}
    case Con{t, rest}:
      known(ix, t) && targets_ok(ix, rest)

def relations_ok(+ix: Index, rs: List<&2, Relation>) -> Bool:
  match rs:
    case Nil{}:
      True{}
    case Con{Relation{k, ts}, rest}:
      targets_ok(ix, ts) && relations_ok(ix, rest)

def links(+ix: Index, ns: List<&2, Node>) -> List<&2, Problem>:
  match ns:
    case Nil{}:
      Nil{}
    case Con{n, rest}:
      Node{+id, +p, r, nm, d, s, a, rl, at, b, v, kids} = n
      +tail = List.append(&2, Problem, child_ok(ix, id, kids), links(ix, rest))
      +listed = U32.is_eq(id, 0) || in_parent(ix, p, id)
      +with_parent = Bool.pick(List<&2, Problem>, listed, tail, Con{BadParent{id}, tail})
      Bool.pick(List<&2, Problem>, relations_ok(ix, rl), with_parent, Con{BadRelation{id}, with_parent})

# Checks the invariants every published tree must hold.
def check.rooted(ok: Bool, +ix: Index) -> Result<&2, &2, Problem, Unit>:
  match ok:
    case False{}:
      Fail{NoRoot{}}
    case True{}:
      first_problem(List.append(&2, Problem, duplicates(listed(ix)), links(ix, listed(ix))))

def check(t: Tree) -> Result<&2, &2, Problem, Unit>:
  +ix = indexed(t)
  check.rooted(root_ok(get(ix, 0)), ix)
