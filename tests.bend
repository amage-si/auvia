import Base
import ./model.bend as M
import ./diff.bend as D
import ./dbus/wire.bend as W
import ./atspi/objects.bend as O
import ./atspi/serve.bend as S
import ./kairo.bend as AK
import ../Mokko/main.bend as Mk
import ../Kairo/types.bend as KT
import ../Kairo/main.bend as K
import ../Tessra/geometry.bend as G

# Auvia's native checks. Golden byte lists come from GLib's GDBusMessage
# encoder (python3 gi, GLib 2.86), an implementation independent of Auvia.

# Fixtures
# --------

def visible() -> List<&2, M.State>:
  [M.Enabled{}, M.Sensitive{}, M.Visible{}, M.Showing{}]

def with_focus(on: Bool, +ss: List<&2, M.State>) -> List<&2, M.State>:
  Bool.pick(List<&2, M.State>, on, List.append(&2, M.State, ss, [M.Focused{}]), ss)

def button(+id: U32, name: String, +focused: Bool, +enabled: Bool, box: M.Box) -> M.Node:
  M.Node{id, 1, M.PushButton{}, name, "Soma um",
    with_focus(focused, Bool.pick(List<&2, M.State>, enabled, List.append(&2, M.State, visible(), [M.Focusable{}]), [M.Visible{}, M.Showing{}, M.Focusable{}])),
    [M.Action{"click", "", "space"}], [M.Relation{M.ControllerFor{}, [3]}], Nil{}, box, None{}, Nil{}}

def label(text: String) -> M.Node:
  M.Node{3, 1, M.Label{}, text, "", visible(), Nil{}, [M.Relation{M.ControlledBy{}, [2]}], [M.Attr{"live", "polite"}],
    M.Box{20.0, 120.0, 160.0, 24.0}, None{}, Nil{}}

def frame(kids: List<&2, U32>) -> M.Node:
  M.Node{1, 0, M.Frame{}, "Janela", "", List.append(&2, M.State, visible(), [M.Active{}]), Nil{}, Nil{}, Nil{},
    M.Box{0.0, 0.0, 400.0, 200.0}, None{}, kids}

def b2(+focus: U32) -> M.Node:
  button(2, "Clique aqui", U32.is_eq(focus, 2), True{}, M.Box{20.0, 60.0, 160.0, 44.0})

def b4(+focus: U32) -> M.Node:
  button(4, "Outro", U32.is_eq(focus, 4), True{}, M.Box{200.0, 60.0, 160.0, 44.0})

def fixture(+focus: U32, text: String) -> M.Tree:
  M.Tree{[M.application("app", [1]), frame([2, 3, 4]), b2(focus), label(text), b4(focus)]}

# Diff rendering
# --------------

def key(c: D.Change) -> String:
  match c:
    case D.StateChanged{id, s, on}:
      "state:" ++ U32.show(id) ++ ":" ++ M.state_name(s) ++ ":" ++ Bool.show(on)
    case D.NameChanged{id, n}:
      "name:" ++ U32.show(id) ++ ":" ++ n
    case D.DescriptionChanged{id, t}:
      "desc:" ++ U32.show(id) ++ ":" ++ t
    case D.RoleChanged{id, r}:
      "role:" ++ U32.show(id) ++ ":" ++ M.role_name(r)
    case D.ValueChanged{id, v}:
      "value:" ++ U32.show(id)
    case D.BoundsChanged{id, b}:
      "bounds:" ++ U32.show(id)
    case D.ParentChanged{id, p}:
      "parent:" ++ U32.show(id) ++ ":" ++ U32.show(p)
    case D.ChildAdded{p, i, c}:
      "child+:" ++ U32.show(p) ++ ":" ++ U32.show(i) ++ ":" ++ U32.show(c)
    case D.ChildRemoved{p, i, c}:
      "child-:" ++ U32.show(p) ++ ":" ++ U32.show(i) ++ ":" ++ U32.show(c)
    case D.FocusGained{id}:
      "focus:" ++ U32.show(id)
    case D.Added{id}:
      "add:" ++ U32.show(id)
    case D.Removed{id}:
      "del:" ++ U32.show(id)

def keys(cs: List<&2, D.Change>) -> String:
  match cs:
    case Nil{}:
      ""
    case Con{c, Nil{}}:
      key(c)
    case Con{c, rest}:
      key(c) ++ "|" ++ keys(rest)

def diffs(a: M.Tree, b: M.Tree) -> String:
  keys(D.diff(a, b))

def same(a: String, +b: String) -> Bool:
  String.eq(a, b)

def b5() -> M.Node:
  button(5, "Novo", False{}, True{}, M.Box{20.0, 150.0, 80.0, 30.0})

def grown() -> M.Tree:
  M.Tree{[M.application("app", [1]), frame([2, 3, 4, 5]), b2(0), label("Cliques: 0"), b4(0), b5()]}

def shrunk() -> M.Tree:
  M.Tree{[M.application("app", [1]), frame([2]), b2(0)]}

