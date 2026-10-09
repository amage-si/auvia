import Base
import ../native/unix.bend as U
import ./wire.bend as W

# A D-Bus connection over a Unix socket: SASL EXTERNAL, Hello, framed
# send/receive and a blocking call for setup. The protocol is Bend; the
# native bridge only connects, reads bytes and reports the uid.

def Res(-A: Type) -> Type:
  Result<&1, &1, U32 & String, A>

# A live link owns its socket, the bytes of an incomplete message, the next
# serial and the unique name the bus assigned. A dead link says why.
type Link is Type:
  Live{sock: Socket, buf: List<&2, U32>, serial: U32, name: String}
  Dead{reason: String}

# Addresses
# ---------

def hex_digit(+n: U32) -> U32:
  Bool.pick(U32, (n < 10 : U32), (n + 48 : U32), (n + 87 : U32))

def hex_value(+c: U32) -> U32:
  Bool.pick(U32, (c >= 97 : U32), (c - 87 : U32), Bool.pick(U32, (c >= 65 : U32), (c - 55 : U32), (c - 48 : U32)))

# "%2d"-style escapes, as D-Bus addresses use them.
def unescape(cs: List<&2, U32>) -> List<&2, U32>:
  match cs:
    case Con{37, Con{+a, Con{+b, rest}}}:
      Con{U32.or(U32.shln(hex_value(a), 4n), hex_value(b)), unescape(rest)}
    case Con{c, rest}:
      Con{c, unescape(rest)}
    case Nil{}:
      Nil{}

def unescape_str(s: String) -> String:
  W.from_utf8(unescape(W.utf8(s)))

def find_key(parts: List<&2, String>) -> Maybe<&2, String>:
  match parts:
    case Nil{}:
      None{}
    case Con{+p, rest}:
      Bool.pick(Maybe<&2, String>, String.starts_with(p, "path="), Some{unescape_str(String.drop(p, 5n))},
        Bool.pick(Maybe<&2, String>, String.starts_with(p, "abstract="), Some{"@" ++ unescape_str(String.drop(p, 9n))}, find_key(rest)))

def first_unix(addrs: List<&2, String>) -> Maybe<&2, String>:
  match addrs:
    case Nil{}:
      None{}
    case Con{+a, rest}:
      Bool.pick(Maybe<&2, String>, String.starts_with(a, "unix:"),
        find_key(String.split(String.drop(a, 5n), ',')), first_unix(rest))

# The socket path of the first unix: address ("@name" for abstract ones).
def socket_path(address: String) -> Maybe<&2, String>:
  first_unix(String.split(address, ';'))

# SASL
# ----

def hex_ascii(cs: List<&2, U32>) -> List<&2, U32>:
  match cs:
    case Nil{}:
      Nil{}
    case Con{+c, rest}:
      Con{hex_digit(U32.shrn(c, 4n)), Con{hex_digit(U32.and(c, 15)), hex_ascii(rest)}}

def crlf(s: String) -> List<&2, U32>:
  List.append(&2, U32, W.utf8(s), [13, 10])

# The NUL credentials byte, then AUTH EXTERNAL with the uid as hex ASCII.
def auth_line(+uid: U32) -> List<&2, U32>:
  Con{0, List.append(&2, U32, W.utf8("AUTH EXTERNAL "), List.append(&2, U32, hex_ascii(W.utf8(U32.show(uid))), [13, 10]))}

def has_crlf(bs: List<&2, U32>) -> Bool:
  match bs:
    case Con{13, Con{10, rest}}:
      True{}
    case Con{b, rest}:
      has_crlf(rest)
    case Nil{}:
      False{}

def is_ok(+line: List<&2, U32>) -> Bool:
  String.starts_with(W.from_utf8(line), "OK ")

# Results
# -------

def fail(-A: Type, code: U32, text: String) -> Res(A):
  Fail{(code, text)}

def reason(e: U32 & String) -> String:
  (code, text) = e
  text

# Receiving
# ---------

def inbox(sock: Socket, ib: W.Inbox, serial: U32, name: String) -> Link & List<&2, W.Message>:
  W.Inbox{msgs, rest, bad} = ib
  (Live{sock, rest, serial, name}, msgs)

