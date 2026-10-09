import Base
import ../../Mokko/visual.bend as MV
import ../../Mokko/demo.bend as D
import ../../Kairo/types.bend as T
import ../../Kairo/ankra_adapter.bend as AA
import ../../Ankra/window.bend as A
import ../../Ankra/app.bend as Loop
import ../../Voltra/gpu.bend as Vo
import ../../Voltra/quads.bend as Q
import ../../Voltra/words.bend as W
import ../../Runika/font.bend as F
import ../model.bend as M
import ../kairo.bend as AK
import ../service.bend as S

# Mokko's text + button + counter window, made accessible by Auvia.
#
# Rendering, layout and interaction are the sibling libraries', imported
# unchanged: Ankra (the native window and its events), Chromi (pixels),
# Runika/Syllo/Dithra (text), Tessra (layout), Kairo (state), Mokko
# (components and the demo model), Voltra (presenting the frame). Auvia
# publishes the semantics Mokko produces for each drawn frame, emits only
# what changed, and routes AT-SPI actions back through Kairo, so an
# assistive technology's "click" counts exactly like a mouse click.
#
# Ankra's native window reports what the official one could not: window
# focus (the frame is `active` only while it has focus, and screen readers
# hear window:activate/deactivate), the window's position on the screen
# (Component answers screen coordinates from it), and the end of the loop
# with the final state (the accessibility connection is closed explicitly).
# The loop waits on the window and on the accessibility bus at once
# (Ankra's `watch`): it wakes for a window event or a call from an
# assistive technology, and for nothing else.

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
  Host{model: D.Model, font: F.Font, cache: MV.Cache, a11y: S.Service, redraws: U32, gpu: Vo.Gpu}

# Requests from assistive technologies
# ------------------------------------

def request_text(r: M.Request) -> String:
  match r:
    case M.Activate{id, i}:
      "activate " ++ U32.show(id) ++ " action " ++ U32.show(i)
    case M.Focus{id}:
      "focus " ++ U32.show(id)
    case M.EditText{id, op, t}:
      "text request on " ++ U32.show(id)

def merged(routed: AK.Routed, +font: F.Font, clicks: Nat, overflow: Bool, dirty: Bool) -> Result<&2, &2, String, MV.Pending>:
  AK.Routed{change, accepted} = routed
  do Result<&2, &2, String, MV.Pending>:
    update : D.Update <- D.changed(change, font, clicks, overflow)
    return MV.merge(update, dirty)

def route_one(p: MV.Pending, +r: M.Request, +font: F.Font) -> Result<&2, &2, String, MV.Pending>:
  MV.Pending{D.Model{s, clicks, overflow}, dirty} = p
  merged(AK.route(s, r), font, clicks, overflow, dirty)

def ok_of(routed: AK.Routed) -> Bool:
  AK.Routed{c, ok} = routed
  ok

def accepted(+p: MV.Pending, +r: M.Request) -> String:
  MV.Pending{D.Model{s, clicks, overflow}, dirty} = p
  Bool.show(ok_of(AK.route(s, r)))

# Each request goes through Kairo exactly once, in arrival order.
def route_all(rs: List<&2, M.Request>, p: MV.Pending, +font: F.Font) -> IO(MV.Pending):
  match rs:
    case Nil{}:
      IO.pure(MV.Pending, p)
    case Con{+r, rest}:
      +before = p
      do IO<MV.Pending>:
        IO.print("auvia: request " ++ request_text(r) ++ " accepted=" ++ accepted(before, r))
        next : MV.Pending <- MV.unwrap(MV.Pending, route_one(before, r, font))
        route_all(rest, next, font)

# Window events
# -------------

# The last position reported in a batch, if any.
type Spot is Data:
  Spot{x: F32, y: F32}

def moved(es: List<&2, A.Input>, last: Maybe<&2, Spot>) -> Maybe<&2, Spot>:
  match es:
    case Nil{}:
      last
    case Con{A.Moved{x, y}, rest}:
      moved(rest, Some{Spot{x, y}})
    case Con{e, rest}:
      moved(rest, last)