def reordered() -> M.Tree:
  M.Tree{[M.application("app", [1]), frame([4, 2, 3]), b2(0), label("Cliques: 0"), b4(0)]}

def moved() -> M.Tree:
  M.Tree{[M.application("app", [1]), frame([2, 3, 4]), button(2, "Clique aqui", False{}, True{}, M.Box{24.0, 60.0, 160.0, 44.0}), label("Cliques: 0"), b4(0)]}

# Model checks
# ------------

def problem(r: Result<&2, &2, M.Problem, Unit>) -> String:
  match r:
    case Done{u}:
      "ok"
    case Fail{p}:
      M.problem_text(p)

def checked(t: M.Tree) -> String:
  problem(M.check(t))

def words(p: U32 & U32, lo: U32, hi: U32) -> Bool:
  (a, b) = p
  U32.is_eq(a, lo) && U32.is_eq(b, hi)

# Wire helpers
# ------------

def bytes_eq(a: List<&2, U32>, b: List<&2, U32>) -> Bool:
  match a b:
    case Nil{} Nil{}:
      True{}
    case Con{x, xs} Con{y, ys}:
      U32.is_eq(x, y) && bytes_eq(xs, ys)
    case _ _:
      False{}

def body_bytes(v: W.Value) -> List<&2, U32>:
  List.reverse(&2, U32, W.out_rev(W.marshal(v, W.Out{0, Nil{}})))

def f64_is(v: W.Value, hi: U32, lo: U32) -> Bool:
  match v:
    case W.DF64{a, b}:
      U32.is_eq(a, hi) && U32.is_eq(b, lo)
    case _:
      False{}

def golden_reply_signal() -> List<&2, U32>:
  [108,2,1,1,9,0,0,0,7,0,0,0,64,0,0,0,7,1,115,0,20,0,0,0,111,114,103,46,102,114,101,101,100,101,115,107,116,111,112,46,68,66,117,115,0,0,0,0,6,1,115,0,4,0,0,0,58,49,46,53,0,0,0,0,8,1,103,0,1,115,0,0,5,1,117,0,1,0,0,0,4,0,0,0,58,49,46,53,0,108,4,1,1,9,0,0,0,8,0,0,0,93,0,0,0,1,1,111,0,21,0,0,0,47,111,114,103,47,102,114,101,101,100,101,115,107,116,111,112,47,68,66,117,115,0,0,0,2,1,115,0,20,0,0,0,111,114,103,46,102,114,101,101,100,101,115,107,116,111,112,46,68,66,117,115,0,0,0,0,8,1,103,0,1,115,0,0,3,1,115,0,12,0,0,0,78,97,109,101,65,99,113,117,105,114,101,100,0,0,0,0,4,0,0,0,58,49,46,53,0]

def golden_doaction_be() -> List<&2, U32>:
  [66,1,0,1,0,0,0,4,0,0,1,44,0,0,0,129,7,1,115,0,0,0,0,4,58,49,46,57,0,0,0,0,1,1,111,0,0,0,0,28,47,111,114,103,47,97,49,49,121,47,97,116,115,112,105,47,97,99,99,101,115,115,105,98,108,101,47,50,0,0,0,0,2,1,115,0,0,0,0,21,111,114,103,46,97,49,49,121,46,97,116,115,112,105,46,65,99,116,105,111,110,0,0,0,6,1,115,0,0,0,0,5,58,49,46,52,50,0,0,0,8,1,103,0,1,105,0,0,3,1,115,0,0,0,0,8,68,111,65,99,116,105,111,110,0,0,0,0,0,0,0,0,0,0,0,0]

def golden_setid() -> List<&2, U32>:
  [108,1,0,1,48,0,0,0,5,0,0,0,140,0,0,0,7,1,115,0,4,0,0,0,58,49,46,50,0,0,0,0,1,1,111,0,31,0,0,0,47,111,114,103,47,97,49,49,121,47,97,116,115,112,105,47,97,99,99,101,115,115,105,98,108,101,47,114,111,111,116,0,2,1,115,0,31,0,0,0,111,114,103,46,102,114,101,101,100,101,115,107,116,111,112,46,68,66,117,115,46,80,114,111,112,101,114,116,105,101,115,0,6,1,115,0,5,0,0,0,58,49,46,52,50,0,0,0,8,1,103,0,3,115,115,118,0,0,0,0,0,0,0,0,3,1,115,0,3,0,0,0,83,101,116,0,0,0,0,0,26,0,0,0,111,114,103,46,97,49,49,121,46,97,116,115,112,105,46,65,112,112,108,105,99,97,116,105,111,110,0,0,2,0,0,0,73,100,0,1,105,0,0,0,7,0,0,0]

def golden_complex_body() -> List<&2, U32>:
  [4,0,0,0,58,49,46,49,0,0,0,0,2,0,0,0,47,120,0,0,19,0,0,0,4,0,0,0,58,49,46,50,0,0,0,0,2,0,0,0,47,121,0,0,22,0,0,0,1,0,0,0,107,0,1,115,0,0,0,0,5,0,0,0,195,167,195,163,111,0,0,0,1,0,0,0,254,255,255,255,3,0,0,0,4,0,0,0,8,0,0,0,0,16,0,0,8,0,0,0,0,0,0,0,0,0,0,0,0,0,240,63,255,255]

