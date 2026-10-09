import Base
import ../model.bend as M
import ../kairo.bend as AK
import ../field.bend as AF
import ../service.bend as S
import ../../Mokko/main.bend as Mk
import ../../Mokko/field.bend as MF
import ../../Kairo/types.bend as KT
import ../../Kairo/main.bend as K
import ../../Kairo/edit.bend as KE
import ../../Runika/font.bend as F
import ../../Tessra/geometry.bend as G

# A window-less accessible app for protocol checks, on the real stack:
# Kairo's state, Mokko's semantics and text field, Auvia's tree. Nothing is
# drawn. A button ("Incrementar") increments a counter label; a text field
# ("Nome", starting as "olá") holds editable text.
#
# An AT-SPI "click" on the button counts as a click (through Kairo);
# GrabFocus moves Kairo's focus; Text and EditableText requests on the field
# go through Mokko's field and Kairo's editing rules, so what the layout
# refuses (U+20AC, for one) reaches the client as a failure and changes
# nothing. There is no clipboard here: copy and paste requests are only
# logged. Runs for about 60 seconds.

def font_path() -> String:
  "/usr/share/fonts/liberation/LiberationSans-Regular.ttf"

def size() -> F32:
  16.0

def field_id() -> U32:
  4

def field_bounds() -> G.Rect:
  G.Rect{20.0, 156.0, 260.0, 44.0}

def field_node() -> KT.Node:
  MF.field_node(field_id(), field_bounds(), "Nome")

def nodes() -> List<&2, KT.Node>:
  [KT.Node{2, G.Rect{20.0, 60.0, 160.0, 44.0}, "Incrementar", KT.ButtonRole{}, True{}, True{}},
    KT.Node{3, G.Rect{20.0, 120.0, 160.0, 24.0}, "Cliques: 0", KT.TextRole{}, True{}, False{}},
    field_node()]

def notes() -> List<&2, AK.Note>:
  [AK.Note{2, "Soma um ao contador", [M.Relation{M.ControllerFor{}, [3]}], Nil{}, "space"},
    AK.Note{3, "", [M.Relation{M.ControlledBy{}, [2]}], [M.Attr{"live", "polite"}], ""}]

type Host is Data:
  Host{state: KT.State, count: U32, field: MF.Field}

# The tree
# --------

def semantics.go(ns: List<&2, KT.Node>, +s: KT.State) -> List<&2, Mk.Semantic>:
  match ns:
    case Nil{}:
      Nil{}
    case Con{n, rest}:
      Con{Mk.semantic(n, s), semantics.go(rest, s)}

def semantics(+s: KT.State) -> List<&2, Mk.Semantic>:
  KT.State{ns, h, f, c, k, t, d, l, a, w, hh} = s
  semantics.go(ns, s)

def contents(r: Result<&2, &2, String, MF.FieldView>) -> List<&2, AK.Content>:
  match r:
    case Fail{e}:
      Nil{}
    case Done{MF.FieldView{v, e}}:
      [AF.content(e)]

def view(app: Host) -> M.Tree:
  Host{+s, c, f} = app
  AK.build.with("auvia-headless", AK.Surface{1, "Auvia headless", 400.0, 220.0, True{}}, semantics(s), notes(),
    contents(MF.view(field_node(), s, f, size(), MF.field_theme(), "Seu nome")))

# Requests
# --------

# A request performed, whether it was, and a line to log about it.
type Handled is Data:
  Handled{request: M.Request, ok: Bool, note: String}

# The app after the requests so far, and what was done (newest first).
type Step is Data:
  Step{app: Host, done: List<&2, Handled>}

def activations(c: KT.Change) -> U32:
  KT.Change{s, actions, d, l} = c
  K.activation_count(actions)

# A button or focus request goes through Kairo; each activation counts.
def routed(+r: M.Request, routed: AK.Routed, +count: U32, f: MF.Field, done: List<&2, Handled>) -> Step:
  AK.Routed{+change, +ok} = routed
  +n = (count + activations(change) : U32)
  Step{Host{K.next(K.set_label(K.next(change), 3, "Cliques: " ++ U32.show(n))), n, f}, Con{Handled{r, ok, ""}, done}}

def request_line(r: KE.Request) -> String:
  match r:
    case KE.NoRequest{}:
      ""
    case KE.CopyText{t}:
      "; copy requested (no clipboard here): " ++ t
    case KE.PasteText{}:
      "; paste requested (no clipboard here)"

def message_line(m: Maybe<&2, String>) -> String:
  match m:
    case None{}:
      ""
    case Some{t}:
      "; refused: " ++ t

def field_line(+f: MF.Field, r: KE.Request) -> String:
  "headless: field \"" ++ MF.text_of(f) ++ "\"" ++ message_line(MF.message(f)) ++ request_line(r)

# A text request goes through Mokko's field and Kairo's editing rules.
def edited(+r: M.Request, e: AF.Edited, s: KT.State, +count: U32, done: List<&2, Handled>) -> Step:
  AF.Edited{MF.Fed{+f, dirty, request}, +ok} = e
  Step{Host{s, count, f}, Con{Handled{r, ok, field_line(f, request)}, done}}