def focus_changed(es: List<&2, A.Input>) -> Bool:
  match es:
    case Nil{}:
      False{}
    case Con{A.Focused{g}, rest}:
      True{}
    case Con{e, rest}:
      focus_changed(rest)

def placed(m: Maybe<&2, Spot>, svc: S.Service) -> IO(S.Service):
  match m:
    case None{}:
      IO.pure(S.Service, svc)
    case Some{Spot{+x, +y}}:
      do IO<S.Service>:
        IO.print("counter: window at " ++ F32.show(x) ++ "," ++ F32.show(y))
        return S.moved(svc, x, y)

# Frames
# ------

def texture(img: Image) -> Array<U32>:
  Q.raster(img, Array.new(U32, W.depth(153600), 0), 0, 0, Q.side(480, 320), 480, 320)

def redraw(p: MV.Pending, +font: F.Font, cache: MV.Cache, svc: S.Service, +redraws: U32, +g: Vo.Gpu) -> IO(Loop.Step<Host>):
  match p:
    case MV.Pending{model, False{}}:
      IO.pure(Loop.Step<Host>, Loop.Keep{Host{model, font, cache, svc, redraws, g}})
    case MV.Pending{+model, True{}}:
      do IO<Loop.Step<Host>>:
        +ready : MV.Cache <- MV.unwrap(MV.Cache, MV.refresh(cache, font, MV.count(model)))
        +frame : D.Frame <- MV.unwrap(D.Frame, MV.view_cached(model, ready))
        image : Image <- IO.try(Image, IO.pure(Result<&1, &1, U32 & String, Image>, MV.draw(frame, ready)))
        published : S.Service <- S.publish(svc, tree(frame, model))
        +g1 : Vo.Gpu <- Vo.upload(g, 480, 320, texture(image))
        IO.print("counter: redraw=" ++ U32.show((redraws + 1 : U32)) ++ " clicks=" ++ Nat.show(MV.count(model)))
        return Loop.Redraw{Host{model, font, ready, published, (redraws + 1 : U32), g1}}

def stepped(inputs: List<&2, T.Input>, got: S.Service & List<&2, M.Request>, +forced: Bool,
  model: D.Model, +font: F.Font, cache: MV.Cache, redraws: U32, +g: Vo.Gpu) -> IO(Loop.Step<Host>):
  (svc, rs) = got
  do IO<Loop.Step<Host>>:
    pending : MV.Pending <- MV.unwrap(MV.Pending, MV.events(inputs, MV.Pending{model, forced}, font))
    routed : MV.Pending <- route_all(rs, pending, font)
    redraw(routed, font, cache, svc, redraws, g)

# One turn: window input through Kairo (with window focus), the window's
# position for screen coordinates, then whatever assistive technologies
# asked since the last turn, then at most one redraw and one diff. A focus
# change or an expose republishes even when the pixels stay the same.
def update(win: A.Win, batch: List<&2, A.Input>, host: Host) -> IO(Loop.Step<Host>):
  Host{model, +font, cache, a11y, redraws, +g} = host
  +es = batch
  do IO<Loop.Step<Host>>:
    inputs : List<&2, T.Input> <- MV.unwrap(List<&2, T.Input>, AA.normalize(es, 1.0))
    here : S.Service <- placed(moved(es, None{}), a11y)
    got : S.Service & List<&2, M.Request> <- S.pump(here)
    stepped(inputs, got, focus_changed(es) || A.exposed(es), model, font, cache, redraws, g)

def drawn(owed: Bool, h: Host) -> Loop.Step<Host>:
  match owed:
    case True{}:
      Loop.Redraw{h}
    case False{}:
      Loop.Keep{h}