def recv.bytes(sock: Socket, bytes: List<&2, U32>, buf: List<&2, U32>, serial: U32, name: String) ->
  IO(Link & List<&2, W.Message>):
  match bytes:
    case Nil{}:
      do IO<Link & List<&2, W.Message>>:
        Socket.close(sock)
        return (Dead{"auvia: the bus closed the connection"}, Nil{})
    case Con{h, t}:
      IO.pure(Link & List<&2, W.Message>, inbox(sock, W.drain.more(buf, Con{h, t}), serial, name))

def recv.res(sock: Socket, r: Res(Maybe<&2, List<&2, U32>>), buf: List<&2, U32>, serial: U32, name: String) ->
  IO(Link & List<&2, W.Message>):
  match r:
    case Fail{e}:
      do IO<Link & List<&2, W.Message>>:
        Socket.close(sock)
        return (Dead{reason(e)}, Nil{})
    case Done{None{}}:
      IO.pure(Link & List<&2, W.Message>, (Live{sock, buf, serial, name}, Nil{}))
    case Done{Some{bytes}}:
      recv.bytes(sock, bytes, buf, serial, name)

def recv.got(got: Socket & Res(Maybe<&2, List<&2, U32>>), buf: List<&2, U32>, serial: U32, name: String) ->
  IO(Link & List<&2, W.Message>):
  (sock, r) = got
  recv.res(sock, r, buf, serial, name)

# Waits up to ms for bytes and answers every message they complete.
def recv(link: Link, ms: U32) -> IO(Link & List<&2, W.Message>):
  match link:
    case Dead{why}:
      IO.pure(Link & List<&2, W.Message>, (Dead{why}, Nil{}))
    case Live{sock, buf, serial, name}:
      do IO<Link & List<&2, W.Message>>:
        got : Socket & Res(Maybe<&2, List<&2, U32>>) <- U.Unix.poll_bytes(sock, 65536, ms)
        recv.got(got, buf, serial, name)

# Sending
# -------

type Batch is Data:
  Batch{bytes: List<&2, U32>, serial: U32}

def next_serial(+s: U32) -> U32:
  Bool.pick(U32, U32.is_eq(s, 4294967295), 1, (s + 1 : U32))

def batch.join(bytes: List<&2, U32>, b: Batch) -> Batch:
  Batch{more, serial} = b
  Batch{List.append(&2, U32, bytes, more), serial}

# Numbers the messages from serial and concatenates their encodings.
def batch(msgs: List<&2, W.Message>, +serial: U32) -> Batch:
  match msgs:
    case Nil{}:
      Batch{Nil{}, serial}
    case Con{m, rest}:
      batch.join(W.encode(W.with_serial(m, serial)), batch(rest, next_serial(serial)))

def sent.res(sock: Socket, r: Res(Unit), buf: List<&2, U32>, serial: U32, name: String) -> IO(Link):
  match r:
    case Fail{e}:
      do IO<Link>:
        Socket.close(sock)
        return Dead{reason(e)}
    case Done{u}:
      IO.pure(Link, Live{sock, buf, serial, name})

def sent(got: Socket & Res(Unit), buf: List<&2, U32>, serial: U32, name: String) -> IO(Link):
  (sock, r) = got
  sent.res(sock, r, buf, serial, name)

def send.bytes(sock: Socket, bytes: List<&2, U32>, buf: List<&2, U32>, serial: U32, name: String) -> IO(Link):
  match bytes:
    case Nil{}:
      IO.pure(Link, Live{sock, buf, serial, name})
    case Con{h, t}:
      do IO<Link>:
        got : Socket & Res(Unit) <- TCP.send_bytes(sock, Con{h, t})
        sent(got, buf, serial, name)

def send.batch(sock: Socket, b: Batch, buf: List<&2, U32>, name: String) -> IO(Link):
  Batch{bytes, serial} = b
  send.bytes(sock, bytes, buf, serial, name)

# Sends the messages in order, numbering each one. TCP.send_bytes is Base's
# send(2) on any socket; a full socket parks this computation, not the app.
def send(link: Link, msgs: List<&2, W.Message>) -> IO(Link):
  match link:
    case Dead{why}:
      IO.pure(Link, Dead{why})
    case Live{sock, buf, +serial, name}:
      send.batch(sock, batch(msgs, serial), buf, name)

