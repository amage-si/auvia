import Base
import ../model.bend as M
import ../diff.bend as D
import ../dbus/wire.bend as W
import ../atspi/objects.bend as O
import ../atspi/serve.bend as S

# Times Auvia's hot paths on fixed inputs: draining a stream of D-Bus
# messages, encoding them, and diffing, checking, announcing and serving a
# tree of n buttons. Every line prints a digest of its result next to the
# time, so two builds can be compared for identical output.
#
#   bend examples/bench.bend -o build/bench && ./build/bench --threads 1 --gpu off

# Inputs
# ------

def signal_msg(+i: U32) -> W.Message:
  W.Message{4, 1, i, 0, "/org/a11y/atspi/accessible/" ++ U32.show(i), "org.a11y.atspi.Event.Object", "StateChanged", "", "", ":1.4",
    W.seq([W.DStr{"focused"}, W.DI32{1}, W.DI32{0}, W.DVar{W.DI32{i}},
      W.array("{sv}", [W.DEntry{W.DStr{"ação"}, W.DVar{W.tuple([W.DI32{1}, W.f64(2.0)])}}])])}

def call_msg(+i: U32) -> W.Message:
  W.Message{1, 0, i, 0, "/org/a11y/atspi/accessible/" ++ U32.show(i), "org.freedesktop.DBus.Properties", "Get", "", ":1.42", ":1.9",
    W.seq([W.DStr{"org.a11y.atspi.Accessible"}, W.DStr{"Name"}])}

def msg(+i: U32) -> W.Message:
  Bool.pick(W.Message, U32.is_eq((i % 2 : U32), 0), signal_msg(i), call_msg(i))

def msgs(n: Nat, +i: U32) -> List<&2, W.Message>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Con{msg(i), msgs(p, (i + 1 : U32))}

def push(bs: List<&2, U32>, tail: List<&2, U32>) -> List<&2, U32>:
  match bs:
    case Nil{}:
      tail
    case Con{b, rest}:
      Con{b, push(rest, tail)}

# n messages back to back, then the first 30 bytes of one more.
def stream(n: Nat, +i: U32) -> List<&2, U32>:
  match n:
    case 0n:
      List.take(&2, U32, W.encode(msg(i)), 30n)
    case 1n+p:
      push(W.encode(msg(i)), stream(p, (i + 1 : U32)))

def label(+id: U32, +v: U32) -> M.Node:
  +changed = U32.is_ne(v, 0)
  M.Node{id, 1, M.PushButton{}, "n" ++ U32.show(id) ++ Bool.pick(String, changed && U32.is_eq((id % 3 : U32), 0), "!", ""), "",
    Bool.pick(List<&2, M.State>, U32.is_eq(id, (v * 5 + 2 : U32)), [M.Enabled{}, M.Focusable{}, M.Focused{}], [M.Enabled{}, M.Focusable{}]),
    [M.Action{"click", "", ""}], Nil{}, Nil{},
    M.Box{Bool.pick(F32, changed && U32.is_eq((id % 4 : U32), 0), 24.0, 20.0), 60.0, 160.0, 44.0}, None{}, None{}, Nil{}}

def kept(+id: U32, +v: U32) -> Bool:
  U32.is_eq(v, 0) || U32.is_ne((id % 5 : U32), 0)

