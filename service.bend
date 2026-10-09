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

# Text calls waiting for the app's verdict (held), the answers of settled
# ones (ready, newest first), and the next ticket.
type Pending is Data:
  Pending{held: List<&2, S.Held>, ready: List<&2, W.Message>, next: U32}

# log: print one line per call answered and per signal batch sent.
type Service is Type:
  Service{link: B.Link, ctx: O.Ctx, tree: M.Index, stats: Stats, log: Bool, pending: Pending}

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
    case D.WindowActivated{id}:
      "window activate " ++ U32.show(id)
    case D.WindowDeactivated{id}:
      "window deactivate " ++ U32.show(id)
    case D.Announced{id, t, level}:
      "announcement from " ++ U32.show(id) ++ " (live " ++ U32.show(level) ++ "): " ++ t
    case D.TextRemoved{id, at, n, t}:
      "text of " ++ U32.show(id) ++ " lost " ++ U32.show(n) ++ " at " ++ U32.show(at) ++ ": " ++ t
    case D.TextInserted{id, at, n, t}:
      "text of " ++ U32.show(id) ++ " gained " ++ U32.show(n) ++ " at " ++ U32.show(at) ++ ": " ++ t
    case D.CaretMoved{id, at}:
      "caret of " ++ U32.show(id) ++ " at " ++ U32.show(at)
    case D.SelectionChanged{id}:
      "selection of " ++ U32.show(id)

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

# Held text calls
# ---------------

def no_pending() -> Pending:
  Pending{Nil{}, Nil{}, 1}

def verdicts(hs: List<&2, S.Held>, +ok: Bool) -> List<&2, W.Message>:
  match hs:
    case Nil{}:
      Nil{}
    case Con{h, rest}:
      List.append(&2, W.Message, S.verdict(h, ok), verdicts(rest, ok))

# The answers owed now: the settled ones in order, then a refusal for every
# call the app did not settle.
def owed(p: Pending) -> List<&2, W.Message>:
  Pending{held, ready, next} = p
  List.append(&2, W.Message, List.reverse(&2, W.Message, ready), verdicts(held, False{}))

def cleared(p: Pending) -> Pending:
  Pending{held, ready, next} = p
  Pending{Nil{}, Nil{}, next}

def ticket_of(h: S.Held) -> U32:
  S.Held{t, c, q} = h
  t

# The held calls other than the ticket's.
def others(hs: List<&2, S.Held>, +ticket: U32) -> List<&2, S.Held>:
  match hs:
    case Nil{}:
      Nil{}
    case Con{+h, more}:
      +tail = others(more, ticket)
      Bool.pick(List<&2, S.Held>, U32.is_eq(ticket_of(h), ticket), tail, Con{h, tail})

# The answers to the ticket's call, newest first.
def answers(hs: List<&2, S.Held>, +ticket: U32, +ok: Bool) -> List<&2, W.Message>:
  match hs:
    case Nil{}:
      Nil{}
    case Con{+h, more}:
      Bool.pick(List<&2, W.Message>, U32.is_eq(ticket_of(h), ticket), S.verdict(h, ok), answers(more, ticket, ok))

def take(p: Pending, +ticket: U32, +ok: Bool) -> Pending:
  Pending{+held, ready, next} = p
  Pending{others(held, ticket), List.append(&2, W.Message, answers(held, ticket, ok), ready), next}

def settled(p: Pending, r: M.Request, +ok: Bool) -> Pending:
  match r:
    case M.EditText{id, op, +ticket}:
      take(p, ticket, ok)
    case _:
      p

# Records the app's verdict on a request pump returned: for a text request
# (EditText), whether it was performed (True) or refused; its caller gets
# that answer with the next publish (after the signals of the change) or
# pump. Activate and Focus were answered when they arrived; settling them
# does nothing. A text request never settled is answered False.
def settle(svc: Service, r: M.Request, ok: Bool) -> Service:
  Service{link, ctx, tree, stats, log, pend} = svc
  Service{link, ctx, tree, stats, log, settled(pend, r, ok)}

def held_more(p: Pending, more: List<&2, S.Held>, +next: U32) -> Pending:
  Pending{held, ready, n} = p
  Pending{List.append(&2, S.Held, held, more), ready, next}

# Lifecycle
# ---------

def locale.pick(r: B.Res(String)) -> String:
  match r:
    case Fail{e}:
      "C"
    case Done{l}:
      l

