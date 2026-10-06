import Base
import ./model.bend as M
import ./diff.bend as D
import ./dbus/bus.bend as B
import ./dbus/wire.bend as W
import ./atspi/objects.bend as O
import ./atspi/serve.bend as S

# An app's presence on the accessibility bus: registration with the
# registry, change signals for each new tree, and answers to method calls.
# Without a reachable bus the service stays offline and the app runs on.

type Stats is Data:
  Stats{calls: U32, signals: U32, requests: U32}

# log: print one line per call answered and per signal batch sent.
type Service is Type:
  Service{link: B.Link, ctx: O.Ctx, tree: M.Tree, stats: Stats, log: Bool}

def a11y_address() -> W.Message:
  W.call("org.a11y.Bus", "/org/a11y/bus", "org.a11y.Bus", "GetAddress", W.DEnd{})

def embed(name: String) -> W.Message:
  W.call(O.registry(), O.root_path(), "org.a11y.atspi.Socket", "Embed", W.seq([O.ref(name, O.root_path())]))

# Address
# -------

def asked(got: B.Link & B.Res(W.Message)) -> IO(B.Res(String)):
  (link, r) = got
  match r:
    case Fail{e}:
      do IO<B.Res(String)>:
        B.close(link)
        return Fail{e}
    case Done{W.Message{k, f, s, rep, p, i, m, e, d, sn, body}}:
      do IO<B.Res(String)>:
        B.close(link)
        return Done{W.text(W.arg(body, 0n))}

def from_session(r: B.Res(String)) -> IO(B.Res(String)):
  match r:
    case Fail{e}:
      IO.pure(B.Res(String), Fail{e})
    case Done{address}:
      do IO<B.Res(String)>:
        link : B.Link <- B.open(address)
        got : B.Link & B.Res(W.Message) <- B.call(link, a11y_address())
        asked(got)

def given(r: B.Res(String)) -> IO(B.Res(String)):
  match r:
    case Done{address}:
      IO.pure(B.Res(String), Done{address})
    case Fail{e}:
      do IO<B.Res(String)>:
        session : B.Res(String) <- IO.get_env("DBUS_SESSION_BUS_ADDRESS")
        from_session(session)

# AT_SPI_BUS_ADDRESS if set, else the session bus's org.a11y.Bus.GetAddress
# (the launcher starts the accessibility bus on first request).
def address() -> IO(B.Res(String)):
  do IO<B.Res(String)>:
    env : B.Res(String) <- IO.get_env("AT_SPI_BUS_ADDRESS")
    given(env)

# Lifecycle
# ---------

def locale.pick(r: B.Res(String)) -> String:
  match r:
    case Fail{e}:
      "C"
    case Done{l}:
      l

def registered(got: B.Link & String, +tree: M.Tree, locale: String, log: Bool) -> IO(Service):
  (link, +name) = got
  +ctx = {O.Ctx{name, 0, locale, 0.0, 0.0} : O.Ctx}
  do IO<Service>:
    sent : B.Link <- B.send(link, Con{embed(name), Nil{}})
    return Service{sent, ctx, tree, Stats{0, 0, 0}, log}

def connected(r: B.Res(String), +tree: M.Tree, locale: String, log: Bool) -> IO(Service):
  match r:
    case Fail{e}:
      IO.pure(Service, Service{B.Dead{B.reason(e)}, O.Ctx{"", 0, locale, 0.0, 0.0}, tree, Stats{0, 0, 0}, log})
    case Done{address}:
      do IO<Service>:
        link : B.Link <- B.open(address)
        registered(B.name(link), tree, locale, log)

# Joins the accessibility bus and embeds the app under the desktop. The
# registry answers Embed asynchronously; pump consumes the reply.
def start(tree: M.Tree, log: Bool) -> IO(Service):
  do IO<Service>:
    lang : B.Res(String) <- IO.get_env("LANG")
    r : B.Res(String) <- address()
    connected(r, tree, locale.pick(lang), log)

def stop(svc: Service) -> IO(Unit):
  Service{link, ctx, tree, stats, log} = svc
  B.close(link)

def status.of(got: B.Link & String, +ctx: O.Ctx, tree: M.Tree, stats: Stats, log: Bool) -> Service & String:
  (link, +why) = got
  O.Ctx{+bus, +app, l, x, y} = ctx
  (Service{link, ctx, tree, stats, log},
    Bool.pick(String, String.is_empty(why), "live as " ++ bus ++ ", app id " ++ U32.show(app), "offline: " ++ why))

# "live as :1.36, app id 3" or the reason the service is offline.
def status(svc: Service) -> Service & String:
  Service{link, +ctx, tree, stats, log} = svc
  status.of(B.reason_of(link), ctx, tree, stats, log)

def stats(svc: Service) -> Service & Stats:
  Service{link, ctx, tree, +st, log} = svc
  (Service{link, ctx, tree, st, log}, st)

# Logging
# -------