# Presents the latest frame (one textured quad); another frame is owed only
# when the swapchain had to be rebuilt.
def draw(win: A.Win, host: Host) -> IO(Loop.Step<Host>):
  Host{model, font, cache, a11y, redraws, g} = host
  do IO<Loop.Step<Host>>:
    +g1 : Vo.Gpu <- Vo.draw(g, [Q.image(0, 0, 480, 320, 0, 0, 480, 320, 4294967295)], 219422463)
    return drawn(Vo.pending(g1), Host{model, font, cache, a11y, redraws, g1})

def report(got: S.Service & String) -> IO(S.Service):
  (svc, text) = got
  do IO<S.Service>:
    IO.print("counter: accessibility " ++ text)
    return svc

def finish(end: A.Win & Host) -> IO(Unit):
  (win, host) = end
  Host{model, font, cache, a11y, redraws, g} = host
  do IO<Unit>:
    S.stop(a11y)
    IO.print("counter: accessibility connection closed; clicks=" ++ Nat.show(MV.count(model)))
    +report : Vo.Report <- Vo.close(g)
    IO.print(Vo.report.show(report))
    +left : U32 <- A.close(win)
    IO.print("counter closed; window objects left: " ++ U32.show(left))

def model_of(p: MV.Pending) -> D.Model:
  MV.Pending{m, d} = p
  m

# The window starts unfocused; Kairo starts assuming focus. Tell it.
def focused(+win: A.Win, model: D.Model, +font: F.Font) -> IO(D.Model):
  do IO<D.Model>:
    p : MV.Pending <- MV.unwrap(MV.Pending, MV.events([T.WindowFocus{A.focused(win)}], MV.Pending{model, False{}}, font))
    return model_of(p)

def watching.if(none: Bool, +win: A.Win, fd: U32) -> IO(A.Win):
  match none:
    case True{}:
      IO.pure(A.Win, win)
    case False{}:
      A.watch(win, fd)

def watching(+win: A.Win, +fd: U32) -> IO(A.Win):
  watching.if(U32.is_eq(fd, A.unwatched()), win, fd)

def run(+win: A.Win, model: D.Model, font: F.Font, cache: MV.Cache, g: Vo.Gpu, got: S.Service & U32) -> IO(Unit):
  (a11y, fd) = got
  do IO<Unit>:
    +w : A.Win <- watching(win, fd)
    end : A.Win & Host <- Loop.run(~Host, ~update, ~draw, w, Host{model, font, cache, a11y, 1, g})
    finish(end)

def started(+win: A.Win, +model: D.Model, +font: F.Font, +assets: MV.Cache, +g: Vo.Gpu) -> IO(Unit):
  do IO<Unit>:
    +frame : D.Frame <- MV.unwrap(D.Frame, MV.view_cached(model, assets))
    image : Image <- IO.try(Image, IO.pure(Result<&1, &1, U32 & String, Image>, MV.draw(frame, assets)))
    +g1 : Vo.Gpu <- Vo.upload(g, 480, 320, texture(image))
    a11y : S.Service <- S.start(tree(frame, model), True{})
    a11y : S.Service <- report(S.status(a11y))
    IO.print("counter ready: click, Tab/Space/Enter, or an AT-SPI client")
    got : S.Service & U32 <- S.descriptor(a11y)
    run(win, model, font, assets, g1, got)

def main() -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, String, F.Font> <- F.load("/usr/share/fonts/liberation/LiberationSans-Regular.ttf")
    +font : F.Font <- MV.unwrap(F.Font, result)
    +initial : D.Model <- MV.unwrap(D.Model, D.init(font, 480.0, 320.0))
    +assets : MV.Cache <- MV.unwrap(MV.Cache, MV.cache(font))
    +win : A.Win <- IO.try(A.Win, A.open(A.Options{title(), 480, 320, False{}, 0, 0, "Auvia", 0}))
    +native : List<&2, U32> <- A.native(win)
    +g : Vo.Gpu <- Vo.open(native, 480, 320, True{})
    +model : D.Model <- focused(win, initial, font)
    started(win, model, font, assets, g)
