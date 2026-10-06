import Base
import ./model.bend as M

# Diffing two published trees into the precise changes an assistive
# technology needs, instead of rebuilding its view.
#
# Order: children removed (descending index), cache removals, states lost,
# property changes, cache additions, children added (ascending index),
# states gained. So focus leaves the old node before it reaches the new one,
# and a new object is announced to caches before its parent lists it.

type Change is Data:
  StateChanged{id: U32, state: M.State, on: Bool}
  NameChanged{id: U32, name: String}
  DescriptionChanged{id: U32, text: String}
  RoleChanged{id: U32, role: M.Role}
  ValueChanged{id: U32, value: F32}
  BoundsChanged{id: U32, bounds: M.Box}
  ParentChanged{id: U32, parent: U32}
  ChildAdded{parent: U32, index: U32, child: U32}
  ChildRemoved{parent: U32, index: U32, child: U32}
  FocusGained{id: U32}
  Added{id: U32}
  Removed{id: U32}

type Delta is Data:
  Delta{child_removed: List<&2, Change>, removed: List<&2, Change>,
    losses: List<&2, Change>, props: List<&2, Change>, added: List<&2, Change>,
    child_added: List<&2, Change>, gains: List<&2, Change>}

def empty() -> Delta:
  Delta{Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}}

def cat(a: List<&2, Change>, b: List<&2, Change>) -> List<&2, Change>:
  List.append(&2, Change, a, b)

def join(a: Delta, b: Delta) -> Delta:
  Delta{a1, a2, a3, a4, a5, a6, a7} = a
  Delta{b1, b2, b3, b4, b5, b6, b7} = b
  Delta{cat(a1, b1), cat(a2, b2), cat(a3, b3), cat(a4, b4), cat(a5, b5), cat(a6, b6), cat(a7, b7)}

def flatten(d: Delta) -> List<&2, Change>:
  Delta{a1, a2, a3, a4, a5, a6, a7} = d
  cat(a1, cat(a2, cat(a3, cat(a4, cat(a5, cat(a6, a7))))))

# States
# ------

def lost(+id: U32, old: List<&2, M.State>, +now: List<&2, M.State>) -> List<&2, Change>:
  match old:
    case Nil{}:
      Nil{}
    case Con{+s, rest}:
      +tail = lost(id, rest, now)
      Bool.pick(List<&2, Change>, M.has_state(now, s), tail, Con{StateChanged{id, s, False{}}, tail})

def focus_extra(+s: M.State, id: U32) -> List<&2, Change>:
  Bool.pick(List<&2, Change>, M.same_state(s, M.Focused{}), [FocusGained{id}], Nil{})

def gained(+id: U32, now: List<&2, M.State>, +old: List<&2, M.State>) -> List<&2, Change>:
  match now:
    case Nil{}:
      Nil{}
    case Con{+s, rest}:
      +tail = gained(id, rest, old)
      Bool.pick(List<&2, Change>, M.has_state(old, s), tail,
        Con{StateChanged{id, s, True{}}, List.append(&2, Change, focus_extra(s, id), tail)})

# Properties
# ----------

def box_eq(a: M.Box, b: M.Box) -> Bool:
  M.Box{x, y, w, h} = a
  M.Box{u, v, s, t} = b
  F32.is_eq(x, u) && F32.is_eq(y, v) && F32.is_eq(w, s) && F32.is_eq(h, t)

def current(m: Maybe<&2, M.Range>) -> F32:
  match m:
    case None{}:
      0.0
    case Some{M.Range{c, lo, hi, st}}:
      c

def value_events(+id: U32, old: Maybe<&2, M.Range>, now: Maybe<&2, M.Range>) -> List<&2, Change>:
  match now:
    case None{}:
      Nil{}
    case Some{M.Range{+c, lo, hi, st}}:
      Bool.pick(List<&2, Change>, F32.is_eq(current(old), c), Nil{}, [ValueChanged{id, c}])

def when(changed: Bool, e: Change) -> List<&2, Change>:
  match changed:
    case False{}:
      Nil{}
    case True{}:
      [e]

