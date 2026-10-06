import Base
import ../dbus/bus.bend as B
import ../dbus/wire.bend as W

# Diagnostic: Hello on the session bus, org.a11y.Bus.GetAddress, then Hello
# on the accessibility bus. Prints each step and closes both connections.

def get_address() -> W.Message:
  W.call("org.a11y.Bus", "/org/a11y/bus", "org.a11y.Bus", "GetAddress", W.DEnd{})

def show_link(got: B.Link & String, label: String) -> IO(B.Link):
  (link, name) = got
  do IO<B.Link>:
    IO.print(label ++ " unique name: " ++ name)
    return link

def show_dead(got: B.Link & String) -> IO(B.Link):
  (link, +why) = got
  do IO<B.Link>:
    IO.print("link state: " ++ Bool.pick(String, String.is_empty(why), "live", why))
    return link

def a11y(+address: String) -> IO(Unit):
  do IO<Unit>:
    IO.print("accessibility bus: " ++ address)
    link : B.Link <- B.open(address)
    link : B.Link <- show_dead(B.reason_of(link))
    link : B.Link <- show_link(B.name(link), "a11y")
    B.close(link)

def answered(got: B.Link & B.Res(W.Message)) -> IO(Unit):
  (link, r) = got
  match r:
    case Fail{e}:
      do IO<Unit>:
        B.close(link)
        IO.print("GetAddress failed: " ++ B.reason(e))
    case Done{W.Message{k, f, s, rep, p, i, m, e, d, sn, body}}:
      do IO<Unit>:
        B.close(link)
        a11y(W.text(W.arg(body, 0n)))

def main() -> IO(Unit):
  do IO<Unit>:
    +address : String <- IO.try(String, IO.get_env("DBUS_SESSION_BUS_ADDRESS"))
    IO.print("session bus: " ++ address)
    link : B.Link <- B.open(address)
    link : B.Link <- show_dead(B.reason_of(link))
    link : B.Link <- show_link(B.name(link), "session")
    got : B.Link & B.Res(W.Message) <- B.call(link, get_address())
    answered(got)
