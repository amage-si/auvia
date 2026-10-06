import Base
import ../../Mokko/visual.bend as V
import ../../Mokko/demo.bend as D
import ../../Kairo/types.bend as T
import ../../Kairo/base_adapter.bend as B
import ../../Ankra/main.bend as A
import ../../Runika/font.bend as F
import ../model.bend as M
import ../kairo.bend as AK
import ../service.bend as S

# Mokko's text + button + counter window, made accessible by Auvia.
#
# Rendering, layout and interaction are the sibling libraries', imported
# unchanged: Ankra (window), Chromi (pixels), Runika/Syllo/Dithra (text),
# Tessra (layout), Kairo (state), Mokko (components and the demo model).
# Auvia publishes the semantics Mokko produces for each drawn frame, emits
# only what changed, and routes AT-SPI actions back through Kairo, so an
# assistive technology's "click" counts exactly like a mouse click.

def app_name() -> String:
  "auvia-counter"

def title() -> String:
  "Auvia - contador"

def frame_id() -> U32:
  100

# What Mokko does not carry yet: the button's description and key, and
# which node the button controls.
def notes() -> List<&2, AK.Note>:
  [AK.Note{2, "Soma um ao contador", [M.Relation{M.ControllerFor{}, [3]}], Nil{}, "space"},
    AK.Note{3, "", [M.Relation{M.ControlledBy{}, [2]}], [M.Attr{"live", "polite"}], ""}]

def active(model: D.Model) -> Bool:
  D.Model{T.State{ns, h, f, c, k, t, d, live, focus, w, hh}, clicks, overflow} = model
  focus

def tree(frame: D.Frame, +model: D.Model) -> M.Tree:
  D.Frame{ps, semantics, overflow} = frame
  AK.build(app_name(), AK.Surface{frame_id(), title(), 480.0, 320.0, active(model)}, semantics, notes())

type Host is Type:
  Host{model: D.Model, adapter: B.Adapter, font: F.Font, cache: V.Cache, a11y: S.Service, redraws: U32}

# Requests from assistive technologies
# ------------------------------------

def request_text(r: M.Request) -> String:
  match r:
    case M.Activate{id, i}:
      "activate " ++ U32.show(id) ++ " action " ++ U32.show(i)
    case M.Focus{id}:
      "focus " ++ U32.show(id)

def merged(routed: AK.Routed, +font: F.Font, clicks: Nat, overflow: Bool, dirty: Bool) -> Result<&2, &2, String, V.Pending>:
  AK.Routed{change, accepted} = routed
  do Result<&2, &2, String, V.Pending>:
    update : D.Update <- D.changed(change, font, clicks, overflow)
    return V.merge(update, dirty)

def route_one(p: V.Pending, +r: M.Request, +font: F.Font) -> Result<&2, &2, String, V.Pending>:
  V.Pending{D.Model{s, clicks, overflow}, dirty} = p
  merged(AK.route(s, r), font, clicks, overflow, dirty)

def ok_of(routed: AK.Routed) -> Bool:
  AK.Routed{c, ok} = routed
  ok

def accepted(+p: V.Pending, +r: M.Request) -> String:
  V.Pending{D.Model{s, clicks, overflow}, dirty} = p
  Bool.show(ok_of(AK.route(s, r)))

# Each request goes through Kairo exactly once, in arrival order.
def route_all(rs: List<&2, M.Request>, p: V.Pending, +font: F.Font) -> IO(V.Pending):
  match rs:
    case Nil{}:
      IO.pure(V.Pending, p)
    case Con{+r, rest}:
      +before = p
      do IO<V.Pending>:
        IO.print("auvia: request " ++ request_text(r) ++ " accepted=" ++ accepted(before, r))
        next : V.Pending <- V.unwrap(V.Pending, route_one(before, r, font))
        route_all(rest, next, font)

# Frames
# ------

def redraw(p: V.Pending, adapter: B.Adapter, +font: F.Font, cache: V.Cache, svc: S.Service, +redraws: U32) -> IO(A.Step<Host>):
  match p:
    case V.Pending{model, False{}}:
      IO.pure(A.Step<Host>, A.Keep{Host{model, adapter, font, cache, svc, redraws}})
    case V.Pending{+model, True{}}:
      do IO<A.Step<Host>>:
        +ready : V.Cache <- V.unwrap(V.Cache, V.refresh(cache, font, V.count(model)))
        +frame : D.Frame <- V.unwrap(D.Frame, V.view_cached(model, ready))
        image : Image <- IO.try(Image, IO.pure(Result<&1, &1, U32 & String, Image>, V.draw(frame, ready)))
        published : S.Service <- S.publish(svc, tree(frame, model))
        IO.print("counter: redraw=" ++ U32.show((redraws + 1 : U32)) ++ " clicks=" ++ Nat.show(V.count(model)))
        return A.Redraw{Host{model, adapter, font, ready, published, (redraws + 1 : U32)}, image}

def stepped(n: B.Normalized, got: S.Service & List<&2, M.Request>, model: D.Model, +font: F.Font, cache: V.Cache, redraws: U32) -> IO(A.Step<Host>):
  B.Normalized{adapter, inputs} = n
  (svc, rs) = got
  do IO<A.Step<Host>>:
    pending : V.Pending <- V.unwrap(V.Pending, V.events(inputs, V.Pending{model, False{}}, font))
    routed : V.Pending <- route_all(rs, pending, font)
    redraw(routed, adapter, font, cache, svc, redraws)

# One frame: window input through Kairo, then whatever assistive
# technologies asked since the last frame, then one redraw and one diff.
def tick(batch: A.Batch, host: Host) -> IO(A.Step<Host>):
  A.Batch{closed, n, events} = batch
  Host{model, adapter, +font, cache, a11y, redraws} = host
  do IO<A.Step<Host>>:
    mapped : B.Normalized <- V.unwrap(B.Normalized, B.normalize(events, adapter, 1.0))
    got : S.Service & List<&2, M.Request> <- S.pump(a11y)
    stepped(mapped, got, model, font, cache, redraws)

def report(got: S.Service & String) -> IO(S.Service):
  (svc, text) = got
  do IO<S.Service>:
    IO.print("counter: accessibility " ++ text)
    return svc

def main() -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, String, F.Font> <- F.load("/usr/share/fonts/liberation/LiberationSans-Regular.ttf")
    +font : F.Font <- V.unwrap(F.Font, result)
    +model : D.Model <- V.unwrap(D.Model, D.init(font, 480.0, 320.0))
    +assets : V.Cache <- V.unwrap(V.Cache, V.cache(font))
    +frame : D.Frame <- V.unwrap(D.Frame, V.view_cached(model, assets))
    image : Image <- IO.try(Image, IO.pure(Result<&1, &1, U32 & String, Image>, V.draw(frame, assets)))
    a11y : S.Service <- S.start(tree(frame, model), True{})
    a11y : S.Service <- report(S.status(a11y))
    IO.print("counter ready: click, Tab/Space/Enter, or an AT-SPI client; max 18000 frames")
    A.run(~Host, ~tick, title(), 480, 320, 18000n, Host{model, B.init(), font, assets, a11y, 1}, image)
    IO.print("counter closed")