def props(o: M.Node, n: M.Node) -> List<&2, Change>:
  M.Node{i0, p0, r0, nm0, d0, s0, a0, rl0, at0, b0, v0, c0} = o
  M.Node{+id, +p, +r, +nm, +d, s, a, rl, at, +b, v, c} = n
  cat(when(Bool.not(String.eq(nm0, nm)), NameChanged{id, nm}),
    cat(when(Bool.not(String.eq(d0, d)), DescriptionChanged{id, d}),
      cat(when(Bool.not(M.same_role(r0, r)), RoleChanged{id, r}),
        cat(value_events(id, v0, v),
          cat(when(Bool.not(box_eq(b0, b)), BoundsChanged{id, b}),
            when(U32.is_ne(p0, p), ParentChanged{id, p}))))))

# Children
# --------

def kids_eq(a: List<&2, U32>, b: List<&2, U32>) -> Bool:
  match a b:
    case Nil{} Nil{}:
      True{}
    case Con{x, xs} Con{y, ys}:
      U32.is_eq(x, y) && kids_eq(xs, ys)
    case _ _:
      False{}

# Old children missing from now, at their old index, last first.
def gone(+id: U32, +old: List<&2, U32>, walk: List<&2, U32>, +now: List<&2, U32>) -> List<&2, Change>:
  match walk:
    case Nil{}:
      Nil{}
    case Con{+c, rest}:
      +tail = gone(id, old, rest, now)
      Bool.pick(List<&2, Change>, M.contains_id(now, c), tail,
        List.append(&2, Change, tail, [ChildRemoved{id, M.index_of(old, c), c}]))

# New children missing from old, at their new index, first first.
def came(+id: U32, +now: List<&2, U32>, walk: List<&2, U32>, +old: List<&2, U32>) -> List<&2, Change>:
  match walk:
    case Nil{}:
      Nil{}
    case Con{+c, rest}:
      +tail = came(id, now, rest, old)
      Bool.pick(List<&2, Change>, M.contains_id(old, c), tail, Con{ChildAdded{id, M.index_of(now, c), c}, tail})

def is_empty(xs: List<&2, Change>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case _:
      False{}

def children_delta(+id: U32, +old: List<&2, U32>, +now: List<&2, U32>) -> Delta:
  +removed = gone(id, old, old, now)
  +added = came(id, now, now, old)
  # Same members in another order: move every child out and back in.
  +reorder = is_empty(removed) && is_empty(added) && Bool.not(kids_eq(old, now))
  Delta{Bool.pick(List<&2, Change>, reorder, gone(id, old, old, Nil{}), removed), Nil{}, Nil{}, Nil{},
    Nil{}, Bool.pick(List<&2, Change>, reorder, came(id, now, now, Nil{}), added), Nil{}}

# Nodes
# -----

def node_delta(o: M.Node, n: M.Node) -> Delta:
  +old = o
  +now = n
  +id = M.node_id(now)
  join(Delta{Nil{}, Nil{}, lost(id, M.node_states(old), M.node_states(now)), props(old, now), Nil{}, Nil{},
    gained(id, M.node_states(now), M.node_states(old))},
    children_delta(id, M.node_children(old), M.node_children(now)))

# A node with no counterpart is announced to caches; if it arrives
# focused, focus is announced too.
def arrival(n: M.Node) -> Delta:
  M.Node{+id, p, r, nm, d, s, a, rl, at, b, v, c} = n
  Delta{Nil{}, Nil{}, Nil{}, Nil{}, [Added{id}], Nil{}, gained(id, List.filter(~M.State, ~(x => M.same_state(x, M.Focused{})), s), Nil{})}

def pair_delta(m: Maybe<&2, M.Node>, n: M.Node) -> Delta:
  match m:
    case None{}:
      arrival(n)
    case Some{o}:
      node_delta(o, n)

def common(+old: List<&2, M.Node>, now: List<&2, M.Node>) -> Delta:
  match now:
    case Nil{}:
      empty()
    case Con{+n, rest}:
      join(pair_delta(M.find(old, M.node_id(n)), n), common(old, rest))

def departures(old: List<&2, M.Node>, +now: List<&2, M.Node>) -> Delta:
  match old:
    case Nil{}:
      empty()
    case Con{o, rest}:
      +id = M.node_id(o)
      +tail = departures(rest, now)
      Bool.pick(Delta, M.has(now, id), tail, join(Delta{Nil{}, [Removed{id}], Nil{}, Nil{}, Nil{}, Nil{}, Nil{}}, tail))

# Every change from old to now, in announcement order.
def diff(old: M.Tree, now: M.Tree) -> List<&2, Change>:
  M.Tree{+a} = old
  M.Tree{+b} = now
  flatten(join(departures(a, b), common(a, b)))