def complex_value() -> W.Value:
  W.seq([W.tuple([W.DStr{":1.1"}, W.DPath{"/x"}]), W.array("(so)", [W.tuple([W.DStr{":1.2"}, W.DPath{"/y"}])]),
    W.array("{sv}", [W.DEntry{W.DStr{"k"}, W.DVar{W.DStr{"ção"}}}]),
    W.tuple([W.DI32{1}, W.DI32{(0 - 2 : U32)}, W.DI32{3}, W.DI32{4}]), W.array("u", [W.DU32{4096}, W.DU32{8}]),
    W.f64(1.0), W.DI16{65535}])

def msg_text(m: Maybe<&2, W.Message>) -> String:
  match m:
    case None{}:
      "none"
    case Some{W.Message{k, f, s, r, p, i, mem, e, d, sn, b}}:
      U32.show(k) ++ "/" ++ U32.show(f) ++ "/" ++ U32.show(s) ++ "/" ++ U32.show(r) ++ "/" ++ p ++ "/" ++ i ++ "/" ++ mem ++ "/" ++ e ++ "/" ++ d ++ "/" ++ sn ++ "/" ++ W.sig(b)

def msgs_text(ms: List<&2, W.Message>) -> String:
  match ms:
    case Nil{}:
      ""
    case Con{m, rest}:
      msg_text(Some{m}) ++ ";" ++ msgs_text(rest)

def inbox_text(ib: W.Inbox) -> String:
  W.Inbox{ms, rest, bad} = ib
  msgs_text(ms) ++ "bad=" ++ U32.show(bad) ++ " rest=" ++ U32.show(W.size(rest))

def body_of(m: Maybe<&2, W.Message>) -> W.Value:
  match m:
    case None{}:
      W.DEnd{}
    case Some{W.Message{k, f, s, r, p, i, mem, e, d, sn, b}}:
      b

def sample() -> W.Message:
  W.Message{1, 0, 42, 0, "/org/a11y/atspi/accessible/2", "org.a11y.atspi.Action", "DoAction", "", ":1.42", ":1.9",
    W.seq([W.DI32{0}, W.array("(so)", [W.tuple([W.DStr{"ação"}, W.DPath{"/a"}])]), W.f64(0.5)])}

def is_int(v: W.Value, +x: U32) -> Bool:
  match v:
    case W.DI32{y}:
      U32.is_eq(x, y)
    case W.DVar{W.DI32{y}}:
      U32.is_eq(x, y)
    case _:
      False{}

# Serving
# -------

def ctx() -> O.Ctx:
  O.Ctx{":1.42", 0, "pt_BR.UTF-8", 0.0, 0.0}

def call(p: String, iface: String, member: String, body: W.Value) -> W.Message:
  W.Message{1, 0, 10, 0, p, iface, member, "", ":1.42", ":1.9", body}

def node_path(id: U32) -> String:
  O.path(id)

def acc() -> String:
  "org.a11y.atspi.Accessible"

def serve1(m: W.Message, t: M.Tree) -> S.Served:
  S.serve([m], ctx(), t)

def ask(m: W.Message) -> S.Served:
  serve1(m, fixture(0, "Cliques: 0"))

def first_out(s: S.Served) -> Maybe<&2, W.Message>:
  S.Served{c, out, r} = s
  List.head(&2, W.Message, out)

def out_count(s: S.Served) -> U32:
  S.Served{c, out, r} = s
  U32.from_nat(List.length(&2, W.Message, out))

def kind_of(m: Maybe<&2, W.Message>) -> U32:
  match m:
    case None{}:
      0
    case Some{W.Message{k, f, s, r, p, i, mem, e, d, sn, b}}:
      k

def reply_kind(s: S.Served) -> U32:
  kind_of(first_out(s))

def error_of(m: Maybe<&2, W.Message>) -> String:
  match m:
    case None{}:
      ""
    case Some{W.Message{k, f, s, r, p, i, mem, e, d, sn, b}}:
      e

def reply_error(s: S.Served) -> String:
  error_of(first_out(s))

def reply_arg(s: S.Served) -> W.Value:
  W.arg(body_of(first_out(s)), 0n)

def reply_sig(s: S.Served) -> String:
  W.sig(body_of(first_out(s)))

def requests(s: S.Served) -> List<&2, M.Request>:
  S.Served{c, out, r} = s
  r

def req_text(rs: List<&2, M.Request>) -> String:
  match rs:
    case Nil{}:
      ""
    case Con{M.Activate{id, i}, rest}:
      "activate:" ++ U32.show(id) ++ ":" ++ U32.show(i) ++ ";" ++ req_text(rest)
    case Con{M.Focus{id}, rest}:
      "focus:" ++ U32.show(id) ++ ";" ++ req_text(rest)

def app_id(s: S.Served) -> U32:
  S.Served{O.Ctx{b, id, l, x, y}, out, r} = s
  id