def step.of(r: M.Request, +s: KT.State, +c: U32, f: MF.Field, +font: F.Font, done: List<&2, Handled>) -> Step:
  match r:
    case M.EditText{id, op, t}:
      +q = {M.EditText{id, op, t} : M.Request}
      edited(q, AF.edit(font, size(), field_bounds(), s, field_id(), f, q), s, c, done)
    case M.Activate{id, i}:
      +q = {M.Activate{id, i} : M.Request}
      routed(q, AK.route(s, q), c, f, done)
    case M.Focus{id}:
      +q = {M.Focus{id} : M.Request}
      routed(q, AK.route(s, q), c, f, done)

def step(r: M.Request, st: Step, +font: F.Font) -> Step:
  Step{Host{+s, +c, f}, done} = st
  step.of(r, s, c, f, font, done)

# Every request in arrival order.
def run(rs: List<&2, M.Request>, st: Step, +font: F.Font) -> Step:
  match rs:
    case Nil{}:
      st
    case Con{r, rest}:
      run(rest, step(r, st, font), font)

# The verdict of every request for the service (text callers wait for it).
def settle_all(ds: List<&2, Handled>, svc: S.Service) -> S.Service:
  match ds:
    case Nil{}:
      svc
    case Con{Handled{r, ok, n}, rest}:
      settle_all(rest, S.settle(svc, r, ok))

def op_text(op: M.TextOp) -> String:
  match op:
    case M.SetCaret{o}:
      "caret " ++ U32.show(o)
    case M.Select{a, b}:
      "select " ++ U32.show(a) ++ "-" ++ U32.show(b)
    case M.SetContents{t}:
      "set \"" ++ t ++ "\""
    case M.Insert{o, t}:
      "insert \"" ++ t ++ "\" at " ++ U32.show(o)
    case M.Delete{a, b}:
      "delete " ++ U32.show(a) ++ "-" ++ U32.show(b)
    case M.Copy{a, b}:
      "copy " ++ U32.show(a) ++ "-" ++ U32.show(b)
    case M.Cut{a, b}:
      "cut " ++ U32.show(a) ++ "-" ++ U32.show(b)
    case M.Paste{o}:
      "paste at " ++ U32.show(o)

def request_text(r: M.Request) -> String:
  match r:
    case M.Activate{id, i}:
      "activate " ++ U32.show(id) ++ " action " ++ U32.show(i)
    case M.Focus{id}:
      "focus " ++ U32.show(id)
    case M.EditText{id, op, t}:
      "text " ++ U32.show(id) ++ ": " ++ op_text(op)

def log(ds: List<&2, Handled>) -> IO(Unit):
  match ds:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{Handled{r, ok, +n}, rest}:
      do IO<Unit>:
        IO.print("headless: request " ++ request_text(r) ++ " accepted=" ++ Bool.show(ok))
        IO.print(n)
        log(rest)

# Loop
# ----

def ran(st: Step, svc: S.Service, k: S.Service -> Host -> IO(Unit)) -> IO(Unit):
  Step{+app, done} = st
  +ds = List.reverse(&2, Handled, done)
  do IO<Unit>:
    log(ds)
    s : S.Service <- S.publish(settle_all(ds, svc), view(app))
    k(s, app)

def pumped(got: S.Service & List<&2, M.Request>, app: Host, +font: F.Font, k: S.Service -> Host -> IO(Unit)) -> IO(Unit):
  (svc, rs) = got
  ran(run(rs, Step{app, Nil{}}, font), svc, k)

def loop(fuel: Nat, svc: S.Service, app: Host, +font: F.Font) -> IO(Unit):
  match fuel:
    case 0n:
      do IO<Unit>:
        IO.print("headless: done")
        S.stop(svc)
    case 1n+p:
      do IO<Unit>:
        got : S.Service & List<&2, M.Request> <- S.pump(svc)
        IO.sleep(50)
        pumped(got, app, font, s => a => loop(p, s, a, font))

def report(got: S.Service & String) -> IO(S.Service):
  (svc, text) = got
  do IO<S.Service>:
    IO.print("headless: " ++ text)
    return svc

def started(+app: Host, +font: F.Font) -> IO(Unit):
  do IO<Unit>:
    svc : S.Service <- S.start(view(app), True{})
    svc : S.Service <- report(S.status(svc))
    loop(1200n, svc, app, font)

def with_field(r: Result<&2, &2, String, MF.Field>, +s: KT.State, +font: F.Font) -> IO(Unit):
  match r:
    case Fail{e}:
      IO.die(Unit, 1, "headless: " ++ e)
    case Done{f}:
      started(Host{s, 0, f}, font)

def with_state(r: Result<&2, &2, KT.Error, KT.State>, +font: F.Font) -> IO(Unit):
  match r:
    case Fail{e}:
      IO.die(Unit, 1, "headless: invalid Kairo nodes")
    case Done{s}:
      with_field(MF.field(font, size(), "olá"), s, font)

def with_font(r: Result<&2, &2, String, F.Font>) -> IO(Unit):
  match r:
    case Fail{e}:
      IO.die(Unit, 1, "headless: cannot load " ++ font_path() ++ ": " ++ e)
    case Done{font}:
      with_state(K.init(nodes(), 400.0, 220.0), font)

def main() -> IO(Unit):
  do IO<Unit>:
    r : Result<&2, &2, String, F.Font> <- F.load(font_path())
    with_font(r)