def close(link: Link) -> IO(Unit):
  match link:
    case Dead{why}:
      IO.pure(Unit, Unit{})
    case Live{sock, buf, serial, name}:
      Socket.close(sock)

def name(link: Link) -> Link & String:
  match link:
    case Dead{why}:
      (Dead{why}, "")
    case Live{sock, buf, serial, +name}:
      (Live{sock, buf, serial, name}, name)

def serial(link: Link) -> Link & U32:
  match link:
    case Dead{why}:
      (Dead{why}, 0)
    case Live{sock, buf, +serial, name}:
      (Live{sock, buf, serial, name}, serial)

def described(got: Socket & U32, buf: List<&2, U32>, serial: U32, name: String) -> Link & U32:
  (sock, fd) = got
  (Live{sock, buf, serial, name}, fd)

# The socket's descriptor number, for an event loop that waits on it beside
# other sources; 4294967295 for a dead link.
def descriptor(link: Link) -> IO(Link & U32):
  match link:
    case Dead{why}:
      IO.pure(Link & U32, (Dead{why}, 4294967295))
    case Live{sock, buf, serial, name}:
      do IO<Link & U32>:
        got : Socket & U32 <- U.Unix.descriptor(sock)
        return described(got, buf, serial, name)

def reason_of(link: Link) -> Link & String:
  match link:
    case Dead{+why}:
      (Dead{why}, why)
    case Live{sock, buf, serial, name}:
      (Live{sock, buf, serial, name}, "")

# Blocking calls (setup only)
# ---------------------------

def find_reply(msgs: List<&2, W.Message>, +serial: U32) -> Maybe<&2, W.Message>:
  match msgs:
    case Nil{}:
      None{}
    case Con{W.Message{+k, f, s, +r, p, i, m, e, d, sn, b}, rest}:
      Bool.pick(Maybe<&2, W.Message>, U32.is_eq(r, serial) && (U32.is_eq(k, 2) || U32.is_eq(k, 3)),
        Some{W.Message{k, f, s, r, p, i, m, e, d, sn, b}}, find_reply(rest, serial))

def reply_result(m: W.Message) -> Res(W.Message):
  match m:
    case W.Message{3, f, s, r, p, i, mem, e, d, sn, b}:
      fail(W.Message, 5, "auvia: " ++ e ++ ": " ++ W.text(W.arg(b, 0n)))
    case other:
      Done{other}

def await.found(m: Maybe<&2, W.Message>, link: Link, k: Link -> IO(Link & Res(W.Message))) -> IO(Link & Res(W.Message)):
  match m:
    case None{}:
      k(link)
    case Some{x}:
      IO.pure(Link & Res(W.Message), (link, reply_result(x)))

# Messages other than the awaited reply are dropped: during setup only the
# bus's own NameAcquired signal can arrive.
def await.step(got: Link & List<&2, W.Message>, +serial: U32, k: Link -> IO(Link & Res(W.Message))) -> IO(Link & Res(W.Message)):
  (link, msgs) = got
  await.found(find_reply(msgs, serial), link, k)

def await(fuel: Nat, link: Link, +serial: U32) -> IO(Link & Res(W.Message)):
  match fuel:
    case 0n:
      IO.pure(Link & Res(W.Message), (link, fail(W.Message, 110, "auvia: no reply from the bus")))
    case 1n+p:
      do IO<Link & Res(W.Message)>:
        got : Link & List<&2, W.Message> <- recv(link, 100)
        await.step(got, serial, l => await(p, l, serial))

def call.sent(link: Link, +serial: U32) -> IO(Link & Res(W.Message)):
  await(50n, link, serial)

def call.with(got: Link & U32, msg: W.Message) -> IO(Link & Res(W.Message)):
  (link, +serial) = got
  do IO<Link & Res(W.Message)>:
    sent : Link <- send(link, [msg])
    call.sent(sent, serial)

# Sends a method call and waits up to five seconds for its reply.
def call(link: Link, msg: W.Message) -> IO(Link & Res(W.Message)):
  call.with(serial(link), msg)