# After Embed, the first tree is announced as if it replaced an empty one:
# caches learn every node, and an active frame activates its window, which
# is how screen readers learn the app's window and speak its title.
def registered(got: B.Link & String, +tree: M.Tree, locale: String, +log: Bool) -> IO(Service):
  (link, +name) = got
  +ctx = {O.Ctx{name, 0, locale, 0.0, 0.0} : O.Ctx}
  +ix = M.indexed(tree)
  +changes = D.diff.indexed(M.index(Nil{}), ix)
  do IO<Service>:
    sent : B.Link <- B.send(link, Con{embed(name), O.announce.in(ctx, ix, changes)})
    log_changes(log, changes)
    return Service{sent, ctx, ix, Stats{0, 0, 0}, log, no_pending()}

def connected(r: B.Res(String), +tree: M.Tree, locale: String, log: Bool) -> IO(Service):
  match r:
    case Fail{e}:
      IO.pure(Service, Service{B.Dead{B.reason(e)}, O.Ctx{"", 0, locale, 0.0, 0.0}, M.indexed(tree), Stats{0, 0, 0}, log, no_pending()})
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
  Service{link, ctx, tree, stats, log, pend} = svc
  B.close(link)

def status.of(got: B.Link & String, +ctx: O.Ctx, tree: M.Index, stats: Stats, log: Bool, pend: Pending) -> Service & String:
  (link, +why) = got
  O.Ctx{+bus, +app, l, x, y} = ctx
  (Service{link, ctx, tree, stats, log, pend},
    Bool.pick(String, String.is_empty(why), "live as " ++ bus ++ ", app id " ++ U32.show(app), "offline: " ++ why))

# "live as :1.36, app id 3" or the reason the service is offline.
def status(svc: Service) -> Service & String:
  Service{link, +ctx, tree, stats, log, pend} = svc
  status.of(B.reason_of(link), ctx, tree, stats, log, pend)

# Records where the window is on the screen, so Component answers in
# screen coordinates use the real origin instead of (0, 0).
def moved(svc: Service, +x: F32, +y: F32) -> Service:
  Service{link, ctx, tree, stats, log, pend} = svc
  Service{link, O.at(ctx, x, y), tree, stats, log, pend}

def stats(svc: Service) -> Service & Stats:
  Service{link, ctx, tree, +st, log, pend} = svc
  (Service{link, ctx, tree, st, log, pend}, st)

# Publishing
# ----------

def count(-A: Data, xs: List<&2, A>) -> U32:
  U32.from_nat(List.length(&2, A, xs))

# Replaces the published tree, announcing exactly what changed.
# Answers to settled text calls go after the signals, so a client that
# reads the text when its call returns sees the change.
def publish(svc: Service, +tree: M.Tree) -> IO(Service):
  Service{link, +ctx, old, Stats{c, s, r}, +log, +pend} = svc
  +ix = M.indexed(tree)
  +changes = D.diff.indexed(old, ix)
  +msgs = O.announce.in(ctx, ix, changes)
  do IO<Service>:
    log_changes(log, changes)
    sent : B.Link <- B.send(link, List.append(&2, W.Message, msgs, owed(pend)))
    return Service{sent, ctx, ix, Stats{c, (s + count(W.Message, msgs) : U32), r}, log, cleared(pend)}

# Answering
# ---------

def calls(msgs: List<&2, W.Message>) -> List<&2, W.Message>:
  match msgs:
    case Nil{}:
      Nil{}
    case Con{W.Message{+k, f, s, r, p, i, m, e, d, sn, b}, rest}:
      +tail = calls(rest)
      Bool.pick(List<&2, W.Message>, U32.is_eq(k, 1), Con{W.Message{k, f, s, r, p, i, m, e, d, sn, b}, tail}, tail)

def answered(link: B.Link, served: S.Served, tree: M.Index, stats: Stats, +log: Bool, +n: U32, pend: Pending) -> IO(Service & List<&2, M.Request>):
  S.Served{ctx, out, +reqs, held, +next} = served
  Stats{c, s, r} = stats
  do IO<Service & List<&2, M.Request>>:
    sent : B.Link <- B.send(link, out)
    return (Service{sent, ctx, tree, Stats{(c + n : U32), s, (r + count(M.Request, reqs) : U32)}, log, held_more(pend, held, next)}, reqs)

def next_ticket(p: Pending) -> U32:
  Pending{h, r, next} = p
  next

