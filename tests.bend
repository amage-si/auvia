import Base
import ./model.bend as M
import ./diff.bend as D
import ./dbus/wire.bend as W
import ./atspi/objects.bend as O
import ./atspi/serve.bend as S
import ./kairo.bend as AK
import ./text.bend as T
import ./field.bend as AF
import ../Mokko/field.bend as MF
import ../Kairo/edit.bend as KE
import ../Runika/font.bend as F
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
    [M.Action{"click", "", "space"}], [M.Relation{M.ControllerFor{}, [3]}], Nil{}, box, None{}, None{}, Nil{}}

def label(text: String) -> M.Node:
  M.Node{3, 1, M.Label{}, text, "", visible(), Nil{}, [M.Relation{M.ControlledBy{}, [2]}], [M.Attr{"live", "polite"}],
    M.Box{20.0, 120.0, 160.0, 24.0}, None{}, None{}, Nil{}}

def frame(kids: List<&2, U32>) -> M.Node:
  M.Node{1, 0, M.Frame{}, "Janela", "", List.append(&2, M.State, visible(), [M.Active{}]), Nil{}, Nil{}, Nil{},
    M.Box{0.0, 0.0, 400.0, 200.0}, None{}, None{}, kids}

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
    case D.WindowActivated{id}:
      "window+:" ++ U32.show(id)
    case D.WindowDeactivated{id}:
      "window-:" ++ U32.show(id)
    case D.Announced{id, t, level}:
      "announce:" ++ U32.show(id) ++ ":" ++ t ++ ":" ++ U32.show(level)
    case D.TextRemoved{id, at, n, t}:
      "text-:" ++ U32.show(id) ++ ":" ++ U32.show(at) ++ ":" ++ U32.show(n) ++ ":" ++ t
    case D.TextInserted{id, at, n, t}:
      "text+:" ++ U32.show(id) ++ ":" ++ U32.show(at) ++ ":" ++ U32.show(n) ++ ":" ++ t
    case D.CaretMoved{id, at}:
      "caret:" ++ U32.show(id) ++ ":" ++ U32.show(at)
    case D.SelectionChanged{id}:
      "selection:" ++ U32.show(id)

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

def inactive() -> M.Tree:
  M.Tree{[M.application("app", [1]), M.Node{1, 0, M.Frame{}, "Janela", "", visible(), Nil{}, Nil{}, Nil{},
    M.Box{0.0, 0.0, 400.0, 200.0}, None{}, None{}, [2, 3, 4]}, b2(0), label("Cliques: 0"), b4(0)]}

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

# Every field of a value, so two decodings compare in full.
def vtext(v: W.Value) -> String:
  match v:
    case W.DByte{x}:
      "y" ++ U32.show(x)
    case W.DBool{b}:
      "b" ++ Bool.show(b)
    case W.DI16{x}:
      "n" ++ U32.show(x)
    case W.DI32{x}:
      "i" ++ U32.show(x)
    case W.DU32{x}:
      "u" ++ U32.show(x)
    case W.DF64{hi, lo}:
      "d" ++ U32.show(hi) ++ ":" ++ U32.show(lo)
    case W.DStr{s}:
      "s'" ++ s ++ "'"
    case W.DPath{s}:
      "o'" ++ s ++ "'"
    case W.DSig{s}:
      "g'" ++ s ++ "'"
    case W.DVar{x}:
      "v<" ++ vtext(x) ++ ">"
    case W.DArr{s, xs}:
      "a" ++ s ++ "[" ++ vtext(xs) ++ "]"
    case W.DStruct{xs}:
      "(" ++ vtext(xs) ++ ")"
    case W.DEntry{k, x}:
      "{" ++ vtext(k) ++ "=" ++ vtext(x) ++ "}"
    case W.DSeq{h, t}:
      vtext(h) ++ "," ++ vtext(t)
    case W.DEnd{}:
      "."

def full_text(m: Maybe<&2, W.Message>) -> String:
  +x = m
  msg_text(x) ++ "|" ++ vtext(body_of(x))

def fulls_text(ms: List<&2, W.Message>) -> String:
  match ms:
    case Nil{}:
      ""
    case Con{m, rest}:
      full_text(Some{m}) ++ ";" ++ fulls_text(rest)

# Length and a 32-bit polynomial hash of a byte list.
def digest.go(bs: List<&2, U32>, +n: U32, +h: U32) -> String:
  match bs:
    case Nil{}:
      U32.show(n) ++ "#" ++ U32.show(h)
    case Con{b, rest}:
      digest.go(rest, (n + 1 : U32), (h * 31 + b + 1 : U32))

def digest(bs: List<&2, U32>) -> String:
  digest.go(bs, 0, 7)

def full_inbox(ib: W.Inbox) -> String:
  W.Inbox{ms, rest, bad} = ib
  fulls_text(ms) ++ "bad=" ++ U32.show(bad) ++ " rest=" ++ digest(rest)

# A body that exercises every type the decoder knows, nested.
def every_value() -> W.Value:
  W.seq([W.DByte{255}, W.DBool{True{}}, W.DI16{65535}, W.DI32{(0 - 7 : U32)}, W.DU32{4000000000}, W.f64(F32.neg(0.75)),
    W.DStr{"ação ✓ 𝄞"}, W.DPath{"/a/b"}, W.DSig{"a{sv}"}, W.DVar{W.DVar{W.array("y", [W.DByte{1}, W.DByte{2}])}},
    W.array("a(ys)", [W.array("(ys)", [W.tuple([W.DByte{3}, W.DStr{"x"}])]), W.array("(ys)", Nil{})]),
    W.array("{sv}", [W.DEntry{W.DStr{"k"}, W.DVar{W.tuple([W.DI32{1}, W.f64(2.0)])}}, W.DEntry{W.DStr{""}, W.DVar{W.DSig{""}}}]),
    W.tuple([W.DByte{9}, W.tuple([W.DI16{1}, W.DU32{2}])]), W.array("n", [W.DI16{1}, W.DI16{2}, W.DI16{3}])])

def every_message() -> W.Message:
  W.Message{4, 1, 77, 5, "/org/a11y/atspi/accessible/9", "org.a11y.atspi.Event.Object", "PropertyChange", "", ":1.3", ":1.4",
    every_value()}