def describe(m: W.Message) -> String:
  W.Message{k, f, s, r, p, i, mem, e, d, sender, b} = m
  "auvia: call " ++ i ++ "." ++ mem ++ " on " ++ p ++ " from " ++ sender

def log_calls(on: Bool, msgs: List<&2, W.Message>) -> IO(Unit):
  match on msgs:
    case False{} _:
      IO.pure(Unit, Unit{})
    case True{} Nil{}:
      IO.pure(Unit, Unit{})
    case True{} Con{m, rest}:
      do IO<Unit>:
        IO.print(describe(m))
        log_calls(True{}, rest)

def change_text(c: D.Change) -> String:
  match c:
    case D.StateChanged{id, s, on}:
      "state " ++ M.state_name(s) ++ "=" ++ Bool.show(on) ++ " on " ++ U32.show(id)
    case D.NameChanged{id, name}:
      "name of " ++ U32.show(id) ++ " = " ++ name
    case D.DescriptionChanged{id, t}:
      "description of " ++ U32.show(id)
    case D.RoleChanged{id, r}:
      "role of " ++ U32.show(id) ++ " = " ++ M.role_name(r)
    case D.ValueChanged{id, v}:
      "value of " ++ U32.show(id)
    case D.BoundsChanged{id, b}:
      "bounds of " ++ U32.show(id)
    case D.ParentChanged{id, p}:
      "parent of " ++ U32.show(id) ++ " = " ++ U32.show(p)
    case D.ChildAdded{p, i, c}:
      "child " ++ U32.show(c) ++ " added to " ++ U32.show(p) ++ " at " ++ U32.show(i)
    case D.ChildRemoved{p, i, c}:
      "child " ++ U32.show(c) ++ " removed from " ++ U32.show(p) ++ " at " ++ U32.show(i)
    case D.FocusGained{id}:
      "focus on " ++ U32.show(id)
    case D.Added{id}:
      "cache add " ++ U32.show(id)
    case D.Removed{id}:
      "cache remove " ++ U32.show(id)

def log_changes(on: Bool, cs: List<&2, D.Change>) -> IO(Unit):
  match on cs:
    case False{} _:
      IO.pure(Unit, Unit{})
    case True{} Nil{}:
      IO.pure(Unit, Unit{})
    case True{} Con{c, rest}:
      do IO<Unit>:
        IO.print("auvia: emit " ++ change_text(c))
        log_changes(True{}, rest)

# Publishing
# ----------

def count(-A: Data, xs: List<&2, A>) -> U32:
  U32.from_nat(List.length(&2, A, xs))

# Replaces the published tree, announcing exactly what changed.
def publish(svc: Service, +tree: M.Tree) -> IO(Service):
  Service{link, +ctx, old, Stats{c, s, r}, +log} = svc
  +changes = D.diff(old, tree)
  +msgs = O.announce(ctx, M.nodes(tree), changes)
  do IO<Service>:
    log_changes(log, changes)
    sent : B.Link <- B.send(link, msgs)
    return Service{sent, ctx, tree, Stats{c, (s + count(W.Message, msgs) : U32), r}, log}

# Answering
# ---------

def calls(msgs: List<&2, W.Message>) -> List<&2, W.Message>:
  match msgs:
    case Nil{}:
      Nil{}
    case Con{W.Message{+k, f, s, r, p, i, m, e, d, sn, b}, rest}:
      +tail = calls(rest)
      Bool.pick(List<&2, W.Message>, U32.is_eq(k, 1), Con{W.Message{k, f, s, r, p, i, m, e, d, sn, b}, tail}, tail)

def answered(link: B.Link, served: S.Served, tree: M.Tree, stats: Stats, +log: Bool, +n: U32) -> IO(Service & List<&2, M.Request>):
  S.Served{ctx, out, +reqs} = served
  Stats{c, s, r} = stats
  do IO<Service & List<&2, M.Request>>:
    sent : B.Link <- B.send(link, out)
    return (Service{sent, ctx, tree, Stats{(c + n : U32), s, (r + count(M.Request, reqs) : U32)}, log}, reqs)

def received(got: B.Link & List<&2, W.Message>, +ctx: O.Ctx, +tree: M.Tree, stats: Stats, +log: Bool) -> IO(Service & List<&2, M.Request>):
  (link, +msgs) = got
  do IO<Service & List<&2, M.Request>>:
    log_calls(log, calls(msgs))
    answered(link, S.serve(msgs, ctx, tree), tree, stats, log, count(W.Message, calls(msgs)))

# Reads what arrived (without waiting), answers every call against the
# published tree, and returns the requests for the app to route.
def pump(svc: Service) -> IO(Service & List<&2, M.Request>):
  Service{link, ctx, tree, stats, log} = svc
  do IO<Service & List<&2, M.Request>>:
    got : B.Link & List<&2, W.Message> <- B.recv(link, 0)
    received(got, ctx, tree, stats, log)