def kids(n: Nat, +id: U32, +v: U32, tail: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      tail
    case 1n+p:
      +rest = kids(p, (id + 1 : U32), v, tail)
      Bool.pick(List<&2, U32>, kept(id, v), Con{id, rest}, rest)

def nodes(n: Nat, +id: U32, +v: U32, tail: List<&2, M.Node>) -> List<&2, M.Node>:
  match n:
    case 0n:
      tail
    case 1n+p:
      +rest = nodes(p, (id + 1 : U32), v, tail)
      Bool.pick(List<&2, M.Node>, kept(id, v), Con{label(id, v), rest}, rest)

def frame(kids: List<&2, U32>) -> M.Node:
  M.Node{1, 0, M.Frame{}, "Janela", "", [M.Enabled{}, M.Active{}], Nil{}, Nil{}, Nil{}, M.Box{0.0, 0.0, 400.0, 200.0}, None{}, None{}, kids}

# Version 0: buttons 2..n+1. Version 1: every fifth dropped, every third
# renamed, every fourth moved, focus moved, and three new buttons.
def tree(+n: Nat, +v: U32) -> M.Tree:
  +extra = U32.is_ne(v, 0)
  M.Tree{Con{M.application("bench", [1]), Con{frame(kids(n, 2, v, Bool.pick(List<&2, U32>, extra, [90000, 90001, 90002], Nil{}))),
    nodes(n, 2, v, Bool.pick(List<&2, M.Node>, extra, [label(90000, v), label(90001, v), label(90002, v)], Nil{}))}}}

# Digests
# -------

def mix(+h: U32, +x: U32) -> U32:
  (h * 31 + x + 1 : U32)

def bytes_hash(bs: List<&2, U32>, +h: U32) -> U32:
  match bs:
    case Nil{}:
      h
    case Con{b, rest}:
      bytes_hash(rest, mix(h, b))

def str_hash(s: String, +h: U32) -> U32:
  bytes_hash(W.utf8(s), h)

def msg_hash(m: W.Message, +h: U32) -> U32:
  W.Message{k, f, s, r, p, i, mem, e, d, sn, b} = m
  str_hash(W.sig(b), str_hash(sn ++ d ++ e ++ mem ++ i ++ p, mix(mix(mix(mix(h, k), f), s), r)))

def msgs_hash(ms: List<&2, W.Message>, +h: U32) -> U32:
  match ms:
    case Nil{}:
      h
    case Con{m, rest}:
      msgs_hash(rest, msg_hash(m, h))

def count(-A: Data, xs: List<&2, A>) -> U32:
  U32.from_nat(List.length(&2, A, xs))

def inbox_text(ib: W.Inbox) -> String:
  W.Inbox{+ms, +rest, bad} = ib
  U32.show(count(W.Message, ms)) ++ " msgs, bad " ++ U32.show(bad) ++ ", rest " ++ U32.show(count(U32, rest)) ++
    ", hash " ++ U32.show(bytes_hash(rest, msgs_hash(ms, 7)))

def key(c: D.Change) -> String:
  match c:
    case D.StateChanged{id, s, on}:
      "s" ++ U32.show(id) ++ M.state_name(s) ++ Bool.show(on)
    case D.NameChanged{id, n}:
      "n" ++ U32.show(id) ++ n
    case D.DescriptionChanged{id, t}:
      "d" ++ U32.show(id) ++ t
    case D.RoleChanged{id, r}:
      "r" ++ U32.show(id) ++ M.role_name(r)
    case D.ValueChanged{id, v}:
      "v" ++ U32.show(id)
    case D.BoundsChanged{id, b}:
      "b" ++ U32.show(id)
    case D.ParentChanged{id, p}:
      "p" ++ U32.show(id) ++ ":" ++ U32.show(p)
    case D.ChildAdded{p, i, c}:
      "+" ++ U32.show(p) ++ ":" ++ U32.show(i) ++ ":" ++ U32.show(c)
    case D.ChildRemoved{p, i, c}:
      "-" ++ U32.show(p) ++ ":" ++ U32.show(i) ++ ":" ++ U32.show(c)
    case D.FocusGained{id}:
      "f" ++ U32.show(id)
    case D.Added{id}:
      "a" ++ U32.show(id)
    case D.Removed{id}:
      "x" ++ U32.show(id)
    case D.WindowActivated{id}:
      "w" ++ U32.show(id)
    case D.WindowDeactivated{id}:
      "W" ++ U32.show(id)
    case D.Announced{id, t, level}:
      "A" ++ U32.show(id) ++ t ++ U32.show(level)
    case D.TextRemoved{id, at, n, t}:
      "t-" ++ U32.show(id) ++ ":" ++ U32.show(at) ++ ":" ++ t
    case D.TextInserted{id, at, n, t}:
      "t+" ++ U32.show(id) ++ ":" ++ U32.show(at) ++ ":" ++ t
    case D.CaretMoved{id, at}:
      "c" ++ U32.show(id) ++ ":" ++ U32.show(at)
    case D.SelectionChanged{id}:
      "S" ++ U32.show(id)

def change_hash(c: D.Change, +h: U32) -> U32:
  str_hash(key(c), h)

def changes_hash(cs: List<&2, D.Change>, +h: U32) -> U32:
  match cs:
    case Nil{}:
      h
    case Con{c, rest}:
      changes_hash(rest, change_hash(c, h))

def changes_text(+cs: List<&2, D.Change>) -> String:
  U32.show(count(D.Change, cs)) ++ " changes, hash " ++ U32.show(changes_hash(cs, 7))

def problem_text(r: Result<&2, &2, M.Problem, Unit>) -> String:
  match r:
    case Done{u}:
      "ok"
    case Fail{p}:
      M.problem_text(p)

def encoded_hash(ms: List<&2, W.Message>, +h: U32) -> U32:
  match ms:
    case Nil{}:
      h
    case Con{m, rest}:
      encoded_hash(rest, bytes_hash(W.encode(m), h))

def served_text(s: S.Served) -> String:
  S.Served{c, +out, rs, h, n} = s
  U32.show(count(W.Message, out)) ++ " replies, hash " ++ U32.show(encoded_hash(out, 7))

# Runs
# ----

def ctx() -> O.Ctx:
  O.Ctx{":1.9", 3, "C", 0.0, 0.0}

def get_items() -> W.Message:
  W.Message{1, 0, 10, 0, O.cache_path(), "org.a11y.atspi.Cache", "GetItems", "", ":1.42", ":1.9", W.DEnd{}}

# Repeats f r times, keeping the last result; r comes from the clock so the
# work cannot start before the clock is read.
def drains(r: Nat, +buf: List<&2, U32>, last: String) -> String:
  match r:
    case 0n:
      last
    case 1n+p:
      drains(p, buf, inbox_text(W.drain(buf)))

def encodes(r: Nat, +ms: List<&2, W.Message>, +h: U32) -> U32:
  match r:
    case 0n:
      h
    case 1n+p:
      encodes(p, ms, encoded_hash(ms, h))

def diffs(r: Nat, +a: M.Tree, +b: M.Tree, last: String) -> String:
  match r:
    case 0n:
      last
    case 1n+p:
      diffs(p, a, b, changes_text(D.diff(a, b)))

def checks(r: Nat, +t: M.Tree, last: String) -> String:
  match r:
    case 0n:
      last
    case 1n+p:
      checks(p, t, problem_text(M.check(t)))

def announces(r: Nat, +t: M.Tree, last: String) -> String:
  match r:
    case 0n:
      last
    case 1n+p:
      announces(p, t, U32.show(encoded_hash(O.announce(ctx(), M.nodes(t), D.diff(M.Tree{Nil{}}, t)), 7)))

def serves(r: Nat, +t: M.Tree, last: String) -> String:
  match r:
    case 0n:
      last
    case 1n+p:
      serves(p, t, served_text(S.serve([get_items()], ctx(), t)))

def reps(+t: Nat, r: Nat) -> Nat:
  Nat.add(r, Nat.sub(t, t))

def ms(+a: Nat, +b: Nat, +r: Nat) -> String:
  Nat.show(Nat.sub(b, a)) ++ " ms for " ++ Nat.show(r)

def wire(+small: List<&2, U32>, +big: List<&2, U32>, +ms20: List<&2, W.Message>) -> IO(Unit):
  do IO<Unit>:
    +t0 : Nat <- IO.now()
    IO.print("drain 160 msgs (33 KB): " ++ drains(reps(t0, 20n), small, ""))
    +t1 : Nat <- IO.now()
    IO.print("  " ++ ms(t0, t1, 20n))
    IO.print("drain 1000 msgs: " ++ drains(reps(t1, 1n), big, ""))
    +t2 : Nat <- IO.now()
    IO.print("  " ++ ms(t1, t2, 1n))
    IO.print("encode 160 msgs: hash " ++ U32.show(encodes(reps(t2, 20n), ms20, 7)))
    +t3 : Nat <- IO.now()
    IO.print("  " ++ ms(t2, t3, 20n))

def model(+n: Nat, +a: M.Tree, +b: M.Tree, +r: Nat) -> IO(Unit):
  do IO<Unit>:
    +t0 : Nat <- IO.now()
    IO.print("diff " ++ Nat.show(n) ++ " nodes: " ++ diffs(reps(t0, r), a, b, ""))
    +t1 : Nat <- IO.now()
    IO.print("  " ++ ms(t0, t1, r))
    IO.print("check " ++ Nat.show(n) ++ " nodes: " ++ checks(reps(t1, r), b, ""))
    +t2 : Nat <- IO.now()
    IO.print("  " ++ ms(t1, t2, r))
    IO.print("announce " ++ Nat.show(n) ++ " nodes: hash " ++ announces(reps(t2, r), b, ""))
    +t3 : Nat <- IO.now()
    IO.print("  " ++ ms(t2, t3, r))
    IO.print("GetItems " ++ Nat.show(n) ++ " nodes: " ++ serves(reps(t3, r), b, ""))
    +t4 : Nat <- IO.now()
    IO.print("  " ++ ms(t3, t4, r))

def main() -> IO(Unit):
  +small = stream(160n, 0)
  +big = stream(1000n, 0)
  +ms20 = msgs(160n, 0)
  +a500 = tree(500n, 0)
  +b500 = tree(500n, 1)
  +a2k = tree(2000n, 0)
  +b2k = tree(2000n, 1)
  do IO<Unit>:
    IO.print("inputs: " ++ U32.show(count(U32, small)) ++ " + " ++ U32.show(count(U32, big)) ++ " bytes, " ++
      U32.show(count(M.Node, M.nodes(a500))) ++ " + " ++ U32.show(count(M.Node, M.nodes(b2k))) ++ " nodes, " ++
      U32.show(count(W.Message, ms20)) ++ " msgs, " ++ U32.show(count(M.Node, M.nodes(b500))) ++ "+" ++ U32.show(count(M.Node, M.nodes(a2k))))
    wire(small, big, ms20)
    model(500n, a500, b500, 10n)
    model(2000n, a2k, b2k, 2n)