# Opening
# -------

def hello() -> W.Message:
  W.call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "Hello", W.DEnd{})

def named(link: Link, name: String) -> Link:
  match link:
    case Dead{why}:
      Dead{why}
    case Live{sock, buf, serial, old}:
      Live{sock, buf, serial, name}

def greeted.res(link: Link, r: Res(W.Message)) -> IO(Link):
  match r:
    case Fail{e}:
      do IO<Link>:
        close(link)
        return Dead{reason(e)}
    case Done{W.Message{k, f, s, rep, p, i, m, e, d, sn, body}}:
      IO.pure(Link, named(link, W.text(W.arg(body, 0n))))

def greeted(got: Link & Res(W.Message)) -> IO(Link):
  (link, r) = got
  greeted.res(link, r)

def started(got: Socket & Res(Unit)) -> IO(Link):
  (sock, r) = got
  match r:
    case Fail{e}:
      do IO<Link>:
        Socket.close(sock)
        return Dead{reason(e)}
    case Done{u}:
      do IO<Link>:
        reply : Link & Res(W.Message) <- call(Live{sock, Nil{}, 1, ""}, hello())
        greeted(reply)

def authed(sock: Socket, ok: Bool) -> IO(Link):
  match ok:
    case False{}:
      do IO<Link>:
        Socket.close(sock)
        return Dead{"auvia: the bus refused EXTERNAL authentication"}
    case True{}:
      do IO<Link>:
        got : Socket & Res(Unit) <- TCP.send_bytes(sock, crlf("BEGIN"))
        started(got)

def line.res(sock: Socket, r: Res(Maybe<&2, List<&2, U32>>), acc: List<&2, U32>,
  k: Socket -> List<&2, U32> -> IO(Link)) -> IO(Link):
  match r:
    case Fail{e}:
      do IO<Link>:
        Socket.close(sock)
        return Dead{reason(e)}
    case Done{None{}}:
      k(sock, acc)
    case Done{Some{bytes}}:
      k(sock, List.append(&2, U32, acc, bytes))

def line.got(got: Socket & Res(Maybe<&2, List<&2, U32>>), acc: List<&2, U32>,
  k: Socket -> List<&2, U32> -> IO(Link)) -> IO(Link):
  (sock, r) = got
  line.res(sock, r, acc, k)

# Reads the server's answer to AUTH (one CRLF-terminated line), then BEGIN.
def line(fuel: Nat, sock: Socket, +acc: List<&2, U32>, done: Bool) -> IO(Link):
  match fuel done:
    case _ True{}:
      authed(sock, is_ok(acc))
    case 0n False{}:
      do IO<Link>:
        Socket.close(sock)
        return Dead{"auvia: D-Bus authentication timed out"}
    case 1n+p False{}:
      do IO<Link>:
        got : Socket & Res(Maybe<&2, List<&2, U32>>) <- U.Unix.poll_bytes(sock, 512, 100)
        line.got(got, acc, s => +bs => line(p, s, bs, has_crlf(bs)))

def asked(got: Socket & Res(Unit)) -> IO(Link):
  (sock, r) = got
  match r:
    case Fail{e}:
      do IO<Link>:
        Socket.close(sock)
        return Dead{reason(e)}
    case Done{u}:
      line(50n, sock, Nil{}, False{})

def connected(r: Res(Socket)) -> IO(Link):
  match r:
    case Fail{e}:
      IO.pure(Link, Dead{reason(e)})
    case Done{sock}:
      do IO<Link>:
        uid : U32 <- U.Unix.uid()
        got : Socket & Res(Unit) <- TCP.send_bytes(sock, auth_line(uid))
        asked(got)

def open.path(path: Maybe<&2, String>) -> IO(Link):
  match path:
    case None{}:
      IO.pure(Link, Dead{"auvia: no unix: path or abstract address"})
    case Some{p}:
      do IO<Link>:
        r : Res(Socket) <- U.Unix.connect(p)
        connected(r)

# Connects, authenticates and says Hello. A failure answers a dead link with
# the reason; nothing is left open.
def open(address: String) -> IO(Link):
  open.path(socket_path(address))