def received(got: B.Link & List<&2, W.Message>, +ctx: O.Ctx, +tree: M.Index, stats: Stats, +log: Bool, +pend: Pending) -> IO(Service & List<&2, M.Request>):
  (link, +msgs) = got
  do IO<Service & List<&2, M.Request>>:
    log_calls(log, calls(msgs))
    answered(link, S.serve.in(msgs, ctx, tree, next_ticket(pend)), tree, stats, log, count(W.Message, calls(msgs)), pend)

def calls_seen(svc: Service) -> Service & U32:
  Service{link, ctx, tree, Stats{+c, s, r}, log, pend} = svc
  (Service{link, ctx, tree, Stats{c, s, r}, log, pend}, c)

def pump.once(svc: Service, ms: U32) -> IO(Service & List<&2, M.Request>):
  Service{link, ctx, tree, stats, log, pend} = svc
  do IO<Service & List<&2, M.Request>>:
    got : B.Link & List<&2, W.Message> <- B.recv(link, ms)
    received(got, ctx, tree, stats, log, pend)

def pump.counted(seen: Service & U32, rs: List<&2, M.Request>, +before: U32,
  k: Service -> List<&2, M.Request> -> Bool -> IO(Service & List<&2, M.Request>)) -> IO(Service & List<&2, M.Request>):
  (svc, +after) = seen
  k(svc, rs, U32.is_ne(before, after))

def pump.step(got: Service & List<&2, M.Request>, rs: List<&2, M.Request>, +before: U32,
  k: Service -> List<&2, M.Request> -> Bool -> IO(Service & List<&2, M.Request>)) -> IO(Service & List<&2, M.Request>):
  (svc, now) = got
  pump.counted(calls_seen(svc), List.append(&2, M.Request, rs, now), before, k)

# One round: read (waiting at most ms), answer, and tell k whether any call
# was answered.
def pump.round(seen: Service & U32, rs: List<&2, M.Request>, ms: U32,
  k: Service -> List<&2, M.Request> -> Bool -> IO(Service & List<&2, M.Request>)) -> IO(Service & List<&2, M.Request>):
  (svc, +before) = seen
  do IO<Service & List<&2, M.Request>>:
    got : Service & List<&2, M.Request> <- pump.once(svc, ms)
    pump.step(got, rs, before, k)

# Clients make one call at a time and wait for each reply, so one batch per
# frame turns a screen reader's few hundred startup calls into seconds.
# After a round that answered calls, wait up to 3 ms for the next one, for
# at most fuel rounds; an idle frame costs one non-blocking read.
def pump.go(fuel: Nat, svc: Service, rs: List<&2, M.Request>, busy: Bool) -> IO(Service & List<&2, M.Request>):
  match fuel busy:
    case _ False{}:
      IO.pure(Service & List<&2, M.Request>, (svc, rs))
    case 0n True{}:
      IO.pure(Service & List<&2, M.Request>, (svc, rs))
    case 1n+p True{}:
      pump.round(calls_seen(svc), rs, 3, s => all => b => pump.go(p, s, all, b))

# Reads what arrived (without waiting), answers every call against the
# published tree, and returns the requests for the app to route, in
# arrival order. While calls keep coming it keeps answering, up to 256
# short rounds.
def pump.rounds(svc: Service) -> IO(Service & List<&2, M.Request>):
  pump.round(calls_seen(svc), Nil{}, 0, s => rs => b => pump.go(256n, s, rs, b))

def owing(p: Pending) -> Bool:
  Pending{held, ready, next} = p
  Bool.not(List.is_empty(&2, S.Held, held) && List.is_empty(&2, W.Message, ready))

def pump.owed(owes: Bool, svc: Service) -> IO(Service & List<&2, M.Request>):
  match owes:
    case False{}:
      pump.rounds(svc)
    case True{}:
      Service{link, ctx, tree, stats, log, +pend} = svc
      do IO<Service & List<&2, M.Request>>:
        sent : B.Link <- B.send(link, owed(pend))
        pump.rounds(Service{sent, ctx, tree, stats, log, cleared(pend)})

def pending_of(svc: Service) -> Service & Pending:
  Service{link, ctx, tree, stats, log, +pend} = svc
  (Service{link, ctx, tree, stats, log, pend}, pend)

def pump.start(got: Service & Pending) -> IO(Service & List<&2, M.Request>):
  (svc, pend) = got
  pump.owed(owing(pend), svc)

# Text answers still owed from the last frame (settled, or refused when
# never settled) go out first.
def pump(svc: Service) -> IO(Service & List<&2, M.Request>):
  pump.start(pending_of(svc))
