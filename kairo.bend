import Base
import ./model.bend as M
import ../Mokko/main.bend as Mk
import ../Kairo/types.bend as KT
import ../Kairo/nodes.bend as KN
import ../Kairo/dirty.bend as KD
import ../Tessra/geometry.bend as G

# The bridge between the AMAGE interaction stack and Auvia's model:
# Mokko's semantics become accessible nodes, and requests from assistive
# technologies go back into Kairo as ordinary changes.

# The window the controls live in. Its node is the frame under the root.
type Surface is Data:
  Surface{id: U32, title: String, width: F32, height: F32, active: Bool}

# What Mokko does not carry yet: a description, relations, attributes and a
# key binding for the node's action. Notes for absent ids are ignored.
type Note is Data:
  Note{id: U32, description: String, relations: List<&2, M.Relation>,
    attributes: List<&2, M.Attr>, key: String}

def box(r: G.Rect) -> M.Box:
  G.Rect{x, y, w, h} = r
  M.Box{x, y, w, h}

def role(r: KT.Role) -> M.Role:
  match r:
    case KT.ButtonRole{}:
      M.PushButton{}
    case KT.TextRole{}:
      M.Label{}

def is_button(r: KT.Role) -> Bool:
  KN.is_button(r)

def note_for(ns: List<&2, Note>, +id: U32) -> Note:
  match ns:
    case Nil{}:
      Note{id, "", Nil{}, Nil{}, ""}
    case Con{Note{+nid, d, rl, at, k}, rest}:
      Bool.pick(Note, U32.is_eq(nid, id), Note{nid, d, rl, at, k}, note_for(rest, id))

def on(ok: Bool, s: M.State) -> List<&2, M.State>:
  match ok:
    case False{}:
      Nil{}
    case True{}:
      [s]

def mk_actions(xs: List<&2, Mk.SemanticAction>, +key: String) -> List<&2, M.Action>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{Mk.Activate{}, rest}:
      Con{M.Action{"click", "", key}, mk_actions(rest, key)}

# A Mokko control as an accessible node. Kairo's momentary press is ARMED
# ("pressed but not yet released"); PRESSED is a toggle's latched state.
def control.noted(frame: U32, s: Mk.Semantic, n: Note) -> M.Node:
  Mk.Semantic{id, +r, label, bounds, +enabled, focused, pressed, actions} = s
  Note{nid, desc, rels, attrs, key} = n
  +button = is_button(r)
  states = List.concat(&2, M.State, [[M.Visible{}, M.Showing{}], on(enabled, M.Enabled{}), on(enabled, M.Sensitive{}),
    on(button, M.Focusable{}), on(focused, M.Focused{}), on(pressed, M.Armed{})])
  M.Node{id, frame, role(r), label, desc, states, mk_actions(actions, key), rels, attrs, box(bounds), None{}, Nil{}}

def semantic_id(s: Mk.Semantic) -> U32:
  Mk.Semantic{id, r, l, b, e, f, p, a} = s
  id

def control(frame: U32, +s: Mk.Semantic, +notes: List<&2, Note>) -> M.Node:
  control.noted(frame, s, note_for(notes, semantic_id(s)))

def controls(+frame: U32, ss: List<&2, Mk.Semantic>, +notes: List<&2, Note>) -> List<&2, M.Node>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{s, rest}:
      Con{control(frame, s, notes), controls(frame, rest, notes)}

def ids(ss: List<&2, Mk.Semantic>) -> List<&2, U32>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{s, rest}:
      Con{semantic_id(s), ids(rest)}

def frame_node(surface: Surface, kids: List<&2, U32>) -> M.Node:
  Surface{id, title, w, h, active} = surface
  M.Node{id, 0, M.Frame{}, title, "", List.append(&2, M.State, [M.Enabled{}, M.Sensitive{}, M.Visible{}, M.Showing{}], on(active, M.Active{})),
    Nil{}, Nil{}, Nil{}, M.Box{0.0, 0.0, w, h}, None{}, kids}

def surface_id(s: Surface) -> U32:
  Surface{id, t, w, h, a} = s
  id

# The tree an app publishes: application root, its window frame, and the
# frame's controls in Mokko's order (which is also Kairo's Tab order).
def build(app: String, +surface: Surface, +semantics: List<&2, Mk.Semantic>, +notes: List<&2, Note>) -> M.Tree:
  +frame = surface_id(surface)
  M.Tree{Con{M.application(app, [frame]), Con{frame_node(surface, ids(semantics)), controls(frame, semantics, notes)}}}

# Routing
# -------

# The outcome of a request: a Kairo change to apply as if it came from the
# user, and whether the request was accepted.
type Routed is Data:
  Routed{change: KT.Change, accepted: Bool}

def target(nodes: List<&2, KT.Node>, +id: U32) -> Maybe<&2, KT.Node>:
  match nodes:
    case Nil{}:
      None{}
    case Con{+n, rest}:
      KT.Node{nid, r, l, role, e, f} = n
      Bool.pick(Maybe<&2, KT.Node>, U32.is_eq(nid, id), Some{n}, target(rest, id))

def eligible(m: Maybe<&2, KT.Node>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{n}:
      KN.eligible(n)

def live(s: KT.State) -> Bool:
  KT.State{ns, h, f, c, k, t, d, live, a, w, hh} = s
  live

def nodes_of(s: KT.State) -> List<&2, KT.Node>:
  KT.State{ns, h, f, c, k, t, d, live, a, w, hh} = s
  ns

def unchanged(s: KT.State) -> Routed:
  Routed{KD.unchanged(s), False{}}

# Exactly one Activated{id}, the same action a click or Space produces, for
# an enabled button of a live runtime; anything else is refused unchanged.
def activate(ok: Bool, +s: KT.State, +id: U32) -> Routed:
  match ok:
    case False{}:
      unchanged(s)
    case True{}:
      Routed{KD.finish(s, s, [KT.Activated{id}]), True{}}

# Moves keyboard focus as Tab would: a pending keyboard gesture is
# cancelled, and only the controls whose look changed are invalidated.
def focus(ok: Bool, +s: KT.State, +id: U32) -> Routed:
  match ok:
    case False{}:
      unchanged(s)
    case True{}:
      KT.State{ns, h, f, c, k, t, d, l, a, w, hh} = s
      Routed{KD.finish(s, KT.State{ns, h, id, c, 0, 0, d, l, a, w, hh}, Nil{}), True{}}

def route(+s: KT.State, r: M.Request) -> Routed:
  match r:
    case M.Activate{+id, index}:
      activate(live(s) && U32.is_eq(index, 0) && eligible(target(nodes_of(s), id)), s, id)
    case M.Focus{+id}:
      focus(live(s) && eligible(target(nodes_of(s), id)), s, id)