def reencodes.of(m: Maybe<&2, W.Message>, bs: List<&2, U32>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{x}:
      bytes_eq(W.encode(x), bs)

# Encoding what decode returns gives back the bytes it read.
def reencodes(m: W.Message) -> Bool:
  +bs = W.encode(m)
  reencodes.of(W.decode(bs), bs)

def corrupt_version(bs: List<&2, U32>) -> List<&2, U32>:
  match bs:
    case Con{a, Con{b, Con{c, Con{v, rest}}}}:
      Con{a, Con{b, Con{c, Con{2, rest}}}}
    case other:
      other

# GLib reply and signal, a bad frame, our own signal, and half a big-endian
# call: two good frames, one dropped, one good, and a tail.
def stream() -> List<&2, U32>:
  List.concat(&2, U32, [golden_reply_signal(), corrupt_version(golden_setid()), W.encode(every_message()),
    golden_setid(), List.take(&2, U32, golden_doaction_be(), 40n)])

# Generated trees
# ---------------

# Buttons 2.. under the frame. Version 1 drops every fifth, renames every
# third, moves every fourth, moves focus, disables every seventh and adds
# three new buttons at the end.
def gen.kept(+id: U32, +v: U32) -> Bool:
  U32.is_eq(v, 0) || U32.is_ne((id % 5 : U32), 0)

def gen.node(+id: U32, +v: U32) -> M.Node:
  +changed = U32.is_ne(v, 0)
  button(id, "n" ++ U32.show(id) ++ Bool.pick(String, changed && U32.is_eq((id % 3 : U32), 0), "!", ""),
    U32.is_eq(id, (v * 5 + 2 : U32)), changed || U32.is_ne((id % 7 : U32), 0),
    M.Box{Bool.pick(F32, changed && U32.is_eq((id % 4 : U32), 0), 24.0, 20.0), 60.0, 160.0, 44.0})

def gen.kids(n: Nat, +id: U32, +v: U32, tail: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      tail
    case 1n+p:
      +rest = gen.kids(p, (id + 1 : U32), v, tail)
      Bool.pick(List<&2, U32>, gen.kept(id, v), Con{id, rest}, rest)

def gen.nodes(n: Nat, +id: U32, +v: U32, tail: List<&2, M.Node>) -> List<&2, M.Node>:
  match n:
    case 0n:
      tail
    case 1n+p:
      +rest = gen.nodes(p, (id + 1 : U32), v, tail)
      Bool.pick(List<&2, M.Node>, gen.kept(id, v), Con{gen.node(id, v), rest}, rest)

def gen(+n: Nat, +v: U32) -> M.Tree:
  +extra = U32.is_ne(v, 0)
  M.Tree{Con{M.application("app", [1]), Con{frame(gen.kids(n, 2, v, Bool.pick(List<&2, U32>, extra, [300, 301, 302], Nil{}))),
    gen.nodes(n, 2, v, Bool.pick(List<&2, M.Node>, extra, [gen.node(300, v), gen.node(301, v), gen.node(302, v)], Nil{}))}}}

def with_node(t: M.Tree, n: M.Node) -> M.Tree:
  M.Tree{ns} = t
  M.Tree{List.append(&2, M.Node, ns, [n])}

def encode_all(ms: List<&2, W.Message>) -> List<&2, U32>:
  match ms:
    case Nil{}:
      Nil{}
    case Con{m, rest}:
      List.append(&2, U32, W.encode(m), encode_all(rest))

def reply_digest(s: S.Served) -> String:
  S.Served{c, out, rs, h, nx} = s
  digest(encode_all(out))

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
  S.Served{c, out, r, h, nx} = s
  List.head(&2, W.Message, out)

def out_count(s: S.Served) -> U32:
  S.Served{c, out, r, h, nx} = s
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
  S.Served{c, out, r, h, nx} = s
  r

def op_text(op: M.TextOp) -> String:
  match op:
    case M.SetCaret{o}:
      "caret:" ++ U32.show(o)
    case M.Select{a, b}:
      "select:" ++ U32.show(a) ++ "-" ++ U32.show(b)
    case M.SetContents{t}:
      "contents:" ++ t
    case M.Insert{o, t}:
      "insert:" ++ U32.show(o) ++ ":" ++ t
    case M.Delete{a, b}:
      "delete:" ++ U32.show(a) ++ "-" ++ U32.show(b)
    case M.Copy{a, b}:
      "copy:" ++ U32.show(a) ++ "-" ++ U32.show(b)
    case M.Cut{a, b}:
      "cut:" ++ U32.show(a) ++ "-" ++ U32.show(b)
    case M.Paste{o}:
      "paste:" ++ U32.show(o)

def req_text(rs: List<&2, M.Request>) -> String:
  match rs:
    case Nil{}:
      ""
    case Con{M.Activate{id, i}, rest}:
      "activate:" ++ U32.show(id) ++ ":" ++ U32.show(i) ++ ";" ++ req_text(rest)
    case Con{M.Focus{id}, rest}:
      "focus:" ++ U32.show(id) ++ ";" ++ req_text(rest)
    case Con{M.EditText{id, op, t}, rest}:
      "edit:" ++ U32.show(id) ++ ":" ++ op_text(op) ++ "#" ++ U32.show(t) ++ ";" ++ req_text(rest)

def app_id(s: S.Served) -> U32:
  S.Served{O.Ctx{b, id, l, x, y}, out, r, h, nx} = s
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
    M.Box{20.0, 160.0, 200.0, 20.0}, Some{M.Range{current, 0.0, 10.0, 0.5}}, None{}, Nil{}}

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

# The Kairo side of a field: node 7 is editable text, focused.
def kfield(enabled: Bool) -> KT.Node:
  KT.Node{7, G.Rect{20.0, 160.0, 240.0, 44.0}, "Nome", KT.EditRole{}, enabled, True{}}

def fstate(enabled: Bool) -> KT.State:
  KT.State{[kbutton(2, 20.0, True{}), ktext(), kfield(enabled)], 0, 7, 0, 0, 0, False{}, True{}, True{}, 480.0, 320.0}

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
    case Some{M.Node{id, p, r, nm, d, s, a, rl, at, b, v, tx, c}}:
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


# Text
# ----

def tstops.go(n: Nat, +i: U32) -> List<&2, M.Stop>:
  match n:
    case 0n:
      [M.Stop{i, (U32.to_f32(i) * 10.0 : F32)}]
    case 1n+p:
      Con{M.Stop{i, (U32.to_f32(i) * 10.0 : F32)}, tstops.go(p, (i + 1 : U32))}

# One caret stop every 10 units, at 0 to n.
def tstops(n: Nat) -> List<&2, M.Stop>:
  tstops.go(n, 0)

def ttext(content: String, +caret: U32, +anchor: U32, stops: List<&2, M.Stop>) -> M.Text:
  T.text(content, caret, anchor, 30.0, 160.0, 20.0, stops)

# "olá mundo": 9 scalars, one stop each; the line at (30, 160), 20 tall.
def ola(+caret: U32, +anchor: U32) -> M.Text:
  ttext("olá mundo", caret, anchor, tstops(9n))

# "café" with a combining acute: 5 scalars, 4 clusters (no stop at 4).
def cafe_text() -> String:
  "cafe" ++ SCon{Chr{769}, SNil{}}

def cafe() -> M.Text:
  ttext(cafe_text(), 0, 0, [M.Stop{0, 0.0}, M.Stop{1, 10.0}, M.Stop{2, 20.0}, M.Stop{3, 30.0}, M.Stop{5, 40.0}])

def entry_states(+enabled: Bool) -> List<&2, M.State>:
  Bool.pick(List<&2, M.State>, enabled, [M.Enabled{}, M.Sensitive{}, M.Visible{}, M.Showing{}, M.Focusable{}, M.Editable{}, M.SingleLine{}],
    [M.Visible{}, M.Showing{}, M.Focusable{}, M.Editable{}, M.SingleLine{}])

def entry(t: M.Text, +enabled: Bool) -> M.Node:
  M.Node{7, 1, M.Entry{}, "Nome", "", entry_states(enabled), Nil{}, Nil{}, Nil{}, M.Box{20.0, 150.0, 260.0, 40.0}, None{}, Some{t}, Nil{}}

def with_entry(t: M.Text, +enabled: Bool) -> M.Tree:
  M.Tree{[M.application("app", [1]), frame([7]), entry(t, enabled)]}

# A label with a text but no Editable state: Text without EditableText.
def read_only() -> M.Tree:
  M.Tree{[M.application("app", [1]), frame([7]), M.Node{7, 1, M.Label{}, "x", "", visible(), Nil{}, Nil{}, Nil{},
    M.Box{20.0, 150.0, 260.0, 40.0}, None{}, Some{ola(0, 0)}, Nil{}}]}

def tcall(member: String, body: W.Value) -> W.Message:
  call(node_path(7), "org.a11y.atspi.Text", member, body)

def ecall(member: String, body: W.Value) -> W.Message:
  call(node_path(7), "org.a11y.atspi.EditableText", member, body)

def task(m: W.Message) -> S.Served:
  serve1(m, with_entry(ola(3, 3), True{}))

def outs(s: S.Served) -> String:
  vtext(body_of(first_out(s)))

def held_of(s: S.Served) -> List<&2, S.Held>:
  S.Served{c, out, r, h, nx} = s
  h

def held_count(s: S.Served) -> U32:
  U32.from_nat(List.length(&2, S.Held, held_of(s)))

def verdict_of(hs: List<&2, S.Held>, ok: Bool) -> String:
  match hs:
    case Con{h, rest}:
      fulls_text(S.verdict(h, ok))
    case Nil{}:
      "none"

def answer_of(s: S.Served, ok: Bool) -> String:
  verdict_of(held_of(s), ok)

def entry_diff(a: M.Text, b: M.Text) -> String:
  diffs(with_entry(a, True{}), with_entry(b, True{}))

def golden_insert_call() -> List<&2, U32>:
  [108,1,0,1,16,0,0,0,12,0,0,0,147,0,0,0,7,1,115,0,4,0,0,0,58,49,46,57,0,0,0,0,1,1,111,0,28,0,0,0,47,111,114,103,47,97,49,49,121,47,97,116,115,112,105,47,97,99,99,101,115,115,105,98,108,101,47,55,0,0,0,0,2,1,115,0,27,0,0,0,111,114,103,46,97,49,49,121,46,97,116,115,112,105,46,69,100,105,116,97,98,108,101,84,101,120,116,0,0,0,0,0,6,1,115,0,5,0,0,0,58,49,46,52,50,0,0,0,8,1,103,0,3,105,115,105,0,0,0,0,0,0,0,0,3,1,115,0,10,0,0,0,73,110,115,101,114,116,84,101,120,116,0,0,0,0,0,0,3,0,0,0,3,0,0,0,226,130,172,0,3,0,0,0]

def golden_string_call() -> List<&2, U32>:
  [108,1,0,1,8,0,0,0,13,0,0,0,138,0,0,0,7,1,115,0,4,0,0,0,58,49,46,57,0,0,0,0,1,1,111,0,28,0,0,0,47,111,114,103,47,97,49,49,121,47,97,116,115,112,105,47,97,99,99,101,115,115,105,98,108,101,47,55,0,0,0,0,2,1,115,0,19,0,0,0,111,114,103,46,97,49,49,121,46,97,116,115,112,105,46,84,101,120,116,0,0,0,0,0,6,1,115,0,5,0,0,0,58,49,46,52,50,0,0,0,8,1,103,0,2,105,117,0,3,1,115,0,17,0,0,0,71,101,116,83,116,114,105,110,103,65,116,79,102,102,115,101,116,0,0,0,0,0,0,0,5,0,0,0,1,0,0,0]

def golden_text_changed_body() -> List<&2, U32>:
  [6,0,0,0,105,110,115,101,114,116,0,0,3,0,0,0,3,0,0,0,1,115,0,0,3,0,0,0,120,121,122,0,0,0,0,0,0,0,0,0]

def golden_caret_body() -> List<&2, U32>:
  [0,0,0,0,0,0,0,0,6,0,0,0,0,0,0,0,1,105,0,0,0,0,0,0,0,0,0,0,0,0,0,0]

def golden_extents_body() -> List<&2, U32>:
  [50,0,0,0,160,0,0,0,10,0,0,0,20,0,0,0]

def golden_string_body() -> List<&2, U32>:
  [5,0,0,0,109,117,110,100,111,0,0,0,4,0,0,0,9,0,0,0]

def decoded(m: Maybe<&2, W.Message>) -> W.Message:
  match m:
    case None{}:
      sample()
    case Some{x}:
      x

def reply_bytes(s: S.Served) -> List<&2, U32>:
  body_bytes(body_of(first_out(s)))

def signal_bytes(c: D.Change) -> List<&2, U32>:
  body_bytes(body_of(signal_of(c)))

def fbuilt(s: KT.State, t: M.Text) -> M.Tree:
  AK.build.with("app", AK.Surface{100, "Janela", 480.0, 320.0, True{}}, semantics(s), notes(), [AK.Content{7, t, "Seu nome"}])

def attrs_text(xs: List<&2, M.Attr>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{M.Attr{k, v}, rest}:
      k ++ "=" ++ v ++ ";" ++ attrs_text(rest)

def attrs_of(m: Maybe<&2, M.Node>) -> String:
  match m:
    case Some{M.Node{id, p, r, nm, d, s, a, rl, at, b, v, tx, c}}:
      attrs_text(at)
    case None{}:
      "missing"

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
    Check{reencodes(sample()) && reencodes(every_message()) && reencodes(W.error_reply(sample(), "a.B", "ç")), "wire: decode then encode reproduces every byte"},
    Check{same(full_text(W.decode(golden_setid())), "1/0/5/0//org/a11y/atspi/accessible/root/org.freedesktop.DBus.Properties/Set//:1.42/:1.2/ssv|s'org.a11y.atspi.Application',s'Id',v<i7>,."), "wire: GLib Properties.Set decodes in full"},
    Check{same(full_text(W.decode(golden_doaction_be())), "1/0/300/0//org/a11y/atspi/accessible/2/org.a11y.atspi.Action/DoAction//:1.42/:1.9/i|i0,."), "wire: GLib big-endian call decodes in full"},
    Check{same(full_text(W.decode(W.encode(every_message()))), "4/1/77/5//org/a11y/atspi/accessible/9/org.a11y.atspi.Event.Object/PropertyChange//:1.3/:1.4/ybniudsogvaa(ys)a{sv}(y(nu))an|y255,bTrue,n65535,i4294967289,u4000000000,d3219652608:0,s'ação ✓ 𝄞',o'/a/b',g'a{sv}',v<v<ay[y1,y2,.]>>,aa(ys)[a(ys)[(y3,s'x',.),.],a(ys)[.],.],a{sv}[{s'k'=v<(i1,d1073741824:0,.)>},{s''=v<g''>},.],(y9,(n1,u2,.),.),an[n1,n2,n3,.],."), "wire: every type, nested, decodes in full"},
    Check{same(full_inbox(W.drain(stream())), "2/1/7/1/////:1.5/org.freedesktop.DBus/s|s':1.5',.;4/1/8/0//org/freedesktop/DBus/org.freedesktop.DBus/NameAcquired////s|s':1.5',.;4/1/77/5//org/a11y/atspi/accessible/9/org.a11y.atspi.Event.Object/PropertyChange//:1.3/:1.4/ybniudsogvaa(ys)a{sv}(y(nu))an|y255,bTrue,n65535,i4294967289,u4000000000,d3219652608:0,s'ação ✓ 𝄞',o'/a/b',g'a{sv}',v<v<ay[y1,y2,.]>>,aa(ys)[a(ys)[(y3,s'x',.),.],a(ys)[.],.],a{sv}[{s'k'=v<(i1,d1073741824:0,.)>},{s''=v<g''>},.],(y9,(n1,u2,.),.),an[n1,n2,n3,.],.;1/0/5/0//org/a11y/atspi/accessible/root/org.freedesktop.DBus.Properties/Set//:1.42/:1.2/ssv|s'org.a11y.atspi.Application',s'Id',v<i7>,.;bad=1 rest=40#651902801"), "wire: a stream splits into good frames, a dropped frame and a tail"},
    Check{same(full_inbox(W.drain(golden_reply_signal())), "2/1/7/1/////:1.5/org.freedesktop.DBus/s|s':1.5',.;4/1/8/0//org/freedesktop/DBus/org.freedesktop.DBus/NameAcquired////s|s':1.5',.;bad=0 rest=0#7"), "wire: two GLib messages drain in full"},
    Check{same(digest(W.encode(every_message())), "394#1391462325") && same(digest(W.encode(sample())), "200#3622258120"), "wire: encoder output is pinned"},
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
    Check{same(diffs(fixture(0, "Cliques: 0"), fixture(2, "Cliques: 1")), "name:3:Cliques: 1|announce:3:Cliques: 1:1|state:2:focused:True|focus:2"), "diff: name change, live-region announcement and focus gain are exact"},
    Check{same(diffs(fixture(0, "Cliques: 0"), grown()), "add:5|child+:1:3:5"), "diff: a new child is cached before its parent lists it"},
    Check{same(diffs(fixture(0, "Cliques: 0"), shrunk()), "child-:1:2:4|child-:1:1:3|del:3|del:4"), "diff: removed children go last index first"},
    Check{same(diffs(fixture(0, "Cliques: 0"), reordered()), "child-:1:2:4|child-:1:1:3|child-:1:0:2|child+:1:0:4|child+:1:1:2|child+:1:2:3"), "diff: reorder moves children out and back"},
    Check{same(diffs(fixture(0, "Cliques: 0"), moved()), "bounds:2"), "diff: geometry change emits only bounds"},
    Check{same(diffs(M.Tree{Nil{}}, fixture(0, "Cliques: 0")), "add:0|add:1|add:2|add:3|add:4|state:1:active:True|window+:1"), "diff: first publication caches every node and activates the window"},
    Check{same(diffs(fixture(0, "Cliques: 0"), inactive()), "state:1:active:False|window-:1") && same(diffs(inactive(), fixture(0, "Cliques: 0")), "state:1:active:True|window+:1"), "diff: frame activity is a window (de)activation"}
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
    Check{same(ints(reply_arg(S.serve([call(node_path(2), "org.a11y.atspi.Component", "GetExtents", W.seq([W.DU32{0}]))],
      O.at(ctx(), 100.0, 50.0), fixture(0, "Cliques: 0")))), "120,110,160,44,"), "atspi: screen extents follow the window origin"},
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
    Check{same(diffs(gen(40n, 0), gen(40n, 1)), "child-:1:38:40|child-:1:33:35|child-:1:28:30|child-:1:23:25|child-:1:18:20|child-:1:13:15|child-:1:8:10|child-:1:3:5|del:5|del:10|del:15|del:20|del:25|del:30|del:35|del:40|state:2:focused:False|name:3:n3!|bounds:4|name:6:n6!|bounds:8|name:9:n9!|name:12:n12!|bounds:12|bounds:16|name:18:n18!|name:21:n21!|name:24:n24!|bounds:24|name:27:n27!|bounds:28|bounds:32|name:33:n33!|name:36:n36!|bounds:36|name:39:n39!|add:300|add:301|add:302|child+:1:32:300|child+:1:33:301|child+:1:34:302|state:7:enabled:True|state:7:sensitive:True|state:7:focused:True|focus:7|state:14:enabled:True|state:14:sensitive:True|state:21:enabled:True|state:21:sensitive:True|state:28:enabled:True|state:28:sensitive:True"), "diff: 40 buttons, removed, renamed, moved and added, in announcement order"},
    Check{same(diffs(M.Tree{Nil{}}, gen(40n, 1)), "add:0|add:1|add:2|add:3|add:4|add:6|add:7|add:8|add:9|add:11|add:12|add:13|add:14|add:16|add:17|add:18|add:19|add:21|add:22|add:23|add:24|add:26|add:27|add:28|add:29|add:31|add:32|add:33|add:34|add:36|add:37|add:38|add:39|add:41|add:300|add:301|add:302|state:1:active:True|window+:1|state:7:focused:True|focus:7") && same(diffs(gen(40n, 1), gen(40n, 0)), "child-:1:34:302|child-:1:33:301|child-:1:32:300|del:300|del:301|del:302|state:7:enabled:False|state:7:sensitive:False|state:7:focused:False|state:14:enabled:False|state:14:sensitive:False|state:21:enabled:False|state:21:sensitive:False|state:28:enabled:False|state:28:sensitive:False|name:3:n3|bounds:4|name:6:n6|bounds:8|name:9:n9|name:12:n12|bounds:12|bounds:16|name:18:n18|name:21:n21|name:24:n24|bounds:24|name:27:n27|bounds:28|bounds:32|name:33:n33|name:36:n36|bounds:36|name:39:n39|add:5|add:10|add:15|add:20|add:25|add:30|add:35|add:40|child+:1:3:5|child+:1:8:10|child+:1:13:15|child+:1:18:20|child+:1:23:25|child+:1:28:30|child+:1:33:35|child+:1:38:40|state:2:focused:True|focus:2"), "diff: generated trees, first publication and the way back"},
    Check{same(checked(gen(40n, 1)), "ok") && same(checked(with_node(gen(40n, 1), gen.node(17, 1))), "auvia: duplicate node id 17") && same(checked(with_node(gen(40n, 1), M.plain(500, 1, M.Label{}, "x", M.zero_box(), Nil{}))), "auvia: node 500 is not listed by its parent"), "model: generated trees check, with a duplicate and an orphan"},
    Check{same(reply_digest(serve1(call(O.cache_path(), "org.a11y.atspi.Cache", "GetItems", W.DEnd{}), gen(40n, 1))), "10688#1642861101") && same(reply_digest(serve1(call(node_path(300), acc(), "GetIndexInParent", W.DEnd{}), gen(40n, 1))), "52#3444926104"), "atspi: cache items and index in parent of a generated tree are pinned"},
    Check{same(digest(encode_all(O.announce(ctx(), M.nodes(gen(40n, 1)), D.diff(M.Tree{Nil{}}, gen(40n, 1))))), "16204#3489676328"), "atspi: first publication signals of a generated tree are pinned"},
    Check{same(diffs(with_slider(2.5), with_slider(3.0)), "value:6") && same(checked(with_slider(1.0)), "ok"), "diff: value change is one event"},
    Check{same(member_of(signal_of(D.StateChanged{2, M.Focused{}, True{}})), "org.a11y.atspi.Event.Object.StateChanged@/org/a11y/atspi/accessible/2:siiva{sv}"), "atspi: state change signal"},
    Check{same(member_of(signal_of(D.WindowActivated{1})), "org.a11y.atspi.Event.Window.Activate@/org/a11y/atspi/accessible/1:siiva{sv}"), "atspi: window activate signal"},
    Check{same(member_of(signal_of(D.Announced{3, "Cliques: 1", 1})), "org.a11y.atspi.Event.Object.Announcement@/org/a11y/atspi/accessible/3:siiva{sv}"), "atspi: announcement signal"},
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
    Check{same(e2e(), "1|name:3:Cliques: 1|announce:3:Cliques: 1:1"), "end to end: AT-SPI DoAction -> one activation -> one name change and one announcement"},
    Check{Bool.not(accepted(AK.route(fstate(True{}), M.Activate{7, 0}))) && accepted(AK.route(fstate(True{}), M.Focus{7})), "kairo: activate requires a button; a field can take focus"}
  ]

def checks.text() -> List<&2, Check>:
  [
    Check{same(vtext(reply_arg(task(call(node_path(7), acc(), "GetInterfaces", W.DEnd{})))), "as[s'org.a11y.atspi.Accessible',s'org.a11y.atspi.Component',s'org.a11y.atspi.Text',s'org.a11y.atspi.EditableText',.]"), "text: an entry implements Text and EditableText"},
    Check{U32.is_eq(W.word(reply_arg(task(call(node_path(7), acc(), "GetRole", W.DEnd{})))), 79) && same(W.text(reply_arg(task(call(node_path(7), acc(), "GetRoleName", W.DEnd{})))), "entry"), "text: entry role (79, \"entry\")"},
    Check{same(vtext(reply_arg(serve1(call(node_path(7), acc(), "GetInterfaces", W.DEnd{}), read_only()))), "as[s'org.a11y.atspi.Accessible',s'org.a11y.atspi.Component',s'org.a11y.atspi.Text',.]") && same(reply_error(serve1(ecall("InsertText", W.seq([W.DI32{0}, W.DStr{"x"}, W.DI32{1}])), read_only())), "org.freedesktop.DBus.Error.UnknownMethod"), "text: a text without the editable state has no EditableText"},
    Check{same(reply_error(ask(call(node_path(3), "org.a11y.atspi.Text", "GetText", W.seq([W.DI32{0}, W.DI32{(0 - 1 : U32)}])))), "org.freedesktop.DBus.Error.UnknownMethod"), "text: a label without a text has no Text"},
    Check{same(outs(task(tcall("GetText", W.seq([W.DI32{0}, W.DI32{(0 - 1 : U32)}])))), "s'olá mundo',.") && same(outs(task(tcall("GetText", W.seq([W.DI32{4}, W.DI32{9}])))), "s'mundo',.") && same(outs(task(tcall("GetText", W.seq([W.DI32{7}, W.DI32{99}])))), "s'do',."), "text: GetText slices by scalar; -1 and past the end mean the end"},
    Check{same(vtext(reply_arg(task(call(node_path(7), "org.freedesktop.DBus.Properties", "Get", W.seq([W.DStr{"org.a11y.atspi.Text"}, W.DStr{"CharacterCount"}]))))), "v<i9>") && same(vtext(reply_arg(task(call(node_path(7), "org.freedesktop.DBus.Properties", "Get", W.seq([W.DStr{"org.a11y.atspi.Text"}, W.DStr{"CaretOffset"}]))))), "v<i3>"), "text: CharacterCount and CaretOffset properties"},
    Check{same(outs(task(tcall("GetStringAtOffset", W.seq([W.DI32{5}, W.DU32{1}])))), "s'mundo',i4,i9,.") && same(outs(task(tcall("GetStringAtOffset", W.seq([W.DI32{3}, W.DU32{1}])))), "s'olá ',i0,i4,.") && same(outs(task(tcall("GetStringAtOffset", W.seq([W.DI32{2}, W.DU32{0}])))), "s'á',i2,i3,."), "text: word (to the next word's start) and character at an offset"},
    Check{same(outs(task(tcall("GetStringAtOffset", W.seq([W.DI32{9}, W.DU32{3}])))), "s'olá mundo',i0,i9,.") && same(outs(task(tcall("GetStringAtOffset", W.seq([W.DI32{9}, W.DU32{0}])))), "s'',i9,i9,.") && same(outs(task(tcall("GetTextAtOffset", W.seq([W.DI32{5}, W.DU32{1}])))), "s'mundo',i4,i9,."), "text: the line is the whole text; nothing past the end; GetTextAtOffset maps boundaries"},
    Check{same(outs(serve1(tcall("GetStringAtOffset", W.seq([W.DI32{4}, W.DU32{0}])), with_entry(cafe(), True{}))), "s'" ++ "e" ++ SCon{Chr{769}, SNil{}} ++ "',i3,i5,."), "text: a combining mark belongs to its base's character"},
    Check{same(outs(task(tcall("GetCharacterExtents", W.seq([W.DI32{2}, W.DU32{1}])))), "i50,i160,i10,i20,.") && same(outs(S.serve([tcall("GetCharacterExtents", W.seq([W.DI32{2}, W.DU32{0}]))], O.at(ctx(), 100.0, 50.0), with_entry(ola(3, 3), True{}))), "i150,i210,i10,i20,.") && same(outs(task(tcall("GetRangeExtents", W.seq([W.DI32{4}, W.DI32{9}, W.DU32{1}])))), "i70,i160,i50,i20,."), "text: character and range extents, in window and screen coordinates"},
    Check{same(outs(task(tcall("GetOffsetAtPoint", W.seq([W.DI32{74}, W.DI32{165}, W.DU32{1}])))), "i4,.") && same(outs(task(tcall("GetOffsetAtPoint", W.seq([W.DI32{74}, W.DI32{300}, W.DU32{1}])))), "i4294967295,.") && same(outs(task(tcall("GetCharacterAtOffset", W.seq([W.DI32{2}])))), "i225,."), "text: offset at a point (nearest stop, -1 outside) and the character at an offset"},
    Check{same(outs(serve1(tcall("GetNSelections", W.DEnd{}), with_entry(ola(9, 4), True{}))), "i1,.") && same(outs(serve1(tcall("GetSelection", W.seq([W.DI32{0}])), with_entry(ola(4, 9), True{}))), "i4,i9,.") && same(outs(task(tcall("GetNSelections", W.DEnd{}))), "i0,.") && same(outs(task(tcall("GetSelection", W.seq([W.DI32{0}])))), "i0,i0,."), "text: one selection, in order, or none"},
    Check{same(reply_sig(task(tcall("GetAttributeRun", W.seq([W.DI32{2}, W.DBool{True{}}])))), "a{ss}ii") && same(reply_sig(task(tcall("GetAttributes", W.seq([W.DI32{2}])))), "a{ss}ii") && same(reply_sig(task(call(node_path(7), acc(), "GetAttributes", W.DEnd{}))), "a{ss}"), "text: Text.GetAttributes is the text's, Accessible.GetAttributes the node's"},
    Check{U32.is_eq(out_count(task(ecall("InsertText", W.seq([W.DI32{3}, W.DStr{"xyz"}, W.DI32{3}])))), 0) && same(req_text(requests(task(ecall("InsertText", W.seq([W.DI32{3}, W.DStr{"xyz"}, W.DI32{3}]))))), "edit:7:insert:3:xyz#1;") && U32.is_eq(held_count(task(ecall("InsertText", W.seq([W.DI32{3}, W.DStr{"xyz"}, W.DI32{3}])))), 1), "text: InsertText is held for the app, with a ticket, and not answered yet"},
    Check{same(answer_of(task(ecall("InsertText", W.seq([W.DI32{3}, W.DStr{"xyz"}, W.DI32{3}]))), True{}), "2/0/0/10/////:1.9//b|bTrue,.;") && same(answer_of(task(ecall("InsertText", W.seq([W.DI32{3}, W.DStr{"€"}, W.DI32{3}]))), False{}), "2/0/0/10/////:1.9//b|bFalse,.;") && same(answer_of(task(ecall("CopyText", W.seq([W.DI32{0}, W.DI32{3}]))), True{}), "2/0/0/10/////:1.9//|.;"), "text: a settled call is answered with its verdict; CopyText with nothing"},
    Check{same(full_text(W.decode(golden_insert_call())), "1/0/12/0//org/a11y/atspi/accessible/7/org.a11y.atspi.EditableText/InsertText//:1.42/:1.9/isi|i3,s'€',i3,.") && same(req_text(requests(task(decoded(W.decode(golden_insert_call()))))), "edit:7:insert:3:€#1;") && same(outs(task(decoded(W.decode(golden_string_call())))), "s'mundo',i4,i9,."), "text: GLib's InsertText and GetStringAtOffset calls decode and are served"},
    Check{same(req_text(requests(S.serve([ecall("InsertText", W.seq([W.DI32{(0 - 1 : U32)}, W.DStr{"!"}, W.DI32{1}])), ecall("DeleteText", W.seq([W.DI32{9}, W.DI32{4}])), ecall("CutText", W.seq([W.DI32{0}, W.DI32{3}])), ecall("PasteText", W.seq([W.DI32{50}])), ecall("SetTextContents", W.seq([W.DStr{"novo"}]))], ctx(), with_entry(ola(3, 3), True{})))), "edit:7:insert:9:!#1;edit:7:delete:4-9#2;edit:7:cut:0-3#3;edit:7:paste:9#4;edit:7:contents:novo#5;"), "text: offsets are clamped and ordered; tickets count up"},
    Check{same(req_text(requests(S.serve([tcall("SetCaretOffset", W.seq([W.DI32{5}])), tcall("SetSelection", W.seq([W.DI32{0}, W.DI32{6}, W.DI32{2}])), tcall("AddSelection", W.seq([W.DI32{1}, W.DI32{2}]))], ctx(), with_entry(ola(3, 3), True{})))), "edit:7:caret:5#1;edit:7:select:6-2#2;edit:7:select:1-2#3;") && same(outs(task(tcall("SetSelection", W.seq([W.DI32{1}, W.DI32{0}, W.DI32{2}])))), "bFalse,.") && same(req_text(requests(serve1(tcall("RemoveSelection", W.seq([W.DI32{0}])), with_entry(ola(9, 4), True{})))), "edit:7:select:9-9#1;"), "text: caret and selection requests; only selection 0 exists"},
    Check{same(outs(serve1(ecall("InsertText", W.seq([W.DI32{0}, W.DStr{"x"}, W.DI32{1}])), with_entry(ola(3, 3), False{}))), "bFalse,.") && same(req_text(requests(serve1(ecall("InsertText", W.seq([W.DI32{0}, W.DStr{"x"}, W.DI32{1}])), with_entry(ola(3, 3), False{})))), ""), "text: a disabled entry refuses edits at once"},
    Check{bytes_eq(signal_bytes(D.TextInserted{7, 3, 3, "xyz"}), golden_text_changed_body()) && bytes_eq(signal_bytes(D.CaretMoved{7, 6}), golden_caret_body()), "text: text-changed and caret-moved signal bodies equal GLib's bytes"},
    Check{bytes_eq(reply_bytes(task(tcall("GetCharacterExtents", W.seq([W.DI32{2}, W.DU32{1}])))), golden_extents_body()) && bytes_eq(reply_bytes(task(tcall("GetStringAtOffset", W.seq([W.DI32{5}, W.DU32{1}])))), golden_string_body()), "text: GetCharacterExtents (iiii) and GetStringAtOffset (sii) replies equal GLib's bytes"},
    Check{same(member_of(signal_of(D.TextRemoved{7, 0, 2, "ol"})), "org.a11y.atspi.Event.Object.TextChanged@/org/a11y/atspi/accessible/7:siiva{sv}") && same(vtext(body_of(signal_of(D.TextRemoved{7, 0, 2, "ol"}))), "s'delete',i0,i2,v<s'ol'>,a{sv}[.],.") && same(member_of(signal_of(D.SelectionChanged{7})), "org.a11y.atspi.Event.Object.TextSelectionChanged@/org/a11y/atspi/accessible/7:siiva{sv}") && same(member_of(signal_of(D.CaretMoved{7, 1})), "org.a11y.atspi.Event.Object.TextCaretMoved@/org/a11y/atspi/accessible/7:siiva{sv}"), "text: delete, caret and selection signals"},
    Check{same(entry_diff(ola(3, 3), ttext("olá, mundo", 4, 4, tstops(10n))), "text+:7:3:1:,|caret:7:4") && same(entry_diff(ola(9, 9), ttext("olá gente", 9, 9, tstops(9n))), "text-:7:4:5:mundo|text+:7:4:5:gente") && same(entry_diff(ttext("aaa", 3, 3, tstops(3n)), ttext("aaaa", 4, 4, tstops(4n))), "text+:7:3:1:a|caret:7:4"), "diff: text changes are one replacement with the common prefix and suffix kept"},
    Check{same(entry_diff(ola(3, 3), ola(5, 5)), "caret:7:5") && same(entry_diff(ola(3, 3), ola(9, 4)), "caret:7:9|selection:7") && same(entry_diff(ola(9, 4), ola(9, 9)), "selection:7") && same(entry_diff(ola(3, 3), ola(3, 3)), ""), "diff: caret moves and selection changes"},
    Check{Bool.not(accepted(AK.route(fstate(True{}), M.EditText{7, M.SetCaret{0}, 1}))) && AK.editable(fstate(True{}), 7) && Bool.not(AK.editable(fstate(False{}), 7)) && Bool.not(AK.editable(fstate(True{}), 2)), "kairo: text requests are left to the field; only an enabled field is editable"},
    Check{same(node_text(M.lookup(fbuilt(fstate(True{}), ola(3, 3)), 7)), "7<100:entry:Nome::0") && M.has_state(node_states(fbuilt(fstate(True{}), ola(3, 3)), 7), M.Editable{}) && M.has_state(node_states(fbuilt(fstate(True{}), ola(3, 3)), 7), M.SingleLine{}) && M.has_state(node_states(fbuilt(fstate(True{}), ola(3, 3)), 7), M.Focused{}) && same(attrs_of(M.lookup(fbuilt(fstate(True{}), ola(3, 3)), 7)), "placeholder-text=Seu nome;") && same(checked(fbuilt(fstate(True{}), ola(3, 3))), "ok"), "kairo: an EditRole node is an editable, single-line entry with its text and placeholder"}
  ]

# With a real font: requests through Mokko's field and Kairo's editing.

def fbounds() -> G.Rect:
  G.Rect{20.0, 160.0, 240.0, 44.0}

def blank() -> MF.Field:
  MF.Field{KE.empty(), Nil{}, Mk.Metrics{0.0, 0.0, 0.0}, 0.0, None{}}

def field_or(r: Result<&2, &2, String, MF.Field>) -> MF.Field:
  match r:
    case Fail{e}:
      blank()
    case Done{f}:
      f

def ffield(+font: F.Font, text: String) -> MF.Field:
  field_or(MF.field(font, 16.0, text))

def fview_content(r: Result<&2, &2, String, MF.FieldView>) -> List<&2, AK.Content>:
  match r:
    case Fail{e}:
      Nil{}
    case Done{MF.FieldView{v, e}}:
      [AF.content(e)]

# The app's tree for a field: Mokko's view gives the EditState.
def ftree(+s: KT.State, f: MF.Field) -> M.Tree:
  AK.build.with("app", AK.Surface{100, "Janela", 480.0, 320.0, True{}}, semantics(s), notes(),
    fview_content(MF.view(kfield(True{}), s, f, 16.0, MF.field_theme(), "Seu nome")))

def aedit(+font: F.Font, +s: KT.State, f: MF.Field, r: M.Request) -> AF.Edited:
  AF.edit(font, 16.0, fbounds(), s, 7, f, r)

def edited_field(e: AF.Edited) -> MF.Field:
  AF.Edited{MF.Fed{f, d, r}, ok} = e
  f

def edited_ok(e: AF.Edited) -> Bool:
  AF.Edited{fed, ok} = e
  ok

def request_text(r: KE.Request) -> String:
  match r:
    case KE.NoRequest{}:
      "none"
    case KE.CopyText{t}:
      "copy:" ++ t
    case KE.PasteText{}:
      "paste"

def edited_request(e: AF.Edited) -> String:
  AF.Edited{MF.Fed{f, d, r}, ok} = e
  request_text(r)

def message_text(m: Maybe<&2, String>) -> String:
  match m:
    case None{}:
      ""
    case Some{t}:
      t

# One edit on "olá" (caret at the end): the outcome, the text, the
# request, the message and the diff the app would publish.
def edit_report(+font: F.Font, e: AF.Edited) -> String:
  +x = e
  +f = edited_field(x)
  Bool.show(edited_ok(x)) ++ "|" ++ MF.text_of(f) ++ "|" ++ edited_request(x) ++ "|" ++ message_text(MF.message(f)) ++ "|" ++
    diffs(ftree(fstate(True{}), ffield(font, "olá")), ftree(fstate(True{}), f))

def on_ola(+font: F.Font, op: M.TextOp) -> String:
  edit_report(font, aedit(font, fstate(True{}), ffield(font, "olá"), M.EditText{7, op, 1}))

def head_text(v: W.Value) -> String:
  match v:
    case W.DSeq{x, rest}:
      vtext(x)
    case _:
      "?"

def x_of(s: S.Served) -> String:
  head_text(body_of(first_out(s)))

def checks.field(+font: F.Font) -> List<&2, Check>:
  [
    Check{same(checked(ftree(fstate(True{}), ffield(font, "olá"))), "ok") && same(outs(serve1(tcall("GetText", W.seq([W.DI32{0}, W.DI32{(0 - 1 : U32)}])), ftree(fstate(True{}), ffield(font, "olá")))), "s'olá',.") && same(x_of(serve1(tcall("GetCharacterExtents", W.seq([W.DI32{0}, W.DU32{1}])), ftree(fstate(True{}), ffield(font, "olá")))), "i32"), "field: Mokko's EditState becomes the entry's text, from the text area's left edge"},
    Check{same(req_text(requests(serve1(decoded(W.decode(golden_insert_call())), ftree(fstate(True{}), ffield(font, "olá"))))), "edit:7:insert:3:€#1;") && same(on_ola(font, M.Insert{3, "€"}), "False|olá|none|Character U+20AC cannot be displayed|"), "field: GLib's InsertText of U+20AC is refused by the layout and changes nothing"},
    Check{same(on_ola(font, M.Insert{3, "zinho"}), "True|olázinho|none||text+:7:3:5:zinho|caret:7:8") && same(on_ola(font, M.Insert{0, "Ah, "}), "True|Ah, olá|none||text+:7:0:4:Ah, |caret:7:4"), "field: InsertText goes through Mokko's feed and is announced"},
    Check{same(on_ola(font, M.Delete{0, 2}), "True|á|none||text-:7:0:2:ol|caret:7:0") && same(on_ola(font, M.SetContents{"novo"}), "True|novo|none||text-:7:0:3:olá|text+:7:0:4:novo|caret:7:4") && same(on_ola(font, M.SetContents{""}), "True||none||text-:7:0:3:olá|caret:7:0"), "field: DeleteText and SetTextContents"},
    Check{same(on_ola(font, M.Insert{1, "\n"}), "False|olá|none|Line breaks are not allowed in this field|") && same(on_ola(font, M.Insert{1, "☕"}), "False|olá|none|Character U+2615 cannot be displayed|"), "field: Kairo's and Syllo's refusals apply to assistive technologies"},
    Check{same(on_ola(font, M.Cut{0, 2}), "True|á|copy:ol||text-:7:0:2:ol|caret:7:0") && same(on_ola(font, M.Copy{1, 3}), "True|olá|copy:lá||") && same(on_ola(font, M.Paste{1}), "True|olá|paste||caret:7:1"), "field: CutText, CopyText and PasteText ask the app for the clipboard"},
    Check{same(on_ola(font, M.SetCaret{1}), "True|olá|none||caret:7:1") && same(on_ola(font, M.Select{0, 2}), "True|olá|none||caret:7:2|selection:7"), "field: caret and selection requests move the field's caret"},
    Check{Bool.not(edited_ok(aedit(font, fstate(False{}), ffield(font, "olá"), M.EditText{7, M.Insert{0, "x"}, 1}))) && Bool.not(edited_ok(aedit(font, fstate(True{}), ffield(font, "olá"), M.EditText{2, M.Insert{0, "x"}, 1}))) && Bool.not(edited_ok(aedit(font, fstate(True{}), ffield(font, "olá"), M.Activate{7, 0}))), "field: a disabled field, another id and other requests are not performed"}
  ]

def checks() -> List<&2, Check>:
  List.concat(&2, Check, [checks.wire(), checks.model(), checks.diff(), checks.serving(), checks.kairo(), checks.text()])

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

def font_path() -> String:
  "/usr/share/fonts/liberation/LiberationSans-Regular.ttf"

def with_font(r: Result<&2, &2, String, F.Font>) -> IO(Unit):
  match r:
    case Fail{e}:
      IO.die(Unit, 1, "Auvia: cannot load " ++ font_path() ++ ": " ++ e)
    case Done{font}:
      report(List.append(&2, Check, checks(), checks.field(font)), 0, 0)

def main() -> IO(Unit):
  do IO<Unit>:
    r : Result<&2, &2, String, F.Font> <- F.load(font_path())
    with_font(r)