def is_bool(v: W.Value, b: Bool) -> Bool:
  match v:
    case W.DBool{x}:
      Bool.not(Bool.xor(x, b))
    case _:
      False{}

def var_inner(v: W.Value) -> W.Value:
  match v:
    case W.DVar{x}:
      x
    case other:
      other

def var_str(v: W.Value) -> String:
  match v:
    case W.DVar{x}:
      W.text(x)
    case _:
      ""

def ref_path(v: W.Value) -> String:
  match v:
    case W.DStruct{W.DSeq{b, W.DSeq{p, W.DEnd{}}}}:
      W.text(p)
    case _:
      "?"

def first_item(v: W.Value) -> W.Value:
  match v:
    case W.DArr{s, W.DSeq{h, t}}:
      h
    case _:
      W.DEnd{}

def items(v: W.Value) -> U32:
  match v:
    case W.DArr{s, xs}:
      U32.from_nat(List.length(&2, W.Value, W.args(xs)))
    case _:
      0

def ints.go(xs: List<&2, W.Value>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{x, rest}:
      U32.show(W.word(x)) ++ "," ++ ints.go(rest)

def ints(v: W.Value) -> String:
  match v:
    case W.DStruct{xs}:
      ints.go(W.args(xs))
    case _:
      "?"

def state_lo(v: W.Value) -> U32:
  W.word(first_item(v))

def slider(+current: F32) -> M.Node:
  M.Node{6, 1, M.Slider{}, "Volume", "", List.append(&2, M.State, visible(), [M.Focusable{}]), Nil{}, Nil{}, Nil{},
    M.Box{20.0, 160.0, 200.0, 20.0}, Some{M.Range{current, 0.0, 10.0, 0.5}}, Nil{}}

def with_slider(+current: F32) -> M.Tree:
  M.Tree{[M.application("app", [1]), frame([6]), slider(current)]}

def disabled_tree() -> M.Tree:
  M.Tree{[M.application("app", [1]), frame([2, 3, 4]), button(2, "Clique aqui", False{}, False{}, M.Box{20.0, 60.0, 160.0, 44.0}), label("Cliques: 0"), b4(0)]}

def no_reply_call() -> W.Message:
  W.Message{1, 1, 11, 0, node_path(2), "org.a11y.atspi.Action", "DoAction", "", ":1.42", ":1.9", W.seq([W.DI32{0}])}

def signal_of(c: D.Change) -> Maybe<&2, W.Message>:
  List.head(&2, W.Message, O.signals(ctx(), M.nodes(fixture(2, "Cliques: 0")), c))

def member_of(m: Maybe<&2, W.Message>) -> String:
  match m:
    case None{}:
      ""
    case Some{W.Message{k, f, s, r, p, i, mem, e, d, sn, b}}:
      i ++ "." ++ mem ++ "@" ++ p ++ ":" ++ W.sig(b)

# Kairo routing
# -------------

def kbutton(+id: U32, x: F32, enabled: Bool) -> KT.Node:
  KT.Node{id, G.Rect{x, 60.0, 160.0, 44.0}, "Botão " ++ U32.show(id), KT.ButtonRole{}, enabled, True{}}

def ktext() -> KT.Node:
  KT.Node{3, G.Rect{20.0, 120.0, 160.0, 24.0}, "Cliques: 0", KT.TextRole{}, True{}, False{}}

def knodes() -> List<&2, KT.Node>:
  [kbutton(2, 20.0, True{}), ktext(), kbutton(5, 200.0, False{})]

def kstate() -> KT.State:
  KT.State{knodes(), 0, 0, 0, 0, 0, False{}, True{}, True{}, 480.0, 320.0}

def closed_state() -> KT.State:
  KT.State{knodes(), 0, 0, 0, 0, 0, False{}, False{}, True{}, 480.0, 320.0}

def activations(r: AK.Routed) -> U32:
  AK.Routed{KT.Change{s, actions, dirty, layout}, ok} = r
  K.activation_count(actions)

def accepted(r: AK.Routed) -> Bool:
  AK.Routed{c, ok} = r
  ok

def routed_state(r: AK.Routed) -> KT.State:
  AK.Routed{KT.Change{s, actions, dirty, layout}, ok} = r
  s

def dirty_count(r: AK.Routed) -> U32:
  AK.Routed{KT.Change{s, actions, dirty, layout}, ok} = r
  U32.from_nat(List.length(&2, G.Rect, dirty))

def kfocus(s: KT.State) -> U32:
  KT.State{ns, h, f, c, k, t, d, l, a, w, hh} = s
  f

def space_down() -> KT.Input:
  KT.KeyDown{KT.SpaceKey{}, False{}, False{}}

def tab() -> KT.Input:
  KT.KeyDown{KT.TabKey{}, False{}, False{}}

def change_count(c: KT.Change) -> U32:
  KT.Change{n, actions, d, l} = c
  K.activation_count(actions)

def release_count(s: KT.State) -> U32:
  change_count(K.dispatch(s, KT.KeyUp{KT.SpaceKey{}}))

def semantics.go(ns: List<&2, KT.Node>, +s: KT.State) -> List<&2, Mk.Semantic>:
  match ns:
    case Nil{}:
      Nil{}
    case Con{n, rest}:
      Con{Mk.semantic(n, s), semantics.go(rest, s)}

# The semantics Mokko derives from a Kairo state.
def semantics(+s: KT.State) -> List<&2, Mk.Semantic>:
  KT.State{ns, h, f, c, k, t, d, l, a, w, hh} = s
  semantics.go(ns, s)

def notes() -> List<&2, AK.Note>:
  [AK.Note{2, "Soma um ao contador", [M.Relation{M.ControllerFor{}, [3]}], Nil{}, "space"},
    AK.Note{3, "", [M.Relation{M.ControlledBy{}, [2]}], [M.Attr{"live", "polite"}], ""}]

def built(s: KT.State) -> M.Tree:
  AK.build("app", AK.Surface{100, "Janela", 480.0, 320.0, True{}}, semantics(s), notes())

def states_of(m: Maybe<&2, M.Node>) -> List<&2, M.State>:
  match m:
    case None{}:
      Nil{}
    case Some{n}:
      M.node_states(n)

def node_states(t: M.Tree, id: U32) -> List<&2, M.State>:
  states_of(M.lookup(t, id))

def node_text(m: Maybe<&2, M.Node>) -> String:
  match m:
    case None{}:
      "missing"
    case Some{M.Node{id, p, r, nm, d, s, a, rl, at, b, v, c}}:
      U32.show(id) ++ "<" ++ U32.show(p) ++ ":" ++ M.role_name(r) ++ ":" ++ nm ++ ":" ++ d ++ ":" ++ U32.show(M.count(c))

# End to end: an AT-SPI DoAction becomes exactly one Kairo activation, and
# the counter's new label becomes exactly one name-change announcement.
def e2e.after(r: AK.Routed, +before: M.Tree) -> String:
  AK.Routed{KT.Change{s, actions, dirty, layout}, ok} = r
  +n = K.activation_count(actions)
  U32.show(n) ++ "|" ++ diffs(before, built(K.next(K.set_label(s, 3, "Cliques: " ++ U32.show(n)))))

def e2e.requested(rs: List<&2, M.Request>, +before: M.Tree) -> String:
  match rs:
    case Con{r, Nil{}}:
      e2e.after(AK.route(kstate(), r), before)
    case _:
      "requests: " ++ req_text(rs)

def e2e() -> String:
  +before = built(kstate())
  e2e.requested(requests(serve1(call(node_path(2), "org.a11y.atspi.Action", "DoAction", W.seq([W.DI32{0}])), before)), before)

type Check is Data:
  Check{ok: Bool, name: String}

def checks.wire() -> List<&2, Check>:
  [
    Check{bytes_eq(body_bytes(complex_value()), golden_complex_body()), "wire: marshalled body equals GLib's bytes ((so) a(so) a{sv} (iiii) au d n)"},
    Check{bytes_eq(body_bytes(W.seq([W.DByte{1}, W.DArr{"(so)", W.DEnd{}}])), [1, 0, 0, 0, 0, 0, 0, 0]), "wire: empty array keeps its length and element padding"},
    Check{same(msg_text(W.decode(W.encode(sample()))), "1/0/42/0//org/a11y/atspi/accessible/2/org.a11y.atspi.Action/DoAction//:1.42/:1.9/ia(so)d"), "wire: encode then decode keeps every header field and the body signature"},
    Check{same(ref_path(first_item(W.arg(body_of(W.decode(W.encode(sample()))), 1n))), "/a"), "wire: nested array of structs decodes"},
    Check{same(inbox_text(W.drain(golden_reply_signal())), "2/1/7/1/////:1.5/org.freedesktop.DBus/s;4/1/8/0//org/freedesktop/DBus/org.freedesktop.DBus/NameAcquired////s;bad=0 rest=0"), "wire: two GLib messages in one read split and decode"},
    Check{same(inbox_text(W.drain(List.take(&2, U32, golden_reply_signal(), 100n))), "2/1/7/1/////:1.5/org.freedesktop.DBus/s;bad=0 rest=11"), "wire: a partial message waits for more bytes"},
    Check{same(msg_text(W.decode(golden_doaction_be())), "1/0/300/0//org/a11y/atspi/accessible/2/org.a11y.atspi.Action/DoAction//:1.42/:1.9/i"), "wire: big-endian GLib call decodes"},
    Check{is_int(W.arg(body_of(W.decode(golden_doaction_be())), 0n), 0), "wire: big-endian argument decodes"},
    Check{is_int(W.arg(body_of(W.decode(golden_setid())), 2n), 7), "wire: variant argument of Properties.Set decodes"},
    Check{same(W.from_utf8(W.utf8("ação, café, ✓, 𝄞")), "ação, café, ✓, 𝄞"), "wire: UTF-8 round trip up to four bytes"},
    Check{f64_is(W.f64(1.0), 1072693248, 0) && f64_is(W.f64(F32.neg(2.5)), 3221487616, 0) && f64_is(W.f64(0.0), 0, 0) && f64_is(W.f64(0.1), 1069128089, 2684354560), "wire: F32 to double is exact"},
    Check{U32.is_eq(W.is_none(W.decode([108, 1, 0, 1, 0, 0])), 1), "wire: truncated message is rejected"}
  ]

def checks.model() -> List<&2, Check>:
  [
    Check{same(checked(fixture(2, "Cliques: 0")), "ok"), "model: fixture is a valid tree"},
    Check{same(checked(M.Tree{[M.application("app", [1]), frame([2, 2]), b2(0)]}), "auvia: duplicate node id 2") || same(checked(M.Tree{[M.application("app", [1]), frame([2]), b2(0), b2(0)]}), "auvia: duplicate node id 2"), "model: duplicate ids rejected"},
    Check{same(checked(M.Tree{[frame([2]), b2(0)]}), "auvia: node 0 must exist and be the application"), "model: tree without application root rejected"},
    Check{same(checked(M.Tree{[M.application("app", [1]), frame([2, 9]), b2(0)]}), "auvia: node 1 lists missing or foreign child 9"), "model: missing child rejected"},
    Check{same(checked(M.Tree{[M.application("app", [1]), frame([3]), b2(0), label("x")]}), "auvia: node 2 is not listed by its parent"), "model: orphan rejected"},
    Check{same(checked(M.Tree{[M.application("app", [1]), frame([2]), b2(0)]}), "auvia: node 2 relates to a missing node"), "model: relation to a missing node rejected"},
    Check{words(M.state_words([M.Focused{}, M.ReadOnly{}, M.Enabled{}], 0, 0), 4352, 2048), "model: state set packs into AT-SPI's two words"}
  ]

def checks.diff() -> List<&2, Check>:
  [
    Check{same(diffs(fixture(2, "Cliques: 0"), fixture(2, "Cliques: 0")), ""), "diff: identical trees emit nothing"},
    Check{same(diffs(fixture(2, "Cliques: 0"), fixture(4, "Cliques: 0")), "state:2:focused:False|state:4:focused:True|focus:4"), "diff: focus leaves the old node before reaching the new one"},
    Check{same(diffs(fixture(0, "Cliques: 0"), fixture(2, "Cliques: 1")), "name:3:Cliques: 1|state:2:focused:True|focus:2"), "diff: name change and focus gain are exact"},
    Check{same(diffs(fixture(0, "Cliques: 0"), grown()), "add:5|child+:1:3:5"), "diff: a new child is cached before its parent lists it"},
    Check{same(diffs(fixture(0, "Cliques: 0"), shrunk()), "child-:1:2:4|child-:1:1:3|del:3|del:4"), "diff: removed children go last index first"},
    Check{same(diffs(fixture(0, "Cliques: 0"), reordered()), "child-:1:2:4|child-:1:1:3|child-:1:0:2|child+:1:0:4|child+:1:1:2|child+:1:2:3"), "diff: reorder moves children out and back"},
    Check{same(diffs(fixture(0, "Cliques: 0"), moved()), "bounds:2"), "diff: geometry change emits only bounds"}
  ]

def checks.serving() -> List<&2, Check>:
  [
    Check{same(ref_path(first_item(reply_arg(ask(call(O.root_path(), acc(), "GetChildren", W.DEnd{}))))), "/org/a11y/atspi/accessible/1"), "atspi: root lists its frame"},
    Check{U32.is_eq(W.word(reply_arg(ask(call(node_path(2), acc(), "GetRole", W.DEnd{})))), 43), "atspi: button role is push button (43)"},
    Check{same(W.text(reply_arg(ask(call(node_path(2), acc(), "GetLocalizedRoleName", W.DEnd{})))), "button"), "atspi: role name"},
    Check{same(var_str(reply_arg(ask(call(node_path(2), "org.freedesktop.DBus.Properties", "Get", W.seq([W.DStr{acc()}, W.DStr{"Name"}]))))), "Clique aqui"), "atspi: Name property"},
    Check{U32.is_eq(U32.and(state_lo(reply_arg(serve1(call(node_path(2), acc(), "GetState", W.DEnd{}), fixture(2, "x")))), 6400), 6400), "atspi: state words carry enabled, focusable and focused"},
    Check{same(ref_path(reply_arg(ask(call(node_path(2), acc(), "GetApplication", W.DEnd{})))), "/org/a11y/atspi/accessible/root"), "atspi: GetApplication points at the root"},
    Check{same(ints(reply_arg(ask(call(node_path(2), "org.a11y.atspi.Component", "GetExtents", W.seq([W.DU32{1}]))))), "20,60,160,44,"), "atspi: window extents"},
    Check{same(ref_path(reply_arg(ask(call(node_path(1), "org.a11y.atspi.Component", "GetAccessibleAtPoint", W.seq([W.DI32{30}, W.DI32{70}, W.DU32{1}]))))), "/org/a11y/atspi/accessible/2"), "atspi: hit test finds the button"},
    Check{same(ref_path(reply_arg(ask(call(node_path(1), "org.a11y.atspi.Component", "GetAccessibleAtPoint", W.seq([W.DI32{390}, W.DI32{190}, W.DU32{1}]))))), "/org/a11y/atspi/null"), "atspi: hit test outside every child is null"},
    Check{is_bool(reply_arg(ask(call(node_path(2), "org.a11y.atspi.Component", "Contains", W.seq([W.DI32{179}, W.DI32{103}, W.DU32{1}])))), True{}) && is_bool(reply_arg(ask(call(node_path(2), "org.a11y.atspi.Component", "Contains", W.seq([W.DI32{180}, W.DI32{103}, W.DU32{1}])))), False{}), "atspi: Contains uses the exclusive right edge"},
    Check{same(reply_sig(ask(call(node_path(2), acc(), "GetRelationSet", W.DEnd{}))), "a(ua(so))") && same(ints(first_item(reply_arg(ask(call(node_path(2), acc(), "GetRelationSet", W.DEnd{}))))), "3,0,"), "atspi: relation set (controller-for)"},
    Check{U32.is_eq(items(reply_arg(ask(call(node_path(3), acc(), "GetAttributes", W.DEnd{})))), 1), "atspi: attributes"},
    Check{U32.is_eq(items(reply_arg(ask(call(O.cache_path(), "org.a11y.atspi.Cache", "GetItems", W.DEnd{})))), 5) && same(reply_sig(ask(call(O.cache_path(), "org.a11y.atspi.Cache", "GetItems", W.DEnd{}))), "a((so)(so)(so)iiassusau)"), "atspi: cache lists every node with libatspi's item signature"},
    Check{same(req_text(requests(ask(call(node_path(2), "org.a11y.atspi.Action", "DoAction", W.seq([W.DI32{0}]))))), "activate:2:0;") && is_bool(reply_arg(ask(call(node_path(2), "org.a11y.atspi.Action", "DoAction", W.seq([W.DI32{0}])))), True{}), "atspi: DoAction(0) answers true and requests one activation"},
    Check{same(req_text(requests(ask(call(node_path(2), "org.a11y.atspi.Action", "DoAction", W.seq([W.DI32{1}]))))), "") && is_bool(reply_arg(ask(call(node_path(2), "org.a11y.atspi.Action", "DoAction", W.seq([W.DI32{1}])))), False{}), "atspi: DoAction on a missing index is refused"},
    Check{same(req_text(requests(serve1(call(node_path(2), "org.a11y.atspi.Action", "DoAction", W.seq([W.DI32{0}])), disabled_tree()))), ""), "atspi: DoAction on a disabled button is refused"},
    Check{same(reply_error(ask(call(node_path(3), "org.a11y.atspi.Action", "DoAction", W.seq([W.DI32{0}])))), "org.freedesktop.DBus.Error.UnknownMethod"), "atspi: a label has no Action interface"},
    Check{same(req_text(requests(ask(call(node_path(2), "org.a11y.atspi.Component", "GrabFocus", W.DEnd{})))), "focus:2;") && same(req_text(requests(ask(call(node_path(3), "org.a11y.atspi.Component", "GrabFocus", W.DEnd{})))), ""), "atspi: GrabFocus only for focusable, enabled nodes"},
    Check{same(reply_error(ask(call("/org/a11y/atspi/accessible/77", acc(), "GetRole", W.DEnd{}))), "org.freedesktop.DBus.Error.UnknownObject"), "atspi: unknown object"},
    Check{U32.is_eq(reply_kind(ask(call("/", "org.freedesktop.DBus.Peer", "Ping", W.DEnd{}))), 2), "atspi: Ping answers on any path"},
    Check{same(reply_error(ask(call(node_path(2), "org.a11y.atspi.Action", "GetRole", W.DEnd{}))), "org.freedesktop.DBus.Error.UnknownMethod"), "atspi: member under the wrong interface is refused"},
    Check{U32.is_eq(app_id(ask(call(O.root_path(), "org.freedesktop.DBus.Properties", "Set", W.seq([W.DStr{"org.a11y.atspi.Application"}, W.DStr{"Id"}, W.DVar{W.DI32{7}}])))), 7), "atspi: the registry sets the application id"},
    Check{U32.is_eq(out_count(ask(no_reply_call())), 0) && same(req_text(requests(ask(no_reply_call()))), "activate:2:0;"), "atspi: NO_REPLY_EXPECTED calls act without a reply"},
    Check{U32.is_eq(out_count(ask(W.signal("/x", "a.b", "C", W.DEnd{}))), 0), "atspi: signals need no answer"},
    Check{same(W.sig(var_inner(reply_arg(serve1(call(node_path(6), "org.freedesktop.DBus.Properties", "Get", W.seq([W.DStr{"org.a11y.atspi.Value"}, W.DStr{"CurrentValue"}])), with_slider(2.5))))), "d") && f64_is(var_inner(reply_arg(serve1(call(node_path(6), "org.freedesktop.DBus.Properties", "Get", W.seq([W.DStr{"org.a11y.atspi.Value"}, W.DStr{"MaximumValue"}])), with_slider(2.5)))), 1076101120, 0), "atspi: Value properties are doubles"},
    Check{same(diffs(with_slider(2.5), with_slider(3.0)), "value:6") && same(checked(with_slider(1.0)), "ok"), "diff: value change is one event"},
    Check{same(member_of(signal_of(D.StateChanged{2, M.Focused{}, True{}})), "org.a11y.atspi.Event.Object.StateChanged@/org/a11y/atspi/accessible/2:siiva{sv}"), "atspi: state change signal"},
    Check{same(member_of(signal_of(D.FocusGained{2})), "org.a11y.atspi.Event.Focus.Focus@/org/a11y/atspi/accessible/2:siiva{sv}"), "atspi: legacy focus signal"},
    Check{same(member_of(signal_of(D.Added{2})), "org.a11y.atspi.Cache.AddAccessible@/org/a11y/atspi/cache:((so)(so)(so)iiassusau)"), "atspi: cache add signal"},
    Check{same(member_of(signal_of(D.ChildRemoved{1, 0, 2})), "org.a11y.atspi.Event.Object.ChildrenChanged@/org/a11y/atspi/accessible/1:siiva{sv}"), "atspi: children changed signal"}
  ]

def checks.kairo() -> List<&2, Check>:
  [
    Check{U32.is_eq(activations(AK.route(kstate(), M.Activate{2, 0})), 1) && accepted(AK.route(kstate(), M.Activate{2, 0})), "kairo: activate produces exactly one Activated"},
    Check{U32.is_eq(activations(AK.route(kstate(), M.Activate{5, 0})), 0) && Bool.not(accepted(AK.route(kstate(), M.Activate{5, 0}))), "kairo: disabled button refuses"},
    Check{Bool.not(accepted(AK.route(kstate(), M.Activate{3, 0}))) && Bool.not(accepted(AK.route(kstate(), M.Activate{99, 0}))) && Bool.not(accepted(AK.route(kstate(), M.Activate{2, 1}))), "kairo: text, unknown id and unknown action refuse"},
    Check{Bool.not(accepted(AK.route(closed_state(), M.Activate{2, 0}))), "kairo: closed runtime refuses"},
    Check{U32.is_eq(kfocus(routed_state(AK.route(kstate(), M.Focus{2}))), 2) && U32.is_eq(dirty_count(AK.route(kstate(), M.Focus{2})), 1), "kairo: focus request moves focus and invalidates one control"},
    Check{Bool.not(accepted(AK.route(kstate(), M.Focus{3}))) && Bool.not(accepted(AK.route(kstate(), M.Focus{5}))), "kairo: text and disabled controls cannot take focus"},
    Check{U32.is_eq(release_count(routed_state(AK.route(K.replay([tab(), space_down()], kstate()), M.Focus{2}))), 0), "kairo: focus request cancels a pending keyboard gesture"},
    Check{same(checked(built(kstate())), "ok"), "kairo: built tree is valid"},
    Check{same(node_text(M.lookup(built(kstate()), 2)), "2<100:button:Botão 2:Soma um ao contador:0") && same(node_text(M.lookup(built(kstate()), 100)), "100<0:frame:Janela::3"), "kairo: Mokko semantics become nodes under the frame"},
    Check{M.has_state(node_states(built(K.replay([KT.PointerDown{30.0, 70.0, 0}], kstate())), 2), M.Armed{}), "kairo: a held press is ARMED"},
    Check{Bool.not(M.has_state(node_states(built(kstate()), 5), M.Enabled{})) && M.has_state(node_states(built(kstate()), 5), M.Focusable{}), "kairo: disabled button is not enabled"},
    Check{same(diffs(built(kstate()), built(K.replay([tab()], kstate()))), "state:2:focused:True|focus:2"), "kairo: Tab is announced as one focus change"},
    Check{same(e2e(), "1|name:3:Cliques: 1"), "end to end: AT-SPI DoAction -> one activation -> one name change"}
  ]

def checks() -> List<&2, Check>:
  List.concat(&2, Check, [checks.wire(), checks.model(), checks.diff(), checks.serving(), checks.kairo()])

def verdict(ok: Bool, +passed: U32, +failed: U32) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("Auvia: " ++ U32.show(passed) ++ " checks passed")
    case False{}:
      IO.die(Unit, 1, "Auvia: " ++ U32.show(failed) ++ " of " ++ U32.show((passed + failed : U32)) ++ " checks FAILED")

def report(cs: List<&2, Check>, +passed: U32, +failed: U32) -> IO(Unit):
  match cs:
    case Nil{}:
      verdict(U32.is_eq(failed, 0), passed, failed)
    case Con{Check{True{}, name}, rest}:
      do IO<Unit>:
        IO.print("PASS: " ++ name)
        report(rest, (passed + 1 : U32), failed)
    case Con{Check{False{}, name}, rest}:
      do IO<Unit>:
        IO.print("FAIL: " ++ name)
        report(rest, passed, (failed + 1 : U32))

def main() -> IO(Unit):
  report(checks(), 0, 0)
