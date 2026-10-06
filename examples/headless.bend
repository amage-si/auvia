import Base
import ../model.bend as M
import ../service.bend as S

# A window-less accessible app for protocol checks: a frame with a button
# and a counter label. AT-SPI "click" on the button increments the counter;
# GrabFocus moves focus. Runs for about 60 seconds.

def button(+focus: U32) -> M.Node:
  M.Node{2, 1, M.PushButton{}, "Incrementar", "Soma um ao contador",
    List.append(&2, M.State, [M.Enabled{}, M.Sensitive{}, M.Visible{}, M.Showing{}, M.Focusable{}],
      Bool.pick(List<&2, M.State>, U32.is_eq(focus, 2), [M.Focused{}], Nil{})),
    [M.Action{"click", "Soma um", "space"}], [M.Relation{M.ControllerFor{}, [3]}], Nil{},
    M.Box{20.0, 60.0, 160.0, 44.0}, None{}, Nil{}}

def label(+count: U32) -> M.Node:
  M.Node{3, 1, M.Label{}, "Cliques: " ++ U32.show(count), "",
    [M.Enabled{}, M.Sensitive{}, M.Visible{}, M.Showing{}], Nil{},
    [M.Relation{M.ControlledBy{}, [2]}], [M.Attr{"live", "polite"}],
    M.Box{20.0, 120.0, 160.0, 24.0}, None{}, Nil{}}

def tree(count: U32, focus: U32) -> M.Tree:
  M.Tree{[M.application("auvia-headless", [1]),
    M.Node{1, 0, M.Frame{}, "Auvia headless", "", [M.Enabled{}, M.Sensitive{}, M.Visible{}, M.Showing{}, M.Active{}],
      Nil{}, Nil{}, Nil{}, M.Box{0.0, 0.0, 400.0, 200.0}, None{}, [2, 3]},
    button(focus), label(count)]}

type Counter is Data:
  Counter{count: U32, focus: U32}

def apply(rs: List<&2, M.Request>, app: Counter) -> Counter:
  match rs:
    case Nil{}:
      app
    case Con{M.Activate{+id, i}, rest}:
      Counter{+c, f} = app
      apply(rest, Counter{Bool.pick(U32, U32.is_eq(id, 2), (c + 1 : U32), c), f})
    case Con{M.Focus{id}, rest}:
      Counter{c, f} = app
      apply(rest, Counter{c, id})

def view(app: Counter) -> M.Tree:
  Counter{c, f} = app
  tree(c, f)

def pumped(got: S.Service & List<&2, M.Request>, app: Counter, k: S.Service -> Counter -> IO(Unit)) -> IO(Unit):
  (svc, rs) = got
  +next = apply(rs, app)
  do IO<Unit>:
    s : S.Service <- S.publish(svc, view(next))
    k(s, next)

def loop(fuel: Nat, svc: S.Service, app: Counter) -> IO(Unit):
  match fuel:
    case 0n:
      do IO<Unit>:
        IO.print("headless: done")
        S.stop(svc)
    case 1n+p:
      do IO<Unit>:
        got : S.Service & List<&2, M.Request> <- S.pump(svc)
        IO.sleep(50)
        pumped(got, app, s => a => loop(p, s, a))

def report(got: S.Service & String) -> IO(S.Service):
  (svc, text) = got
  do IO<S.Service>:
    IO.print("headless: " ++ text)
    return svc

def main() -> IO(Unit):
  do IO<Unit>:
    svc : S.Service <- S.start(tree(0, 0), True{})
    svc : S.Service <- report(S.status(svc))
    loop(1200n, svc, Counter{0, 0})
